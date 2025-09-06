# `lint-helm.yml`

Comprehensive Helm chart validation with two parallel jobs: chart structure linting using `chart-testing` and documentation validation using `helm-docs`. Ensures charts follow best practices and documentation stays current.

## Inputs

| Input             | Type    | Description                                  | Required | Default |
| ----------------- | ------- | -------------------------------------------- | -------- | ------- |
| HELM_DOCS_VERSION | string  | Version (image tag) of `jnorwood/helm-docs`  | No       | 1.14.2  |
| CT_CONF_PATH      | string  | Path to the chart-testing configuration file | Yes      | -       |
| LINT_CHARTS       | boolean | Whether to run the chart linting job         | No       | true    |
| LINT_DOCS         | boolean | Whether to run the chart docs linting job    | No       | true    |

## Permissions

| Scope    | Access | Description               |
| -------- | ------ | ------------------------- |
| contents | read   | Read chart sources & docs |

## Notes

- **Two conditional jobs for flexible validation:**
  - **`lint-charts`**: Uses `helm/chart-testing-action` with `ct lint` to validate chart structure, syntax, dependencies, best practices, and version increment requirements. Runs only if `LINT_CHARTS=true`.
  - **`lint-docs`**: Uses `jnorwood/helm-docs` with `--validate` flag to ensure documentation matches current chart configuration without making changes. Runs only if `LINT_DOCS=true`.
- Set `LINT_CHARTS=false` to skip chart structure validation (useful for docs-only changes).
- Set `LINT_DOCS=false` to skip documentation validation (useful for chart logic changes without doc updates).
- Chart-testing requires a configuration file (typically `.github/ct.yaml`) to define linting rules, target branch, chart directories, and validation options.
- Documentation validation mounts `./charts` read-only and exits non-zero if generated docs would differ from committed files.
- Jobs run independently when both are enabled; workflow succeeds if all enabled jobs pass.
- Consider pinning Docker images by digest for stronger supply-chain guarantees if stability is critical.
- When you modify `Chart.yaml`, `values.yaml`, or templates that affect documentation, regenerate the docs locally:
  ```bash
  docker run --rm \
    -v "$(pwd)/charts:/helm-docs" \
    -u $(id -u) \
    docker.io/jnorwood/helm-docs:1.14.2
  ```
  Then review and commit the updated `README.md` under `charts/<chart-name>/`. After committing, the `lint-docs` job should pass again.

## Examples

### Simple example

```yaml
jobs:
  lint-helm:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/lint-helm.yml@main
    with:
      HELM_DOCS_VERSION: 1.14.2
      CT_CONF_PATH: .github/ct.yaml
```

Example chart-testing configuration (`.github/ct.yaml`):

```yaml
# See https://github.com/helm/chart-testing/blob/main/doc/ct_lint.md
target-branch: main
chart-dirs:
  - charts
helm-extra-args: --timeout 600s
check-version-increment: true
validate-maintainers: false
excluded-charts:
  - unstable-chart
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
```

### Docs-only validation

```yaml
jobs:
  lint-helm-docs-only:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/lint-helm.yml@main
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: false
      LINT_DOCS: true
```

### Charts-only validation

```yaml
jobs:
  lint-helm-charts-only:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/lint-helm.yml@main
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: true
      LINT_DOCS: false
```
