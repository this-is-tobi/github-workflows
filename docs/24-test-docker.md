# `test-docker.yml`

Run a command inside a built Docker image, from either a registry reference or an image tarball artifact.

## Inputs

| Input               | Type   | Description                                                                              | Required | Default          |
| ------------------- | ------ | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE               | string | Image to run the test against (e.g., `ghcr.io/my-org/my-image:1.2.3`)                    | No       | -                |
| IMAGE_ARTIFACT      | string | Artifact holding an image tarball to load and test locally instead of pulling `IMAGE`    | No       | -                |
| IMAGE_ARTIFACT_FILE | string | Name of the tarball file inside `IMAGE_ARTIFACT`                                         | No       | image.tar        |
| COMMAND             | string | Command to run inside the container, as typed after the image reference                  | **Yes**  | -                |
| ENTRYPOINT          | string | Override the image entrypoint (e.g., `bash`)                                             | No       | -                |
| WORKSPACE_PATH      | string | Repository path mounted read-only into the container                                     | No       | -                |
| WORKSPACE_MOUNT     | string | Path `WORKSPACE_PATH` is mounted at inside the container                                 | No       | /workspace       |
| RUN_ARGS            | string | Extra arguments passed to `docker run` (e.g., `--network host -e FOO=bar`)               | No       | -                |
| RUNS_ON             | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                     | Required |
| ----------------- | --------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into registry (not needed for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password used to login into registry (not needed for `ghcr.io`) | No       |

## Permissions

| Scope    | Access | Description              |
| -------- | ------ | ------------------------ |
| contents | read   | Read repository contents |
| packages | read   | Pull images from GHCR    |

## Notes

- One of `IMAGE` or `IMAGE_ARTIFACT` must be set; the workflow fails fast with a clear message if neither is.
- `IMAGE_ARTIFACT` takes precedence over `IMAGE` when both are set. The tarball is loaded with `docker load` and the reference is read from its output, since the artifact name says nothing about how the image inside is tagged.
- This pairs with `build-docker.yml` used with `PUSH: false`, letting you test an image **before** it is published rather than after.
- `ENTRYPOINT` is needed whenever the image declares one that would otherwise swallow `COMMAND` — a shell, or a service start script. Without it, `COMMAND` is passed as arguments to the existing entrypoint.
- `WORKSPACE_PATH` mounts a directory from the calling repository read-only, so test scripts can live next to the code they verify instead of being inlined into the workflow.
- `COMMAND` and `RUN_ARGS` are word-split into argv, so they behave as they would on a shell command line.
- The repository is only checked out when `WORKSPACE_PATH` is set.
- This catches the class of breakage a successful `docker build` cannot: a tool that installed but does not execute, a binary that never reached `PATH`, a missing shared library.

## Examples

### Smoke-test a published image

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-docker.yml@v0
    permissions:
      contents: read
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      COMMAND: my-binary --version
```

### Run test scripts kept in the repository

Mount a directory of test scripts and run one against the image. `ENTRYPOINT: bash` overrides an entrypoint that would otherwise consume the command.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-docker.yml@v0
    permissions:
      contents: read
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-image:pr-${{ github.event.pull_request.number }}
      ENTRYPOINT: bash
      WORKSPACE_PATH: ci/tests
      WORKSPACE_MOUNT: /tests
      COMMAND: /tests/smoke.sh
```

### Test an image that was built but not pushed

Gate publication on the test result instead of testing after the fact.

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
      BUILD_ARM64: false

  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-docker.yml@v0
    needs:
    - build
    permissions:
      contents: read
      packages: read
    with:
      IMAGE_ARTIFACT: ${{ needs.build.outputs.artifact-prefix }}-amd64
      ENTRYPOINT: bash
      WORKSPACE_PATH: ci/tests
      WORKSPACE_MOUNT: /tests
      COMMAND: /tests/smoke.sh
```

### Test a matrix of images

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-docker.yml@v0
    permissions:
      contents: read
      packages: read
    strategy:
      fail-fast: false
      matrix:
        image: [api, web, worker]
    with:
      IMAGE: ghcr.io/my-org/${{ matrix.image }}:latest
      ENTRYPOINT: bash
      WORKSPACE_PATH: ci/tests
      WORKSPACE_MOUNT: /tests
      COMMAND: /tests/${{ matrix.image }}.sh
```
