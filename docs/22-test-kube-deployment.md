# `test-kube-deployment.yml`

Test Kubernetes deployments in an ephemeral [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker) cluster. Creates the cluster, optionally pulls and loads container images from GHCR, installs prerequisite Helm charts, deploys the application via Helm or a custom command, waits for all rollouts to complete, runs a validation command, shows cluster state on failure, and always cleans up the cluster — even on error.

## Inputs

| Input          | Type    | Description                                                                                                                       | Required | Default            |
| -------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------ |
| KIND_VERSION   | string  | Kind version to install                                                                                                           | No       | `0.27.0`           |
| KIND_CONFIG    | string  | Path to a Kind cluster configuration file (relative to repo root)                                                                 | No       | -                  |
| KIND_CLUSTER_NAME | string | Name of the Kind cluster to create                                                                                             | No       | `chart-testing`    |
| IMAGES         | string  | Newline-separated container images to pull and load into the Kind cluster. GHCR images are authenticated automatically.           | No       | -                  |
| IMAGE_ARTIFACTS | string | Name or glob pattern of workflow artifact(s) holding image tarballs to load into the cluster                                      | No       | -                  |
| IMAGE_ARTIFACTS_FILE | string | Name of the tarball file inside each artifact matched by `IMAGE_ARTIFACTS`                                                 | No       | `image.tar`        |
| HELM_PREREQS   | string  | Newline-separated prerequisite Helm charts to install before the app (format per line: `namespace release chart [helm_flags...]`) | No       | -                  |
| HELM_CHART     | string  | Path to the Helm chart directory to deploy. Mutually exclusive with `DEPLOY_COMMAND`.                                             | No       | -                  |
| HELM_RELEASE   | string  | Helm release name for the application                                                                                             | No       | `app`              |
| HELM_VALUES    | string  | Path to Helm values file for the application deployment                                                                           | No       | -                  |
| HELM_ARGS      | string  | Additional arguments passed to `helm upgrade --install`                                                                           | No       | -                  |
| DEPLOY_COMMAND | string  | Custom shell command to run instead of Helm deploy. Mutually exclusive with `HELM_CHART`.                                         | No       | -                  |
| DEPLOY_TIMEOUT | string  | Timeout for deployment rollout wait                                                                                               | No       | `300s`             |
| PRE_COMMAND    | string  | Shell command to run after checkout but before cluster creation                                                                   | No       | -                  |
| TEST_COMMAND   | string  | Shell command to run after deployment for validation                                                                              | No       | -                  |
| FAIL_ON_ERROR  | boolean | Whether to fail the workflow when `TEST_COMMAND` exits with a non-zero code                                                       | No       | `true`             |
| RUNS_ON        | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                          | No       | `["ubuntu-24.04"]` |

## Permissions

| Scope    | Access | Description                                          |
| -------- | ------ | ---------------------------------------------------- |
| packages | read   | Authenticate against GHCR to pull images into Kind   |
| contents | read   | Checkout repository sources (chart, values, configs) |

## Notes

- **KIND_VERSION** must NOT include a `v` prefix (the workflow prepends `v` automatically); the default is `0.27.0`. Passing `v0.27.0` would result in `vv0.27.0`.
- **HELM_ARGS** (and the trailing flags of each `HELM_PREREQS` entry) are word-split into argv on whitespace only: quotes, globs and `$VAR` are **not** interpreted. A flag value containing a space cannot be expressed here — use `HELM_VALUES` with a values file instead. `HELM_ARGS` is read as a single line, so use a folded block scalar (`>-`, as in the examples below) rather than a literal one (`|`) when spreading flags over several lines.
- **IMAGES** is newline-separated. Pass a YAML literal block scalar (`|`) in the caller:
  ```yaml
  with:
    IMAGES: |
      ghcr.io/my-org/api:pr-42
      ghcr.io/my-org/worker:pr-42
  ```
  Only `ghcr.io` images are authenticated automatically (using `github.token`). Images from other registries must be public or authentication must be handled via `PRE_COMMAND`.
- **IMAGE_ARTIFACTS** loads images that were never pushed to a registry, using `kind load image-archive`. It accepts an exact artifact name or a glob pattern, matching the `pattern` input of `actions/download-artifact`:
  ```yaml
  with:
    IMAGE_ARTIFACTS: image-*-amd64
  ```
  This pairs with `build-docker.yml` used with `PUSH: false`, so a Helm deploy can be validated against the exact image a PR produces without publishing it first. The artifacts must come from the **same workflow run**. `IMAGE_ARTIFACTS` and `IMAGES` can be combined — for instance a locally built app image alongside published sidecars.

  The tarballs carry their own tag (`<IMAGE_NAME>:<IMAGE_TAG>` as built), so Helm values must reference that same tag. Set `imagePullPolicy: IfNotPresent` (or `Never`) in your values, otherwise the kubelet tries to pull the image from the registry and ignores the loaded copy.
- **KIND_CLUSTER_NAME** is passed both to the cluster creation step and to every `kind load` invocation. Override it only if you need a specific cluster name (e.g., a `KIND_CONFIG` or test script that references it by name).
- **HELM_PREREQS** is also newline-separated. Each line has the form `namespace release chart [helm_flags...]`. The first three fields are positional; everything after is passed directly to `helm upgrade --install`. Use native Helm flags such as `--repo`, `--values`, `--set`, `--version`, etc.:
  ```yaml
  with:
    HELM_PREREQS: |
      traefik traefik traefik --repo https://traefik.github.io/charts --values ./ci/kind/traefik-values.yml
      cnpg-system cloudnative-pg cloudnative-pg --repo https://cloudnative-pg.github.io/charts
  ```
  The `--repo` flag tells Helm to fetch the chart directly from the given URL — no separate repository registration step is needed.

