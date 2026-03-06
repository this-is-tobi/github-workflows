# `lint-js.yml`

Comprehensive JavaScript/TypeScript file linting using ESLint with automatic runtime and package manager detection. Supports Node.js and Bun runtimes with npm, pnpm, yarn, and bun package managers. Automatically sets up `@antfu/eslint-config` if no ESLint configuration exists.

## Inputs

| Input              | Type    | Description                                     | Required | Default                |
| ------------------ | ------- | ----------------------------------------------- | -------- | ---------------------- |
| RUNTIME_VERSION    | string  | Runtime version to use (Node.js or Bun version) | No       | "24"                   |
| PACKAGE_MANAGER    | string  | Package manager to use (npm, pnpm, yarn, bun)   | No       | "npm"                  |
| RUNTIME            | string  | JavaScript runtime to use (node, bun)           | No       | "node"                 |
| ESLINT_CONFIG      | string  | ESLint config package to use                    | No       | "@antfu/eslint-config" |
| WORKING_DIRECTORY  | string  | Working directory for the project               | No       | "."                    |
| LINT_PATHS         | string  | Paths to lint (space or comma-separated)        | No       | "."                    |
| ESLINT_CONFIG_FILE | string  | Path to custom ESLint config file               | No       | ""                     |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on linting errors  | No       | true                   |

## Permissions

| Scope    | Access | Description                   |
| -------- | ------ | ----------------------------- |
| contents | read   | Read source files for linting |

## Notes

- **Automatic Detection**: Intelligently detects package manager and runtime based on lock files and configuration files.
- **Multi-Runtime Support**: Works with Node.js and Bun runtimes.
- **Multi-Package Manager Support**: Supports npm, pnpm, yarn, and bun package managers.
- **Auto-Configuration**: Automatically installs and configures `@antfu/eslint-config` if no ESLint config exists.
- **File Type Support**: Lints JavaScript, TypeScript, JSON, JSONC, Markdown, and YAML files.
- **Package Manager Detection**: Looks for `bun.lockb`/`bun.lock` → uses Bun, `pnpm-lock.yaml` → uses pnpm, `yarn.lock` → uses Yarn, falls back to npm.
- **Runtime Detection**: Looks for Bun lock files → uses Bun, falls back to Node.js.
- **ESLint Config Detection**: Checks for existing ESLint config files, creates `eslint.config.js` with `@antfu/eslint-config` if none found.
- The workflow creates a temporary ESLint configuration using `@antfu/eslint-config` if no configuration is detected.
- The default configuration enables linting for JS, TS, JSON, JSONC, YAML, and Markdown files.
- Custom ESLint configurations take precedence over the auto-generated one.

## Examples

The following examples range from a zero-config invocation with automatic package detection to fully customised setups with alternative runtimes, custom ESLint configs, monorepo path overrides, and non-blocking mode.

### Simple example

Overrides auto-detection by pinning the runtime version and package manager explicitly. When no ESLint config is found in the project, `@antfu/eslint-config` is installed automatically and a temporary `eslint.config.js` is generated.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      RUNTIME_VERSION: "18"
      PACKAGE_MANAGER: "pnpm"
      LINT_PATHS: "src tests"
```

### Bun runtime

`RUNTIME: bun` and `PACKAGE_MANAGER: bun` should be set together for a consistent setup. Bun is detected automatically from lock files, but setting them explicitly avoids any ambiguity.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      RUNTIME: "bun"
      PACKAGE_MANAGER: "bun"
      LINT_PATHS: "src,tests,docs"
```

### Custom ESLint config

Installs `@company/eslint-config` instead of the default `@antfu/eslint-config`. The installed package is used as the base for the auto-generated `eslint.config.js`.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      ESLINT_CONFIG: "@company/eslint-config"
      LINT_PATHS: "apps packages"
```

### Monorepo with working directory

Runs two parallel lint jobs, each scoped to a separate package. Each job installs and lints independently within its `WORKING_DIRECTORY`, so different runtimes, package managers, or `LINT_PATHS` can be configured per package.

```yaml
jobs:
  lint-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      WORKING_DIRECTORY: "packages/frontend"
      LINT_PATHS: "src components"
      
  lint-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      WORKING_DIRECTORY: "packages/backend"
      PACKAGE_MANAGER: "pnpm"
      LINT_PATHS: "src,tests"
```

### Non-blocking linting

Reports all linting violations in the workflow summary without failing the job. Useful when gradually introducing linting rules into a project that already has pre-existing violations.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      FAIL_ON_ERROR: false
      LINT_PATHS: "src tests docs"
```

### Custom config file

Loads an existing ESLint config file from disk. When `ESLINT_CONFIG_FILE` is set, the auto-install of `ESLINT_CONFIG` is skipped and the file is used directly by the ESLint CLI.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    with:
      ESLINT_CONFIG_FILE: ".eslintrc.custom.js"
      LINT_PATHS: "apps,packages,tools"
```
