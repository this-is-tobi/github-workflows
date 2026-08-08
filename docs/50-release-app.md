# `release-app.yml`

Create releases using [`release-please`](https://github.com/googleapis/release-please), optionally tag major/minor versions, and support automerge of generated PRs.

> **References:** [googleapis/release-please-action](https://github.com/googleapis/release-please-action) · [googleapis/release-please](https://github.com/googleapis/release-please)

## Inputs

| Input                    | Type    | Description                                                                                                                                                                                      | Required | Default                          |
| ------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | -------------------------------- |
| ENABLE_PRERELEASE        | boolean | Enable prerelease functionality                                                                                                                                                                  | No       | false                            |
| TAG_MAJOR_AND_MINOR      | boolean | Tag major and minor versions                                                                                                                                                                     | No       | false                            |
| AUTOMERGE_PRERELEASE     | boolean | Automatically merge the prerelease PR                                                                                                                                                            | No       | false                            |
| AUTOMERGE_RELEASE        | boolean | Automatically merge the release PR                                                                                                                                                               | No       | false                            |
| AUTOMERGE_METHOD         | string  | How the PR is merged when automerge is enabled: `auto` (queue until required checks pass, needs **Allow auto-merge** on the repo) or `admin` (merge now, bypassing branch protection)            | No       | auto                             |
| RELEASE_PR_AUTHOR        | string  | Optional hardening: only act on release pull requests opened by this login — see [Which pull requests are eligible](#which-pull-requests-are-eligible)                                            | No       | ""                               |
| PRERELEASE_BRANCH        | string  | Branch to create the prerelease on                                                                                                                                                               | No       | develop                          |
| RELEASE_BRANCH           | string  | Branch to create the release on                                                                                                                                                                  | No       | main                             |
| REBASE_PRERELEASE_BRANCH | boolean | Rebase prerelease branch on release after release                                                                                                                                                | No       | false                            |
| RELEASE_CONFIG_FILE      | string  | Release-please config file for release branch                                                                                                                                                    | No       | release-please-config.json       |
| RELEASE_MANIFEST_FILE    | string  | Release-please manifest file for release branch                                                                                                                                                  | No       | .release-please-manifest.json    |
| PRERELEASE_CONFIG_FILE   | string  | Release-please config file for prerelease branch                                                                                                                                                 | No       | release-please-config-rc.json    |
| PRERELEASE_MANIFEST_FILE | string  | Release-please manifest file for prerelease branch                                                                                                                                               | No       | .release-please-manifest-rc.json |
| RELEASE_ASSET_PATHS      | string  | Comma-separated list of local file paths to upload as release assets (e.g., `dist/app-linux-amd64,dist/app-darwin-amd64`)                                                                        | No       | -                                |
| RELEASE_ARTIFACT_NAMES   | string  | Artifact name or glob pattern matching one or more artifacts (uploaded by previous jobs via `actions/upload-artifact`) to download and attach to the release (e.g., `my-binaries` or `my-app-*`) | No       | -                                |
| PUBLISH_DRAFT_RELEASE    | boolean | Publish the GitHub Release once the assets have been attached. Enable together with `"draft": true` and `"force-tag-creation": true` in the release-please config to stay compatible with [immutable releases](#immutable-releases)                | No       | false                            |
| RUNS_ON                  | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                                                         | No       | ["ubuntu-24.04"]                 |

## Secrets

| Secret          | Description                                                                                                                                              | Required | Default |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------- |
| APP_CLIENT_ID   | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, authenticates as a GitHub App — takes precedence over `GH_PAT`. See [Authentication](./05-authentication.md) | No       | -       |
| APP_PRIVATE_KEY | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                                                                                          | No       | -       |
| GH_PAT          | GitHub Personal Access Token. Legacy alternative, still supported (see [Token setup](#token-setup))                                                       | No       | -       |

> Supplying App credentials makes the release pull request trigger `pull_request` workflows, so its CI actually runs — `GITHUB_TOKEN` cannot. It also makes the release **tag** and **GitHub Release** created by release-please fire `push: tags:` and `release:` triggers, which `GITHUB_TOKEN` never did. Check what your pipeline triggers on before switching. See [Loop safety](./05-authentication.md#loop-safety).

> `APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`.

> **Automerge is gated on the `AUTOMERGE_*` inputs, not on credentials.** Adding App credentials never enables merging by itself. If automerge is enabled and no credential is supplied, the job fails rather than silently skipping.

## Outputs

| Output          | Description                               |
| --------------- | ----------------------------------------- |
| release-created | Whether a release was created in this run |
| version         | Full semver value (e.g., `1.2.3`)         |
| major-tag       | Major version tag (e.g., `1`)             |
| minor-tag       | Minor version tag (e.g., `2`)             |
| patch-tag       | Patch version tag (e.g., `3`)             |

## Permissions

| Scope         | Access | Description                                       |
| ------------- | ------ | ------------------------------------------------- |
| contents      | write  | Create tags/commits and update manifest files     |
| issues        | write  | Create or update issues opened by release tooling |
| pull-requests | write  | Create, update, and optionally merge release PRs  |

## Token setup

A credential is only required when `AUTOMERGE_PRERELEASE` or `AUTOMERGE_RELEASE` is enabled. Use either a **GitHub App** (preferred) or a **Personal Access Token**, stored as repository secrets in the repository that runs this workflow.

### GitHub App (recommended)

Set `APP_CLIENT_ID` and `APP_PRIVATE_KEY`. Beyond automerge this also makes the release pull request trigger `pull_request` workflows, which `GITHUB_TOKEN` cannot — see [Authentication](./05-authentication.md) for the full setup.

Required App repository permissions: **Contents: Read & Write**, **Pull requests: Read & Write**, **Issues: Read & Write**, **Metadata: Read**.

### Which pull requests are eligible

A head branch name is chosen by whoever opened the pull request — on a fork PR it is just a branch inside their own repository — so it identifies a pull request but authorizes nothing. Three filters decide what this workflow will amend or merge:

1. **Fork pull requests are rejected outright.** Without this, any GitHub user could open a PR from a branch named `release-please--branches--main` and have it merged into your release branch — under `AUTOMERGE_METHOD: admin`, past branch protection and every required check.
2. **The branch must match exactly**, either `release-please--branches--<base>` or `release-please--branches--<base>--components--<name>` — the only two shapes release-please produces. A prefix match alone also accepted `release-please--branches--main-anything`.
3. **The pull request author must match**, which closes the remaining case the fork check cannot: someone with push access crafting a release-please-shaped branch in your own repository.

All three are on by default and need no configuration. The author is **derived from whichever credential opened the pull request**:

| Credential | Author the workflow expects | Derived from |
| ---------- | --------------------------- | ------------ |
| GitHub App | `app/<app-slug>` | the token action's own `app-slug` output |
| `GITHUB_TOKEN` | `app/github-actions` | fixed — this is always the author |
| `GH_PAT` | *(check skipped)* | the author is the token owner, which cannot be derived |

> Note the `app/` prefix. That is how the API reports a bot author — **not** `github-actions[bot]`. Setting `RELEASE_PR_AUTHOR: github-actions[bot]` would match nothing and silently stop every merge.

Set `RELEASE_PR_AUTHOR` only to override the derivation — pin your PAT owner's login under `GH_PAT`, or pass `*` to disable the author check while keeping the fork and branch guards.

**Can an outsider forge the author?** No. `author.login` is set by GitHub from the identity that opened the pull request; it is not attacker-supplied. A fork's `GITHUB_TOKEN` is an installation token scoped to that fork, so it cannot open a pull request in your repository at all — and the fork check rejects cross-repository pull requests before the author is even examined. The two guards are independent, and the fork check fails closed: a pull request whose fork status cannot be determined is refused rather than allowed.

**What remains.** Someone who *already has push access* could add a workflow that has your own `github-actions` bot open a pull request on a release-please-shaped branch. That passes all three filters. `RELEASE_PR_AUTHOR` does not help — they would match it. This is the trust boundary of push access rather than something the workflow can close: anyone who can push a workflow can already run arbitrary code in CI. If that matters for your repository, require review on `.github/workflows/**` via CODEOWNERS, and prefer `AUTOMERGE_METHOD: auto` so branch protection still applies.

### How the merge happens

The automerge step uses `gh pr merge --rebase`, with the method chosen by `AUTOMERGE_METHOD`:

- `auto` (default) queues the PR and lets GitHub merge it once all required status checks pass. This requires **Settings > General > Allow auto-merge** to be enabled on the repository.
- `admin` force-merges immediately, bypassing branch protection and required status checks.

There is **no automatic fallback between them**. If `auto` is selected and auto-merge is not enabled on the repository, the job fails with a message naming the setting to enable. This is deliberate: falling back to `--admin` would merge past the very checks App authentication makes run.

The step merges **every** open release-please pull request targeting the current branch, so monorepos using `separate-pull-requests` (one pull request per component) are handled — not just the first one found.

### Fine-grained PAT

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) scoped to the **current repository** with the following permissions:

| Permission    | Access       | Reason                                            |
| ------------- | ------------ | ------------------------------------------------- |
| Contents      | Read & Write | Push commits (manifest sync, rebase branch)       |
| Pull requests | Read & Write | Enable auto-merge on release PRs                  |

> With `AUTOMERGE_METHOD: admin` the PAT owner must be a **repository admin** for the force-merge to succeed.

### Classic PAT

Alternatively, create a [classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) with the **`repo`** scope.

### Where to store it

Add the credential as **repository secrets** (`APP_CLIENT_ID` + `APP_PRIVATE_KEY`, or `GH_PAT`):  
**Settings > Secrets and variables > Actions > New repository secret**

If both are set, the App takes precedence — useful for verifying the switch before removing the PAT.

## Notes

- Set `ENABLE_PRERELEASE: false` to disable all prerelease functionality and work only with release branches.
- Config and manifest files are configurable via inputs, with sensible defaults for both release and prerelease workflows.
- On `RELEASE_BRANCH` (default `main`), uses the files specified by `RELEASE_CONFIG_FILE` and `RELEASE_MANIFEST_FILE`.
- On `PRERELEASE_BRANCH` (default `develop`), uses the files specified by `PRERELEASE_CONFIG_FILE` and `PRERELEASE_MANIFEST_FILE` (only when `ENABLE_PRERELEASE: true`).
- If `TAG_MAJOR_AND_MINOR: true`, tags `v<major>` and `v<major>.<minor>` after a release is created.
- If `AUTOMERGE_*` is enabled and a PAT is provided, attempts to automerge the release PR.
- Optionally rebases `PRERELEASE_BRANCH` onto `RELEASE_BRANCH` after a release when `REBASE_PRERELEASE_BRANCH: true` (only when `ENABLE_PRERELEASE: true`).
- `RELEASE_ASSET_PATHS` uploads files that are already present on the runner filesystem. `RELEASE_ARTIFACT_NAMES` accepts a name or glob pattern — the matching artifacts are downloaded via `actions/download-artifact` before being attached to the release; both inputs can be used together.
- `PUBLISH_DRAFT_RELEASE: true` publishes the release after the assets have been attached. It is a no-op when the release is not a draft, so the step is safe to re-run. See [immutable releases](#immutable-releases).

## Configuration

Release-please requires a config file and a manifest file in the repository root. The manifest tracks the current version and is updated automatically on each release.

### Release config (`release-please-config.json`)

Minimal config for a single-package repository using the `node` release type (adjusts `package.json` version). See the [release-please docs](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md) for all available options and release types.

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "node",
      "initial-version": "0.0.1",
      "include-component-in-tag": false,
      "versioning": "prerelease",
      "prerelease": false,
      "prerelease-type": "",
      "extra-files": []
    }
  }
}
```

### Release manifest (`.release-please-manifest.json`)

Tracks the current version for each package path. Release-please updates this file automatically — set the initial version to your current release.

```json
{
  ".": "0.0.1"
}
```

### Prerelease config (`release-please-config-rc.json`)

Used when `ENABLE_PRERELEASE: true`. Identical structure to the release config but adds `prerelease-type` to control the prerelease identifier appended to the version.

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "node",
  "prerelease-type": "rc",
  "packages": {
    ".": {
      "release-type": "node",
      "initial-version": "0.0.1",
      "include-component-in-tag": false,
      "versioning": "prerelease",
      "prerelease": true,
      "prerelease-type": "rc",
      "extra-files": []
    }
  }
}
```

### Prerelease manifest (`.release-please-manifest-rc.json`)

```json
{
  ".": "0.0.1"
}
```

## Immutable releases

[Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) freeze a GitHub Release the moment it is published: assets can no longer be added, changed or removed, and the associated tag can no longer be moved or deleted. The only ordering GitHub supports is therefore **create as a draft → attach the assets → publish**.

This only matters if you attach assets, through `RELEASE_ASSET_PATHS` or `RELEASE_ARTIFACT_NAMES`. Without assets the workflow is already compatible and there is nothing to change.

Three changes are needed, two of them in your own release-please config:

```jsonc
{
  "packages": {
    ".": {
      // Create the release as a draft, so assets can still be attached to it.
      "draft": true,
      // GitHub does not create the git tag until a draft is published, and
      // release-please needs the tag to resolve the previous release.
      "force-tag-creation": true
    }
  }
}
```

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      RELEASE_ARTIFACT_NAMES: my-app-binaries
      PUBLISH_DRAFT_RELEASE: true
```

Worth knowing:

- **`PUBLISH_DRAFT_RELEASE` is an explicit opt-in.** release-please's `draft` option is also the documented way to hold a release back for manual publication, so this workflow never publishes a draft unless asked to.
- **The step is idempotent.** An already-published release is left untouched, so the step is safe to re-run.
- **`release:` events fire later.** A draft fires nothing; `release: published`/`released` comes from the publish step, once the assets are attached. Check the triggers of any workflow that reacts to your releases.
- **A mid-run failure leaves a draft**, which you can publish with `gh release edit <tag> --draft=false` or by re-running. That is exactly what this setup buys you: without it, on a repository with immutable releases, a failed asset upload leaves a published, incomplete release that is **unrecoverable** — the tag name stays burned even after deleting the release.
- **The floating `v<major>`/`v<major>.<minor>` tags from `TAG_MAJOR_AND_MINOR` are unaffected.** Immutability locks only tags carrying a published release, and release-please only ever creates releases on `v<major>.<minor>.<patch>`.

> [!WARNING]
> [`release-helm.yml`](./51-release-helm.md) with `CREATE_GITHUB_RELEASE: true` is **not** compatible with immutable releases: `chart-releaser` creates the release and then attaches the chart `.tgz` in two separate API calls, with no draft option ([helm/chart-releaser#591](https://github.com/helm/chart-releaser/issues/591)). The default mode (`CREATE_GITHUB_RELEASE: false`, OCI publishing only) is unaffected.

## Examples

The examples cover the main release scenarios: a full setup with prerelease support, a release-only flow, and a build that attaches compiled binaries to the GitHub Release.

> They use GitHub App credentials, the recommended mode. To use a personal access token instead, replace the two `APP_*` lines with <span v-pre>`GH_PAT: ${{ secrets.GH_PAT }}`</span> — nothing else changes. Both can be passed together during a migration; the App wins. See [Authentication](./05-authentication.md) for end-to-end setup of either.

### Simple example

Full two-branch setup with `develop` for prereleases and `main` for stable releases. `AUTOMERGE_*: true` requires a PAT with sufficient permissions to bypass branch protection rules. `REBASE_PRERELEASE_BRANCH: true` keeps `develop` rebased onto `main` automatically after each stable release.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: true
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_PRERELEASE: true
      AUTOMERGE_RELEASE: true
      REBASE_PRERELEASE_BRANCH: true
      # Optional: customize config and manifest files
      RELEASE_CONFIG_FILE: custom-release-config.json
      PRERELEASE_CONFIG_FILE: custom-prerelease-config.json
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Release-only workflow

Single-branch workflow targeting only `main`. No prerelease config files are required. `TAG_MAJOR_AND_MINOR: true` adds convenience aliases (`v1`, `v1.2`) to each stable release tag.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: false
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Attach build artifacts to the release

Two options are available depending on where the artifacts live.

**Option 1 — files on the runner filesystem** (`RELEASE_ASSET_PATHS`): use this when the files are produced in the same job (or already present on the runner).

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: false
      RELEASE_ASSET_PATHS: "dist/my-app-linux-amd64,dist/my-app-darwin-amd64"
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

**Option 2 — artifacts from a previous job** (`RELEASE_ARTIFACT_NAMES`): accepts a name or glob pattern — matching artifacts uploaded via `actions/upload-artifact` in the same run are downloaded automatically before being attached to the release.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v6
    - name: Build
      run: make build
    - uses: actions/upload-artifact@v7
      with:
        name: my-app-binaries
        path: dist/

  release:
    needs: build
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: false
      RELEASE_ARTIFACT_NAMES: "my-app-binaries"  # or a glob like "my-app-*"
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

Both inputs can be combined when some files are local and others come from previous jobs.
