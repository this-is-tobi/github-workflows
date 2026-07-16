# `attest-docker.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) and/or a cosign keyless signature to an already-built Docker image. Designed to run **after** `build-docker.yml`.

## Inputs

| Input                     | Type    | Description                                                                                                                                        | Required | Default          |
| ------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME                | string  | Full image name including registry and path (e.g. `ghcr.io/my-org/my-image`). Normalized automatically.                                               | Yes      | -                |
| DIGEST                    | string  | Digest of the image to attest (e.g. `sha256:abc123...`). Use the `digest` output of `build-docker.yml`.                                               | Yes      | -                |
| PROVENANCE                | boolean | Generate GitHub's standard [SLSA](https://slsa.dev/) build provenance attestation (calling workflow, repository and commit)                           | No       | false            |
| SBOM                      | boolean | Generate an SBOM (Software Bill of Materials) attestation for the image                                                                               | No       | false            |
| SIGN                      | boolean | Keyless-sign the image digest with [cosign](https://github.com/sigstore/cosign)                                                                       | No       | false            |
| PREDICATE_TYPE            | string  | URI identifying the type of a custom in-toto predicate to attach **in addition** to the standard attestations. Set together with `PREDICATE`. Use a URI you control (not `https://slsa.dev/provenance/v1`). | No       | -                |
| PREDICATE                 | string  | JSON content for the custom in-toto predicate. Set together with `PREDICATE_TYPE`.                                                                    | No       | -                |
| RUNS_ON                   | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                              | No       | ["ubuntu-24.04"] |

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
- At least one of `PROVENANCE`, `SBOM`, or `SIGN` must be `true` for the job to perform a useful action.
- **SLSA Provenance**: `PROVENANCE: true` generates GitHub's standard auto-detected SLSA build provenance (workflow, repo, commit of the calling repository) via [`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance), attached to the image in the registry.
- **SBOM**: generates an SPDX SBOM via Trivy, then attests and attaches it to the image in the registry.
- **Signing**: when `SIGN` is `true`, the image digest is keyless-signed with cosign (Sigstore/Fulcio via OIDC), independent of `PROVENANCE`/`SBOM`.
- **Custom predicate**: set both `PREDICATE_TYPE` and `PREDICATE` to attach an extra in-toto attestation **alongside** the standard provenance — useful, for example, to record an upstream source/version and architectures that this build mirrors, which the auto-generated provenance has no field for. Use a predicate type URI you control; do **not** reuse the reserved `https://slsa.dev/provenance/v1` type, as GitHub validates its `buildType` against a fixed allowlist and rejects custom values.
- The image name is automatically normalized (lowercase, `_` replaced with `-`) for OCI registry compatibility.
- For `ghcr.io`, authentication uses `github.token` automatically; for other registries, provide `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` as secrets.
- **Alternative**: when using `build-docker.yml` in a **matrix strategy**, outputs from individual matrix jobs cannot be easily forwarded to this workflow. In that case, prefer enabling `PROVENANCE` and/or `SBOM` directly in `build-docker.yml` instead — each matrix job will attest its own image automatically.

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
