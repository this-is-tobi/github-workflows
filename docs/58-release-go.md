# `release-go.yml`

Builds and publishes a Go project with [GoReleaser](https://goreleaser.com) —
the cross-compilation matrix, archives, checksums and the GitHub release — and
can run the whole thing in snapshot mode without publishing anything.

## Inputs

| Input              | Type    | Description                                                                          | Required | Default            |
| ------------------ | ------- | ------------------------------------------------------------------------------------ | -------- | ------------------ |
| GO_VERSION         | string  | Go version to use. Empty reads it from `go.mod`                                      | No       | ""                 |
| WORKING_DIRECTORY  | string  | Directory holding the module and its GoReleaser configuration                        | No       | "."                |
| CONFIG             | string  | Path to the GoReleaser configuration. Empty lets GoReleaser find its own             | No       | ""                 |
| GORELEASER_VERSION | string  | GoReleaser version to install                                                        | No       | "~> v2"            |
| DISTRIBUTION       | string  | GoReleaser distribution (`goreleaser`, `goreleaser-pro`)                             | No       | "goreleaser"       |
| SNAPSHOT           | boolean | Build without publishing anything                                                    | No       | false              |
| ARGS               | string  | Extra arguments appended to the GoReleaser invocation                                | No       | ""                 |
| REGISTRY           | string  | Container registry to log into first. Empty skips the login                          | No       | ""                 |
| REGISTRY_USERNAME  | string  | Username for the container registry                                                  | No       | ""                 |
| ARTIFACT_NAME      | string  | Artifact name for the built `dist`. Empty uploads nothing                            | No       | ""                 |
| FETCH_DEPTH        | number  | Checkout depth. 0 fetches the whole history, which is what versioning needs          | No       | 0                  |
| RUNS_ON            | string  | Runner labels as JSON array                                                          | No       | '["ubuntu-24.04"]' |

## Secrets

| Secret            | Description                                                                | Required |
| ----------------- | -------------------------------------------------------------------------- | -------- |
| GORELEASER_KEY    | License key for `goreleaser-pro`                                           | No       |
| REGISTRY_PASSWORD | Password or token for the registry named by `REGISTRY`                     | No       |
| EXTRA_ENV         | Additional environment as `KEY=VALUE` lines — a tap token, a signing key   | No       |

## Permissions

| Scope    | Access | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| contents | write  | Create the release and upload its assets           |

> A snapshot publishes nothing and needs only `contents: read`.

## Notes

- **The configuration is checked before anything is built.** A configuration
  invalid in a way GoReleaser only notices at the publish step leaves a
  half-finished release behind, which is the one outcome a release workflow must
  not have.
- **`FETCH_DEPTH` defaults to 0 and the tags are fetched explicitly.**
  GoReleaser derives the version and the changelog from tags; a shallow clone
  produces a release that believes it is the first one.
- **Snapshot mode is the pull-request mode.** It proves the whole release matrix
  compiles at the moment a change lands rather than at the moment somebody tags
  — which is when a platform-specific build failure is most expensive to find.
- **`EXTRA_ENV` goes to the job environment, never to an argv.** An argv is
  visible to every other process on the runner. Each value is also passed to
  `::add-mask::`, and a line that is not `KEY=VALUE` is refused rather than
  dropped: a dropped entry surfaces much later as an authentication failure
  inside a half-finished release.
- **Credentials are kept on the checkout**, unlike the lint and test workflows
  here: GoReleaser runs `git` against this checkout and may legitimately need to
  reach the remote.

## Usage

### Snapshot on every pull request

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: read
    with:
      SNAPSHOT: true
      ARTIFACT_NAME: dist
```

### Release on a tag

```yaml
on:
  push:
    tags: ["v*"]

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
```

### Publishing a Homebrew tap alongside the release

GoReleaser reads the token for the tap repository from the environment, so it
arrives as a secret rather than as an input.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
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
      REGISTRY_USERNAME: ${{ github.actor }}
    secrets:
      REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
```

### A module in a subdirectory

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-go.yml@v0
    permissions:
      contents: write
    with:
      WORKING_DIRECTORY: cmd/tool
      CONFIG: .goreleaser.yaml
```
