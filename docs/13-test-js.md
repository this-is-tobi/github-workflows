# `test-js.yml`

Comprehensive JavaScript/TypeScript test execution using Vitest with automatic runtime and package manager detection. Supports Node.js and Bun runtimes with npm, pnpm, yarn, and bun package managers. Automatically installs Vitest if not present in dependencies and test files are detected.

## Inputs

| Input                  | Type    | Description                                         | Required | Default             |
| ---------------------- | ------- | --------------------------------------------------- | -------- | ------------------- |
| RUNTIME_VERSION        | string  | Runtime version to use (Node.js or Bun version)     | No       | "22"                |
| PACKAGE_MANAGER        | string  | Package manager to use (npm, pnpm, yarn, bun)       | No       | "npm"               |
| RUNTIME                | string  | JavaScript runtime to use (node, bun)               | No       | "node"              |
| WORKING_DIRECTORY      | string  | Working directory for the project                   | No       | "."                 |
| TEST_COMMAND           | string  | Custom test command to run (defaults to vitest run) | No       | ""                  |
| COVERAGE               | boolean | Whether to collect test coverage                    | No       | false               |
| COVERAGE_REPORTER      | string  | Coverage reporter to use (text, lcov, html, json)   | No       | "text"              |
| COVERAGE_ARTIFACT_NAME | string  | Name of the coverage artifact                       | No       | unit-tests-coverage |
| COVERAGE_ARTIFACT_PATH | string  | Path where to download the coverage artifact        | No       | ./coverage          |
| FAIL_ON_ERROR          | boolean | Whether to fail the workflow on test failures       | No       | true                |
| TIMEOUT                | string  | Test timeout in milliseconds                        | No       | "60000"             |

## Permissions

| Scope    | Access | Description                 |
| -------- | ------ | --------------------------- |
| contents | read   | Read source files for tests |

## Notes

- **Automatic Detection**: Intelligently detects package manager and runtime based on lock files and configuration files.
- **Multi-Runtime Support**: Works with Node.js and Bun runtimes.
- **Multi-Package Manager Support**: Supports npm, pnpm, yarn, and bun package managers.
- **Test File Detection**: Automatically detects test files (*.test.*, *.spec.*) and test directories (test/, tests/, __tests__/).
- **Auto-Installation**: Automatically installs Vitest if not present in package.json but test files are found.
- **Coverage Support**: Optional test coverage collection with configurable reporters.
- **Flexible Test Commands**: Uses package.json test script if available, falls back to direct Vitest execution.
- **Smart Skipping**: Skips test execution gracefully when no test files are found.
- **Package Manager Detection**: Same logic as lint-js.yml - looks for lock files to determine the appropriate package manager.
- **Runtime Detection**: Detects Bun vs Node.js based on lock files and project configuration.

## Examples

### Simple example

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      RUNTIME_VERSION: "20"
      PACKAGE_MANAGER: "pnpm"
```

### With coverage

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      COVERAGE: true
      COVERAGE_REPORTER: "lcov"
      RUNTIME_VERSION: "18"
```

### Bun runtime

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      RUNTIME: "bun"
      PACKAGE_MANAGER: "bun"
      COVERAGE: true
```

### Custom test command

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      TEST_COMMAND: "npm run test:unit"
      TIMEOUT: "120000"
```

### Monorepo testing

```yaml
jobs:
  test-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      WORKING_DIRECTORY: "packages/frontend"
      COVERAGE: true
      COVERAGE_REPORTER: "text"
      
  test-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      WORKING_DIRECTORY: "packages/backend"
      PACKAGE_MANAGER: "pnpm"
      TIMEOUT: "180000"
```

### Non-blocking tests

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/test-js.yml@main
    with:
      FAIL_ON_ERROR: false
      COVERAGE: true
```
