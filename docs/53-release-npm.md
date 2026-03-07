# `release-npm.yml`

Install dependencies, optionally build, and publish one or more packages to any NPM-compatible registry.

Supports Node.js and Bun runtimes, all major package managers (npm, yarn, pnpm, bun), and any registry — npmjs.org, GitHub Packages, or a custom host.

## Inputs

| Input             | Type    | Description                                                                                   | Required | Default                      |
| ----------------- | ------- | --------------------------------------------------------------------------------------------- | -------- | ---------------------------- |
| RUNTIME           | string  | JavaScript runtime to use (`node` or `bun`)                                                   | No       | `node`                       |
| RUNTIME_VERSION   | string  | Runtime version to install                                                                    | No       | `24`                         |
| PACKAGE_MANAGER   | string  | Package manager to use (`npm`, `yarn`, `pnpm`, `bun`)                                         | No       | `npm`                        |
| WORKING_DIRECTORY | string  | Working directory for install, build and publish commands                                     | No       | `.`                          |
| REGISTRY_URL      | string  | NPM registry URL                                                                              | No       | `https://registry.npmjs.org` |
| SCOPE             | string  | Scope for the NPM registry (e.g. `@my-org`). Leave empty for unscoped packages.               | No       | -                            |
| PRE_COMMAND       | string  | Shell command to run at repo root before install/build (e.g. build shared deps in a monorepo) | No       | -                            |
| BUILD_COMMAND     | string  | Shell command to build the package (runs in `WORKING_DIRECTORY`)                              | No       | -                            |
| PUBLISH_COMMAND   | string  | Custom publish command (overrides auto-detected publish). Runs in `WORKING_DIRECTORY`         | No       | -                            |
| TAG               | string  | NPM dist-tag for the published version (e.g. `latest`, `beta`, `next`)                        | No       | `latest`                     |
| ACCESS            | string  | Package access level (`public` or `restricted`)                                               | No       | `public`                     |
| DRY_RUN           | boolean | Perform a dry-run publish (validate without uploading)                                        | No       | false                        |
| FAIL_ON_ERROR     | boolean | Whether to fail the workflow on publish errors                                                | No       | true                         |
| RUNS_ON           | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)      | No       | `["ubuntu-24.04"]`           |

## Secrets

| Secret    | Description                               | Required |
| --------- | ----------------------------------------- | -------- |
| NPM_TOKEN | Authentication token for the NPM registry | Yes      |

## Permissions

| Scope    | Access | Description                                      |
| -------- | ------ | ------------------------------------------------ |
| contents | read   | Check out the repository                         |
| packages | write  | Required only when publishing to GitHub Packages |

## Notes

- Authentication uses the `NODE_AUTH_TOKEN` environment variable, set from `NPM_TOKEN`, which is the standard mechanism understood by npm, yarn, pnpm and bun.
- For the **Node.js** runtime, `actions/setup-node` creates the `.npmrc` auth entry automatically based on `REGISTRY_URL` and `SCOPE`.
- For the **Bun** runtime, the registry URL and auth token are written to the user-level `.npmrc` manually, since `actions/setup-node` is not invoked — this covers both the default registry and scoped registries.
- **pnpm** is set up automatically via `pnpm/action-setup` when `PACKAGE_MANAGER: pnpm`; no manual install is needed.
- The `yarn` publish step uses `yarn npm publish` (Yarn Berry / v2+).
- `pnpm publish` is called with `--no-git-checks` to avoid requiring a clean git state in CI.
- `PRE_COMMAND` runs at the **repo root** with `NODE_AUTH_TOKEN` set — useful for building shared workspace packages before publishing. `BUILD_COMMAND` runs inside `WORKING_DIRECTORY`.
- `PUBLISH_COMMAND` fully overrides the auto-detected publish step and is the right option for Turborepo, Lerna, or any custom release tooling.
- `DRY_RUN` appends `--dry-run` to the publish command (all package managers support this flag) to validate packaging without uploading.
- `FAIL_ON_ERROR: false` sets `continue-on-error: true` on the publish step, useful when some packages in a matrix may already be published.
- Dependency caches are keyed by package manager, OS, architecture, and the combined hash of all lock files.

## Examples

### Simple publish to npmjs.org

Installs deps with npm and publishes the package at the repo root.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: .
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Monorepo: build shared deps then publish

Builds a shared workspace package first (`PRE_COMMAND` at repo root), then installs and builds the target package before publishing.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
    with:
      RUNTIME: bun
      RUNTIME_VERSION: "1.3.10"
      PACKAGE_MANAGER: bun
      PRE_COMMAND: "bun run build --filter=@my-org/shared"
      BUILD_COMMAND: "bun run build"
      WORKING_DIRECTORY: ./packages/my-lib
      TAG: latest
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Publish to GitHub Packages

Set `REGISTRY_URL` to the GitHub Packages endpoint and pass `github.token` as the secret. The `packages: write` permission is required on the calling job.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
      packages: write
    with:
      REGISTRY_URL: "https://npm.pkg.github.com"
      SCOPE: "@my-org"
      TAG: latest
    secrets:
      NPM_TOKEN: ${{ github.token }}
```

### Prerelease with dry-run validation

Publishes under the `beta` dist-tag. `DRY_RUN: true` validates packaging without uploading — useful to check before the actual release.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
    with:
      TAG: beta
      DRY_RUN: true
      ACCESS: public
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Custom publish command (Turborepo / Lerna)

When a custom release tool manages publishing, override the default step entirely via `PUBLISH_COMMAND`.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
    with:
      PUBLISH_COMMAND: "npx turbo publish --filter=./packages/*"
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```
