# `clean-images.yml`

Delete container images from GHCR (GitHub Container Registry): a specific version addressed by its tag, and/or the versions that have become orphaned.

For GitHub Actions caches, see [clean-cache](./70-clean-cache.md).

## Inputs

| Input          | Type    | Description                                                                              | Required | Default             |
| -------------- | ------- | ------------------------------------------------------------------------------------------ | -------- | ------------------- |
| IMAGE          | string  | Image to act on (e.g., `ghcr.io/owner/repo/service:pr-123`)                              | Yes      | -                   |
| CLEAN_TAGGED   | boolean | Delete the version carrying exactly the tag present in `IMAGE`                           | No       | true                |
| CLEAN_ORPHANED | boolean | Delete every version whose tags are all git SHAs                                         | No       | false               |
| PROTECTED_TAGS | string  | Comma separated tags never to delete, on top of the version-like tags always kept        | No       | latest,main,develop |
| RUNS_ON        | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"]    |

## Permissions

| Scope    | Access | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| packages | write  | Required to delete GHCR container package versions |

## What is never deleted

A GHCR version carries **every** tag pushed to its digest. Deleting through one of them deletes them all: if an ephemeral tag and a release tag share a digest, removing the former would take the latter with it.

A version is kept as soon as it carries at least:

- a version-like tag — `0.2.0`, `0.2.0-rc.1`, `v1.2.3`: every release and prerelease is kept indefinitely;
- a tag listed in `PROTECTED_TAGS` — by default `latest`, `main`, `develop`.

The refusal is explicit: the job prints a warning naming the protected tags it found, and exits 0 without deleting anything.

This guard is about the **content of the version**, not about pull request state: `CLEAN_TAGGED` deletes the tag it is given, including `pr-<N>` of a pull request that is still open. Targeting only closed pull requests is the caller's responsibility — see the example below.

## Notes

- `IMAGE` must carry a tag when `CLEAN_TAGGED` is enabled; the job fails explicitly otherwise, rather than looking up a tag that cannot exist and exiting 0.
- `CLEAN_ORPHANED` reads only the package name: the tag in `IMAGE` is ignored and may be omitted.
- A version counts as orphaned once **all** its remaining tags look like a git SHA (7–40 hex characters): a moving tag such as `pr-<N>` or a branch name was reassigned to a newer build, and nothing meaningful keeps it alive.
- When a deleted version is a multi-arch manifest list, the per-platform images it references — never tagged themselves — are deleted with it, since nothing could find them afterwards.
- Untagged versions are never deleted directly: they are the per-platform images of a manifest list, and removing one on its own would break the image referencing it.
- A failed deletion — a version already gone, for instance — is logged without failing the job.

## Examples

### Scheduled sweep (recommended)

Reconciles recently closed pull requests once a day, then collects orphans. The `list-closed-prs` job is the only one needing `pull-requests: read`; it is also what guarantees no open pull request is targeted.

A `pull_request: closed` trigger is not reliable here: with `AUTOMERGE_METHOD: admin` the merge does not wait for checks, so the cleanup fires while the build is still pushing its image. It finds nothing, exits 0, and the image lands seconds later with nothing left to remove it.

```yaml
name: Clean images

on:
  schedule:
  - cron: '0 1 * * *'
  workflow_dispatch:
    inputs:
      LOOKBACK_DAYS:
        description: How far back to reconcile closed pull requests
        required: false
        type: number
        default: 3

jobs:
  list-closed-prs:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
    outputs:
      prs: ${{ steps.list.outputs.prs }}
    steps:
    - id: list
      env:
        GH_TOKEN: ${{ github.token }}
        REPO: ${{ github.repository }}
        # The `schedule` trigger has no `inputs` context.
        LOOKBACK_DAYS: ${{ inputs.LOOKBACK_DAYS || 3 }}
      run: |
        set -euo pipefail
        CUTOFF=$(date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)
        PRS=$(gh pr list -R "$REPO" --state closed --limit 100 \
          --json number,closedAt \
          | jq -c --arg c "$CUTOFF" \
            '[.[] | select(.closedAt >= $c) | {number}]')
        echo "prs=$PRS" >> "$GITHUB_OUTPUT"

  sweep-images:
    needs: list-closed-prs
    # An empty matrix vector is a workflow error, not an empty run.
    if: ${{ needs.list-closed-prs.outputs.prs != '[]' }}
    uses: this-is-tobi/github-workflows/.github/workflows/clean-images.yml@v0
    permissions:
      packages: write
    strategy:
      fail-fast: false
      matrix:
        pr: ${{ fromJSON(needs.list-closed-prs.outputs.prs) }}
    with:
      IMAGE: ghcr.io/${{ github.repository }}/app:pr-${{ matrix.pr.number }}

  sweep-orphans:
    # Independent of any pull request: collects versions left carrying only a
    # SHA, after a moving tag was reassigned to a newer build.
    uses: this-is-tobi/github-workflows/.github/workflows/clean-images.yml@v0
    permissions:
      packages: write
    with:
      IMAGE: ghcr.io/${{ github.repository }}/app
      CLEAN_TAGGED: false
      CLEAN_ORPHANED: true
```

### Delete a specific image

```yaml
jobs:
  cleanup:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-images.yml@v0
    permissions:
      packages: write
    with:
      IMAGE: ghcr.io/this-is-tobi/tools/debug:pr-123
```

### Collect orphans only

The tag is omitted: `CLEAN_ORPHANED` reads only the package name.

```yaml
jobs:
  cleanup-orphans:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-images.yml@v0
    permissions:
      packages: write
    with:
      IMAGE: ghcr.io/this-is-tobi/tools/debug
      CLEAN_TAGGED: false
      CLEAN_ORPHANED: true
```
