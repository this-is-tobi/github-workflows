# `build-docker.yml`

Build and push container images using Docker Buildx with optional multi-arch support.

## Inputs

| Input               | Type    | Description                                                                              | Required | Default          |
| ------------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME          | string  | Name of the image to build                                                               | Yes      | -                |
| IMAGE_TAG           | string  | Tag used to build image                                                                  | Yes      | -                |
| LATEST_TAG          | boolean | Whether to tag the image with 'latest'                                                   | No       | false            |
| TAG_MAJOR_AND_MINOR | boolean | Tag with major and minor versions (e.g. '1.2.3' -> '1.2' & '1')                          | No       | false            |
| IMAGE_DOCKERFILE    | string  | Path of the Dockerfile                                                                   | Yes      | -                |
| IMAGE_CONTEXT       | string  | Path of the build context                                                                | Yes      | -                |
| IMAGE_TARGET        | string  | Target stage to build in the Dockerfile (builds the last stage if not set)               | No       | -                |
| BUILD_ARGS          | string  | Newline-separated list of Docker build args (e.g. `MY_ARG=value`)                        | No       | -                |
| CACHE               | boolean | Enable Docker build cache (uses GitHub Actions cache backend)                            | No       | false            |
| PROVENANCE          | boolean | Generate SLSA provenance attestation for the image                                       | No       | false            |
| SBOM                | boolean | Generate SBOM attestation for the image                                                  | No       | false            |
| BUILD_AMD64         | boolean | Build for amd64                                                                          | No       | true             |
| BUILD_ARM64         | boolean | Build for arm64                                                                          | No       | true             |
| USE_QEMU            | boolean | Use QEMU emulator for arm64                                                              | No       | false            |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                     | Required |
| ----------------- | --------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into registry (not needed for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password used to login into registry (not needed for `ghcr.io`) | No       |

## Outputs

| Output | Description                                              |
| ------ | -------------------------------------------------------- |
| digest | SHA256 digest of the pushed multi-arch manifest          |
| image  | Normalized image name (lowercase, `_` replaced with `-`) |

## Permissions

| Scope        | Access | Description                                                      |
| ------------ | ------ | ---------------------------------------------------------------- |
| packages     | write  | Push images to GHCR when applicable                              |
| contents     | read   | Read repository to build context                                 |
| id-token     | write  | Required to sign attestations via OIDC (only if attesting)       |
| attestations | write  | Required to create GitHub attestations (only if attesting)       |

## Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- `LATEST_TAG` input allows tagging images as `latest`.
- `TAG_MAJOR_AND_MINOR` creates additional tags for stable releases (e.g., `1.2.3` also tags `1.2` and `1`). Only applies to non-prerelease versions.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials via secrets.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.
- The workflow exposes two outputs: `digest` (the SHA256 digest of the pushed manifest) and `image` (the normalized image name). These are designed to be consumed by `attest-docker.yml` for provenance and SBOM attestations.
- Prerelease versions (containing `-alpha`, `-beta`, `-rc`, etc.) are detected and handled appropriately.
- Short SHA tag is automatically added for traceability.
- Branch-based tags exclude `main` and `develop` branches.
- `IMAGE_TARGET` allows targeting a specific stage in a multi-stage Dockerfile; if omitted, the last stage is built.
- `BUILD_ARGS` accepts a newline-separated list of `KEY=value` pairs passed as Docker build arguments.
- `CACHE` enables the GitHub Actions cache backend (`type=gha`) to speed up repeated builds, scoped per image name.
- When `PROVENANCE` or `SBOM` is enabled, attestation runs as an additional job after the image is built and merged. Internally, this delegates to the `attest-docker.yml` reusable workflow so that attestation logic is maintained in a single place. This is especially useful when using `build-docker.yml` in a **matrix strategy**, where outputs from individual matrix jobs cannot easily be passed to a separate `attest-docker.yml` call. By attesting within the same workflow, each matrix combination attests its own image automatically.
- The dedicated `attest-docker.yml` workflow can also be called separately after building — this is useful when you need more control over the attestation step or when not using a matrix.

## Examples

The examples below cover the most common build scenarios: a basic multi-architecture image, latest-tagging on the main branch, an AMD64-only build for faster CI, and publishing to a custom registry with explicit credentials.

### Simple example

Builds a multi-arch image (AMD64 + ARM64) and pushes it to GHCR. Each architecture is built in a separate job and then merged into a single manifest list. With `USE_QEMU: false`, native ARM runners are expected; set `USE_QEMU: true` to emulate ARM on an AMD64 runner.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
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
    permissions:
      packages: write
      contents: read
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
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: false
```

### Custom (non-GHCR) registry

For registries other than `ghcr.io`, provide explicit credentials as secrets:

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
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Provenance and SBOM attestations

Attestation can be enabled directly in the build workflow by setting `PROVENANCE` and/or `SBOM` to `true`. This is particularly convenient when building **multiple images in a matrix**, as each matrix job attests its own image without needing to wire outputs to a separate workflow. Note that the caller must grant the additional `id-token: write` and `attestations: write` permissions.

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
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: ${{ needs.release.outputs.version }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      LATEST_TAG: true
      PROVENANCE: true
      SBOM: true
```

### Matrix build with built-in attestation

When building multiple images in a matrix, outputs from individual matrix jobs cannot be forwarded to a separate `attest-docker.yml` call. Enabling attestation directly solves this:

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
        - image: ghcr.io/my-org/frontend
          context: ./apps/frontend
          dockerfile: ./apps/frontend/Dockerfile
        - image: ghcr.io/my-org/backend
          context: ./apps/backend
          dockerfile: ./apps/backend/Dockerfile
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ matrix.image }}
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ${{ matrix.context }}
      IMAGE_DOCKERFILE: ${{ matrix.dockerfile }}
      PROVENANCE: true
      SBOM: true
```

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile

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
