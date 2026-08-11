# `release-helm-local.yml`

Package a specific Helm chart from the **current repository** at an explicit version (`helm package`) and push it to an OCI registry (e.g. `ghcr.io`). No git-tag change detection, no GitHub Pages, no GitHub Release — just package and push whatever commit you point it at.

Use this instead of [`release-helm.yml`](./51-release-helm.md) when the chart lives in a **monorepo** alongside application code. In a monorepo the git-tag namespace is dominated by **application** tags (e.g. `v1.2.3`, and the moving `v1`/`v1.2` tags produced by `release-app` with `TAG_MAJOR_AND_MINOR`). `chart-releaser`'s "latest tag" diff base then points at a recent app commit, so it frequently detects **no changed charts and releases nothing**. This workflow sidesteps that entirely: you drive the release explicitly, with no git-tag inspection at all.

## Why a separate workflow

This used to be a `MODE: local` branch inside `release-helm.yml`, alongside the `chart-releaser` code path. GitHub validates a reusable workflow's *entire* declared job graph against what the caller grants — including a job gated behind an `if:` on `MODE` that will never be true for a given caller. A monorepo caller passing `MODE: local` still had to grant `contents: write` (needed only by the `chart-releaser` job, which never ran for it), or the run failed at startup:

```
Error calling workflow '.../release-helm.yml@v0'.
The nested job 'release' is requesting 'contents: write', but is only allowed 'contents: read'.
```

Splitting into two files means each one only ever declares the permissions its own job needs — this workflow needs `contents: read`, full stop, because it never creates a git tag, release or pages commit.

The same reasoning splits [`dispatch-helm-chart.yml`](./54-dispatch-helm-chart.md) out of [`update-helm-chart.yml`](./53-update-helm-chart.md). `ci/tests/permission-union.test.sh` now enforces the rule, so a future workflow cannot quietly reintroduce the shape.

## Inputs

| Input         | Type   | Description                                                                                                                                              | Required | Default          |
| ------------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| CHARTS_DIR    | string | Directory containing the Helm charts                                                                                                                      | No       | ./charts         |
| CHART_NAME    | string | Chart directory under `CHARTS_DIR` to release (e.g. `my-app`). Leave empty to package every chart directly under `CHARTS_DIR`.                            | No       | -                |
| CHART_VERSION | string | Chart version to stamp (`helm package --version`). Defaults to the `version` already in `Chart.yaml`.                                                     | No       | -                |
| APP_VERSION   | string | App version to stamp (`helm package --app-version`). Defaults to the `appVersion` already in `Chart.yaml`.                                                | No       | -                |
| CHECKOUT_REF  | string | Git ref (branch or SHA) to check out before packaging, e.g. the `commit-sha` output of `update-helm-chart.yml` local mode. Defaults to the commit that triggered the workflow. | No | -           |
| HELM_REPOS    | string | Helm repositories to add for chart dependencies (name=url, comma-separated). Optional; skipped if empty.                                                  | No       | -                |
| REGISTRY      | string | OCI registry to push charts to (e.g. `ghcr.io`, `registry.gitlab.com`)                                                                                     | No       | ghcr.io          |
| REPOSITORY    | string | Repository path in the OCI registry (defaults to `github.repository`)                                                                                     | No       | -                |
| RUNS_ON       | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                  | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                | Required |
| ----------------- | ------------------------------------------------------------------------------------------ | -------- |
| REGISTRY_USERNAME | Username for OCI registry authentication (uses `github.actor` automatically for `ghcr.io`). **Required** when `REGISTRY` is not `ghcr.io` | No       |
| REGISTRY_PASSWORD | Password for OCI registry authentication (uses `GITHUB_TOKEN` automatically for `ghcr.io`). **Required** alongside `REGISTRY_USERNAME` under the same conditions | No       |

No GitHub App/PAT credentials — this workflow never creates a git tag, release or commit, so there's nothing that needs a credential beyond registry login.

## Permissions

| Scope    | Access | Description       |
| -------- | ------ | ------------------ |
| contents | read   | Checkout only       |
| packages | write  | Push the chart to the OCI registry (`ghcr.io`) |

