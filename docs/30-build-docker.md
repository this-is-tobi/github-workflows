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
| BUILD_AMD64         | boolean | Build for amd64                                                                          | No       | true             |
| BUILD_ARM64         | boolean | Build for arm64                                                                          | No       | true             |
| USE_QEMU            | boolean | Use QEMU emulator for arm64                                                              | No       | false            |
| REGISTRY_USERNAME   | string  | Username used to login into registry                                                     | No       | -                |
| REGISTRY_PASSWORD   | string  | Password used to login into registry                                                     | No       | -                |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description                         |
| -------- | ------ | ----------------------------------- |
| packages | write  | Push images to GHCR when applicable |
| contents | read   | Read repository to build context    |

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
