# `attest-go.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) and/or a cosign keyless signature to a Go release, published or still a draft. Designed to run **after** [`release-go.yml`](./58-release-go.md), once its GoReleaser step has attached the binaries to the GitHub Release. On a repository with [immutable releases](#immutable-releases), it is also the job that publishes the release.

## Inputs

| Input              | Type    | Description                                                                                                      | Required | Default            |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------ | -------- | ------------------ |
| TAG                 | string  | Release tag to attest (e.g. the `tag-name` output of [`release-app.yml`](./50-release-app.md), or `github.ref_name` on a tag-push trigger) | Yes      | -                   |
| WORKING_DIRECTORY   | string  | Directory holding the Go module (`go.mod`/`go.sum`) to catalog for SBOM. Only used when `SBOM` is true             | No       | "."                 |
| CHECKSUMS_FILE      | string  | Name of the checksum file release-go.yml's GoReleaser configuration produced, as a release asset                   | No       | "checksums.txt"     |
| PROVENANCE          | boolean | Generate GitHub's standard [SLSA](https://slsa.dev/) build provenance attestation, covering every asset listed in `CHECKSUMS_FILE` | No       | false               |
| SBOM                | boolean | Generate an SBOM from the Go module at `WORKING_DIRECTORY`, attest it, and upload it to the release                | No       | false               |
| SIGN                | boolean | Keyless-sign `CHECKSUMS_FILE` with [cosign](https://github.com/sigstore/cosign)                                     | No       | false               |
| PUBLISH_DRAFT_RELEASE | boolean | Publish the release once everything is attached, if it is still a draft. For [immutable releases](#immutable-releases); a no-op on a published release | No | false |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                            | No       | `["ubuntu-24.04"]` |

## Secrets

| Secret          | Description                                                                                                         | Required |
| --------------- | --------------------------------------------------------------------------------------------------------------------- | -------- |
| APP_CLIENT_ID   | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, the release is published as the App, so `release: published` triggers fire. Only used with `PUBLISH_DRAFT_RELEASE`. See [Authentication](./05-authentication.md) | No |
| APP_PRIVATE_KEY | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                                                     | No       |
| GH_PAT          | Personal access token, same purpose as the App credentials and resolved after them                                  | No       |

Unlike [`attest-docker.yml`](./31-attest-docker.md) and [`attest-helm.yml`](./56-attest-helm.md), there is no registry involved - everything this workflow reads or writes is a GitHub Release asset, reached with the job's own `GITHUB_TOKEN`. The credentials above serve one step only: publishing the draft, because a release published with `GITHUB_TOKEN` fires no `release:` trigger. Supplying only one of `APP_CLIENT_ID`/`APP_PRIVATE_KEY` fails the job rather than falling back.

## Permissions

| Scope        | Access | Description                                                                          |
| ------------ | ------ | ------------------------------------------------------------------------------------- |
| contents     | write  | `gh release download` (read), `gh release upload` (write - the SBOM file and the cosign signature bundle) and publishing the draft with `PUBLISH_DRAFT_RELEASE` (write) |
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

## Immutable releases

[Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) lock a release's assets the moment it is published. `SBOM` and `SIGN` both upload to the release, so on such a repository the release has to **stay a draft until this workflow has run**, and be published here, last. `PROVENANCE` uploads nothing and works on a published release either way.

| Job | Without immutable releases | With immutable releases |
| --- | --- | --- |
| release-please ([`release-app.yml`](./50-release-app.md)), if used | as usual | `"draft": true` and `"force-tag-creation": true` in its config; `PUBLISH_DRAFT_RELEASE` **off** |
| GoReleaser ([`release-go.yml`](./58-release-go.md)) | as usual | `release.draft: true`, plus `release.use_existing_draft: true` when release-please created the release |
| `attest-go.yml` | as usual | `PUBLISH_DRAFT_RELEASE: true` |

Whichever job comes last publishes. Without `SBOM`/`SIGN` there is nothing to attach after GoReleaser, so GoReleaser can publish itself (`release.draft: false`) and this workflow needs no `PUBLISH_DRAFT_RELEASE` - see [`release-go.yml`](./58-release-go.md#immutable-releases).

Worth knowing:

- **A release that is already published and immutable is refused up front.** With `SBOM` or `SIGN`, the first step after the input check asks whether the release can still take assets, and stops with an explanation if not - before cosign writes a signature to the public transparency log for a bundle the release would never carry.
- **Publishing comes last, and only after every step succeeded.** Provenance runs even after an SBOM or signing failure; publishing does not, because a release published without them stays that way for good. A failure leaves the draft, and a re-run attaches what is missing - `--clobber` replaces what the first attempt already uploaded.
- **The step is idempotent.** A published release is left alone, so it is safe to re-run.
- **`release:` events fire on publication, here.** A draft fires nothing; `release: published` comes from this workflow's last step - and only under the App credentials or `GH_PAT`, since a release published with `GITHUB_TOKEN` triggers no workflow.
- **The release also gets GitHub's own [release attestation](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/verifying-the-integrity-of-a-release)** on publication, covering the tag, the commit and every asset's digest: `gh release verify <tag>`, `gh release verify-asset <tag> <file>`. It records what the release holds, not how it was built - `PROVENANCE` stays the record of that.

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

### On a repository with immutable releases

release-please creates the release as a draft, GoReleaser attaches the binaries to that draft and leaves it one, and this workflow attaches the SBOM and the signature and then publishes. In `release-please-config.json`:

```json
{
  "packages": {
    ".": {
      "draft": true,
      "force-tag-creation": true
    }
  }
}
```

In `.goreleaser.yaml` (`name_template` has to render the name release-please gave the release - the bare tag, `{{ .Tag }}`, for a single package - since GoReleaser finds a draft by name):

```yaml
release:
  draft: true
  use_existing_draft: true
  name_template: "{{ .Tag }}"
```

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
      SIGN: true
      PUBLISH_DRAFT_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

`binaries` needs no App credentials here: it no longer publishes, so nothing it does fires a trigger. The App credentials move to `attest`, which does.

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
