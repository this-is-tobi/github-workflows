# `attest-docker.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) to an already-built Docker image. Designed to run **after** `build-docker.yml`.

## Inputs

| Input      | Type    | Description                                                                                             | Required | Default          |
| ---------- | ------- | ------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME | string  | Full image name including registry and path (e.g. `ghcr.io/my-org/my-image`). Normalized automatically. | Yes      | -                |
| DIGEST     | string  | Digest of the image to attest (e.g. `sha256:abc123...`). Use the `digest` output of `build-docker.yml`. | Yes      | -                |
| PROVENANCE | boolean | Generate a [SLSA](https://slsa.dev/) provenance attestation for the image                               | No       | false            |
| SBOM       | boolean | Generate an SBOM (Software Bill of Materials) attestation for the image                                 | No       | false            |
| RUNS_ON    | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                | No       | ["ubuntu-24.04"] |

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
- At least one of `PROVENANCE` or `SBOM` must be `true` for the job to perform a useful action.
- **SLSA Provenance**: generates an attestation conforming to [SLSA level 3](https://slsa.dev/spec/v1.0/levels), attached to the image in the registry.
- **SBOM**: generates an SPDX SBOM via Trivy, then attests and attaches it to the image in the registry.
- The image name is automatically normalized (lowercase, `_` replaced with `-`) for OCI registry compatibility.
- For `ghcr.io`, authentication uses `github.token` automatically; for other registries, provide `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` as secrets.

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
