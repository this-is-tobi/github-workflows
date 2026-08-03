# `build-docker.yml`

Build and push container images using Docker Buildx with optional multi-arch support. Pushing can be disabled to export the image as a tarball artifact instead, so a downstream job can load it and run tests against it.

## Inputs

| Input               | Type    | Description                                                                               | Required | Default          |
| ------------------- | ------- | ----------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE_NAME          | string  | Name of the image to build                                                                | Yes      | -                |
| IMAGE_TAG           | string  | Tag used to build image                                                                   | Yes      | -                |
| LATEST_TAG          | boolean | Whether to tag the image with 'latest'                                                    | No       | false            |
| TAG_MAJOR_AND_MINOR | boolean | Tag with major and minor versions (e.g. '1.2.3' -> '1.2' & '1')                           | No       | false            |
| IMAGE_DOCKERFILE    | string  | Path of the Dockerfile                                                                    | Yes      | -                |
| IMAGE_CONTEXT       | string  | Path of the build context                                                                 | Yes      | -                |
| IMAGE_TARGET        | string  | Target stage to build in the Dockerfile (builds the last stage if not set)                | No       | -                |
| PUSH                | boolean | Push the image to the registry. When `false`, the image is exported as a tarball artifact | No       | true             |
| BUILD_ARGS          | string  | Newline-separated list of Docker build args (e.g. `MY_ARG=value`)                         | No       | -                |
| CACHE               | boolean | Enable Docker build cache (uses GitHub Actions cache backend)                             | No       | false            |
| PROVENANCE          | boolean | Generate SLSA provenance attestation for the image                                        | No       | false            |
| SBOM                | boolean | Generate SBOM attestation for the image                                                   | No       | false            |
| BUILD_AMD64         | boolean | Build for amd64                                                                           | No       | true             |
| BUILD_ARM64         | boolean | Build for arm64                                                                           | No       | true             |
| USE_QEMU            | boolean | Use QEMU emulator for arm64                                                               | No       | false            |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)  | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                                  | Required |
| ----------------- | ------------------------------------------------------------------------------------------------------------ | -------- |
| REGISTRY_USERNAME | Username used to login into registry (not needed for `ghcr.io`)                                              | No       |
| REGISTRY_PASSWORD | Password used to login into registry (not needed for `ghcr.io`)                                              | No       |
| BUILD_SECRETS     | Newline-separated `KEY=VALUE` build secrets, exposed to the Dockerfile via BuildKit secret mounts (not ARGs) | No       |

## Outputs

| Output          | Description                                                                          |
| --------------- | ------------------------------------------------------------------------------------ |
| digest          | SHA256 digest of the pushed multi-arch manifest (empty when `PUSH` is `false`)       |
| image           | Normalized image name (lowercase, `_` replaced with `-`)                             |
| artifact-prefix | Prefix of the image tarball artifacts when `PUSH` is `false` (e.g. `image-my-image`) |

## Permissions

| Scope        | Access | Description                            |
| ------------ | ------ | -------------------------------------- |
| packages     | write  | Push images to GHCR when applicable    |
| contents     | read   | Read repository to build context       |
| id-token     | write  | Required to sign attestations via OIDC |
| attestations | write  | Required to create GitHub attestations |

> GitHub statically validates permissions against every job declared in a called reusable workflow, including the `attest` job — even when it's skipped at runtime because `PROVENANCE`/`SBOM` are both `false`. Callers must always grant `id-token: write` and `attestations: write`, or the workflow fails to even start with `Error calling workflow ... is only allowed 'attestations: none, id-token: none'`.

## Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- Inputs are validated up-front in the `infos` job: setting both `BUILD_AMD64` and `BUILD_ARM64` to `false` fails fast instead of silently building AMD64 only.
- `LATEST_TAG` input allows tagging images as `latest`.
- `TAG_MAJOR_AND_MINOR` creates additional tags for stable releases (e.g., `1.2.3` also tags `1.2` and `1`). Only applies to non-prerelease versions.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials via secrets.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.
- The workflow exposes three outputs: `digest` (the SHA256 digest of the pushed manifest), `image` (the normalized image name) and `artifact-prefix` (the tarball artifact prefix used when `PUSH` is `false`). The first two are designed to be consumed by `attest-docker.yml` for provenance and SBOM attestations.
- Prerelease versions (containing `-alpha`, `-beta`, `-rc`, etc.) are detected and handled appropriately.
- Short SHA tag is automatically added for traceability.
- Branch-based tags exclude `main` and `develop` branches.
- `IMAGE_TARGET` allows targeting a specific stage in a multi-stage Dockerfile; if omitted, the last stage is built.
- `BUILD_ARGS` accepts a newline-separated list of `KEY=value` pairs passed as Docker build arguments.
- `BUILD_SECRETS` accepts a newline-separated list of `KEY=value` pairs forwarded to `docker/build-push-action`'s `secrets` input. Unlike `BUILD_ARGS`, these are mounted as files via BuildKit (`RUN --mount=type=secret,id=KEY cat /run/secrets/KEY`) and never persisted in image layers or history — use this instead of `BUILD_ARGS` for tokens/credentials needed only during the build.
- `CACHE` enables the GitHub Actions cache backend (`type=gha`) to speed up repeated builds, scoped per image name. It works the same whether or not the image is pushed.

### Building without pushing (`PUSH: false`)

- Setting `PUSH: false` swaps the registry exporter for the `docker` exporter: the image is written to a tarball and uploaded as a workflow artifact instead of being pushed. This is the intended way to build an image and run tests against it before publishing it.
- A reusable workflow's jobs run on their own runners, so an image loaded into the build job's Docker daemon is **not** visible to the caller's test job. The tarball artifact is what bridges the two.
- **Artifact naming**: one artifact per architecture, named `<artifact-prefix>-amd64` / `<artifact-prefix>-arm64`, each containing a single `image.tar`. Use the `artifact-prefix` output rather than hardcoding the name — it is derived from the normalized image name (e.g. `ghcr.io/my-org/my_image` -> `image-my-image`).
- The tarball embeds the image under `<IMAGE_NAME>:<IMAGE_TAG>`, so after `docker load -i image.tar` the image is directly runnable under that reference.
- The `merge` job (manifest list creation) and the `attest` job are **skipped** when `PUSH` is `false` — there is nothing in a registry to merge or attest. Consequently the `digest` output is empty, so downstream steps consuming it (notably `attest-docker.yml`) must not be wired to a non-pushing build.
- Two workflows in this repository consume the tarball artifact directly, so a non-pushed image can still be fully validated: `scan-trivy.yml` via its `IMAGE_ARTIFACT` input (Trivy tarball mode) and `test-kube-deployment.yml` via its `IMAGE_ARTIFACTS` input (`kind load image-archive`). Attestation is the one thing that genuinely cannot work without a push, since attestations are bound to a registry digest.
- **Multi-arch**: with `USE_QEMU: false` (native runners), building both architectures produces two independent single-arch tarballs — one per runner — which is usually what you want, since a test job can only run one architecture anyway.
- **Unsupported combination**: `PUSH: false` + `USE_QEMU: true` + both `BUILD_AMD64` and `BUILD_ARM64`. The `docker` exporter cannot write a multi-platform manifest list to a tarball, so the workflow fails fast in the `infos` job with an explicit error. Either use native runners (`USE_QEMU: false`) or build a single architecture at a time.
- **Registry login** is skipped when `PUSH` is `false`, unless the image targets `ghcr.io` (where credentials always resolve from the job token) or `REGISTRY_USERNAME` is provided. This means a non-GHCR image can be built without any registry credentials, while private base images can still be pulled by passing the secrets anyway.
- The caller still needs to grant `packages: write`, `id-token: write` and `attestations: write` even with `PUSH: false`, because GitHub validates permissions statically against every job declared in the reusable workflow — including the ones skipped at runtime.
- When `PROVENANCE` or `SBOM` is enabled, attestation runs as an additional job after the image is built and merged. Internally, this delegates to the `attest-docker.yml` reusable workflow so that attestation logic is maintained in a single place. This is especially useful when using `build-docker.yml` in a **matrix strategy**, where outputs from individual matrix jobs cannot easily be passed to a separate `attest-docker.yml` call. By attesting within the same workflow, each matrix combination attests its own image automatically.
- The dedicated `attest-docker.yml` workflow can also be called separately after building — this is useful when you need more control over the attestation step or when not using a matrix.

