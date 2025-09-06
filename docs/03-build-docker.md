# `build-docker.yml`

Build and push container images using Docker Buildx with optional multi-arch support.

## Inputs

| Input             | Type    | Description                            | Required | Default |
| ----------------- | ------- | -------------------------------------- | -------- | ------- |
| IMAGE_NAME        | string  | Name of the image to build             | Yes      | -       |
| IMAGE_TAG         | string  | Tag used to build image                | Yes      | -       |
| LATEST_TAG        | boolean | Whether to tag the image with 'latest' | No       | false   |
| IMAGE_DOCKERFILE  | string  | Path of the Dockerfile                 | Yes      | -       |
| IMAGE_CONTEXT     | string  | Path of the build context              | Yes      | -       |
| BUILD_AMD64       | boolean | Build for amd64                        | No       | true    |
| BUILD_ARM64       | boolean | Build for arm64                        | No       | true    |
| USE_QEMU          | boolean | Use QEMU emulator for arm64            | No       | false   |
| REGISTRY_USERNAME | string  | Username used to login into registry   | No       | -       |
| REGISTRY_PASSWORD | string  | Password used to login into registry   | No       | -       |

## Permissions

| Scope    | Access | Description                         |
| -------- | ------ | ----------------------------------- |
| packages | write  | Push images to GHCR when applicable |
| contents | read   | Read repository to build context    |

## Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- `LATEST_TAG` input allows tagging images as `latest`.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.

## Examples

### Simple example

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/build-docker.yml@main
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      LATEST_TAG: true
      BUILD_AMD64: true
      BUILD_ARM64: true
      USE_QEMU: false
```
