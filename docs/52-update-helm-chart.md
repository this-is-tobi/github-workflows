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
| RUNS_ON               | string | Runner labels as JSON array                                                                       | No       | ["ubuntu-24.04"]       |

## Secrets

| Secret | Description                                                                  | Required | Default |
| ------ | ---------------------------------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (needed to trigger remote workflow / create PR) | No       | -       |

## Permissions

| Scope         | Access | Description                           |
| ------------- | ------ | ------------------------------------- |
| pull-requests | write  | Create/update the chart update PR     |
| contents      | write  | Commit modified chart & docs          |
| actions       | write  | Trigger remote workflow (caller mode) |

## Notes

- `RUN_MODE=caller`: Validates `CHART_REPO` is provided, then invokes `gh workflow run <WORKFLOW_NAME>` in the target repo, forwarding: `CHART_NAME`, `APP_VERSION`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, and forcing `RUN_MODE=called` in the remote execution.
- `RUN_MODE=called`: Reads current chart `version` from `charts/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using Release Please-compatible logic, updates both `version` and `appVersion`, regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- **Version bump logic** (Release Please compatible):
  - `major`: `1.2.3` → `2.0.0`
  - `minor`: `1.2.3` → `1.3.0`
  - `patch`: `1.2.3` → `1.2.4`
  - `prerelease`: `1.2.3` → `1.2.3-rc` → `1.2.3-rc.1` → `1.2.3-rc.2` (increments prerelease number)
- Branch naming pattern: `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq` and `docker` (for `jnorwood/helm-docs`). No longer requires `npx semver`.
- No explicit outputs are exposed; derive the new version from the PR title or branch name if needed.

## Examples

These examples illustrate both sides of the `workflow_call` pattern: the caller workflow that triggers the chart update in another repository, and the called workflow that applies the version bump locally.

### Caller mode

Dispatches the `update-app-version.yml` workflow in the remote chart repository via `gh workflow run`. The remote workflow receives `CHART_NAME`, `APP_VERSION`, `UPGRADE_TYPE`, and `PRERELEASE_IDENTIFIER` and runs in `called` mode, opening a PR that bumps the chart `version` and sets `appVersion`.

```yaml
jobs:
  trigger-chart-update:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Caller mode – prerelease bump

`UPGRADE_TYPE: prerelease` increments the prerelease counter (`1.2.3-rc` → `1.2.3-rc.1` → `1.2.3-rc.2`). `APP_VERSION` is written as-is into `appVersion`; only the chart `version` field follows the prerelease bump logic.

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0-rc.1
      UPGRADE_TYPE: prerelease
      PRERELEASE_IDENTIFIER: rc
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Called mode

Runs the version update directly in the current repository without any remote dispatch. Reads `charts/my-service/Chart.yaml`, bumps `version` by a minor increment, sets `appVersion: 1.4.0`, regenerates docs with `helm-docs`, and opens a PR with the changes.

```yaml
jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
```
