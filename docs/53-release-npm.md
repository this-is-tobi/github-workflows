# `release-npm.yml`

Install dependencies, optionally build, and publish one or more packages to any NPM-compatible registry.

Supports Node.js and Bun runtimes, all major package managers (npm, yarn, pnpm, bun), and any registry — npmjs.org, GitHub Packages, or a custom host.

## Inputs

| Input             | Type    | Description                                                                                   | Required | Default                      |
| ----------------- | ------- | --------------------------------------------------------------------------------------------- | -------- | ---------------------------- |
| RUNTIME           | string  | JavaScript runtime (`node` or `bun`). Empty auto-detects                                      | No       | `""`                         |
| RUNTIME_VERSION   | string  | Runtime version to use. Empty resolves to a per-runtime default (Node.js 24, Bun latest)      | No       | -                            |
| PACKAGE_MANAGER   | string  | Package manager (`npm`, `yarn`, `pnpm`, `bun`). Empty auto-detects                            | No       | `""`                         |
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

| Secret    | Description                                                                                                                                                                                       | Required |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| NPM_TOKEN | Authentication token for the NPM registry. Optional if the registry has trusted publishing (OIDC) configured for the calling workflow - see [Trusted publishing](#trusted-publishing-oidc) below. | No       |

## Permissions

| Scope    | Access | Description                                                 |
| -------- | ------ | ----------------------------------------------------------- |
| contents | read   | Check out the repository                                    |
| id-token | write  | Mint the OIDC token used for trusted publishing (npm, pnpm) |

## Notes

- Authentication uses the `NODE_AUTH_TOKEN` environment variable, set from `NPM_TOKEN`, which is the standard mechanism understood by npm, yarn, pnpm and bun.
- For the **Node.js** runtime, `actions/setup-node` creates the `.npmrc` auth entry automatically based on `REGISTRY_URL` and `SCOPE`.
- For the **Bun** runtime, the registry URL and auth token are written to the user-level `.npmrc` manually, since `actions/setup-node` is not invoked — this covers both the default registry and scoped registries. Bun is set up whenever `PACKAGE_MANAGER: bun` is used, even with `RUNTIME: node`. Bun has no OIDC/trusted-publishing support ([oven-sh/bun#24855](https://github.com/oven-sh/bun/issues/24855)), so when `NPM_TOKEN` is omitted the publish step transparently falls back to the npm CLI, which handles the OIDC exchange — install and build still run with bun.
- **Auto-detection** (à la [`@antfu/ni`](https://github.com/antfu-collective/ni)): when `PACKAGE_MANAGER`/`RUNTIME` are empty, the workflow walks upward from `WORKING_DIRECTORY` to the checkout root, checking at each level for the corepack `packageManager` field in `package.json` first, then lock files (`bun.lockb`/`bun.lock` → bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` → npm), falling back to npm if nothing is found up to the root. This means a job scoped to a monorepo package (`WORKING_DIRECTORY: packages/my-lib`) still detects the package manager from the workspace root's lock file. The runtime resolves to Bun when the detected package manager is bun, else Node.js. Set the inputs explicitly to override. The detected package manager also selects the matching publish step.
- **pnpm/yarn** are set up automatically via Corepack when the detected package manager is `pnpm` or `yarn`; no manual install is needed, and the version pinned in `package.json`'s `packageManager` field (if any) is used. Yarn Berry (`.yarnrc.yml`) installs with `--immutable`, classic with `--frozen-lockfile`.
- The `yarn` publish step uses `yarn npm publish` (Yarn Berry / v2+).
- `pnpm publish` is called with `--no-git-checks` to avoid requiring a clean git state in CI.
- `PRE_COMMAND` runs at the **repo root** with `NODE_AUTH_TOKEN` set — useful for building shared workspace packages before publishing. `BUILD_COMMAND` runs inside `WORKING_DIRECTORY`.
- `PUBLISH_COMMAND` fully overrides the auto-detected publish step and is the right option for Turborepo, Lerna, or any custom release tooling.
- `DRY_RUN` appends `--dry-run` to the publish command to validate packaging without uploading. Note: Yarn Berry's `yarn npm publish` does not support `--dry-run`, so `DRY_RUN: true` is not supported with `PACKAGE_MANAGER: yarn`.
- `FAIL_ON_ERROR: false` sets `continue-on-error: true` on the publish step, useful when some packages in a matrix may already be published.
- Dependency caches are keyed by package manager, OS, architecture, and the combined hash of all lock files.

### Trusted publishing (OIDC)

npm and pnpm support [trusted publishing](https://docs.npmjs.com/trusted-publishers/): publishing via a short-lived OIDC token instead of a long-lived `NPM_TOKEN`. To use it:

1. On npmjs.com, configure a trusted publisher for the package pointing at your repository and **the entry-point workflow file that GitHub actually triggers** (e.g. `.github/workflows/cd.yml`) — not this reusable `release-npm.yml` file. npm validates the caller workflow that started the run, not any reusable workflow it calls into.
2. Grant `id-token: write` on the calling job (in your `cd.yml`) — this workflow already requests it internally, but both are required since permissions must be explicit at every level of a reusable-workflow call chain.
3. Omit the `NPM_TOKEN` secret, or keep passing it as a fallback — npm's CLI (≥ 11.5.1, bundled with Node.js 24+) tries OIDC first and only falls back to a static token if OIDC isn't available.
4. pnpm's OIDC support is newer and has had regressions in some releases (see [pnpm#11513](https://github.com/pnpm/pnpm/issues/11513)) — pin a known-good `packageManager` version and verify a real publish before relying on it exclusively.
5. bun has no OIDC support ([oven-sh/bun#24855](https://github.com/oven-sh/bun/issues/24855)): with `PACKAGE_MANAGER: bun` and no `NPM_TOKEN`, this workflow publishes through the npm CLI instead of `bun publish` — no caller change needed beyond dropping the secret.

If you switch an existing package from a token-based setup to trusted publishing, remember to update the trusted publisher's registered workflow path whenever you change which file is the actual entry point (e.g. after moving CI/CD to reusable workflows).

## Examples

### Simple publish to npmjs.org

Installs deps with npm and publishes the package at the repo root.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
      id-token: write
    with:
      WORKING_DIRECTORY: .
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Trusted publishing (no token)

Once a trusted publisher is configured on npmjs.com for this exact repo and calling workflow file (see [Trusted publishing](#trusted-publishing-oidc)), the `NPM_TOKEN` secret can be dropped entirely — `id-token: write` is all that's needed.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
      id-token: write
    with:
      WORKING_DIRECTORY: .
```

### Monorepo: build shared deps then publish

Builds a shared workspace package first (`PRE_COMMAND` at repo root), then installs and builds the target package before publishing.

```yaml
jobs:
  release-npm:
    uses: this-is-tobi/github-workflows/.github/workflows/release-npm.yml@v0
    permissions:
      contents: read
      id-token: write
    with:
      RUNTIME: bun
      RUNTIME_VERSION: 1.3.10
      PACKAGE_MANAGER: bun
      PRE_COMMAND: bun run build --filter=@my-org/shared
      BUILD_COMMAND: bun run build
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
      id-token: write
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
      id-token: write
    with:
      PUBLISH_COMMAND: "npx turbo publish --filter=./packages/*"
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```
