# `clean-cache.yml`

Delete GitHub Actions caches belonging to a pull request or a branch.

For container images, see [clean-images](./71-clean-images.md).

## Inputs

| Input       | Type   | Description                                                                              | Required | Default          |
| ----------- | ------ | ------------------------------------------------------------------------------------------ | -------- | ---------------- |
| PR_NUMBER   | number | ID number of the pull request whose caches should be deleted                             | No       | -                |
| BRANCH_NAME | string | Branch name whose caches should be deleted                                               | No       | -                |
| RUNS_ON     | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Permissions

| Scope   | Access | Description                         |
| ------- | ------ | ----------------------------------- |
| actions | write  | Manage Actions caches via cache API |

## When to trigger this workflow

A scheduled sweep is the recommended trigger.

Triggering on `pull_request: closed` looks natural but stops working as soon as pull requests are merged with `AUTOMERGE_METHOD: admin` — the only option when **Allow auto-merge** cannot be enabled on the repository (see [global workflow examples](./90-global-workflows-examples.md)).

`admin` merges **without waiting for checks**. The cleanup therefore fires at merge time, while the pull request's build is still writing its caches: it finds only some of them, or none, and exits 0. The run is green despite having done nothing, and caches accumulate with no failing signal to reveal it.

A scheduled sweep, run once the builds have settled, cannot lose that race and collects whatever earlier runs left behind. It is idempotent: a second pass over an already-clean pull request prints `No cache keys found` and exits 0.

If the repository does have auto-merge and uses `AUTOMERGE_METHOD: auto`, the merge happens only once checks pass — a `pull_request: closed` trigger then becomes a useful low-latency complement.

## Notes

- At least one of `PR_NUMBER` or `BRANCH_NAME` is needed; with neither, the job is skipped.
- A pull request's caches are scoped to `refs/pull/<N>/merge`, never to `refs/heads/<branch>` — the latter only holds caches written by a `push`-triggered workflow. When both inputs are supplied, **both refs are swept**.
- A failed deletion — a key evicted between the listing and the delete, for instance by a concurrent run — is logged without failing the job; the remaining keys are still processed.
- The number of keys actually deleted is reported at the end of the job.

## Examples

### Scheduled sweep (recommended)

Reconciles recently closed pull requests once a day. The `list-closed-prs` job is the only one needing `pull-requests: read`.

```yaml
name: Clean cache

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
          --json number,headRefName,closedAt \
          | jq -c --arg c "$CUTOFF" \
            '[.[] | select(.closedAt >= $c) | {number, headRefName}]')
        echo "prs=$PRS" >> "$GITHUB_OUTPUT"

  sweep-caches:
    needs: list-closed-prs
    # An empty matrix vector is a workflow error, not an empty run.
    if: ${{ needs.list-closed-prs.outputs.prs != '[]' }}
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@v0
    permissions:
      actions: write
    strategy:
      fail-fast: false
      matrix:
        pr: ${{ fromJSON(needs.list-closed-prs.outputs.prs) }}
    with:
      PR_NUMBER: ${{ matrix.pr.number }}
      BRANCH_NAME: ${{ matrix.pr.headRefName }}
```

### Clean the caches of a deleted branch

```yaml
on:
  delete:

jobs:
  cleanup:
    if: ${{ github.event.ref_type == 'branch' }}
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@v0
    permissions:
      actions: write
    with:
      BRANCH_NAME: ${{ github.event.ref }}
```
