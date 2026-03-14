# `update-helm-chart.yml`

Trigger a chart update workflow in a remote Helm charts repository (caller mode) or update a chart in-place (called mode) by incrementing its version and regenerating documentation.

## Inputs

| Input                 | Type   | Description                                                                                       | Required | Default                |
| --------------------- | ------ | ------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUN_MODE              | string | Execution mode `caller` (trigger remote repo workflow) or `called` (update chart in current repo) | Yes      | -                      |
| WORKFLOW_NAME         | string | Workflow file name in chart repo to trigger (caller mode)                                         | No       | update-app-version.yml |
| CHART_REPO            | string | Target chart repository (`owner/repo`) when in caller mode                                        | No       | -                      |
| CHART_DIR             | string | Directory containing the Helm charts (in `CHART_REPO`)                                            | No       | charts                 |
| CHART_NAME            | string | Name of the chart to update (in `CHART_DIR`)                                                      | Yes      | -                      |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion)                                           | Yes      | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, or `prerelease`                        | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`)                                        | No       | rc                     |
| AUTOMERGE_PRERELEASE  | bool   | Automatically merge the PR when `UPGRADE_TYPE` is `prerelease` (requires `GH_PAT`)                | No       | false                  |
| AUTOMERGE_RELEASE     | bool   | Automatically merge the PR when `UPGRADE_TYPE` is not `prerelease` (requires `GH_PAT`)            | No       | false                  |
| RUNS_ON               | string | Runner labels as JSON array                                                                       | No       | ["ubuntu-24.04"]       |

## Secrets

| Secret | Description                                                                  | Required | Default |
| ------ | ---------------------------------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (needed to trigger remote workflow / automerge, see [Token setup](#token-setup)) | No       | -       |

## Permissions

| Scope         | Access | Description                           |
| ------------- | ------ | ------------------------------------- |
| pull-requests | write  | Create/update the chart update PR     |
| contents      | write  | Commit modified chart & docs          |
| actions       | write  | Trigger remote workflow (caller mode) |

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
- `RUN_MODE=called`: Reads current chart `version` from `charts/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using Release Please-compatible logic, updates both `version` and `appVersion`, regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- **Version bump logic** (Release Please compatible):
  - `major`: `1.2.3` → `2.0.0`
  - `minor`: `1.2.3` → `1.3.0`
  - `patch`: `1.2.3` → `1.2.4`
  - `prerelease`: `1.2.3` → `1.2.3-rc` → `1.2.3-rc.1` → `1.2.3-rc.2` (increments prerelease number)
- **Automerge (mode `called`)**: If `AUTOMERGE_PRERELEASE: true` (when `UPGRADE_TYPE: prerelease`) or `AUTOMERGE_RELEASE: true` (otherwise), and a `GH_PAT` is provided, the workflow attempts to merge the PR automatically:
  - If the repository has the *Allow auto-merge* setting enabled, uses `gh pr merge --auto` (merge triggers after required checks pass).
  - Otherwise, uses `gh pr merge --admin` to force-merge immediately.
  - Merge strategy is `--rebase`.
- Branch naming pattern: `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq` and `docker` (for `jnorwood/helm-docs`). No longer requires `npx semver`.
- No explicit outputs are exposed; derive the new version from the PR title or branch name if needed.

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

`UPGRADE_TYPE: prerelease` increments the prerelease counter (`1.2.3-rc` → `1.2.3-rc.1` → `1.2.3-rc.2`). `APP_VERSION` is written as-is into `appVersion`; only the chart `version` field follows the prerelease bump logic. `AUTOMERGE_PRERELEASE: true` will auto-merge the resulting PR.

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