## Examples

The examples below cover the most common build scenarios: a basic multi-architecture image, latest-tagging on the main branch, an AMD64-only build for faster CI, building without pushing to test the image first, and publishing to a custom registry with explicit credentials.

### Simple example

Builds a multi-arch image (AMD64 + ARM64) and pushes it to GHCR. Each architecture is built in a separate job and then merged into a single manifest list. With `USE_QEMU: false`, native ARM runners are expected; set `USE_QEMU: true` to emulate ARM on an AMD64 runner.

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
      id-token: write
      attestations: write
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
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: false
```

### Build without pushing, then test the image

Set `PUSH: false` to build the image and export it as a tarball artifact instead of publishing it. A downstream job downloads the artifact, loads it into its local Docker daemon and runs tests against the real image — no registry involved, and nothing is published if the tests fail.

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
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: false
      BUILD_AMD64: true
      BUILD_ARM64: false

  test:
    runs-on: ubuntu-24.04
    needs:
    - build
    permissions:
      contents: read
    steps:
    - name: Checks-out repository
      uses: actions/checkout@v7

    - name: Download image tarball
      uses: actions/download-artifact@v8
      with:
        name: ${{ needs.build.outputs.artifact-prefix }}-amd64
        path: /tmp

    - name: Load image
      run: docker load -i /tmp/image.tar

    - name: Run tests against the image
      run: |
        docker run -d --name app -p 8080:8080 \
          ${{ needs.build.outputs.image }}:pr-${{ github.event.pull_request.number }}
        ./ci/scripts/smoke-test.sh http://localhost:8080
```

### Build once, test, then push on success

A common CI/CD shape: validate the image before publishing it. The first call builds without pushing so tests run against the exact artifact, and the second call rebuilds and pushes only if the tests passed. With `CACHE: true` the second build is almost entirely a cache hit, so the rebuild is cheap.

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
      IMAGE_TAG: ${{ github.sha }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: false
      CACHE: true

  test:
    runs-on: ubuntu-24.04
    needs:
    - build
    permissions:
      contents: read
    steps:
    - name: Download image tarball
      uses: actions/download-artifact@v8
      with:
        name: ${{ needs.build.outputs.artifact-prefix }}-amd64
        path: /tmp

    - name: Load and test image
      run: |
        docker load -i /tmp/image.tar
        docker run --rm ${{ needs.build.outputs.image }}:${{ github.sha }} --version

  push:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    needs:
    - test
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: ${{ github.sha }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: true
      CACHE: true
      LATEST_TAG: ${{ github.ref_name == 'main' }}
      PROVENANCE: true
      SBOM: true
```

### Testing both architectures without pushing

With `USE_QEMU: false`, each architecture is built on its own native runner and exported as its own tarball, so both can be tested in parallel. Note that `PUSH: false` cannot be combined with `USE_QEMU: true` when both architectures are requested — the `docker` exporter cannot write a multi-platform tarball, and the workflow fails fast in that case.

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
      PUSH: false
      BUILD_AMD64: true
      BUILD_ARM64: true
      USE_QEMU: false

  test:
    strategy:
      matrix:
        include:
        - arch: amd64
          runner: ubuntu-24.04
        - arch: arm64
          runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    needs:
    - build
    permissions:
      contents: read
    steps:
    - name: Download image tarball
      uses: actions/download-artifact@v8
      with:
        name: ${{ needs.build.outputs.artifact-prefix }}-${{ matrix.arch }}
        path: /tmp

    - name: Load and test image
      run: |
        docker load -i /tmp/image.tar
        docker run --rm ${{ needs.build.outputs.image }}:1.2.3 --version
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
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: registry.example.com/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Passing a build-time secret

For a Dockerfile step that needs a credential only during the build (e.g. fetching private content via a token), use `BUILD_SECRETS` and consume it with a BuildKit secret mount so it never lands in image layers:

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
    secrets:
      BUILD_SECRETS: |
        GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
```

```dockerfile
# In the Dockerfile:
RUN --mount=type=secret,id=GITHUB_TOKEN \
    my-tool --token "$(cat /run/secrets/GITHUB_TOKEN)"
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
      id-token: write
      attestations: write
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
