# `test-vitest.yml`

Comprehensive JavaScript/TypeScript test execution using Vitest with automatic runtime and package manager detection. Supports Node.js and Bun runtimes with npm, pnpm, yarn, and bun package managers. Skips the test job gracefully when Vitest is not listed as a dependency.

## Inputs

| Input                  | Type    | Description                                                                              | Required | Default             |
| ---------------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ------------------- |
| RUNTIME_VERSION        | string  | Runtime version to use. Empty resolves to a per-runtime default (Node.js 24, Bun latest) | No       | ""                  |
| PACKAGE_MANAGER        | string  | Package manager (npm, pnpm, yarn, bun). Empty auto-detects                               | No       | ""                  |
| RUNTIME                | string  | JavaScript runtime (node, bun). Empty auto-detects                                       | No       | ""                  |
| WORKING_DIRECTORY      | string  | Working directory for the project                                                        | No       | "."                 |
| TEST_COMMAND           | string  | Custom test command to run (defaults to vitest run)                                      | No       | ""                  |
| TEST_PRECOMMAND        | string  | Custom command to run before tests (e.g. build)                                          | No       | ""                  |
| COVERAGE               | boolean | Whether to collect test coverage                                                         | No       | false               |
| COVERAGE_REPORTER      | string  | Coverage reporter to use (text, lcov, html, json)                                        | No       | "text"              |
| COVERAGE_ARTIFACT_NAME | string  | Name of the coverage artifact                                                            | No       | unit-tests-coverage |
| COVERAGE_ARTIFACT_PATH | string  | Path where to download the coverage artifact                                             | No       | ./coverage          |
| FAIL_ON_ERROR          | boolean | Whether to fail the workflow on test failures                                            | No       | true                |
| TIMEOUT                | string  | Test timeout in milliseconds                                                             | No       | "60000"             |

## Permissions

| Scope    | Access | Description                 |
| -------- | ------ | --------------------------- |
| contents | read   | Read source files for tests |

## Notes

- **Automatic Detection**: Intelligently detects package manager and runtime based on lock files and configuration files.
- **Multi-Runtime Support**: Works with Node.js and Bun runtimes.
- **Multi-Package Manager Support**: Supports npm, pnpm, yarn, and bun package managers.
- **Test File Detection**: Automatically detects test files (*.test.*, *.spec.*) and test directories (test/, tests/, __tests__/).
- **Vitest Requirement**: Skips test execution gracefully when Vitest is not listed as a dependency in package.json.
- **Coverage Support**: Optional test coverage collection with configurable reporters.
- **Flexible Test Commands**: Uses package.json test script if available, falls back to direct Vitest execution.
- **Package Manager Detection** (same logic as `lint-js.yml`, à la [`@antfu/ni`](https://github.com/antfu-collective/ni)): explicit input wins, else the corepack `packageManager` field, then lock files, then npm. Yarn Berry (`.yarnrc.yml`) installs with `--immutable`, classic with `--frozen-lockfile`.
- **Runtime Detection**: explicit input wins, else Bun when the detected package manager or a bun lock file says so, else Node.js.
- **Coverage inputs apply to direct Vitest invocation only**: The `COVERAGE`, `COVERAGE_REPORTER`, and `TIMEOUT` inputs only take effect when the workflow invokes Vitest directly (i.e. when `package.json` has no `test` script). If `package.json` defines a `test` script, the workflow runs that script instead and these inputs are ignored.

## Examples

The following examples range from a minimal invocation to customised setups covering coverage upload, alternative runtimes, custom test commands, monorepo paths, and non-blocking mode.

### Simple example

Auto-detects Vitest, the runtime, and the package manager from project files — a typical call needs no `with:` block at all. Pin `RUNTIME`/`PACKAGE_MANAGER`/`RUNTIME_VERSION` only to override detection or lock a specific version.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
```

### With coverage

`COVERAGE: true` runs Vitest with the `--coverage` flag and uploads the report as a GitHub Actions artifact. The default artifact name `unit-tests-coverage` matches the expected input of `scan-sonarqube.yml`, making the two workflows easy to chain.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      COVERAGE: true
      COVERAGE_REPORTER: lcov
      RUNTIME_VERSION: "18"
```

### Bun runtime

Sets the runtime and package manager to Bun for faster installs and test runs. Coverage collection remains available via `COVERAGE: true`.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      RUNTIME: bun
      PACKAGE_MANAGER: bun
      COVERAGE: true
```

### Custom test command

`TEST_COMMAND` replaces the default `vitest run` invocation entirely — any shell command is accepted. `TIMEOUT` controls the per-test timeout in milliseconds passed to Vitest.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      TEST_COMMAND: "npm run test:unit"
      TIMEOUT: "120000"
```

### Monorepo testing

One job per package in parallel, each scoped to its own `WORKING_DIRECTORY` with its own timeout or coverage settings. A monorepo uses a **single** package manager, so both jobs pin the same one (`pnpm` here).

```yaml
jobs:
  test-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: packages/frontend
      PACKAGE_MANAGER: pnpm
      COVERAGE: true
      COVERAGE_REPORTER: text

  test-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: packages/backend
      PACKAGE_MANAGER: pnpm
      TIMEOUT: "180000"
```

> `PACKAGE_MANAGER` is set explicitly because detection only inspects the job's `WORKING_DIRECTORY`, and in a workspace monorepo the lock file lives at the repository root — a sub-directory has nothing to detect. A single job at the root (`WORKING_DIRECTORY: .`) that tests every package avoids this — see the [monorepo CI example](./90-global-workflows-examples.md#monorepo-app).

### Non-blocking tests

The job always succeeds even when tests fail, but coverage is still collected and uploaded. Useful when introducing a test suite into an existing project with known failures.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      FAIL_ON_ERROR: false
      COVERAGE: true
      COVERAGE_REPORTER: lcov
```
