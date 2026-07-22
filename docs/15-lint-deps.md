# `lint-deps.yml`

Run dependency and package-hygiene checks with the same setup ergonomics as [`lint-js.yml`](./13-lint-js.md). It auto-detects the runtime and package manager, wires up the install step, then runs whatever check commands you pass — typically [`knip`](https://knip.dev) (unused files, dependencies and exports) and [`publint`](https://publint.dev) (package manifest correctness).

The workflow is **command-driven**: it never installs the checkers itself. Your repository owns `knip`/`publint` as pinned devDependencies, so versions stay reproducible and the workflow works with any monorepo orchestrator (turbo, nx, plain scripts). An empty command **skips** that check, so a repo can run only knip, only publint, or both.

## Inputs

| Input             | Type    | Description                                                                                                | Required | Default |
| ----------------- | ------- | ---------------------------------------------------------------------------------------------------------- | -------- | ------- |
| RUNTIME           | string  | JavaScript runtime to use (node, bun). Empty auto-detects from lock files                                  | No       | ""      |
| RUNTIME_VERSION   | string  | Runtime version to use. Empty resolves to a per-runtime default (Node.js 24, Bun latest)                   | No       | ""      |
| PACKAGE_MANAGER   | string  | Package manager (npm, pnpm, yarn, bun). Empty auto-detects from the `packageManager` field and lock files  | No       | ""      |
| WORKING_DIRECTORY | string  | Working directory for the project                                                                          | No       | "."     |
| INSTALL_COMMAND   | string  | Override install command. Empty uses the package manager's default (`npm ci`, `pnpm`/`yarn`/`bun` install) | No       | ""      |
| PRE_COMMAND       | string  | Command to run before the checks (e.g. a build so publint can inspect `dist`/types). Skipped if empty      | No       | ""      |
| KNIP_COMMAND      | string  | Command to run knip (unused files/deps/exports). Skipped if empty                                          | No       | ""      |
| PUBLINT_COMMAND   | string  | Command to run publint (package manifest correctness). Skipped if empty                                    | No       | ""      |
| FAIL_ON_ERROR     | boolean | Whether to fail the workflow when a check reports errors                                                   | No       | true    |

## Permissions

| Scope    | Access | Description                     |
| -------- | ------ | ------------------------------- |
| contents | read   | Read source files and manifests |

## Notes

- **Auto-detection** (à la [`@antfu/ni`](https://github.com/antfu-collective/ni)): when `PACKAGE_MANAGER`/`RUNTIME` are empty, the package manager is resolved from the corepack `packageManager` field in `package.json` first, then lock files (`bun.lock`/`bun.lockb` → bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn), falling back to npm; the runtime resolves to Bun when the package manager or a lock file says so, else Node.js. Set the inputs explicitly to override. Yarn Berry (`.yarnrc.yml`) installs with `--immutable`, classic with `--frozen-lockfile`.
- **Command-driven, not tool-pinned**: the workflow never installs knip/publint — the consumer's repo owns those as pinned devDependencies, so versions stay reproducible and the workflow works with any monorepo orchestrator.
- **Empty command = skip**: leave `KNIP_COMMAND` or `PUBLINT_COMMAND` empty to run only the other one. Passing neither runs install (and any `PRE_COMMAND`) and nothing else.
- **publint needs a build**: publint inspects the published `dist`/types. Either point `PUBLINT_COMMAND` at a task that builds first (e.g. a turbo target with `dependsOn: [build]`) or pass `PRE_COMMAND: <build>` so the artifacts exist before the check runs.
- **FAIL_ON_ERROR**: when `false`, a failing check is reported as a non-blocking step (via `continue-on-error`) instead of failing the job — useful while adopting a checker on a codebase with pre-existing findings.
- **Mirrors `lint-js.yml`**: same pinned action SHAs and the same `RUNTIME`/`RUNTIME_VERSION`/`PACKAGE_MANAGER`/`WORKING_DIRECTORY`/`FAIL_ON_ERROR` inputs, so callers configure it the same way.
- **Extensible**: the same command-driven shape extends to other hygiene tools — add a `PRE_COMMAND`/extra step for tools like `sherif` (monorepo version consistency) or `are-the-types-wrong` (type resolution).

## Examples

The examples range from a minimal both-checks invocation to running a single checker, building before publint, monorepo working directories, and non-blocking mode.

### Simple example

Runs both knip and publint with a Bun runtime. The checkers resolve from the repository's own devDependencies.

```yaml
jobs:
  lint-deps:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      RUNTIME: bun
      PACKAGE_MANAGER: bun
      KNIP_COMMAND: bun run knip
      PUBLINT_COMMAND: bun run publint
```

### knip only

Leaving `PUBLINT_COMMAND` empty skips publint, so only the unused-code check runs.

```yaml
jobs:
  lint-deps:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      KNIP_COMMAND: npx knip
```

### Build before publint

publint inspects the built package. Use `PRE_COMMAND` to build first when the publint task does not build on its own.

```yaml
jobs:
  lint-deps:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      PACKAGE_MANAGER: pnpm
      PRE_COMMAND: pnpm run build
      PUBLINT_COMMAND: pnpm exec publint
```

### Monorepo with working directory

Runs the checks scoped to a single package. Each job installs and checks independently within its `WORKING_DIRECTORY`.

```yaml
jobs:
  lint-deps-api:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: apps/api
      PACKAGE_MANAGER: pnpm
      KNIP_COMMAND: pnpm exec knip
      PUBLINT_COMMAND: pnpm exec publint
```

### Non-blocking checks

Reports findings without failing the job. Useful while gradually adopting a checker on a codebase that already has findings.

```yaml
jobs:
  lint-deps:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      FAIL_ON_ERROR: false
      KNIP_COMMAND: npx knip
      PUBLINT_COMMAND: npx publint
```
