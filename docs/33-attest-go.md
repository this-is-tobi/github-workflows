# `attest-go.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) and/or a cosign keyless signature to an already-published Go release. Designed to run **after** [`release-go.yml`](./58-release-go.md), once its GoReleaser step has published the GitHub Release.

## Inputs

| Input              | Type    | Description                                                                                                      | Required | Default            |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------ | -------- | ------------------ |
| TAG                 | string  | Release tag to attest (e.g. the `tag-name` output of [`release-app.yml`](./50-release-app.md), or `github.ref_name` on a tag-push trigger) | Yes      | -                   |
| WORKING_DIRECTORY   | string  | Directory holding the Go module (`go.mod`/`go.sum`) to catalog for SBOM. Only used when `SBOM` is true             | No       | "."                 |
| CHECKSUMS_FILE      | string  | Name of the checksum file release-go.yml's GoReleaser configuration produced, as a release asset                   | No       | "checksums.txt"     |
| PROVENANCE          | boolean | Generate GitHub's standard [SLSA](https://slsa.dev/) build provenance attestation, covering every asset listed in `CHECKSUMS_FILE` | No       | false               |
| SBOM                | boolean | Generate an SBOM from the Go module at `WORKING_DIRECTORY`, attest it, and upload it to the release                | No       | false               |
| SIGN                | boolean | Keyless-sign `CHECKSUMS_FILE` with [cosign](https://github.com/sigstore/cosign)                                     | No       | false               |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                            | No       | `["ubuntu-24.04"]` |

## Secrets

None. Unlike [`attest-docker.yml`](./31-attest-docker.md) and [`attest-helm.yml`](./56-attest-helm.md), there is no registry involved - everything this workflow reads or writes is a GitHub Release asset, reached with the job's own `GITHUB_TOKEN`.

## Permissions

| Scope        | Access | Description                                                                          |
| ------------ | ------ | ------------------------------------------------------------------------------------- |
| contents     | write  | `gh release download` (read) and `gh release upload` (write - the SBOM file and the cosign signature bundle) |
| id-token     | write  | Required to sign with cosign and to attest via OIDC                                   |
| attestations | write  | Required to create GitHub attestations                                                |

## Notes

- **This workflow is designed to be called after `release-go.yml`**, using the tag it released. It reads the release back through the GitHub API (`gh release download`) rather than reusing `release-go.yml`'s local `dist/` - the same reason `attest-docker.yml` takes a `DIGEST` instead of a locally-built image: an attestation is only honest about what it names, and what a downstream user actually downloads is the published release asset, not a same-run copy of it. This also means no `ARTIFACT_NAME` has to be kept in sync between the two workflows - only a `needs:` ordering and the tag.
- At least one of `PROVENANCE`, `SBOM` or `SIGN` must be `true` for the job to perform a useful action.
- **Every capability is anchored to `CHECKSUMS_FILE`, not to individual assets.** `actions/attest` and `actions/attest-build-provenance` both accept a checksums file directly via `subject-checksums` - a feature documented upstream by name for GoReleaser - so the resulting attestation lists every real release asset as a subject without this workflow re-deriving digests or guessing which files a release contains. `SIGN` signs that same file with cosign: GoReleaser's checksum step already gives every other asset a verifiable link to it (`sha256sum -c checksums.txt`), so signing it once extends that existing verification story into "and this file's signer is provably this CI pipeline."
- **SBOM scans the Go module's source (`go.mod`/`go.sum`), not the published binaries or archives.** This is a deliberate difference from `attest-docker.yml`'s Trivy scan of a built image, for two reasons:
  1. It would not work correctly. syft's directory cataloger does not unpack archives it merely finds while walking a directory - a folder holding only a `.tar.gz` catalogs zero packages, the same scan against the binary directly (or the archive as the explicit scan target) catalogs the real dependency count. Scanning downloaded release assets would need per-format extraction (`tar`, `unzip`, `ar`+`tar` for `.deb`, `cpio` for `.rpm`) with real failure modes of its own, for a result no more accurate than the option below.
  2. It is not needed. A statically linked (`CGO_ENABLED=0`) Go binary's dependency set is fully and exactly determined by `go.sum` - unlike an OS package layered into a container image, nothing can be in the binary that `go.sum` does not name. Scanning the module source is not an approximation of scanning the binary; for this artifact class the two agree by construction, and the source is what syft's own Go-module cataloger is built to read directly.
- **A repository with more than one Go module gets a wider inventory than just this release.** `SBOM` scans `WORKING_DIRECTORY` as given. For a monorepo, or a plugin architecture where each plugin is built as an independent module, that directory may contain other `go.mod`/`go.sum` files (and other ecosystems - syft also catalogs GitHub Actions usage under `.github/workflows/`, for instance) that have nothing to do with the binaries this specific release ships. Narrow `WORKING_DIRECTORY` to the module that produced this release, or accept the wider inventory.
- **SBOM attestation uses `actions/attest` directly, not `cosign`** - unlike `attest-docker.yml`. `actions/attest` refuses a predicate over 16 MiB, which is exactly why `attest-docker.yml` cannot use it for an image SBOM ("the transitive module graph of a few dozen statically linked Go... binaries runs to thousands of packages" - see [`attest-docker.yml`'s notes](./31-attest-docker.md#why-the-sbom-uses-cosign)). A single Go module's own dependency graph is that same graph, once - not duplicated per platform archive - and realistically stays well under the cap. This is a permanent choice for this workflow, not a size-conditional fallback: it buys one consistent verification story (`gh attestation verify`, the same command as `PROVENANCE`, visible in the repository's Attestations tab) instead of `cosign`'s separate command and invisibility there. A dependency graph large enough to exceed 16 MiB is a real limit of this workflow worth knowing about, not something it silently works around - disable `SBOM` if you hit it.
- **The SBOM is also uploaded to the release as a plain `sbom.spdx.json` file**, alongside its attestation - the attestation is the durable, verifiable record; the plain file is for reading it directly without extracting it from the attestation bundle first.
- **Signing uses cosign's blob commands**, not the OCI ones `attest-docker.yml`/`attest-helm.yml` use: `cosign sign-blob --bundle` against the downloaded checksums file, uploaded back to the release as `<CHECKSUMS_FILE>.cosign.bundle`.
- **Provenance is not gated on the SBOM or SIGN steps succeeding.** It is the attestation that establishes where and from what the release was built, so a problem generating an SBOM or signing the checksums file must never be the reason a release ships without it.
- The checksums file's absence is diagnosed once, in its own step, with one message naming `CHECKSUMS_FILE` - rather than as whichever of three different, more opaque `cosign`/`actions/attest` failures happened to run first.

## Verifying attestations

**Provenance and SBOM** are both GitHub attestations (also visible in the repository's Attestations tab), verified the same way, against the checksums file the subjects were derived from or against any individual downloaded asset:

```sh
gh attestation verify checksums.txt --owner <org>
gh attestation verify myapp_1.2.3_linux_amd64.tar.gz --owner <org>
```

**Signing** is a cosign bundle, downloaded alongside the file it covers:

```sh
cosign verify-blob --bundle checksums.txt.cosign.bundle \
  --certificate-identity-regexp '^https://github.com/<org>/<workflows-repo>/.github/workflows/attest-go.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
```

> [!IMPORTANT]
> The certificate identity is the **reusable workflow that signed it** - `attest-go.yml` in the repository hosting these workflows - not the repository being released. Keyless signing records the called workflow in the certificate, so anchoring the pattern to your own repository will fail to match. Do not drop the constraint to make it pass: without it, verification accepts a signature from anyone.

## Examples

### After a release, with provenance and SBOM

```yaml
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

### Provenance and signing, on a tag-push trigger

Without release-please: `TAG` reads `github.ref_name` directly, and both jobs run off the same `push: tags:` trigger.

```yaml
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

  attest:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-go.yml@v0
    needs:
    - release
    permissions:
      contents: write
      id-token: write
      attestations: write
    with:
      TAG: ${{ github.ref_name }}
      PROVENANCE: true
      SIGN: true
```

### A module in a subdirectory, with a renamed checksum file

```yaml
jobs:
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
      WORKING_DIRECTORY: cmd/tool
      CHECKSUMS_FILE: tool_checksums.txt
      SBOM: true
```
