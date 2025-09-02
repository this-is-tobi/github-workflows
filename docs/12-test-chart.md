# `test-helm.yml`

Test Helm charts by installing them in a Kubernetes cluster using `chart-testing`. Creates a temporary Kind cluster and attempts to install charts to verify they work correctly.

## Inputs

| Input        | Type   | Description                                  | Required | Default |
| ------------ | ------ | -------------------------------------------- | -------- | ------- |
| CT_CONF_PATH | string | Path to the chart-testing configuration file | Yes      | -       |

## Permissions

| Scope    | Access | Description                    |
| -------- | ------ | ------------------------------ |
| contents | read   | Read chart sources for testing |

## Notes

- Uses `helm/chart-testing-action` with `ct install` to test chart installations in a real Kubernetes environment.
- Creates a temporary Kind (Kubernetes in Docker) cluster using `helm/kind-action` for testing.
- Dynamically selects target branch: uses PR head branch (`github.head_ref`) when testing pull requests, otherwise falls back to repository default branch.
- Chart-testing configuration file defines which charts to test, dependencies, and installation parameters.
- Requires charts to have valid `values.yaml` and proper Kubernetes manifests that can be deployed.
- Consider adding integration tests or custom validation scripts in your chart-testing configuration.

## Examples

### Simple example

```yaml
jobs:
  test-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@main
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