- **HELM_CHART vs DEPLOY_COMMAND** are mutually exclusive. If `HELM_CHART` is set, the Helm deploy step runs and `DEPLOY_COMMAND` is ignored. If only `DEPLOY_COMMAND` is set, it runs instead. If neither is set, only cluster creation and image loading are performed (useful for debugging clusters).
- **DEPLOY_TIMEOUT** applies to the kubectl rollout wait step, which polls every deployment in every namespace. Set it high enough for slow-starting images (e.g., databases).
- **FAIL_ON_ERROR** set to `false` lets the workflow report test results without blocking your pipeline. The raw exit code is still visible in the step output.
- **PRE_COMMAND** and **TEST_COMMAND** and **DEPLOY_COMMAND** support multiline shell scripts via the caller's YAML pipe operator:
  ```yaml
  with:
    TEST_COMMAND: |
      kubectl wait --for=condition=ready pod -l app=api --timeout=60s
      curl -sf http://localhost/healthz
  ```
- **Cluster cleanup** runs unconditionally via `if: always()`, even when earlier steps fail, ensuring no leftover Kind clusters on the runner.
- **Show logs on failure** automatically dumps the last 50 lines of logs from non-`Running` pods when any step fails, making it easy to diagnose startup or crash errors without accessing the runner directly.
- Kind is installed automatically by `helm/kind-action`. No pre-installation is required on the runner beyond Docker (pre-installed on GitHub-hosted `ubuntu-*` runners).
- `FAIL_ON_ERROR` is enforced by an explicit gate step at the end of the job, not by `continue-on-error`. An expression there (<span v-pre>`${{ !inputs.FAIL_ON_ERROR }}`</span>) silently resolves to `true` even when the input is set, which makes the gate a no-op — the step fails, the job reports success, and the only trace is a `failure` annotation in the run summary. Reports, artifacts and cleanup still run before the gate fires.

## Examples

### Minimal — deploy a Helm chart

Bare-minimum invocation: pull and load one GHCR image, deploy a local Helm chart, and wait for rollout.

```yaml
jobs:
  deploy-test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-kube-deployment.yml@v0
    permissions:
      packages: read
      contents: read
    with:
      IMAGES: |
        ghcr.io/my-org/my-app:pr-${{ github.event.pull_request.number }}
      HELM_CHART: ./helm
      HELM_VALUES: ./ci/kind/helm-values.yaml
```

### Full — prereqs, custom Kind config, test command

Multi-image deployment with prerequisite charts (Traefik, CloudNativePG), a custom Kind cluster config, and an HTTP health-check as the validation step.

```yaml
jobs:
  deploy-test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-kube-deployment.yml@v0
    permissions:
      packages: read
      contents: read
    with:
      KIND_CONFIG: ./ci/kind/kind-config.yml
      IMAGES: |
        ghcr.io/my-org/api:pr-42
        ghcr.io/my-org/worker:pr-42
      HELM_PREREQS: |
        traefik traefik traefik --repo https://traefik.github.io/charts --values ./ci/kind/traefik-values.yml
        cnpg-system cloudnative-pg cloudnative-pg --repo https://cloudnative-pg.github.io/charts
      HELM_CHART: ./helm
      HELM_RELEASE: my-app
      HELM_VALUES: ./ci/kind/helm-values.prod.yaml
      HELM_ARGS: --set api.image.tag=pr-42 --set worker.image.tag=pr-42
      TEST_COMMAND: "curl -sf http://localhost/healthz"
```

### Deploy an image that was built but not pushed

Pair with `build-docker.yml` using `PUSH: false` to validate a real Helm deploy against the exact image a PR produces, without publishing anything. The build exports the image as a tarball artifact, which is loaded straight into the cluster with `kind load image-archive`.

Note `imagePullPolicy: IfNotPresent` in the Helm args — without it the kubelet tries to pull the tag from the registry and never uses the loaded image.

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
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: false
      BUILD_ARM64: false

  deploy-test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-kube-deployment.yml@v0
    needs:
    - build
    permissions:
      packages: read
      contents: read
    with:
      IMAGE_ARTIFACTS: ${{ needs.build.outputs.artifact-prefix }}-amd64
      HELM_CHART: ./helm
      HELM_VALUES: ./ci/kind/helm-values.yaml
      HELM_ARGS: >-
        --set image.tag=pr-${{ github.event.pull_request.number }}
        --set image.pullPolicy=IfNotPresent
      TEST_COMMAND: "curl -sf http://localhost/healthz"
```

For a monorepo building several images in a matrix, use a glob to load them all at once:

```yaml
with:
  IMAGE_ARTIFACTS: image-*-amd64
```

### Custom deploy (no Helm)

Use raw `kubectl apply` instead of Helm, then wait for pods to become ready.

```yaml
jobs:
  deploy-test:
    permissions:
      packages: read
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-kube-deployment.yml@v0
    with:
      DEPLOY_COMMAND: kubectl apply -f ./k8s/
      TEST_COMMAND: |
        kubectl wait --for=condition=ready pod -l app=my-app --timeout=120s
        kubectl get pods -A
```

### Non-blocking tests

Run smoke tests after deploy but do not block the pipeline on failure (useful for flaky integration tests that you want to observe without gating merges).

```yaml
jobs:
  deploy-test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-kube-deployment.yml@v0
    permissions:
      packages: read
      contents: read
    with:
      IMAGES: |
        ghcr.io/my-org/my-app:pr-${{ github.event.pull_request.number }}
      HELM_CHART: ./helm
      HELM_VALUES: ./ci/kind/helm-values.yaml
      TEST_COMMAND: "curl -sf http://localhost/healthz"
      FAIL_ON_ERROR: false
```
