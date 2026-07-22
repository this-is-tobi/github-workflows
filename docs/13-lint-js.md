# `lint-js.yml`

Comprehensive JavaScript/TypeScript file linting using ESLint with automatic runtime and package manager detection. Supports Node.js and Bun runtimes with npm, pnpm, yarn, and bun package managers. Automatically sets up `@antfu/eslint-config` if no ESLint configuration exists.

## Inputs

| Input              | Type    | Description                                                                              | Required | Default                |
| ------------------ | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUNTIME_VERSION    | string  | Runtime version to use. Empty resolves to a per-runtime default (Node.js 24, Bun latest) | No       | ""                     |
| PACKAGE_MANAGER    | string  | Package manager (npm, pnpm, yarn, bun). Empty auto-detects                               | No       | ""                     |
| RUNTIME            | string  | JavaScript runtime (node, bun). Empty auto-detects                                       | No       | ""                     |
| ESLINT_CONFIG      | string  | ESLint config package to use                                                             | No       | "@antfu/eslint-config" |
| WORKING_DIRECTORY  | string  | Working directory for the project                                                        | No       | "."                    |
| LINT_PATHS         | string  | Paths to lint (comma- or space-separated)                                                | No       | "."                    |
| ESLINT_CONFIG_FILE | string  | Path to custom ESLint config file                                                        | No       | ""                     |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on linting errors                                           | No       | true                   |

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
- **Package Manager Detection** (à la [`@antfu/ni`](https://github.com/antfu-collective/ni)): an explicit `PACKAGE_MANAGER` wins; otherwise the workflow walks upward from `WORKING_DIRECTORY` to the checkout root — the same resolution npm/pnpm/yarn/bun workspaces themselves use — checking at each level for the corepack `packageManager` field in `package.json` first, then lock files (`bun.lockb`/`bun.lock` → Bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → Yarn, `package-lock.json` → npm). The closest directory with a signal wins, falling back to npm if nothing is found anywhere up to the root. This means a job scoped to a monorepo sub-package (`WORKING_DIRECTORY: packages/frontend`) still detects the package manager from the workspace root's lock file.
- **Runtime Detection**: an explicit `RUNTIME` wins; otherwise Bun when the detected package manager is bun, else Node.js.
- **Yarn Berry**: when a `.yarnrc.yml` is present the install uses `--immutable`; classic Yarn uses `--frozen-lockfile`.
- **ESLint Config Detection**: Checks for existing ESLint config files, creates `eslint.config.js` with `@antfu/eslint-config` if none found.
- The workflow creates a temporary ESLint configuration using `@antfu/eslint-config` if no configuration is detected.
- The default configuration enables linting for JS, TS, JSON, JSONC, YAML, and Markdown files.
- Custom ESLint configurations take precedence over the auto-generated one.
- **ESLINT_CONFIG must be antfu-compatible**: When no ESLint config exists, the workflow auto-generates an `eslint.config.js` that imports the package specified by `ESLINT_CONFIG` (defaulting to `@antfu/eslint-config`) as the `antfu` export and passes antfu-specific options. A non-antfu-compatible config package passed via `ESLINT_CONFIG` would fail to load.

## Examples

The following examples range from a zero-config invocation with automatic package detection to fully customised setups with alternative runtimes, custom ESLint configs, monorepo path overrides, and non-blocking mode.

### Simple example

The runtime and package manager are auto-detected, so a typical call only sets what to lint. When no ESLint config is found in the project, `@antfu/eslint-config` is installed automatically and a temporary `eslint.config.js` is generated.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      LINT_PATHS: src tests
```

### Pinning the runtime and package manager

Detection covers most repositories; pin `RUNTIME`/`PACKAGE_MANAGER`/`RUNTIME_VERSION` only to override it — for example to force a specific Node version, or when no lock file is committed for detection to read.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      RUNTIME: bun
      PACKAGE_MANAGER: bun
      RUNTIME_VERSION: 1.3.10
      LINT_PATHS: "src,tests,docs"
```

### Custom ESLint config

Installs `@company/eslint-config` instead of the default `@antfu/eslint-config`. The installed package is used as the base for the auto-generated `eslint.config.js`.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      ESLINT_CONFIG: "@company/eslint-config"
      LINT_PATHS: apps packages
```

### Monorepo with working directory

Runs one lint job per package in parallel, each scoped to its own `WORKING_DIRECTORY` and `LINT_PATHS`. Neither job sets `PACKAGE_MANAGER`: detection walks up from `packages/frontend`/`packages/backend` to the repository root and finds the single lock file that a monorepo's workspace keeps there.

```yaml
jobs:
  lint-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: packages/frontend
      LINT_PATHS: src components

  lint-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: packages/backend
      LINT_PATHS: "src,tests"
```

> Pin `PACKAGE_MANAGER` explicitly only if a sub-package genuinely uses a different package manager than the rest of the repository (uncommon), or ships its own lock file that should take precedence over the workspace root's. An even simpler alternative for most monorepos is a single job at the root (`WORKING_DIRECTORY: .`) that lints every package in one pass — see the [monorepo CI example](./90-global-workflows-examples.md#monorepo-app).

### Non-blocking linting

Reports all linting violations in the workflow summary without failing the job. Useful when gradually introducing linting rules into a project that already has pre-existing violations.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      FAIL_ON_ERROR: false
      LINT_PATHS: src tests docs
```

### Custom config file

Loads an existing ESLint config file from disk. When `ESLINT_CONFIG_FILE` is set, the auto-install of `ESLINT_CONFIG` is skipped and the file is used directly by the ESLint CLI.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      ESLINT_CONFIG_FILE: .eslintrc.custom.js
      LINT_PATHS: "apps,packages,tools"
```
