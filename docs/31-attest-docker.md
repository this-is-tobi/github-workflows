# `attest-docker.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) and/or a cosign keyless signature to an already-built Docker image. Designed to run **after** `build-docker.yml`.

## Inputs

| Input          | Type    | Description                                                                                                                                                                                                 | Required | Default          |
| -------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME     | string  | Full image name including registry and path (e.g. `ghcr.io/my-org/my-image`). Normalized automatically.                                                                                                     | Yes      | -                |
| DIGEST         | string  | Digest of the image to attest (e.g. `sha256:abc123...`). Use the `digest` output of `build-docker.yml`.                                                                                                     | Yes      | -                |
| PROVENANCE     | boolean | Generate GitHub's standard [SLSA](https://slsa.dev/) build provenance attestation (calling workflow, repository and commit)                                                                                 | No       | false            |
| SBOM           | boolean | Generate an SBOM (Software Bill of Materials) attestation for the image                                                                                                                                     | No       | false            |
| SIGN           | boolean | Keyless-sign the image digest with [cosign](https://github.com/sigstore/cosign)                                                                                                                             | No       | false            |
| PREDICATE_TYPE | string  | URI identifying the type of a custom in-toto predicate to attach **in addition** to the standard attestations. Set together with `PREDICATE`. Use a URI you control (not `https://slsa.dev/provenance/v1`). | No       | -                |
| PREDICATE      | string  | JSON content for the custom in-toto predicate. Set together with `PREDICATE_TYPE`.                                                                                                                          | No       | -                |
| RUNS_ON        | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                                                                    | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                     | Required |
| ----------------- | --------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into registry (not needed for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password used to login into registry (not needed for `ghcr.io`) | No       |

## Permissions

| Scope        | Access | Description                            |
| ------------ | ------ | -------------------------------------- |
| packages     | write  | Push attestations to the registry      |
| id-token     | write  | Required to sign attestations via OIDC |
| attestations | write  | Required to create GitHub attestations |

## Notes

- This workflow is designed to be called **after** `build-docker.yml`, using its `digest` and `image` outputs.
- At least one of `PROVENANCE`, `SBOM`, `SIGN`, or a custom predicate (both `PREDICATE` and `PREDICATE_TYPE` set) must be provided for the job to perform a useful action.
- **SLSA Provenance**: `PROVENANCE: true` generates GitHub's standard auto-detected SLSA build provenance (workflow, repo, commit of the calling repository) via [`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance), attached to the image in the registry.
- **SBOM**: generates an SPDX SBOM via Trivy, then attaches it to the image in the registry as a **cosign** attestation (keyless, Sigstore/Fulcio via OIDC). See *Verifying attestations* below — the SBOM is verified differently from the provenance.
- The SBOM is an **inventory, not a vulnerability report** — Trivy logs `"--format spdx-json" disables security scanning`, which is expected. Findings go stale within days while the package list does not, so baking them in would ship a verdict that is wrong shortly after publication. Scan the SBOM against a current database when you need one, without re-pulling the image: `trivy sbom sbom.spdx.json`.
- **Signing**: when `SIGN` is `true`, the image digest is keyless-signed with cosign (Sigstore/Fulcio via OIDC), independent of `PROVENANCE`/`SBOM`.
- **Custom predicate**: set both `PREDICATE_TYPE` and `PREDICATE` together to attach an extra in-toto attestation **alongside** the standard provenance — useful, for example, to record an upstream source/version and architectures that this build mirrors, which the auto-generated provenance has no field for. Omitting either input while providing the other causes a fast-fail error. Use a predicate type URI you control; do **not** reuse the reserved `https://slsa.dev/provenance/v1` type, as GitHub validates its `buildType` against a fixed allowlist and rejects custom values.
- The image name is automatically normalized (lowercase, `_` replaced with `-`) for OCI registry compatibility.
- For `ghcr.io`, authentication uses `github.token` automatically; for other registries, provide `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` as secrets.
- **Matrix builds**: a matrix `build-docker.yml` job cannot feed a single matrix-shaped `attest` job — `needs.<job>.outputs.<name>` collapses to one value across all matrix combinations (GitHub's documented last-write-wins behavior), so the digest a matrixed `attest` job would see is wrong for every combination but one. Use one explicit, non-matrixed `build`/`attest` job pair per image instead. See [build-docker.yml → Matrix builds](./30-build-docker.md#matrix-builds) for the full pattern.
- Provenance is not gated on the SBOM steps: it is the attestation that establishes where and from what the image was built, so a problem generating or attaching an SBOM never costs an image its provenance.

## Verifying attestations

The two attestations use different mechanisms, so they are verified with different commands.

**Provenance** — a GitHub attestation, also visible in the repository's Attestations tab:

```sh
gh attestation verify oci://<registry>/<image>:<tag> --owner <org>
```

**SBOM** — a cosign attestation:

```sh
cosign verify-attestation --type spdxjson \
  --certificate-identity-regexp '^https://github.com/<org>/<workflows-repo>/.github/workflows/attest-docker.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  <registry>/<image>@<digest>
```

> [!IMPORTANT]
> The certificate identity is the **reusable workflow that signed it** — `attest-docker.yml` in the repository hosting these workflows — not the repository being released. Keyless signing records the called workflow in the certificate, so anchoring the pattern to your own repository will fail to match. Do not drop the constraint to make it pass: without it, verification accepts a signature from anyone.

### Why the SBOM uses cosign

`actions/attest` refuses an SBOM larger than 16 MiB. That is reachable on ordinary content — the transitive module graph of a few dozen statically linked Go or Rust binaries runs to thousands of packages — and the only way to fit under it would be to drop entries, which removes exactly the supply-chain data the SBOM exists to carry.

cosign has no such ceiling, so it is used for **every** SBOM rather than as a fallback past some size. If the mechanism switched with size, the command needed to verify an image's SBOM would depend on how large that image happened to be, and could change from one release to the next as it grew. One mechanism means one command, for every image, permanently.

Provenance stays on `actions/attest-build-provenance` because that action *generates* the SLSA predicate — build platform, workflow, commit, invocation. cosign only signs a predicate you already have.

The trade-off: SBOMs do not appear in the repository's Attestations tab and are not returned by `gh attestation verify`. Provenance still is.

## Examples

### After a build with provenance and SBOM

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: ${{ needs.release.outputs.version }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      LATEST_TAG: true

  attest:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.build.outputs.image }}
      DIGEST: ${{ needs.build.outputs.digest }}
      PROVENANCE: true
      SBOM: true
```

### Provenance only

```yaml
jobs:
  attest:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.build.outputs.image }}
      DIGEST: ${{ needs.build.outputs.digest }}
      PROVENANCE: true
```

### Standard provenance plus a custom predicate (e.g. mirror metadata)

```yaml
jobs:
  attest:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.build.outputs.image }}
      DIGEST: ${{ needs.build.outputs.digest }}
      SIGN: true
      SBOM: true
      PROVENANCE: true
      PREDICATE_TYPE: https://my-org.github.io/my-repo/mirror/v1
      PREDICATE: '{"upstream":{"repository":"upstream-org/upstream-repo","source":"https://github.com/upstream-org/upstream-repo","version":"1.2.3","ref":"v1.2.3"},"mirror":{"architectures":["amd64","arm64"]}}'
```

### With a custom registry

```yaml
jobs:
  attest:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: docker.io/my-org/my-image
      DIGEST: ${{ needs.build.outputs.digest }}
      PROVENANCE: true
      SBOM: true
    secrets:
      REGISTRY_USERNAME: ${{ secrets.DOCKER_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}
```
