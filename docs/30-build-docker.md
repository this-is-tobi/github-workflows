# `build-docker.yml`

Build and push container images using Docker Buildx with optional multi-arch support.

## Inputs

| Input               | Type    | Description                                                                                            | Required | Default          |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------ | -------- | ---------------- |
| IMAGE_NAME          | string  | Name of the image to build                                                                             | Yes      | -                |
| IMAGE_TAG           | string  | Tag used to build image                                                                                | Yes      | -                |
| LATEST_TAG          | boolean | Whether to tag the image with 'latest'                                                                 | No       | false            |
| TAG_MAJOR_AND_MINOR | boolean | Tag with major and minor versions (e.g. '1.2.3' -> '1.2' & '1')                                        | No       | false            |
| IMAGE_DOCKERFILE    | string  | Path of the Dockerfile                                                                                 | Yes      | -                |
| IMAGE_CONTEXT       | string  | Path of the build context                                                                              | Yes      | -                |
| IMAGE_TARGET        | string  | Target stage to build in the Dockerfile (builds the last stage if not set)                             | No       | -                |
| BUILD_ARGS          | string  | Newline-separated list of Docker build args (e.g. `MY_ARG=value`)                                      | No       | -                |
| PROVENANCE          | boolean | Generate SLSA provenance attestation after the image is pushed (via `actions/attest-build-provenance`) | No       | false            |
| SBOM                | boolean | Generate an SPDX SBOM and attest it after the image is pushed (Trivy scan + `actions/attest-sbom`)     | No       | false            |
| CACHE               | boolean | Enable Docker build cache (uses GitHub Actions cache backend)                                          | No       | false            |
| BUILD_AMD64         | boolean | Build for amd64                                                                                        | No       | true             |
| BUILD_ARM64         | boolean | Build for arm64                                                                                        | No       | true             |
| USE_QEMU            | boolean | Use QEMU emulator for arm64                                                                            | No       | false            |
| REGISTRY_USERNAME   | string  | Username used to login into registry                                                                   | No       | -                |
| REGISTRY_PASSWORD   | string  | Password used to login into registry                                                                   | No       | -                |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)               | No       | ["ubuntu-24.04"] |

## Permissions

| Scope        | Access | Description                                                       |
| ------------ | ------ | ----------------------------------------------------------------- |
| packages     | write  | Push images to GHCR when applicable                               |
| contents     | read   | Read repository to build context                                  |
| id-token     | write  | Obtain an OIDC token for keyless attestation signing via Sigstore |
| attestations | write  | Push attestations to the registry and GitHub's attestation store  |

## Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- `LATEST_TAG` input allows tagging images as `latest`.
- `TAG_MAJOR_AND_MINOR` creates additional tags for stable releases (e.g., `1.2.3` also tags `1.2` and `1`). Only applies to non-prerelease versions.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.
- Prerelease versions (containing `-alpha`, `-beta`, `-rc`, etc.) are detected and handled appropriately.
- Short SHA tag is automatically added for traceability.
- Branch-based tags exclude `main` and `develop` branches.
- `IMAGE_TARGET` allows targeting a specific stage in a multi-stage Dockerfile; if omitted, the last stage is built.
- `BUILD_ARGS` accepts a newline-separated list of `KEY=value` pairs passed as Docker build arguments.
- `PROVENANCE` generates a SLSA provenance attestation using `actions/attest-build-provenance`. It runs **after** the multi-arch merge so the attestation correctly targets the final index digest, not individual per-arch digests. The per-arch build step explicitly disables `docker/build-push-action`'s automatic provenance (`provenance: false`) because those per-arch attestations would not survive the `imagetools create` merge — and on public repos they can also leak `BUILD_ARGS` values into the provenance payload.
- `SBOM` generates an SPDX 2.3 SBOM by scanning the final merged image with Trivy, then attests it via `actions/attest-sbom`. Same post-merge timing as `PROVENANCE`; `docker/build-push-action`'s built-in SBOM is also suppressed for the same digest-merge reason.
- When either `PROVENANCE` or `SBOM` is enabled, attestations are signed keylessly via Sigstore/Fulcio using the workflow's OIDC token, and pushed both to GitHub's attestation store and to the OCI registry as referrers. Verifiable with `gh attestation verify`.
- `CACHE` enables the GitHub Actions cache backend (`type=gha`) to speed up repeated builds, scoped per image name.

## Examples

The examples below cover the most common build scenarios: a basic multi-architecture image, latest-tagging on the main branch, an AMD64-only build for faster CI, and publishing to a custom registry with explicit credentials.

### Simple example

Builds a multi-arch image (AMD64 + ARM64) and pushes it to GHCR. Each architecture is built in a separate job and then merged into a single manifest list. With `USE_QEMU: false`, native ARM runners are expected; set `USE_QEMU: true` to emulate ARM on an AMD64 runner.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: true
      USE_QEMU: false
```

### Tag as latest on main branch

Uses the commit SHA as the image tag for full traceability. `LATEST_TAG` is a GitHub expression that resolves to `true` only on `main`. Combined with `TAG_MAJOR_AND_MINOR: true`, a tagged release `1.2.3` also creates the convenience aliases `1.2` and `1`.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: ${{ github.sha }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      LATEST_TAG: ${{ github.ref_name == 'main' }}
      TAG_MAJOR_AND_MINOR: true
```

### AMD64-only build (faster CI)

Disabling ARM64 removes the cross-arch build job and significantly reduces CI time — a sensible trade-off for PR checks. The PR-number tag makes the image easy to identify and pull for manual testing.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: false
```

### Custom (non-GHCR) registry

For registries other than `ghcr.io`, provide explicit credentials:

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: registry.example.com/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      REGISTRY_USERNAME: ${{ vars.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Provenance and SBOM attestations

Enabling both flags adds an `attest` job that runs after the multi-arch manifest is created. The job scans the final merged image digest with Trivy (SPDX SBOM) and generates SLSA provenance — both signed keylessly via Sigstore and pushed to the registry as OCI referrers. Attestations can be inspected with `docker buildx imagetools inspect <image>` or verified with `gh attestation verify`.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PROVENANCE: true
      SBOM: true
```
