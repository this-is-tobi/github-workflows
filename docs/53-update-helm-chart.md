# `update-helm-chart.yml`

Bump a Helm chart version following its **own release lifecycle** (release-please-compatible logic, including prereleases), optionally injecting a new `appVersion`. The chart must live in the repository calling this workflow. Two delivery modes:

- **`called`** — update the chart via a pull request, optionally automerged. This is the mode a chart repository runs when it receives a dispatch from [`dispatch-helm-chart.yml`](./54-dispatch-helm-chart.md).
- **`local`** — bump the chart and commit directly on the current branch, exposing the new version as an output. Designed for **monorepos** where the chart lives next to the app and the bump happens mid-pipeline (chain with [`release-helm-local.yml`](./52-release-helm-local.md) to publish it in the same run).

The chart version and the app version are **decoupled on purpose**: an app release bumps the chart (patch/prerelease) and updates `appVersion`, while a chart-only change (leave `APP_VERSION` empty) bumps the chart without touching `appVersion`.

> **Chart in a separate repository?** Call [`dispatch-helm-chart.yml`](./54-dispatch-helm-chart.md) from the app repository. It triggers the chart repository's entry-point workflow, which calls this one in `called` mode.

> **Which mode where?** The repo that *hosts the chart* owns the release style: `called` = PR-gated (release-please style), `local` = direct in-pipeline. Both styles work identically whether the chart lives in a monorepo or in a dedicated chart repository — see the [chart release patterns matrix](./90-global-workflows-examples.md#helm-chart-release-patterns).

## Inputs

| Input                 | Type   | Description                                                                                       | Required | Default                |
| --------------------- | ------ | ------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUN_MODE              | string | How the bump is delivered: `called` (open a pull request) or `local` (commit directly on the current branch). An unrecognised value fails the job | Yes      | -                      |
| CHART_NAME            | string | Name of the chart to update (in `CHART_DIR`)                                                      | Yes      | -                      |
| CHART_DIR             | string | Directory containing the Helm charts                                                              | No       | charts                 |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion). Leave empty to keep the current appVersion (chart-only release). When set, must match `^[A-Za-z0-9][A-Za-z0-9.+_-]*$` | No       | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `auto` (default - level derived from the appVersion delta, see [`auto` mode](#auto-mode)), `major`, `minor`, `patch` or `prerelease` | No       | auto                   |
| PRERELEASE_IDENTIFIER | string | Identifier used when the bump enters the prerelease flow - `UPGRADE_TYPE: prerelease`, or `auto` with a prerelease `APP_VERSION` (e.g. `rc`). Must match `^[A-Za-z0-9-]+$`          | No       | rc                     |
| HELM_DOCS_VERSION     | string | Version of helm-docs used to regenerate the chart README. Pinned rather than tracking `:latest`   | No       | v1.14.2                |
| AUTOMERGE_PRERELEASE  | bool   | Automatically merge the PR when the bump is a prerelease (called mode)                      | No       | false                  |
| AUTOMERGE_RELEASE     | bool   | Automatically merge the PR when the bump is not a prerelease (called mode)                  | No       | false                  |
| AUTOMERGE_METHOD      | string | How the PR is merged when automerge is enabled: `auto` (queue until required checks pass, needs **Allow auto-merge**) or `admin` (merge now, bypassing branch protection) | No       | auto                   |
| BASE_BRANCH           | string | Base branch to open the chart-update pull request against (called mode)                           | No       | main                   |
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
| chart-version          | New chart version computed by the bump                                  |
| previous-chart-version | Chart version before the bump                                           |
| commit-sha             | SHA of the bump commit pushed on the current branch (local mode only)   |

## Permissions

| Scope         | Access | Description                                              |
| ------------- | ------ | -------------------------------------------------------- |
| contents      | write  | Commit modified chart & docs (both modes)                |
| pull-requests | write  | Create and merge the chart update PR (called mode)       |

> **In `local` mode** both scopes must still be granted, although that mode never uses `pull-requests: write`. A job's `permissions:` cannot depend on an input, and keeping both modes in one job is what avoids duplicating the ~130 lines of version-bump logic into a second file. The surplus is on your own repository, on top of the `contents: write` already needed to push.

## Token setup

A credential is required for **automerge**, and recommended in `called` mode so the chart update pull request actually runs its CI. Use either a **GitHub App** (preferred) or a **Personal Access Token**, stored as repository secrets in this repository.

### GitHub App (recommended)

Set `APP_CLIENT_ID` and `APP_PRIVATE_KEY`. Beyond automerge, this also makes the chart update pull request trigger `pull_request` workflows, which `GITHUB_TOKEN` cannot — see [Authentication](./05-authentication.md).

Required App repository permissions: **Contents: Read & Write, Pull requests: Read & Write, Metadata: Read**, installed on the **current** repository.

`APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`, which would silently authenticate as something other than the App.

### Automerge behaviour

The token is used for `gh pr merge --rebase`, with the method chosen by `AUTOMERGE_METHOD`:

- `auto` (default) queues the PR and lets GitHub merge it once all required status checks pass. This requires **Settings > General > Allow auto-merge** to be enabled on the repository.
- `admin` force-merges immediately, bypassing branch protection and required status checks.

There is **no automatic fallback between them**. If `auto` is selected and auto-merge is not enabled, the job fails with a message naming the setting to enable — falling back to `--admin` would merge past the very checks App authentication makes run.

#### Fine-grained PAT

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) scoped to this repository with:

| Permission    | Access       | Reason                                   |
| ------------- | ------------ | ---------------------------------------- |
| Contents      | Read & Write | Required by `gh pr merge`                |
| Pull requests | Read & Write | Enable auto-merge on the chart update PR |

> If the repository does **not** have "Allow auto-merge" enabled, the PAT owner must be a **repository admin** for the `--admin` merge to succeed.

#### Classic PAT

Create a [classic token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) with the **`repo`** scope.

#### Where to store it

Add the token as a **repository secret** named `GH_PAT` in this repository:  
**Settings > Secrets and variables > Actions > New repository secret**

## Notes

- `RUN_MODE=called`: Reads the current chart `version` from `<CHART_DIR>/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using Release Please-compatible logic, updates `version` (and `appVersion` when `APP_VERSION` is provided), regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- `RUN_MODE=local`: Same bump as `called`, but **commits directly on the current branch** instead of opening a PR, and exposes `chart-version` / `commit-sha` outputs so downstream jobs in the same pipeline can publish the chart (chain with [`release-helm-local.yml`](./52-release-helm-local.md)'s `CHECKOUT_REF`). Notes:
  - The push is authenticated with `GITHUB_TOKEN`, and such pushes **never trigger new workflow runs** — no CD loop; release the chart in the same run using the outputs. The commit deliberately carries no skip-ci marker: `GITHUB_TOKEN` alone already prevents the loop, and the marker would additionally suppress `pull_request` checks for any pull request a human later opens FROM this branch (e.g. a manual `develop` → `main` promotion).
  - Direct pushes require the branch to accept them (no "require a pull request" protection rule for `github-actions[bot]`); if your branch is protected, use `called` mode with automerge instead.
  - Leave `APP_VERSION` empty for a **chart-only release** (bumps `version`, keeps `appVersion`).
- An unrecognised `RUN_MODE` **fails the job** rather than quietly doing nothing.
- **Version bump logic** (Release Please compatible):
  - `major`: `1.2.3` → `2.0.0`
  - `minor`: `1.2.3` → `1.3.0`
  - `patch`: `1.2.3` → `1.2.4`
  - `prerelease`: `1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2` (from a stable version the patch is bumped first, then the prerelease counter increments)
- **Automerge (called mode)**: If `AUTOMERGE_PRERELEASE: true` (when the bump is a prerelease) or `AUTOMERGE_RELEASE: true` (otherwise), the workflow merges the PR automatically. The distinction is made on the **resolved** flow, not the `UPGRADE_TYPE` input: under `auto`, an rc bump is treated as a prerelease. It is gated on those inputs alone — supplying credentials never enables it by itself, and if no credential is supplied the job **fails** rather than skipping silently.
  - `AUTOMERGE_METHOD: auto` (default) uses `gh pr merge --auto`; the merge happens once required checks pass. Requires *Allow auto-merge* on the repository, and fails naming that setting if it is off.
  - `AUTOMERGE_METHOD: admin` uses `gh pr merge --admin` to force-merge immediately, bypassing branch protection and required checks.
  - There is **no automatic fallback** between them.
  - Merge strategy is `--rebase`.
- **Injection**: `APP_VERSION` and `PRERELEASE_IDENTIFIER` are written into `Chart.yaml` with `yq` + `strenv()`, never `sed`, so they can only ever be stored, never interpreted. They are validated at the top of the job as well.
- Branch naming pattern (called mode): `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq` and `docker` (for `jnorwood/helm-docs`).

## Examples

> These examples use GitHub App credentials, the recommended mode. To use a personal access token instead, replace the two `APP_*` lines with <span v-pre>`GH_PAT: ${{ secrets.GH_PAT }}`</span> — nothing else changes. See [Authentication](./05-authentication.md) for end-to-end setup of either.

### Called mode

Runs the version update in the current repository. Reads `charts/my-service/Chart.yaml`, bumps `version` by a minor increment, sets `appVersion: 1.4.0`, regenerates docs with `helm-docs`, and opens a PR with the changes.

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

### Called mode – prerelease bump

`UPGRADE_TYPE: prerelease` bumps the chart prerelease version (`1.2.3` → `1.2.4-rc` → `1.2.4-rc.1` → `1.2.4-rc.2`: from a stable version the patch is bumped first, then the counter increments). `APP_VERSION` is written as-is into `appVersion`; only the chart `version` field follows the prerelease bump logic.
### `auto` mode

`UPGRADE_TYPE: auto` makes the chart mirror the app's own bump instead of a level the caller hardcodes:

- **The level** is derived from the appVersion delta - what `Chart.yaml` holds before the update vs `APP_VERSION` (different major → `major`, different minor → `minor`, else `patch`). Only the `X.Y.Z` base is compared.
- **The flow** is selected by the shape of `APP_VERSION`: a prerelease (e.g. `0.3.0-rc.1`) enters or continues the chart's rc cycle, a stable version applies the standard bump (or strips the suffix when the chart is mid-cycle). One value therefore covers both branches of a two-branch pipeline - no more conditioning on `github.ref_name`.

| Current chart (version / appVersion) | `APP_VERSION` | Result | Why |
| --- | --- | --- | --- |
| `0.2.8` / `0.2.2` | `0.2.3-rc` | `0.2.9-rc` | patch delta, cycle entry |
| `0.2.8` / `0.2.2` | `0.3.0-rc` | `0.3.0-rc` | minor delta, the cycle opens at the right level |
| `0.3.0-rc` / `0.3.0-rc` | `0.3.0-rc.1` | `0.3.0-rc.1` | cycle iteration |
| `0.2.9-rc.2` / `0.2.3-rc.1` | `0.3.0-rc.1` | `0.3.0-rc.2` | mid-cycle escalation: the base rises, the counter is carried verbatim - the same rule release-please applies to the app |
| `0.3.0-rc.2` / `0.3.0-rc.2` | `0.3.0` | `0.3.0` | promotion: the level is already in the base, the suffix is dropped |
| `0.3.0` / `0.3.0` | `0.3.1` | `0.3.1` | direct hotfix on the release branch |

When there is no delta to read, `auto` falls back to a patch bump with a warning rather than failing - it is the default value, and a default cannot demand what the caller never stated:

- Empty `APP_VERSION` (chart-only release): patch bump, with a warning suggesting an explicit level.
- Non-semver current `appVersion` (e.g. `latest`, common on a chart predating the pipeline): patch bump for this run; the run writes a real version into `appVersion`, so the delta is derivable from the next run on. The flow still follows the shape of `APP_VERSION`: a prerelease never yields a stable chart version.

Only an `APP_VERSION` that is supplied but not semver fails the run: that value came from the caller on this very run.


```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0-rc.1
      UPGRADE_TYPE: prerelease
      PRERELEASE_IDENTIFIER: rc
      AUTOMERGE_PRERELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

### Local mode – monorepo pipeline

The chart lives in the same repository as the app. After `release-app` publishes the app version, the chart is bumped **on its own lifecycle** (`prerelease` on `develop`, `patch` on `main` — graduation from `x.y.z-rc.n` to `x.y.z` is automatic), committed directly on the branch, then published to the OCI registry in the same run by `release-helm-local`.

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
      # UPGRADE_TYPE defaults to 'auto': the chart mirrors the app's bump,
      # derived from the appVersion delta, and the shape of APP_VERSION
      # selects the flow (rc cycle or release) - the same on both branches.
      APP_VERSION: ${{ needs.release.outputs.version }}

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
