# `test-playwright.yml`

Run end-to-end Playwright tests across a dynamic matrix of browsers. Handles JavaScript runtime installation (Node.js or Bun), system browser setup (Chrome, Firefox, Edge), dependency caching, and failure artifact collection. Each browser runs in its own parallel job.

## Inputs

| Input              | Type    | Description                                                                                      | Required | Default                                  |
| ------------------ | ------- | ------------------------------------------------------------------------------------------------ | -------- | ---------------------------------------- |
| BROWSERS           | string  | Comma-separated browsers to test (`chrome`, `firefox`, `edge`, `electron`)                       | No       | `chrome`                                 |
| RUNTIME            | string  | JavaScript runtime to use (`node` or `bun`)                                                      | No       | `node`                                   |
| RUNTIME_VERSION    | string  | Runtime version to install                                                                       | No       | `24`                                     |
| PACKAGE_MANAGER    | string  | Package manager to use (`npm`, `yarn`, `pnpm`, `bun`)                                            | No       | `npm`                                    |
| WORKING_DIRECTORY  | string  | Working directory for running commands                                                           | No       | `.`                                      |
| PRE_COMMAND        | string  | Shell command to run before tests (e.g., env setup, build)                                       | No       | -                                        |
| TEST_COMMAND       | string  | Shell command for running Playwright tests. The `$BROWSER` env var contains the current browser. | No       | `npx playwright test --project=$BROWSER` |
| ARTIFACT_PATH      | string  | Path to upload as artifact on failure (e.g., `test-results/`, `screenshots/`)                    | No       | -                                        |
| ARTIFACT_RETENTION | number  | Number of days to keep failure artifacts                                                         | No       | `14`                                     |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on test errors                                                      | No       | `true`                                   |
| RUNS_ON            | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)         | No       | `["ubuntu-24.04"]`                       |

## Permissions

| Scope    | Access | Description                     |
| -------- | ------ | ------------------------------- |
| contents | read   | Checkout repository source code |

## Notes

- **Browser matrix** — the `BROWSERS` input is split by comma into a dynamic GitHub Actions matrix. Each browser becomes a separate parallel job named `E2E tests (<browser>)`.

- **`$BROWSER` env var** — set automatically for each matrix job. Reference it directly in `TEST_COMMAND`:
  ```yaml
  with:
    TEST_COMMAND: "npx playwright test --project=$BROWSER"
  ```

- **System browsers vs bundled** — Chrome, Firefox, and Edge are provisioned as system browsers via the `browser-actions/setup-*` actions. This avoids downloading Playwright's bundled browser binaries (faster CI). Your Playwright config should use system [channels](https://playwright.dev/docs/browsers#google-chrome--microsoft-edge):
  ```ts
  // playwright.config.ts
  projects: [
    { name: 'chrome', use: { channel: 'chrome' } },
    { name: 'firefox', use: { channel: 'firefox' } },
  ]
  ```
  If you prefer bundled browsers instead, add `npx playwright install --with-deps` in `PRE_COMMAND` and omit the matching browser from `BROWSERS`.

- **`electron` browser** — no system setup action runs for Electron. Ensure Electron is available via your project dependencies or `PRE_COMMAND`.

- **Artifacts** are uploaded **only on failure** to avoid storage waste. Set `ARTIFACT_PATH` to the directory Playwright writes reports/screenshots to. Each browser gets its own artifact named `playwright-report-<browser>`.

- **`pnpm` support** — if `PACKAGE_MANAGER` is `pnpm`, the `pnpm/action-setup` action is run automatically before dependency installation.

- **PRE_COMMAND** runs after dependency installation and before tests. Use it for build steps, environment setup scripts, or `npx playwright install --with-deps` for bundled browsers.

- **FAIL_ON_ERROR** set to `false` allows tests to report results without blocking the pipeline. The step outcome is still visible in the Actions UI.

## Examples

### Minimal — single browser

Runs Playwright tests against Chrome using the default Node.js runtime. No artifacts uploaded unless you set `ARTIFACT_PATH`.

```yaml
jobs:
  e2e-tests:
    permissions:
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-playwright.yml@v0
```

### Multi-browser with artifacts

Tests against Chrome and Firefox in parallel. On failure, Playwright reports are uploaded and retained for 7 days.

```yaml
jobs:
  e2e-tests:
    permissions:
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-playwright.yml@v0
    with:
      BROWSERS: "chrome,firefox"
      ARTIFACT_PATH: ./test-results/
      ARTIFACT_RETENTION: 7
```

### Bun runtime with custom test command

Uses Bun as both the runtime and package manager. The `$BROWSER` variable is injected automatically.

```yaml
jobs:
  e2e-tests:
    permissions:
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-playwright.yml@v0
    with:
      RUNTIME: bun
      RUNTIME_VERSION: "1.3.10"
      PACKAGE_MANAGER: bun
      BROWSERS: "chrome,firefox"
      PRE_COMMAND: "bun run build"
      TEST_COMMAND: "bun run test:e2e -- --project=$BROWSER"
      ARTIFACT_PATH: ./test-results/
```

### Monorepo — app-specific tests

Restrict execution to a sub-package via `WORKING_DIRECTORY`. Combine with a build step in `PRE_COMMAND`.

```yaml
jobs:
  e2e-tests:
    permissions:
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-playwright.yml@v0
    with:
      RUNTIME: bun
      PACKAGE_MANAGER: bun
      WORKING_DIRECTORY: packages/frontend
      BROWSERS: "chrome,firefox"
      PRE_COMMAND: "bun run build"
      TEST_COMMAND: "bun run test:e2e -- --project=$BROWSER"
      ARTIFACT_PATH: ./packages/frontend/test-results/
```

### Non-blocking tests

Run E2E tests without gating the pipeline. Failures are visible in the Actions UI but don't block merges.

```yaml
jobs:
  e2e-tests:
    permissions:
      contents: read
    uses: this-is-tobi/github-workflows/.github/workflows/test-playwright.yml@v0
    with:
      BROWSERS: "chrome,firefox"
      TEST_COMMAND: "npx playwright test --project=$BROWSER"
      FAIL_ON_ERROR: false
```
