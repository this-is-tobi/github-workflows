# `update-helm-chart.yml`

Bump a Helm chart version following its **own release lifecycle** (release-please-compatible logic, including prereleases), optionally injecting a new `appVersion`. Three modes:

- **`caller`** — trigger the update workflow in a remote chart repository (app repo → chart repo).
- **`called`** — update the chart in the current repository via a pull request (the chart repo side).
- **`local`** — bump the chart and commit directly on the current branch, exposing the new version as an output. Designed for **monorepos** where the chart lives next to the app and the bump happens mid-pipeline (chain with [`release-helm.yml`](./51-release-helm.md) in `local` mode to publish it in the same run).

The chart version and the app version are **decoupled on purpose**: an app release bumps the chart (patch/prerelease) and updates `appVersion`, while a chart-only change (leave `APP_VERSION` empty) bumps the chart without touching `appVersion`.

> **Which mode where?** The repo that *hosts the chart* owns the release style: `called` = PR-gated (release-please style), `local` = direct in-pipeline. Both styles work identically whether the chart lives in a monorepo or in a dedicated chart repository — see the [chart release patterns matrix](./90-global-workflows-examples.md#helm-chart-release-patterns).

## Inputs

| Input                 | Type   | Description                                                                                       | Required | Default                |
| --------------------- | ------ | ------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUN_MODE              | string | Execution mode: `caller` (trigger remote repo workflow), `called` (update chart in current repo via PR) or `local` (bump and commit directly on the current branch) | Yes      | -                      |
| WORKFLOW_NAME         | string | Workflow file name in chart repo to trigger (caller mode)                                         | No       | update-app-version.yml |
| CHART_REPO            | string | Target chart repository (`owner/repo`) when in caller mode                                        | No       | -                      |
| CHART_DIR             | string | Directory containing the Helm charts (in `CHART_REPO`)                                            | No       | charts                 |
| CHART_NAME            | string | Name of the chart to update (in `CHART_DIR`)                                                      | Yes      | -                      |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion). Leave empty to keep the current appVersion (chart-only release). When set, must match `^[A-Za-z0-9][A-Za-z0-9.+_-]*$` | No       | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, or `prerelease`                        | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`). Must match `^[A-Za-z0-9-]+$`          | No       | rc                     |
| HELM_DOCS_VERSION     | string | Version of helm-docs used to regenerate the chart README. Pinned rather than tracking `:latest`   | No       | v1.14.2                |
| AUTOMERGE_PRERELEASE  | bool   | Automatically merge the PR when `UPGRADE_TYPE` is `prerelease`                                    | No       | false                  |
| AUTOMERGE_RELEASE     | bool   | Automatically merge the PR when `UPGRADE_TYPE` is not `prerelease`                                | No       | false                  |
| AUTOMERGE_METHOD      | string | How the PR is merged when automerge is enabled: `auto` (queue until required checks pass, needs **Allow auto-merge**) or `admin` (merge now, bypassing branch protection) | No       | auto                   |
| BASE_BRANCH           | string | Base branch: to open the chart-update pull request against (called mode), or the branch the `workflow_dispatch` targets in `CHART_REPO` (caller mode) | No       | main                   |
| RUNS_ON               | string | Runner labels as JSON array                                                                       | No       | ["ubuntu-24.04"]       |

## Secrets

| Secret          | Description                                                                                                                              | Required | Default |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| APP_CLIENT_ID   | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, authenticates as a GitHub App — takes precedence over `GH_PAT`. See [Authentication](./05-authentication.md) | No       | -       |
| APP_PRIVATE_KEY | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                                                                          | No       | -       |
| GH_PAT          | GitHub Personal Access Token. Legacy alternative, still supported (see [Token setup](#token-setup))                                       | No       | -       |

> **Automerge is gated on the `AUTOMERGE_*` inputs, not on credentials.** Adding App credentials never enables merging by itself. If automerge is enabled and no credential is supplied, the job fails rather than silently skipping.

## Outputs

| Output                 | Description                                                             |
| ---------------------- | ----------------------------------------------------------------------- |
| chart-version          | New chart version computed by the bump (called and local modes)         |
| previous-chart-version | Chart version before the bump (called and local modes)                  |
| commit-sha             | SHA of the bump commit pushed on the current branch (local mode only)   |

## Permissions

| Scope         | Access | Description                                              |
| ------------- | ------ | -------------------------------------------------------- |
| pull-requests | write  | Create/update the chart update PR (called mode)          |
| contents      | write  | Commit modified chart & docs (called and local modes)    |

> In **caller mode** the reusable job runs with `permissions: {}` and dispatches the remote workflow using the App token or `GH_PAT` (never `GITHUB_TOKEN`), so no `GITHUB_TOKEN` scopes are required on the caller job. The permissions above apply to **called and local modes** (local mode does not open a PR, but the job declares both scopes).

## Token setup

A credential is required in **caller mode** (to dispatch a workflow in another repository) and for **automerge** in both modes. Use either a **GitHub App** (preferred) or a **Personal Access Token**, stored as repository secrets in the repository that runs this workflow.

### GitHub App (recommended)

Set `APP_CLIENT_ID` and `APP_PRIVATE_KEY`. Beyond automerge and dispatch, this also makes the chart update pull request trigger `pull_request` workflows, which `GITHUB_TOKEN` cannot — see [Authentication](./05-authentication.md).

Required App repository permissions:

| Mode | Permissions | Installed on |
| ---- | ----------- | ------------ |
| caller | Actions: Read & Write, Metadata: Read | the **chart** repository |
| called / local | Contents: Read & Write, Pull requests: Read & Write, Metadata: Read | the **current** repository |

In caller mode the token is minted scoped to `CHART_REPO` only, so the App must be installed on that repository's owner. `CHART_REPO` must be given as `owner/repository`; a bare repository name is rejected before any token is minted, since it would otherwise resolve the owner to the repository name.

`APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`, which would silently authenticate as something other than the App.

### `AUTOMERGE_METHOD` in caller mode

Caller mode merges nothing itself — it dispatches to the chart repository, which merges in `called` mode. `AUTOMERGE_METHOD` is forwarded with the dispatch, so the choice stays with the caller.

This needs the chart repository's entry-point workflow to declare an `AUTOMERGE_METHOD` input. If it does not, the dispatch is retried once without it and the job emits a `::warning::`; the chart repository's own default (`auto`) then applies. Add the input to that workflow to take control of the merge method from the app side — the [template](./90-global-workflows-examples.md#update-app-version-workflow) includes it.

### Caller mode

The token is passed to `gh workflow run --repo <CHART_REPO>` to trigger the remote workflow.

#### Fine-grained PAT (recommended)

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) scoped to the **target chart repository** (`CHART_REPO`) with:

| Permission | Access       | Reason                                      |
| ---------- | ------------ | ------------------------------------------- |
| Actions    | Read & Write | Trigger workflow dispatch in the chart repo |

#### Classic PAT

Create a [classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) with the **`repo`** scope (grants access to all repos the user can access).

#### Where to store it

Add the token as a **repository secret** named `GH_PAT` in the **source (app) repository** — the one that calls this workflow:  
**Settings > Secrets and variables > Actions > New repository secret**

### Called mode — automerge

The token is used for `gh pr merge --rebase`, with the method chosen by `AUTOMERGE_METHOD`:

- `auto` (default) queues the PR and lets GitHub merge it once all required status checks pass. This requires **Settings > General > Allow auto-merge** to be enabled on the repository.
- `admin` force-merges immediately, bypassing branch protection and required status checks.

There is **no automatic fallback between them**. If `auto` is selected and auto-merge is not enabled, the job fails with a message naming the setting to enable — falling back to `--admin` would merge past the very checks App authentication makes run.

#### Fine-grained PAT (recommended)

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) scoped to the **chart repository** (where the PR is created) with:

| Permission    | Access       | Reason                                   |
| ------------- | ------------ | ---------------------------------------- |
| Contents      | Read & Write | Required by `gh pr merge`                |
| Pull requests | Read & Write | Enable auto-merge on the chart update PR |

> If the repository does **not** have "Allow auto-merge" enabled, the PAT owner must be a **repository admin** for the `--admin` merge to succeed.

#### Classic PAT

Create a [classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) with the **`repo`** scope.

#### Where to store it

Add the token as a **repository secret** named `GH_PAT` in the **chart repository**:  
**Settings > Secrets and variables > Actions > New repository secret**

> **Tip:** If you use both caller and called modes (caller in app repo triggers called in chart repo), you need **two secrets**: one in the app repo (for `gh workflow run`) and one in the chart repo (for automerge). They can use the same PAT if it has permissions on both repositories.

## Notes

- `RUN_MODE=caller`: Validates `CHART_REPO` is provided, then invokes `gh workflow run <WORKFLOW_NAME> --ref <BASE_BRANCH>` in the target repo, forwarding: `CHART_NAME`, `APP_VERSION`, `CHART_DIR`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, `AUTOMERGE_PRERELEASE`, `AUTOMERGE_RELEASE`, and forcing `RUN_MODE=called` in the remote execution. `--ref` is always explicit — see the note below the caller mode example for why.
- `RUN_MODE=called`: Reads current chart `version` from `charts/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using Release Please-compatible logic, updates `version` (and `appVersion` when `APP_VERSION` is provided), regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- `RUN_MODE=local`: Same bump as `called`, but **commits directly on the current branch** instead of opening a PR, and exposes `chart-version` / `commit-sha` outputs so downstream jobs in the same pipeline can publish the chart (chain with [`release-helm-local.yml`](./52-release-helm-local.md)'s `CHECKOUT_REF`). Notes:
  - The push is authenticated with `GITHUB_TOKEN`, and such pushes **never trigger new workflow runs** — no CD loop; release the chart in the same run using the outputs. The commit deliberately carries no skip-ci marker: `GITHUB_TOKEN` alone already prevents the loop, and the marker would additionally suppress `pull_request` checks for any pull request a human later opens FROM this branch (e.g. a manual `develop` → `main` promotion).
  - Direct pushes require the branch to accept them (no "require a pull request" protection rule for `github-actions[bot]`); if your branch is protected, use `called` mode with automerge instead.
  - Leave `APP_VERSION` empty for a **chart-only release** (bumps `version`, keeps `appVersion`).
- **Version bump logic** (Release Please compatible):
  - `major`: `1.2.3` → `2.0.0`
  - `minor`: `1.2.3` → `1.3.0`
  - `patch`: `1.2.3` → `1.2.4`
  - `prerelease`: `1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2` (from a stable version the patch is bumped first, then the prerelease counter increments)
- **Automerge (mode `called`)**: If `AUTOMERGE_PRERELEASE: true` (when `UPGRADE_TYPE: prerelease`) or `AUTOMERGE_RELEASE: true` (otherwise), the workflow merges the PR automatically. It is gated on those inputs alone — supplying credentials never enables it by itself, and if no credential is supplied the job **fails** rather than skipping silently.
  - `AUTOMERGE_METHOD: auto` (default) uses `gh pr merge --auto`; the merge happens once required checks pass. Requires *Allow auto-merge* on the repository, and fails naming that setting if it is off.
  - `AUTOMERGE_METHOD: admin` uses `gh pr merge --admin` to force-merge immediately, bypassing branch protection and required checks.
  - There is **no automatic fallback** between them.
  - Merge strategy is `--rebase`.
- Branch naming pattern (called mode): `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq` and `docker` (for `jnorwood/helm-docs`). No longer requires `npx semver`.
- The new chart version is exposed via the `chart-version` output (see [Outputs](#outputs)).

## Examples

These examples illustrate both sides of the `workflow_call` pattern: the caller workflow that triggers the chart update in another repository, and the called workflow that applies the version bump locally.

> They use GitHub App credentials, the recommended mode. To use a personal access token instead, replace the two `APP_*` lines with <span v-pre>`GH_PAT: ${{ secrets.GH_PAT }}`</span> — nothing else changes. In **caller mode** the App must be installed on the repository named by `CHART_REPO`, since the token is minted scoped to it. See [Authentication](./05-authentication.md) for end-to-end setup of either.

### Caller mode

Dispatches the `update-app-version.yml` workflow in the remote chart repository via `gh workflow run`. The remote workflow receives `CHART_NAME`, `APP_VERSION`, `CHART_DIR`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, `AUTOMERGE_PRERELEASE`, `AUTOMERGE_RELEASE` and `AUTOMERGE_METHOD`, and runs in `called` mode, opening a PR that bumps the chart `version` and sets `appVersion`.

Every one of those must be declared as an input on the remote workflow — GitHub rejects a dispatch carrying an undeclared input (`422 Unexpected inputs provided`) instead of ignoring it. `AUTOMERGE_METHOD` is the exception: the dispatch is retried without it and warns, so chart repositories that predate it keep working.

```yaml
jobs:
  trigger-chart-update:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions: {}
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
      AUTOMERGE_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

> The dispatch always targets `BASE_BRANCH` explicitly (`--ref`) rather than letting `gh workflow run` resolve `CHART_REPO`'s default branch itself: that resolution goes through a GraphQL `defaultBranchRef` query, which fails for a token scoped to `Actions: Read and write` only (`unable to determine default branch for <repo>: GraphQL: Resource not accessible by integration (repository.defaultBranchRef)`). If `CHART_REPO`'s default branch isn't `main`, set `BASE_BRANCH` explicitly — this applies with either credential, App or `GH_PAT`.

### Caller mode – prerelease bump with automerge

`UPGRADE_TYPE: prerelease` bumps the chart prerelease version (`1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2`: from a stable version the patch is bumped first, then the counter increments). `APP_VERSION` is written as-is into `appVersion`; only the chart `version` field follows the prerelease bump logic. `AUTOMERGE_PRERELEASE: true` will auto-merge the resulting PR.

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions: {}
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0-rc.1
      UPGRADE_TYPE: prerelease
      PRERELEASE_IDENTIFIER: rc
      AUTOMERGE_PRERELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Called mode

Runs the version update directly in the current repository without any remote dispatch. Reads `charts/my-service/Chart.yaml`, bumps `version` by a minor increment, sets `appVersion: 1.4.0`, regenerates docs with `helm-docs`, and opens a PR with the changes.

```yaml
jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
```

### Called mode – with automerge

Same as above but with `AUTOMERGE_RELEASE: true` to automatically merge the PR after checks pass. Requires a credential — App or PAT — and *Allow auto-merge* enabled on the repository, unless `AUTOMERGE_METHOD: admin` is set.

```yaml
jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
      AUTOMERGE_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Local mode – monorepo pipeline

The chart lives in the same repository as the app. After `release-app` publishes the app version, the chart is bumped **on its own lifecycle** (`prerelease` on `develop`, `patch` on `main` — graduation from `x.y.z-rc.n` to `x.y.z` is automatic), committed directly on the branch, then published to the OCI registry in the same run by `release-helm` in `local` mode.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    needs:
    - release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: local
      CHART_NAME: my-service
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm-local.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      CHART_NAME: my-service
      # Package exactly the bump commit pushed by the previous job
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

For a **chart-only release** (chart fix with no app release), call the same `bump-chart` + `release-chart` pair with `APP_VERSION` omitted — see the [CI/CD examples](./90-global-workflows-examples.md) for the full monorepo pipeline including the chart-only trigger.
