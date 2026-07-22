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
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion). Leave empty to keep the current appVersion (chart-only release)                                           | No       | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, or `prerelease`                        | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`)                                        | No       | rc                     |
| AUTOMERGE_PRERELEASE  | bool   | Automatically merge the PR when `UPGRADE_TYPE` is `prerelease` (requires `GH_PAT`)                | No       | false                  |
| AUTOMERGE_RELEASE     | bool   | Automatically merge the PR when `UPGRADE_TYPE` is not `prerelease` (requires `GH_PAT`)            | No       | false                  |
| BASE_BRANCH           | string | Base branch to open the chart-update pull request against (called mode)                           | No       | main                   |
| RUNS_ON               | string | Runner labels as JSON array                                                                       | No       | ["ubuntu-24.04"]       |

## Secrets

| Secret | Description                                                                                                   | Required | Default |
| ------ | ------------------------------------------------------------------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (needed to trigger remote workflow / automerge, see [Token setup](#token-setup)) | No       | -       |

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

> In **caller mode** the reusable job runs with `permissions: {}` and dispatches the remote workflow using `GH_PAT` (not `GITHUB_TOKEN`), so no `GITHUB_TOKEN` scopes are required on the caller job. The permissions above apply to **called and local modes** (local mode does not open a PR, but the job declares both scopes).

## Token setup

The `GH_PAT` secret is required in **caller mode** (to dispatch a workflow in another repository) and for **automerge** in both modes. It must be a GitHub **Personal Access Token** stored as a repository secret named `GH_PAT` in the repository that runs this workflow.

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

The token is used for `gh pr merge --rebase` with either `--auto` or `--admin`:

- If the repository has **Settings > General > Allow auto-merge** enabled, the workflow uses `--auto` (the PR merges automatically once all required status checks pass).
- Otherwise, it falls back to `--admin` which force-merges immediately, bypassing branch protection rules.

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

- `RUN_MODE=caller`: Validates `CHART_REPO` is provided, then invokes `gh workflow run <WORKFLOW_NAME>` in the target repo, forwarding: `CHART_NAME`, `APP_VERSION`, `CHART_DIR`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, `AUTOMERGE_PRERELEASE`, `AUTOMERGE_RELEASE`, and forcing `RUN_MODE=called` in the remote execution.
- `RUN_MODE=called`: Reads current chart `version` from `charts/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using Release Please-compatible logic, updates `version` (and `appVersion` when `APP_VERSION` is provided), regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- `RUN_MODE=local`: Same bump as `called`, but **commits directly on the current branch** instead of opening a PR, and exposes `chart-version` / `commit-sha` outputs so downstream jobs in the same pipeline can publish the chart (chain with `release-helm.yml` `MODE: local` + `CHECKOUT_REF`). Notes:
  - The push is authenticated with `GITHUB_TOKEN`, and such pushes **never trigger new workflow runs** — no CD loop; release the chart in the same run using the outputs.
  - Direct pushes require the branch to accept them (no "require a pull request" protection rule for `github-actions[bot]`); if your branch is protected, use `called` mode with automerge instead.
  - Leave `APP_VERSION` empty for a **chart-only release** (bumps `version`, keeps `appVersion`).
- **Version bump logic** (Release Please compatible):
  - `major`: `1.2.3` → `2.0.0`
  - `minor`: `1.2.3` → `1.3.0`
  - `patch`: `1.2.3` → `1.2.4`
  - `prerelease`: `1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2` (from a stable version the patch is bumped first, then the prerelease counter increments)
- **Automerge (mode `called`)**: If `AUTOMERGE_PRERELEASE: true` (when `UPGRADE_TYPE: prerelease`) or `AUTOMERGE_RELEASE: true` (otherwise), and a `GH_PAT` is provided, the workflow attempts to merge the PR automatically:
  - If the repository has the *Allow auto-merge* setting enabled, uses `gh pr merge --auto` (merge triggers after required checks pass).
  - Otherwise, uses `gh pr merge --admin` to force-merge immediately.
  - Merge strategy is `--rebase`.
- Branch naming pattern (called mode): `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq` and `docker` (for `jnorwood/helm-docs`). No longer requires `npx semver`.
- The new chart version is exposed via the `chart-version` output (see [Outputs](#outputs)).

## Examples

These examples illustrate both sides of the `workflow_call` pattern: the caller workflow that triggers the chart update in another repository, and the called workflow that applies the version bump locally.

### Caller mode

Dispatches the `update-app-version.yml` workflow in the remote chart repository via `gh workflow run`. The remote workflow receives `CHART_NAME`, `APP_VERSION`, `CHART_DIR`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, `AUTOMERGE_PRERELEASE`, and `AUTOMERGE_RELEASE` and runs in `called` mode, opening a PR that bumps the chart `version` and sets `appVersion`.

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
      GH_PAT: ${{ secrets.GH_PAT }}
```

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
      GH_PAT: ${{ secrets.GH_PAT }}
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

Same as above but with `AUTOMERGE_RELEASE: true` to automatically merge the PR after checks pass. Requires `GH_PAT` to be provided.

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
      GH_PAT: ${{ secrets.GH_PAT }}
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
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      MODE: local
      CHART_NAME: my-service
      # Package exactly the bump commit pushed by the previous job
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

For a **chart-only release** (chart fix with no app release), call the same `bump-chart` + `release-chart` pair with `APP_VERSION` omitted — see the [CI/CD examples](./90-global-workflows-examples.md) for the full monorepo pipeline including the chart-only trigger.
