# `test-kube-deployment.yml`

Test Kubernetes deployments in an ephemeral [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker) cluster. Creates the cluster, optionally pulls and loads container images from GHCR, installs prerequisite Helm charts, deploys the application via Helm or a custom command, waits for all rollouts to complete, runs a validation command, shows cluster state on failure, and always cleans up the cluster — even on error.

## Inputs

| Input          | Type    | Description                                                                                                                       | Required | Default            |
| -------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------ |
| KIND_VERSION   | string  | Kind version to install                                                                                                           | No       | `0.27.0`           |
| KIND_CONFIG    | string  | Path to a Kind cluster configuration file (relative to repo root)                                                                 | No       | -                  |
| IMAGES         | string  | Newline-separated container images to pull and load into the Kind cluster. GHCR images are authenticated automatically.           | No       | -                  |
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

- **IMAGES** is newline-separated. Pass a YAML literal block scalar (`|`) in the caller:
  ```yaml
  with:
    IMAGES: |
      ghcr.io/my-org/api:pr-42
      ghcr.io/my-org/worker:pr-42
  ```
  Only `ghcr.io` images are authenticated automatically (using `github.token`). Images from other registries must be public or authentication must be handled via `PRE_COMMAND`.
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
      HELM_ARGS: "--set api.image.tag=pr-42 --set worker.image.tag=pr-42"
      TEST_COMMAND: "curl -sf http://localhost/healthz"
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
      DEPLOY_COMMAND: "kubectl apply -f ./k8s/"
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
