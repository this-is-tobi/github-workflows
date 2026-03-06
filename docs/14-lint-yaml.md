# `lint-yaml.yml`

Lint YAML files using `yamllint`. Scans a configurable path for YAML files and reports style or syntax issues, with optional strict mode to treat warnings as errors.

## Inputs

| Input       | Type    | Description                                                                              | Required | Default          |
| ----------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| CONFIG_FILE | string  | Path to a `yamllint` configuration file (uses `yamllint` default config when omitted)    | No       | ""               |
| SCAN_PATH   | string  | Path to scan for YAML files                                                              | No       | .                |
| STRICT      | boolean | Whether to use strict mode (treats warnings as errors)                                   | No       | false            |
| RUNS_ON     | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description            |
| -------- | ------ | ---------------------- |
| contents | read   | Read YAML source files |

## Notes

- Uses `yamllint` (installed via pip) for YAML linting.
- When `CONFIG_FILE` is provided and the file exists, it is passed via `--config-file`; otherwise `yamllint` uses its built-in default rules.
- `STRICT: true` adds `--strict` to the `yamllint` invocation, causing warnings to be treated as errors.
- Scans the path specified by `SCAN_PATH` (defaults to the repository root `.`).

## Examples

The examples cover the default scan over the entire repository, restricting the scan to a specific path with strict mode enabled, and using a custom yamllint configuration file.

### Simple example

Scans all YAML files in the repository root with yamllint's built-in default rules. No configuration file is required.

```yaml
jobs:
  lint-yaml:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-yaml.yml@v0
```

### Custom scan path with strict mode

`SCAN_PATH: "./charts"` restricts the scan to Helm chart YAML only. `STRICT: true` promotes warnings to errors, enforcing a stricter style standard for chart files.

```yaml
jobs:
  lint-yaml:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-yaml.yml@v0
    with:
      SCAN_PATH: "./charts"
      STRICT: true
```

### With custom config file

Loads project-specific yamllint rules (e.g. indentation width, line length). `STRICT: false` keeps warnings as non-blocking informational messages.

```yaml
jobs:
  lint-yaml:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-yaml.yml@v0
    with:
      CONFIG_FILE: ".yamllint.yml"
      SCAN_PATH: "."
      STRICT: false
```
