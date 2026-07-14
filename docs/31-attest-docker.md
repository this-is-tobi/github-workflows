# `attest-docker.yml`

Generate and attach security attestations (SLSA provenance and/or SBOM) and/or a cosign keyless signature to an already-built Docker image. Designed to run **after** `build-docker.yml`.

## Inputs

| Input                     | Type    | Description                                                                                                                                        | Required | Default          |
| ------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME                | string  | Full image name including registry and path (e.g. `ghcr.io/my-org/my-image`). Normalized automatically.                                               | Yes      | -                |
| DIGEST                    | string  | Digest of the image to attest (e.g. `sha256:abc123...`). Use the `digest` output of `build-docker.yml`.                                               | Yes      | -                |
| PROVENANCE                | boolean | Generate a [SLSA](https://slsa.dev/) provenance attestation for the image                                                                             | No       | false            |
| SBOM                      | boolean | Generate an SBOM (Software Bill of Materials) attestation for the image                                                                               | No       | false            |
| SIGN                      | boolean | Keyless-sign the image digest with [cosign](https://github.com/sigstore/cosign)                                                                       | No       | false            |
| PROVENANCE_PREDICATE_TYPE | string  | URI identifying a custom provenance predicate type. Set together with `PROVENANCE_PREDICATE` to replace the default auto-generated SLSA build provenance. Ignored if `PROVENANCE` is `false`. | No       | -                |
| PROVENANCE_PREDICATE      | string  | JSON content for a custom provenance predicate. Set together with `PROVENANCE_PREDICATE_TYPE`. Ignored if `PROVENANCE` is `false`.                    | No       | -                |
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
- **SLSA Provenance**: generates an attestation conforming to [SLSA level 3](https://slsa.dev/spec/v1.0/levels), attached to the image in the registry.
- **SBOM**: generates an SPDX SBOM via Trivy, then attests and attaches it to the image in the registry.
- **Signing**: when `SIGN` is `true`, the image digest is keyless-signed with cosign (Sigstore/Fulcio via OIDC), independent of `PROVENANCE`/`SBOM`.
- **Custom provenance predicate**: by default, `PROVENANCE: true` generates GitHub's standard auto-detected SLSA build provenance (workflow, repo, commit of the calling repository). Set both `PROVENANCE_PREDICATE_TYPE` and `PROVENANCE_PREDICATE` to attach your own predicate instead — useful, for example, to record an upstream source/version that this build actually mirrors, which the auto-generated provenance has no field for.
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

### Signing plus a custom provenance predicate

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
      PROVENANCE_PREDICATE_TYPE: https://slsa.dev/provenance/v1
      PROVENANCE_PREDICATE: '{"buildDefinition":{"buildType":"https://example.com/mirror","externalParameters":{"upstreamVersion":"1.2.3"},"resolvedDependencies":[{"uri":"git+https://github.com/upstream-org/upstream-repo","digest":{"gitCommit":"v1.2.3"}}]},"runDetails":{"builder":{"id":"${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}}}'
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
