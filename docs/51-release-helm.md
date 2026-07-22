# `release-helm.yml`

Release Helm charts to an OCI registry (e.g. `ghcr.io`). Two strategies are available via `MODE`:

- **`chart-releaser`** (default) — uses [`chart-releaser-action`](https://github.com/helm/chart-releaser-action) to auto-detect charts whose version changed since the last git tag, package them, push them to the OCI registry, and optionally (`CREATE_GITHUB_RELEASE: true`) create GitHub Releases + tags and maintain a classic `index.yaml` Helm repo on a pages branch. Best for a **dedicated charts repository**.
- **`local`** — packages a specific chart from the current repository at an explicit version (`helm package`) and pushes it to the OCI registry. No git-tag change detection, no GitHub Pages. Best for a **monorepo** where the chart lives alongside application code (see [Modes](#modes)).

See [Modes](#modes) for how to choose.

## Inputs

| Input                 | Type    | Description                                                                                                                                                                                           | Required | Default          |
| --------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| MODE                  | string  | Release strategy: `chart-releaser` (auto-detect changed charts — dedicated charts repo) or `local` (package a specific chart at an explicit version and push to OCI — monorepo). See [Modes](#modes). | No       | chart-releaser   |
| CHARTS_DIR            | string  | Directory containing the Helm charts                                                                                                                                                                  | No       | ./charts         |
| CHART_NAME            | string  | **local mode** — chart directory under `CHARTS_DIR` to release (e.g. `my-app`). Leave empty to package every chart directly under `CHARTS_DIR`.                                                       | No       | -                |
| CHART_VERSION         | string  | **local mode** — chart version to stamp (`helm package --version`). Defaults to the `version` already in `Chart.yaml`.                                                                                | No       | -                |
| APP_VERSION           | string  | **local mode** — app version to stamp (`helm package --app-version`). Defaults to the `appVersion` already in `Chart.yaml`.                                                                           | No       | -                |
| CHECKOUT_REF          | string  | **local mode** — git ref (branch or SHA) to check out before packaging, e.g. the `commit-sha` output of `update-helm-chart.yml` local mode. Defaults to the commit that triggered the workflow.       | No       | -                |
| CREATE_GITHUB_RELEASE | boolean | **chart-releaser mode** — also create a GitHub Release and git tag per changed chart and update `index.yaml` on the pages branch. Requires the pages branch to already exist.                         | No       | false            |
| PAGES_BRANCH          | string  | **chart-releaser mode** — branch that receives `index.yaml` when `CREATE_GITHUB_RELEASE` is `true`. Must already exist.                                                                               | No       | gh-pages         |
| HELM_REPOS            | string  | Helm repositories to add for chart dependencies (name=url, comma-separated). Optional; skipped if empty.                                                                                              | No       | -                |
| REGISTRY              | string  | OCI registry to push charts to (e.g. `ghcr.io`, `registry.gitlab.com`)                                                                                                                                | No       | ghcr.io          |
| REPOSITORY            | string  | Repository path in the OCI registry (defaults to `github.repository`)                                                                                                                                 | No       | -                |
| RUNS_ON               | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                                                              | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                | Required |
| ----------------- | ------------------------------------------------------------------------------------------ | -------- |
| REGISTRY_USERNAME | Username for OCI registry authentication (uses `github.actor` automatically for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password for OCI registry authentication (uses `GITHUB_TOKEN` automatically for `ghcr.io`) | No       |

## Permissions

Grant these on the **caller** job depending on the mode:

| Scope    | Access | When                                                                                                    |
| -------- | ------ | ------------------------------------------------------------------------------------------------------- |
| packages | write  | Always — push charts to the OCI registry (`ghcr.io`)                                                    |
| contents | read   | `local` mode — checkout only                                                                            |
| contents | write  | `chart-releaser` mode with `CREATE_GITHUB_RELEASE: true` — create releases/tags and update `index.yaml` |

> The reusable workflow declares one job per mode; only the job matching `MODE` runs. In `chart-releaser` mode grant `contents: write` (harmless if `CREATE_GITHUB_RELEASE` is left `false`); in `local` mode `contents: read` is sufficient.

## Modes

Choose `MODE` based on where the chart lives:

### `chart-releaser` (default) — dedicated charts repository

Uses `chart-releaser-action`, which finds changed charts by running `git diff` between the **latest git tag** and `HEAD`, scoped to `CHARTS_DIR`. It then packages each chart whose `Chart.yaml` version doesn't yet have a release. This is ideal when the repository's tags belong to the charts (e.g. `my-chart-1.2.0`).

### `local` — monorepo (chart alongside application code)

In a monorepo the git-tag namespace is dominated by **application** tags (e.g. `v1.2.3`, and the moving `v1`/`v1.2` tags produced by `release-app` with `TAG_MAJOR_AND_MINOR`). `chart-releaser`'s "latest tag" diff base then points at a recent app commit, so it frequently detects **no changed charts and releases nothing**. `local` mode sidesteps this entirely:

- No git-tag change detection — you drive the release explicitly.
- Packages `CHARTS_DIR/CHART_NAME` (or every chart under `CHARTS_DIR` if `CHART_NAME` is empty) with `helm package`, stamping `CHART_VERSION`/`APP_VERSION` when provided (no `Chart.yaml` commit required).
- Pushes the resulting `.tgz` to the OCI registry. No GitHub Pages, no GitHub Release.

**Keep the two lifecycles separate**: the chart has its own semver stream — it bumps when the app releases (with a new `appVersion`), but it can also release on its own (values/template fix, no app change). The version brain for that is [`update-helm-chart.yml`](./52-update-helm-chart.md) in `local` mode: it computes the next chart version (release-please-compatible, prerelease-aware), commits the bump on the branch, and outputs `commit-sha` — which you feed to this workflow via `CHECKOUT_REF` so the published package matches the committed state. The `CHART_VERSION`/`APP_VERSION` stamping inputs are an escape hatch for stateless setups; prefer the committed `Chart.yaml` as the source of truth. See the [monorepo example](#monorepo-local-mode) and the [CI/CD examples](./90-global-workflows-examples.md).

> `local` mode is the **harmonized publisher** across topologies: it publishes the committed `Chart.yaml` whether the bump arrived via a direct commit (same-run `CHECKOUT_REF`) or a merged PR (a `paths: charts/**` chart CD with a version-bumped guard). The full 2×2 matrix — PR-gated vs direct × monorepo vs dedicated chart repo — is documented in the [chart release patterns](./90-global-workflows-examples.md#helm-chart-release-patterns).

## Notes

- **CREATE_GITHUB_RELEASE behavior** (chart-releaser mode): When `false` (the default), the workflow only packages changed charts and pushes them to the OCI registry — **no GitHub Pages branch is required**. When `true`, it additionally creates a GitHub Release and git tag for each changed chart and updates `index.yaml` on the pages branch (e.g. `gh-pages`); this **requires that pages branch to already exist** and a grant of `contents: write`.
- **HELM_REPOS is optional** (both modes): The "add repos" step is skipped when `HELM_REPOS` is empty. Provide it when your charts pull dependencies from external repositories (used by `helm dependency update` in `local` mode, and by `chart-releaser` packaging).
- **chart-releaser mode** detects charts via `git diff` from the latest git tag and only releases charts whose `Chart.yaml` version was bumped compared to the previous release; requires SemVer chart versions and `fetch-depth: 0` (the workflow sets it).
- **local mode** does not inspect git history: it packages exactly what you point it at, at the version in `Chart.yaml` unless `CHART_VERSION`/`APP_VERSION` override it. This makes chart releases deterministic in a monorepo and needs no `Chart.yaml` commit.
- Charts can be pulled using: `helm pull oci://ghcr.io/<owner>/<repo>/<chart-name> --version <version>`

## Examples

The examples show releasing to the default GitHub Packages (ghcr.io) OCI registry, publishing to a custom registry with explicit credentials, a minimal setup that relies entirely on workflow defaults, and opting into GitHub Releases.

### Simple example

With default settings, packages the changed charts and pushes them to the OCI registry (no GitHub Pages branch needed). External repositories are optionally pre-registered via `HELM_REPOS`.

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
```

### Custom OCI registry

To push charts to a registry other than `ghcr.io`, supply credentials as secrets:

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CHARTS_DIR: ./charts
      REGISTRY: registry.example.com
      REPOSITORY: my-org/helm-charts
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Minimal (GitHub Packages only)

When all defaults are acceptable (ghcr.io, charts in `./charts`, no external repos):

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
```

### Also create GitHub Releases (classic Helm repo)

Set `CREATE_GITHUB_RELEASE: true` to additionally create GitHub Releases and git tags and maintain an `index.yaml`-based Helm repo on the pages branch. The `PAGES_BRANCH` (default `gh-pages`) **must already exist** in the repository.

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CREATE_GITHUB_RELEASE: true
      PAGES_BRANCH: gh-pages
```

### Monorepo (local mode)

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
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: patch

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      MODE: local
      CHARTS_DIR: ./charts
      CHART_NAME: my-app
      # Package exactly the bump commit pushed by update-helm-chart
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

> The chart and the app deliberately keep **separate versions**: here an app `1.4.0` release might publish chart `0.7.3` with `appVersion: 1.4.0`. A chart-only fix re-runs the same `bump-chart` + `release-chart` pair with `APP_VERSION` omitted. The `CHART_VERSION`/`APP_VERSION` inputs of this workflow remain available as a stateless escape hatch (stamp at package time, no commit), if you accept that `Chart.yaml` in git won't reflect published versions.
