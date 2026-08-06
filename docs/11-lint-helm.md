# `lint-helm.yml`

Comprehensive Helm chart validation with two parallel jobs: chart structure linting using `chart-testing` and documentation validation using `helm-docs`. Ensures charts follow best practices and documentation stays current.

## Inputs

| Input             | Type    | Description                                                                              | Required | Default          |
| ----------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| HELM_DOCS_VERSION | string  | Version (image tag) of `jnorwood/helm-docs`                                              | No       | v1.14.2          |
| CT_CONF_PATH      | string  | Path to the chart-testing configuration file                                             | Yes      | -                |
| CHARTS_DIR        | string  | Directory scanned by `helm-docs` for the `lint-docs` job. Should match, or contain, the `chart-dirs` configured in `CT_CONF_PATH` - e.g. a chart's own directory for a monorepo with a single chart at its root. | No       | charts           |
| LINT_CHARTS       | boolean | Whether to run the chart linting job                                                     | No       | true             |
| LINT_DOCS         | boolean | Whether to run the chart docs linting job                                                | No       | true             |
| RUNS_ON           | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description               |
| -------- | ------ | ------------------------- |
| contents | read   | Read chart sources & docs |

## Notes

- **Two conditional jobs for flexible validation:**
  - **`lint-charts`**: Uses `helm/chart-testing-action` with `ct lint` to validate chart structure, syntax, dependencies, best practices, and version increment requirements. Runs only if `LINT_CHARTS=true`.
  - **`lint-docs`**: Uses `jnorwood/helm-docs` with a read-only volume mount of `CHARTS_DIR`. If committed documentation is out of date, helm-docs' attempt to regenerate files fails against the read-only mount, causing the job to fail. Runs only if `LINT_DOCS=true`.
- Set `LINT_CHARTS=false` to skip chart structure validation (useful for docs-only changes).
- Set `LINT_DOCS=false` to skip documentation validation (useful for chart logic changes without doc updates).
- Chart-testing requires a configuration file (typically `.github/ct.yaml`) to define linting rules, target branch, chart directories, and validation options.
- Jobs run independently when both are enabled; workflow succeeds if all enabled jobs pass.
- Consider pinning Docker images by digest for stronger supply-chain guarantees if stability is critical.
- When you modify `Chart.yaml`, `values.yaml`, or templates that affect documentation, regenerate the docs locally:
  ```bash
  docker run --rm \
    -v "$(pwd)/charts:/helm-docs" \
    -u $(id -u) \
    docker.io/jnorwood/helm-docs:v1.14.2
  ```
  Then review and commit the updated `README.md` under `charts/<chart-name>/`. After committing, the `lint-docs` job should pass again.

## Examples

The examples illustrate the three main usage modes: running both checks together, validating Helm documentation only, and linting charts only.

### Simple example

```yaml
jobs:
  lint-helm:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    permissions:
      contents: read
    with:
      HELM_DOCS_VERSION: v1.14.2
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

Skips `ct lint` entirely and only checks that `helm-docs` output matches committed documentation. Faster than the full lint pass and useful for PRs that only touch documentation.

```yaml
jobs:
  lint-helm-docs-only:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    permissions:
      contents: read
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: false
      LINT_DOCS: true
```

### Monorepo with a single chart at its root

For a chart living directly at e.g. `helm/Chart.yaml` rather than nested under `charts/<name>/`, point `CHARTS_DIR` at it and set `chart-dirs: [.]` in the chart-testing config so `ct lint` discovers it too.

```yaml
jobs:
  lint-helm:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    permissions:
      contents: read
    with:
      CT_CONF_PATH: .github/ct.yaml
      CHARTS_DIR: helm
```

### Charts-only validation

Runs `ct lint` for chart structure and schema validation but skips the `helm-docs` consistency check. Use this when making chart logic changes that do not affect documentation.

```yaml
jobs:
  lint-helm-charts-only:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    permissions:
      contents: read
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: true
      LINT_DOCS: false
```
