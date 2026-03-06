# `lint-helm-schema.yml`

Validate Helm chart values files against a JSON schema using `check-jsonschema`. Ensures that `values.yaml` and any additional values files conform to the chart's declared schema.

## Inputs

| Input        | Type   | Description                                                                                                                                          | Required | Default            |
| ------------ | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------ |
| CHART_PATH   | string | Path to the Helm chart directory containing the JSON schema                                                                                          | Yes      | -                  |
| SCHEMA_FILE  | string | JSON schema filename relative to `CHART_PATH`                                                                                                        | No       | values.schema.json |
| VALUES_FILES | string | Comma-separated list of values files to validate against the schema, relative to `CHART_PATH` (e.g., `values.yaml,test-values.yaml,values/dev.yaml`) | No       | values.yaml        |
| RUNS_ON      | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                             | No       | ["ubuntu-24.04"]   |

## Permissions

| Scope    | Access | Description        |
| -------- | ------ | ------------------ |
| contents | read   | Read chart sources |

## Notes

- Uses `check-jsonschema` (installed via pip) to validate values files against the chart's JSON schema.
- Fails if the schema file (`SCHEMA_FILE`) does not exist under `CHART_PATH`.
- Skips individual values files that are not found (with a warning) rather than failing, unless no files remain to validate.
- Multiple values files can be validated in a single run by providing a comma-separated list in `VALUES_FILES`.
- Useful to catch values that do not match the expected structure before deploying.

## Examples

The examples show validating a chart with a single values file, providing multiple values files for broader schema coverage, and using a custom JSON schema instead of the default `values.schema.json`.

### Simple example

Validates `values.yaml` against `values.schema.json` in `charts/my-chart`. Fails immediately if the schema file does not exist or if any value does not conform to its declared type or constraint.

```yaml
jobs:
  lint-helm-schema:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm-schema.yml@main
    with:
      CHART_PATH: charts/my-chart
```

### Multiple values files

Validates three values files in a single run — useful for projects with per-environment overrides. Files that are not found are skipped with a warning rather than a hard failure.

```yaml
jobs:
  lint-helm-schema:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm-schema.yml@main
    with:
      CHART_PATH: charts/my-chart
      VALUES_FILES: "values.yaml,values/dev.yaml,values/prod.yaml"
```

### Custom schema file

Uses `custom-schema.json` instead of the default `values.schema.json`. Useful when a non-standard naming convention is in use, or to apply a specific schema to a subset of values files.

```yaml
jobs:
  lint-helm-schema:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm-schema.yml@main
    with:
      CHART_PATH: charts/my-chart
      SCHEMA_FILE: custom-schema.json
      VALUES_FILES: "values.yaml,ci-values.yaml"
```
