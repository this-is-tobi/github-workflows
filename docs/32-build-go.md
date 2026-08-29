# `build-go.yml`

Compiles a Go project across its whole release matrix with [GoReleaser](https://goreleaser.com), and publishes none of it.

This is the pull-request half of the Go pipeline. Cross-compilation failures are host-independent and invisible from a laptop — a build constraint that resolves on darwin and not on windows compiles clean for everybody who never builds for windows — so the cheapest place to find one is the pull request that introduced it, rather than the tag that ships it.

For the publishing half, see [`release-go.yml`](./58-release-go.md).

## Inputs

| Input                   | Type    | Description                                                                    | Required | Default            |
| ----------------------- | ------- | ------------------------------------------------------------------------------ | -------- | ------------------ |
| GO_VERSION              | string  | Go version to use. Empty reads it from `go.mod`                                | No       | ""                 |
| WORKING_DIRECTORY       | string  | Directory holding the module and its GoReleaser configuration                  | No       | "."                |
| CONFIG                  | string  | Path to the GoReleaser configuration. Empty lets GoReleaser find its own       | No       | ""                 |
| GORELEASER_VERSION      | string  | GoReleaser version to install                                                  | No       | "~> v2"            |
| DISTRIBUTION            | string  | GoReleaser distribution (`goreleaser`, `goreleaser-pro`)                       | No       | "goreleaser"       |
| PACKAGE                 | boolean | Produce the full distribution (archives, checksums) instead of bare binaries   | No       | false              |
| SINGLE_TARGET           | boolean | Build only for the runner's platform. Rejected with `PACKAGE`                  | No       | false              |
| IDS                     | string  | Build ids to build, comma-separated. Rejected with `PACKAGE`                   | No       | ""                 |
| ARGS                    | string  | Extra arguments appended to the GoReleaser invocation                          | No       | ""                 |
| ARTIFACT_NAME           | string  | Artifact name for the built distribution. Empty uploads nothing                | No       | ""                 |
| ARTIFACT_RETENTION_DAYS | number  | How long to keep the uploaded artifact                                         | No       | 7                  |
| CACHE                   | boolean | Whether to cache the module and build caches                                   | No       | true               |
| FETCH_DEPTH             | number  | Checkout depth                                                                 | No       | 1                  |
| RUNS_ON                 | string  | Runner labels as JSON array                                                    | No       | '["ubuntu-24.04"]' |

## Secrets

| Secret         | Description                                | Required |
| -------------- | ------------------------------------------ | -------- |
| GORELEASER_KEY | License key for `goreleaser-pro`           | No       |

## Permissions

| Scope    | Access | Description                  |
| -------- | ------ | ---------------------------- |
| contents | read   | Read the checked-out sources |

## Notes

- **`contents: read` is the point of this workflow existing separately.** Everything here runs under `--snapshot` and publishes nothing, so a caller can run it on a pull request without granting a release-capable token to a job a pull request starts. Keeping one workflow with a "don't publish" switch would have forced `contents: write` on every caller, including that one.
- **`PACKAGE` chooses between two GoReleaser commands, not between two destinations.** Off runs `goreleaser build`, GoReleaser's own analogue of `go build` — binaries and nothing else. On runs `goreleaser release --snapshot`, which is the only way to get archives and the checksum file. Both publish nothing, and both stamp a snapshot version.
- **`SINGLE_TARGET` and `IDS` are refused with `PACKAGE` rather than ignored.** Neither flag exists on `goreleaser release`, so honouring them silently would let a caller read a green run as having built one target when the whole matrix was built.
- **No credentials reach the checkout.** GoReleaser reads the working tree and the local object database here and writes only to `dist/`.
- **The configuration is checked first.** A `.goreleaser.yaml` that is invalid in a way GoReleaser only notices at publish time is best found on the pull request that introduced it, where nothing is at stake.
- **`FETCH_DEPTH` is shallow by default**, unlike [`release-go.yml`](./58-release-go.md). No changelog is generated and the stamped version is discarded with the run, so the tag history is history this would only pay for.

## Usage

### Compile check on every pull request

```yaml
name: CI

on:
  pull_request:
    branches:
    - "**"

jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-go.yml@v0
    permissions:
      contents: read
```

### Verifying the packaging pipeline, not just the compile

`PACKAGE: true` runs the archiving, checksumming and SBOM steps that a plain compile never reaches — the ones that break when an archive gains a file that does not exist, or when a hook is added that only runs on the release path.

```yaml
jobs:
  package:
    uses: this-is-tobi/github-workflows/.github/workflows/build-go.yml@v0
    permissions:
      contents: read
    with:
      PACKAGE: true
      ARTIFACT_NAME: dist-preview
```

> **These archives are not release assets.** `--snapshot` stamps a derived version rather than a tagged one — `myapp_0.0.1-next_linux_amd64.tar.gz` — and setting `GORELEASER_CURRENT_TAG` does not change that, because snapshot mode ignores it. Upload them to read, not to hand out. To attach real assets to a release, use [`release-go.yml`](./58-release-go.md), which runs on the tag and stamps it.

### A fast check on the runner's platform only

Worth it where the matrix is large and a separate job already covers the other targets — and worth understanding as a reduction in what the job checks.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-go.yml@v0
    permissions:
      contents: read
    with:
      SINGLE_TARGET: true
```

### A module in a subdirectory

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-go.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: cmd/tool
      CONFIG: .goreleaser.yaml
```
