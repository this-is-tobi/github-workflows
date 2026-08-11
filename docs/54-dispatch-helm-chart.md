# `dispatch-helm-chart.yml`

Trigger a chart update in a **separate chart repository**, via `workflow_dispatch`.

The app repository writes nothing: it sends the version to the chart repository, which runs its own entry-point workflow (normally [`update-helm-chart.yml`](./53-update-helm-chart.md) in `called` mode) and opens the pull request on its side.

> If the chart lives in the **same repository** as the app, this is not the workflow you want — call [`update-helm-chart.yml`](./53-update-helm-chart.md) directly.

## Inputs

| Input                 | Type   | Description                                                                                                                             | Required | Default                |
| --------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| CHART_REPO            | string | Target chart repository (`owner/repo`)                                                                                                  | Yes      | -                      |
| CHART_NAME            | string | Name of the chart to update (in `CHART_DIR`)                                                                                            | Yes      | -                      |
| WORKFLOW_NAME         | string | Workflow file name to trigger in the chart repository                                                                                   | No       | update-app-version.yml |
| CHART_DIR             | string | Directory containing the Helm charts (in `CHART_REPO`)                                                                                  | No       | charts                 |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion). Leave empty to keep the current appVersion (chart-only release)                 | No       | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, `prerelease`, or `auto` - forwarded verbatim to the chart repository, where [`update-helm-chart.yml`](./53-update-helm-chart.md#auto-mode) derives the level from the appVersion delta | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`)                                                                              | No       | rc                     |
| AUTOMERGE_PRERELEASE  | bool   | Ask the chart repository to merge its update PR when `UPGRADE_TYPE` is `prerelease`                                                     | No       | false                  |
| AUTOMERGE_RELEASE     | bool   | Ask the chart repository to merge its update PR when `UPGRADE_TYPE` is not `prerelease`                                                 | No       | false                  |
| AUTOMERGE_METHOD      | string | How the chart repository should merge: `auto` (queue until required checks pass, needs **Allow auto-merge** there) or `admin` (merge now, bypassing branch protection) | No       | auto                   |
| BASE_BRANCH           | string | Branch of `CHART_REPO` the workflow is dispatched on, and the base its pull request is opened against                                    | No       | main                   |
| RUNS_ON               | string | Runner labels as JSON array                                                                                                             | No       | ["ubuntu-24.04"]       |

## Secrets

| Secret          | Description                                                                                                                              | Required | Default |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| APP_CLIENT_ID   | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, authenticates as a GitHub App — takes precedence over `GH_PAT`. See [Authentication](./05-authentication.md) | No\*     | -       |
| APP_PRIVATE_KEY | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                                                                          | No\*     | -       |
| GH_PAT          | GitHub Personal Access Token. Legacy alternative, still supported (see [Token setup](#token-setup))                                       | No\*     | -       |

\* None is formally required, but **one of the two modes must be supplied**: `APP_CLIENT_ID` + `APP_PRIVATE_KEY`, or `GH_PAT`. `GITHUB_TOKEN` cannot dispatch a workflow in another repository; with no credential the job fails explicitly rather than doing nothing.

## Permissions

| Scope | Access | Description |
| ----- | ------ | ----------- |
| -     | -      | None        |

This is the entire reason the workflow is separate. Everything it does authenticates against `CHART_REPO` with the App token (or `GH_PAT`); **nothing touches the calling repository**. The calling job should therefore declare `permissions: {}`:

```yaml
  dispatch-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/dispatch-helm-chart.yml@v0
    permissions: {}
    with:
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

> **Why dispatching lives in its own workflow.** GitHub validates the permissions requested by **every** job of a called reusable workflow at parse time, whatever their `if:`. A caller always grants the union, so any job sharing a workflow with this one would push its own scopes onto every dispatch call — for work that never runs. One job per privilege level is what keeps `permissions: {}` reachable here. `ci/tests/permission-union.test.sh` enforces the rule across all the reusable workflows.

## Token setup

The credential is used for `gh workflow run --repo <CHART_REPO>`, and is minted scoped to that repository alone.

### GitHub App (recommended)

Set `APP_CLIENT_ID` and `APP_PRIVATE_KEY` as repository secrets in the **app repository** (the one calling this workflow).

| Requirement       | Value                                                        |
| ----------------- | ------------------------------------------------------------ |
| App installed on  | the **chart** repository (`CHART_REPO`), not the app one     |
| App permissions   | Actions: Read & Write, Metadata: Read                        |
| Token scoped to   | `CHART_REPO` only — never the current repository             |

`CHART_REPO` must be given as `owner/repository`; a bare repository name is rejected before any token is minted, since it would otherwise resolve the owner to the repository name.

`APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`, which would silently authenticate as something other than the App.

### Fine-grained PAT

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) scoped to the **target chart repository** (`CHART_REPO`) with:

| Permission | Access       | Reason                                      |
| ---------- | ------------ | ------------------------------------------- |
| Actions    | Read & Write | Trigger workflow dispatch in the chart repo |

### Classic PAT

Create a [classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) with the **`repo`** scope (grants access to all repos the user can access).

### Where to store it

Add the token as a **repository secret** named `GH_PAT` in the **source (app) repository** — the one that calls this workflow:  
**Settings > Secrets and variables > Actions > New repository secret**

> If the chart repository also uses automerge, it needs its **own** credential for `gh pr merge` — see [`update-helm-chart.yml`](./53-update-helm-chart.md#token-setup). The same PAT can serve both if it has permissions on both repositories.

## Notes

- The dispatch is **asynchronous**: this job succeeds as soon as the `workflow_dispatch` is accepted, without waiting for the update to complete in `CHART_REPO`.
- **`BASE_BRANCH` is always passed explicitly** (`gh workflow run --ref`). Without it, `gh` resolves `CHART_REPO`'s default branch itself through a GraphQL `defaultBranchRef` query, which exceeds the token's `actions: write` scope and fails (`unable to determine default branch for <repo>: GraphQL: Resource not accessible by integration (repository.defaultBranchRef)`). If `CHART_REPO`'s default branch isn't `main`, set `BASE_BRANCH` — this applies with either credential, App or `GH_PAT`.
- **`AUTOMERGE_METHOD` compatibility**: a chart repository whose entry-point workflow does not declare that input makes the API reject the whole dispatch (`422 Unexpected inputs provided`) rather than ignore the extra value. The dispatch is therefore retried once without it and emits a `::warning::` saying the chart repository's own default applies. Add the `AUTOMERGE_METHOD` input to that workflow to control the merge method from the app side — the [template](./90-global-workflows-examples.md#update-app-version-workflow) includes it.
- **Validation happens before the token is minted**: `CHART_REPO` is checked for shape (`owner/repository`, single line) and `BASE_BRANCH` for embedded whitespace up front, so a malformed value fails cheaply instead of surfacing as an opaque API error.

## Dispatch contract

`CHART_REPO`'s entry-point workflow must be `workflow_dispatch`-triggerable and declare these inputs — GitHub rejects a dispatch carrying an undeclared input instead of ignoring it:

| Input                   | Sent by this workflow                            |
| ----------------------- | ------------------------------------------------ |
| `RUN_MODE`              | always `called`                                  |
| `APP_VERSION`           | `inputs.APP_VERSION`                             |
| `CHART_NAME`            | `inputs.CHART_NAME`                              |
| `CHART_DIR`             | `inputs.CHART_DIR` (trailing slashes stripped)   |
| `UPGRADE_TYPE`          | `inputs.UPGRADE_TYPE`                            |
| `PRERELEASE_IDENTIFIER` | `inputs.PRERELEASE_IDENTIFIER`                   |
| `AUTOMERGE_PRERELEASE`  | `inputs.AUTOMERGE_PRERELEASE`                    |
| `AUTOMERGE_RELEASE`     | `inputs.AUTOMERGE_RELEASE`                       |
| `AUTOMERGE_METHOD`      | `inputs.AUTOMERGE_METHOD` (see compatibility above) |

A ready-to-use entry-point workflow is in the [CI/CD examples](./90-global-workflows-examples.md#update-app-version-workflow).

## Examples

> These examples use GitHub App credentials, the recommended mode. To use a personal access token instead, replace the two `APP_*` lines with <span v-pre>`GH_PAT: ${{ secrets.GH_PAT }}`</span> — nothing else changes. The App must be installed on the repository named by `CHART_REPO`, since the token is minted scoped to it. See [Authentication](./05-authentication.md) for end-to-end setup of either.

### Dispatch after an app release

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write

  trigger-chart-update:
    uses: this-is-tobi/github-workflows/.github/workflows/dispatch-helm-chart.yml@v0
    needs:
    - release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    # Nothing is written on this repository: everything goes through the App
    # token to CHART_REPO.
    permissions: {}
    with:
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: minor
      AUTOMERGE_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Prerelease bump with automerge

`UPGRADE_TYPE: prerelease` bumps the chart prerelease version (`1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2`: from a stable version the patch is bumped first, then the counter increments). `APP_VERSION` is written as-is into `appVersion`; only the chart `version` field follows the prerelease bump logic. `AUTOMERGE_PRERELEASE: true` asks the chart repository to merge the resulting PR.

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/dispatch-helm-chart.yml@v0
    permissions: {}
    with:
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

### Chart repository whose default branch isn't `main`

```yaml
jobs:
  trigger-chart-update:
    uses: this-is-tobi/github-workflows/.github/workflows/dispatch-helm-chart.yml@v0
    permissions: {}
    with:
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0
      # Dispatched on this branch of CHART_REPO, and the base of the PR opened there.
      BASE_BRANCH: develop
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```
