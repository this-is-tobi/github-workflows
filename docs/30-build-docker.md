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
| BUILD_SECRET_GITHUB_TOKEN | string | Which credential to expose as a `github_token=<token>` build secret, readable at `/run/secrets/github_token`. Raises the GitHub API rate limit for tools resolving releases during the build (mise, aqua, ubi). One of `none`, `app`, `pat`, `job-token` — see [Build secret credential](#build-secret-credential) | No | none |
| CACHE               | boolean | Enable Docker build cache (uses GitHub Actions cache backend)                             | No       | false            |
| CACHE_MODE          | string  | Buildx cache export mode: `max` (all intermediate layers) or `min` (final image only)    | No       | max              |
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
| APP_CLIENT_ID     | GitHub App **Client ID**, used only to mint the token injected by `BUILD_SECRET_GITHUB_TOKEN`. The token is minted read-only regardless of the App's own permissions — see below. Must be supplied together with `APP_PRIVATE_KEY`; setting only one fails the job | No |
| APP_PRIVATE_KEY   | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID` | No |
| GH_PAT            | Personal access token, same purpose as the App credentials and resolved after them. **Use a read-only token** — see below | No |

## Build secret credential

`BUILD_SECRET_GITHUB_TOKEN` mounts a credential at `/run/secrets/github_token`, readable by **everything the Dockerfile executes** — every install script, package postinstall hook and prebuilt binary. How tight that credential is depends entirely on which one answers, so you name it rather than letting the workflow resolve one silently:

| Value       | Resolves to                          | Narrowed to                                               | Narrowed by                   |
| ----------- | ------------------------------------ | --------------------------------------------------------- | ----------------------------- |
| `none`      | nothing injected *(default)*         | —                                                          | —                             |
| `app`       | App token; **fails** if absent       | `contents: read` + `metadata: read`, this repository only | This workflow, at mint time   |
| `pat`       | App token, else `GH_PAT`; **fails** if neither | Whatever you granted the PAT                     | You, when you created it      |
| `job-token` | App token, else `GH_PAT`, else `GITHUB_TOKEN` | **Nothing** — the job's whole `permissions:` block | Nobody; it cannot be narrowed |

Each mode fails rather than widening to the next credential on its own, so a caller can never mount something broader than it asked for.

**`app` is the only mode this workflow can narrow itself.** It mints a fresh read-only token regardless of what the App installation is otherwise allowed to do, which is why the same App used for releases is safe to pass here — the narrowing, not the App, is what makes it read-only.

**`pat` cannot be narrowed by the workflow.** The token is injected exactly as you created it, so give it `Contents: read` on this repository and nothing more, and never use a classic token.

**`job-token` is the widest option, not a safe default.** `GITHUB_TOKEN`'s permissions are fixed when the job starts and there is no way to attenuate them per-step, so it arrives carrying every scope the calling job granted — for this workflow normally including `packages: write`. A compromised transitive build dependency could push to your registry with it. The workflow emits a `::warning::` whenever this mode actually falls through to the job token. Choose it only when you accept that, and prefer leaving `BUILD_SECRET_GITHUB_TOKEN` at `none` if you have no App and no rate-limit problem to solve.

See [Authentication](./05-authentication.md#what-build-docker-actually-injects).

## Outputs

| Output          | Description                                                                          |
| --------------- | ------------------------------------------------------------------------------------ |
| digest          | SHA256 digest of the pushed multi-arch manifest (empty when `PUSH` is `false`)       |
| image           | Normalized image name (lowercase, `_` replaced with `-`)                             |
| artifact-prefix | Prefix of the image tarball artifacts when `PUSH` is `false` (e.g. `image-my-image`) |

## Permissions

| Scope    | Access | Description                          |
| -------- | ------ | ------------------------------------- |
| packages | write  | Push images to GHCR when applicable   |
| contents | read   | Read repository to build context      |

This workflow never needs `id-token`/`attestations` — it has no nested call that requests them. Attestation is a separate, explicit composition step; see [Attestation and signing](#attestation-and-signing-attest-dockeryml) below.

## Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- Inputs are validated up-front in the `infos` job: setting both `BUILD_AMD64` and `BUILD_ARM64` to `false` fails fast instead of silently building AMD64 only.
- `LATEST_TAG` input allows tagging images as `latest`.
- `TAG_MAJOR_AND_MINOR` creates additional tags for stable releases (e.g., `1.2.3` also tags `1.2` and `1`). Only applies to non-prerelease versions.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials via secrets.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.
- The workflow exposes three outputs: `digest` (the SHA256 digest of the pushed manifest), `image` (the normalized image name) and `artifact-prefix` (the tarball artifact prefix used when `PUSH` is `false`). The first two are designed to be consumed by a following [`attest-docker.yml`](#attestation-and-signing-attest-dockeryml) call.
- Prerelease versions (containing `-alpha`, `-beta`, `-rc`, etc.) are detected and handled appropriately.
- Short SHA tag is automatically added for traceability.
- Branch-based tags exclude `main` and `develop` branches.
- `IMAGE_TARGET` allows targeting a specific stage in a multi-stage Dockerfile; if omitted, the last stage is built.
- `BUILD_ARGS` accepts a newline-separated list of `KEY=value` pairs passed as Docker build arguments.
- `BUILD_SECRETS` accepts a newline-separated list of `KEY=value` pairs forwarded to `docker/build-push-action`'s `secrets` input. Unlike `BUILD_ARGS`, these are mounted as files via BuildKit (`RUN --mount=type=secret,id=KEY cat /run/secrets/KEY`) and never persisted in image layers or history — use this instead of `BUILD_ARGS` for tokens/credentials needed only during the build.
- `CACHE` enables the GitHub Actions cache backend (`type=gha`) to speed up repeated builds, scoped per image name. It works the same whether or not the image is pushed.
- `CACHE_MODE` matters once a repository builds several large images. A repository gets **10 GB** of Actions cache; `mode=max` exports every intermediate layer, and past that budget GitHub evicts least-recently-used entries — builds then import a cache manifest and hit *nothing*, silently paying full rebuild cost while still looking cached. Check actual usage (`gh api /repos/{owner}/{repo}/actions/caches`) and drop to `min` if the total is over: a smaller cache that survives beats a complete one that is always evicted.

### Building without pushing (`PUSH: false`)

- Setting `PUSH: false` swaps the registry exporter for the `docker` exporter: the image is written to a tarball and uploaded as a workflow artifact instead of being pushed. This is the intended way to build an image and run tests against it before publishing it.
- A reusable workflow's jobs run on their own runners, so an image loaded into the build job's Docker daemon is **not** visible to the caller's test job. The tarball artifact is what bridges the two.
- **Artifact naming**: one artifact per architecture, named `<artifact-prefix>-amd64` / `<artifact-prefix>-arm64`, each containing a single `image.tar`. Use the `artifact-prefix` output rather than hardcoding the name — it is derived from the normalized image name (e.g. `ghcr.io/my-org/my_image` -> `image-my-image`).
- The tarball embeds the image under `<IMAGE_NAME>:<IMAGE_TAG>`, so after `docker load -i image.tar` the image is directly runnable under that reference.
- The `merge` job (manifest list creation) is **skipped** when `PUSH` is `false` — there is nothing in a registry to merge. Consequently the `digest` output is empty, so a following [`attest-docker.yml`](#attestation-and-signing-attest-dockeryml) call must not be wired to a non-pushing build.
- Two workflows in this repository consume the tarball artifact directly, so a non-pushed image can still be fully validated: `scan-trivy.yml` via its `IMAGE_ARTIFACT` input (Trivy tarball mode) and `test-kube-deployment.yml` via its `IMAGE_ARTIFACTS` input (`kind load image-archive`). Attestation is the one thing that genuinely cannot work without a push, since attestations are bound to a registry digest.
- **Multi-arch**: with `USE_QEMU: false` (native runners), building both architectures produces two independent single-arch tarballs — one per runner — which is usually what you want, since a test job can only run one architecture anyway.
- **Unsupported combination**: `PUSH: false` + `USE_QEMU: true` + both `BUILD_AMD64` and `BUILD_ARM64`. The `docker` exporter cannot write a multi-platform manifest list to a tarball, so the workflow fails fast in the `infos` job with an explicit error. Either use native runners (`USE_QEMU: false`) or build a single architecture at a time.
- **Registry login** is skipped when `PUSH` is `false`, unless the image targets `ghcr.io` (where credentials always resolve from the job token) or `REGISTRY_USERNAME` is provided. This means a non-GHCR image can be built without any registry credentials, while private base images can still be pulled by passing the secrets anyway.

## Attestation and signing (`attest-docker.yml`)

This workflow has no built-in attestation path — it never declares a nested call requesting `id-token`/`attestations`, so a caller that only builds and pushes never needs to grant them. Provenance, SBOM and cosign signing are entirely [`attest-docker.yml`](./31-attest-docker.md)'s responsibility, composed as a second, explicit job fed by this workflow's `digest`/`image` outputs:

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

Only the `attest` job needs `id-token`/`attestations` — `build` never does, regardless of how many images a pipeline builds or whether any of them get attested.

### Matrix builds

A matrix `build` job cannot feed a single matrix-shaped `attest` job: `needs.<job>.outputs.<name>` collapses to one value across all matrix combinations (GitHub's documented behavior — the last combination to finish wins), so an `attest` job matrixed the same way would silently attest the wrong image, or the same one twice, for every combination but the last. There is no `id`/index correlation between an upstream and downstream matrix.

The correct pattern is one explicit, non-matrixed `build`/`attest` job **pair per image** — more to write than a matrix, but each pair is independently correct and only grants the extra permissions where they're actually used:

```yaml
jobs:
  build-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/frontend
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./apps/frontend
      IMAGE_DOCKERFILE: ./apps/frontend/Dockerfile

  attest-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build-frontend
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.build-frontend.outputs.image }}
      DIGEST: ${{ needs.build-frontend.outputs.digest }}
      PROVENANCE: true
      SBOM: true

  build-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/backend
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./apps/backend
      IMAGE_DOCKERFILE: ./apps/backend/Dockerfile

  attest-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    needs:
    - build-backend
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.build-backend.outputs.image }}
      DIGEST: ${{ needs.build-backend.outputs.digest }}
      PROVENANCE: true
      SBOM: true
```

If only *some* images need attestation, this pattern also means only those images' jobs carry the extra permissions — the others stay at `packages: write` + `contents: read`, unlike a shared matrix where every combination would need to grant the same superset regardless of which images actually use it.

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

### Build without pushing, then test the image

Set `PUSH: false` to build the image and export it as a tarball artifact instead of publishing it. A downstream job downloads the artifact, loads it into its local Docker daemon and runs tests against the real image — no registry involved, and nothing is published if the tests fail.

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
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: ${{ github.sha }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: true
      CACHE: true
      LATEST_TAG: ${{ github.ref_name == 'main' }}
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

Attestation and signing examples (provenance, SBOM, cosign signing, matrix builds) now live in [Attestation and signing](#attestation-and-signing-attest-dockeryml) above, since they're composed via a separate `attest-docker.yml` job rather than inputs on this workflow.
