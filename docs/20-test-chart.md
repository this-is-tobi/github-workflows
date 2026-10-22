# `test-helm.yml`

Test Helm charts by installing them in a Kubernetes cluster using `chart-testing`. Creates a temporary Kind cluster and attempts to install charts to verify they work correctly. The cluster is only created when `chart-testing` has a chart to install.

## Inputs

| Input        | Type   | Description                                                                              | Required | Default          |
| ------------ | ------ | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| CT_CONF_PATH | string | Path to the chart-testing configuration file                                             | Yes      | -                |
| RUNS_ON      | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description                    |
| -------- | ------ | ------------------------------ |
| contents | read   | Read chart sources for testing |

## Notes

- Uses `helm/chart-testing-action` with `ct install` to test chart installations in a real Kubernetes environment.
- Creates a temporary Kind (Kubernetes in Docker) cluster using `helm/kind-action` for testing.
- **A run that changes no chart creates no cluster.** The cluster is most of the job (about 40 of 56 seconds), and a caller's path filter is usually wider than the chart directories `ct` looks at (`ci/`, `template/`, the workflows), so such runs are common. `ct list-changed` is asked first, with the same configuration and target branch as the install; when it reports nothing, the job ends with a notice and no cluster. A configuration that sets `charts:` or `all: true` always installs, since `ct install` then processes those charts whether or not they changed and `ct list-changed` does not say so.
- The target branch `ct install` diffs against is the branch the pull request merges into (`github.base_ref`), falling back to the repository's default branch outside a pull request. `ct` installs only the charts that differ from it, so the pull request's own branch would diff to nothing and install nothing.
- Chart-testing configuration file defines which charts to test, dependencies, and installation parameters.
- Requires charts to have valid `values.yaml` and proper Kubernetes manifests that can be deployed.
- Consider adding integration tests or custom validation scripts in your chart-testing configuration.

## Examples

The example shows the most common invocation, pointing to a custom `ct.yaml` configuration file for chart-testing settings.

### Simple example

Points to a `ct.yaml` that controls which charts are installed, their dependencies, timeouts, and whether a version increment is required. A Kind cluster is created automatically for each run and torn down afterwards.

```yaml
jobs:
  test-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@v0
    permissions:
      contents: read
    with:
      CT_CONF_PATH: .github/ct.yaml
```

Example chart-testing configuration for testing (`.github/ct.yaml`):

```yaml
# See https://github.com/helm/chart-testing/blob/main/doc/ct_install.md
target-branch: main
chart-dirs:
  - charts
helm-extra-args: --timeout 600s
check-version-increment: false  # Usually false for install testing
validate-maintainers: false
excluded-charts:
  - unstable-chart
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
```
