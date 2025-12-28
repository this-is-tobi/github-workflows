# `update-helm-chart.yml`

Trigger a chart update workflow in a remote Helm charts repository (caller mode) or update a chart in-place (called mode) by incrementing its version and regenerating documentation.

## Inputs

| Input                 | Type   | Description                                                                                       | Required | Default                |
| --------------------- | ------ | ------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUN_MODE              | string | Execution mode `caller` (trigger remote repo workflow) or `called` (update chart in current repo) | Yes      | -                      |
| WORKFLOW_NAME         | string | Workflow file name in chart repo to trigger (caller mode)                                         | No       | update-app-version.yml |
| CHART_REPO            | string | Target chart repository (`owner/repo`) when in caller mode                                        | No       | -                      |
| CHART_NAME            | string | Name of the chart directory under `charts/`                                                       | Yes      | -                      |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion)                                           | Yes      | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, or `prerelease`                        | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`)                                        | No       | rc                     |

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

### Caller mode

```yaml
jobs:
  trigger-chart-update:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
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

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
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

```yaml
jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      UPGRADE_TYPE: minor
```