## Notes

- Does not inspect git history: it packages exactly what you point it at, at the version in `Chart.yaml` unless `CHART_VERSION`/`APP_VERSION` override it. This makes chart releases deterministic in a monorepo and needs no `Chart.yaml` commit.
- **Keep the chart and app lifecycles separate**: the chart has its own semver stream — it bumps when the app releases (with a new `appVersion`), but it can also release on its own (values/template fix, no app change). The version brain for that is [`update-helm-chart.yml`](./53-update-helm-chart.md) in `local` mode: it computes the next chart version (release-please-compatible, prerelease-aware), commits the bump on the branch, and outputs `commit-sha` — which you feed to this workflow via `CHECKOUT_REF` so the published package matches the committed state. The `CHART_VERSION`/`APP_VERSION` stamping inputs are an escape hatch for stateless setups; prefer the committed `Chart.yaml` as the source of truth.
- **Harmonized publisher**: this workflow publishes the committed `Chart.yaml` whether the bump arrived via a direct commit (same-run `CHECKOUT_REF`) or a merged PR (a `paths: charts/**` chart CD with a version-bumped guard). The full 2×2 matrix — PR-gated vs direct × monorepo vs dedicated chart repo — is documented in the [chart release patterns](./90-global-workflows-examples.md#helm-chart-release-patterns).
- **No `PUBLISH_OCI` switch, unlike [`release-helm.yml`](./51-release-helm.md)**: the OCI registry is this workflow's only distribution channel. In a monorepo the GitHub Releases and git tags belong to the *application*, so the chart cannot claim them for its own packages — which rules out the tgz-on-release + `index.yaml` channel chart-releaser offers in a dedicated chart repository. An input to disable the OCI push would leave this workflow with nothing to publish, so there isn't one.
- **Registry credentials are validated up front**: with a `REGISTRY` other than `ghcr.io`, missing `REGISTRY_USERNAME`/`REGISTRY_PASSWORD` fail the run with an explicit message rather than reaching `helm registry login` with an empty password and failing on an opaque authentication error.
- **Credentials are cleared afterwards**: a `helm registry logout` step runs whenever the login succeeded, including after a failed push. Hosted runners are ephemeral so this is a no-op there, but `RUNS_ON` also supports self-hosted runners, where Helm's registry config would otherwise outlive the job.
- Charts can be pulled using: `helm pull oci://ghcr.io/<owner>/<repo>/<chart-name> --version <version>`

## Examples

### Monorepo chart, released alongside the app

The chart lives in the same repository as the app (e.g. `charts/my-app`) and is released as part of the app pipeline — but on **its own version stream**. `update-helm-chart` (local mode) computes and commits the chart bump (setting `appVersion` to the app release), then this workflow packages that exact commit and pushes it to the OCI registry. No `gh-pages`, no chart-releaser change detection, no chart-bump PR.

```yaml
on:
  push:
    branches:
    - main

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
      CHART_NAME: my-app
      # UPGRADE_TYPE defaults to 'auto': the chart mirrors the app's bump,
      # derived from the appVersion delta.
      APP_VERSION: ${{ needs.release.outputs.version }}

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm-local.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      CHARTS_DIR: ./charts
      CHART_NAME: my-app
      # Package exactly the bump commit pushed by update-helm-chart
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

> The chart and the app deliberately keep **separate versions**: here an app `1.4.0` release might publish chart `0.7.3` with `appVersion: 1.4.0`. A chart-only fix re-runs the same `bump-chart` + `release-chart` pair with `APP_VERSION` omitted. The `CHART_VERSION`/`APP_VERSION` inputs of this workflow remain available as a stateless escape hatch (stamp at package time, no commit), if you accept that `Chart.yaml` in git won't reflect published versions.

### Custom OCI registry

```yaml
jobs:
  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm-local.yml@v0
    permissions:
      contents: read
      packages: write
    with:
      CHARTS_DIR: ./charts
      CHART_NAME: my-app
      REGISTRY: registry.example.com
      REPOSITORY: my-org/helm-charts
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```
