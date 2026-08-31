# `release-go.yml`

Publishes a Go project with [GoReleaser](https://goreleaser.com) — the cross-compilation matrix, archives, checksums and the GitHub Release itself.

This is the publishing half of the Go pipeline. The compiling half is [`build-go.yml`](./32-build-go.md), which runs the same matrix under `--snapshot` and needs only `contents: read`.

> **Something else may already own your releases.** If the repository uses [`release-app.yml`](./50-release-app.md), release-please creates the tag, the notes and the Release. Read [Composing with `release-app`](#composing-with-release-app) before wiring both — the two are meant to be chained, not chosen between.

## Inputs

| Input                   | Type    | Description                                                                 | Required | Default            |
| ----------------------- | ------- | --------------------------------------------------------------------------- | -------- | ------------------ |
| GO_VERSION              | string  | Go version to use. Empty reads it from `go.mod`                             | No       | ""                 |
| WORKING_DIRECTORY       | string  | Directory holding the module and its GoReleaser configuration               | No       | "."                |
| CONFIG                  | string  | Path to the GoReleaser configuration. Empty lets GoReleaser find its own    | No       | ""                 |
| GORELEASER_VERSION      | string  | GoReleaser version to install                                               | No       | "~> v2"            |
| DISTRIBUTION            | string  | GoReleaser distribution (`goreleaser`, `goreleaser-pro`)                    | No       | "goreleaser"       |
| ARGS                    | string  | Extra arguments appended to the GoReleaser invocation                       | No       | ""                 |
| REGISTRY                | string  | Container registry to log into first. Empty skips the login                 | No       | ""                 |
| ARTIFACT_NAME           | string  | Artifact name for the released `dist`. Empty uploads nothing                | No       | ""                 |
| ARTIFACT_RETENTION_DAYS | number  | How long to keep the uploaded artifact                                      | No       | 7                  |
| FETCH_DEPTH             | number  | Checkout depth. 0 fetches the whole history, which is what versioning needs | No       | 0                  |
| RUNS_ON                 | string  | Runner labels as JSON array                                                 | No       | '["ubuntu-24.04"]' |

## Secrets

| Secret            | Description                                                                        | Required |
| ----------------- | ---------------------------------------------------------------------------------- | -------- |
| APP_CLIENT_ID     | GitHub App Client ID. With `APP_PRIVATE_KEY`, the release can fire `release:`       | No       |
| APP_PRIVATE_KEY   | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                    | No       |
| GH_PAT            | Personal access token, same purpose, resolved after the App                         | No       |
| GORELEASER_KEY    | License key for `goreleaser-pro`                                                    | No       |
| REGISTRY_USERNAME | Username for `REGISTRY`. Required when it is set and is not `ghcr.io`               | No       |
| REGISTRY_PASSWORD | Password or token for `REGISTRY`. Required alongside `REGISTRY_USERNAME`            | No       |
| EXTRA_ENV         | Additional environment as `KEY=VALUE` lines — a tap token, a signing key            | No       |

## Permissions

| Scope    | Access | Description                                                       |
| -------- | ------ | ----------------------------------------------------------------- |
| contents | write  | Create the release and upload its assets                          |
| packages | write  | Push images, for a configuration that publishes them to `ghcr.io` |

> `permissions:` takes no expressions, so `packages: write` is declared even with `REGISTRY` empty, where nothing uses it — the same unavoidable shape `release-helm.yml` carries. A caller that publishes no images may grant `packages: none` to take it back; what the job gets is the intersection.

## Authentication

This workflow accepts all three modes described in [`docs/05-authentication.md`](./05-authentication.md), resolved as **App token → `GH_PAT` → `GITHUB_TOKEN`**.

The mode is not cosmetic here. **A GitHub Release created with `GITHUB_TOKEN` cannot fire `release:` triggers**, and the failure is silent: the release appears, its assets are attached, and a downstream job — an attestation, an image build, an announcement — waiting on `on: release: types: [published]` simply never starts. Supply the App credentials if anything is listening.

Supplying exactly one of `APP_CLIENT_ID` / `APP_PRIVATE_KEY` fails the job rather than falling through, because a silent fallback would downgrade authentication without saying so.

The App token is minted with `permission-contents: write` and nothing else, and scoped to the calling repository. It reaches only the GoReleaser step. The checkout deliberately keeps the job's own `GITHUB_TOKEN` instead: the tag fetch needs a credential in a private repository, and `GITHUB_TOKEN` cannot trigger workflows, so nothing `git` does here can re-enter the caller's pipeline.

## Composing with `release-app`

Two things creating the same GitHub Release is the failure mode to avoid, so pick which one owns it.

| Situation                            | Who owns the release | What to call                                                                    |
| ------------------------------------ | -------------------- | -------------------------------------------------------------------------------- |
| No release-please in the repository  | GoReleaser           | **This workflow**, on `push: tags:`                                              |
| release-please is already there      | release-please       | [`release-app.yml`](./50-release-app.md) first, then **this workflow** after it   |

In the second row release-please owns the version, the tag and the notes, and this workflow only attaches the binaries to the release it made. That works because GoReleaser's [`release.mode`](https://goreleaser.com/customization/release/) defaults to `keep-existing`, which leaves an existing release's notes alone — setting it to `replace` would overwrite the changelog release-please generated. A `.goreleaser.yaml` written for the standalone case usually also carries `release.draft: true`, which is worth dropping here: the release is already published by the time GoReleaser sees it.

Chain it as a `needs:` job rather than on `on: release: published`. Both work, but the trigger only fires if release-please itself ran under App or PAT credentials — [`GITHUB_TOKEN` cannot trigger workflows](./05-authentication.md#why-the-app-mode-exists) — whereas `needs:` does not care.

```yaml
name: CD

on:
  push:
    branches:
    - main

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

  binaries:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    if: ${{ needs.release.outputs.release-created == 'true' }}
    needs:
    - release
    permissions:
      contents: write
      packages: write
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

> The `Fetch tags` step is what makes this work: release-please creates the tag during the run above, so it did not exist when this job's checkout resolved. Fetching brings it in, and GoReleaser then sees an ordinary tagged commit.

What **not** to reach for here is `build-go.yml` with `PACKAGE: true` feeding `RELEASE_ARTIFACT_NAMES`. It looks like the same shape as the [CLI-as-a-release-asset pattern](./90-global-workflows-examples.md), and it produces archives named for a snapshot version — `myapp_0.0.1-next_linux_amd64.tar.gz` — because `--snapshot` ignores the tag it would need. Those belong on a pull request, not on a release.

## Attesting what was released

This workflow has no built-in attestation path — it never declares a nested call requesting `id-token`/`attestations`, so a caller that only wants binaries published never needs to grant them. SLSA provenance, an SBOM and cosign signing are entirely [`attest-go.yml`](./33-attest-go.md)'s responsibility, composed as a second job that reads the release this workflow just published back through the GitHub API rather than through any output of this one:

```yaml
attest:
  uses: this-is-tobi/github-workflows/.github/workflows/attest-go.yml@v0
  needs:
  - release
  - binaries
  permissions:
    contents: write
    id-token: write
    attestations: write
  with:
    TAG: ${{ needs.release.outputs.tag-name }}
    PROVENANCE: true
    SBOM: true
```

See [`attest-go.yml`](./33-attest-go.md) for the full input list and how `TAG` is supplied on a plain tag-push trigger instead.

## Notes

- **The configuration is checked before anything is built.** A configuration invalid in a way GoReleaser only notices at the publish step leaves a half-finished release behind, which is the one outcome a release workflow must not have.
- **`FETCH_DEPTH` defaults to 0 and the tags are fetched explicitly.** GoReleaser derives the version and the changelog from tags; a shallow clone produces a release that believes it is the first one. The extra `git fetch --force --tags` is GoReleaser's own documented setup: checkout writes the triggering tag as a lightweight local tag, so an annotated tag's message and date are not what is in the working copy until it is re-fetched.
- **`EXTRA_ENV` goes to the job environment, never to an argv.** An argv is visible to every other process on the runner. Each value is passed to `::add-mask::` *before* it is written, and a line that is not `KEY=VALUE` is refused rather than dropped: a dropped entry surfaces much later as an authentication failure inside a half-finished release. A value spanning several lines — a PEM key pasted whole — is refused for the same reason, rather than being truncated to its first line.
- **`EXTRA_ENV` will not set `PATH`, `NODE_OPTIONS`, `LD_PRELOAD`, `LD_LIBRARY_PATH`, `DYLD_*`, `GITHUB_*`, `ACTIONS_*` or `RUNNER_*`.** Those change how the rest of the job runs rather than passing a value to GoReleaser. `GITHUB_TOKEN` in particular is refused rather than honoured: the release step sets it at step level, which wins, so an entry here would be accepted, ignored, and blamed for nothing.
- **`ghcr.io` needs no registry secrets.** It accepts the job's own token. Any other registry requires both `REGISTRY_USERNAME` and `REGISTRY_PASSWORD`, and the job fails naming them rather than piping an empty password into `docker login` partway through.

## Usage

### Release on a tag

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
      packages: write
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Publishing a Homebrew tap alongside the release

GoReleaser reads the token for the tap repository from the environment, so it arrives as a secret rather than as an input.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
      packages: write
    secrets:
      EXTRA_ENV: |
        HOMEBREW_TAP_GITHUB_TOKEN=${{ secrets.TAP_TOKEN }}
```

### Also pushing container images

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      REGISTRY: ghcr.io
```

### A module in a subdirectory

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      WORKING_DIRECTORY: cmd/tool
      CONFIG: .goreleaser.yaml
```
