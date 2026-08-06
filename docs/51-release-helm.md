# `release-helm.yml`

Release Helm charts to an OCI registry (e.g. `ghcr.io`) using [`chart-releaser-action`](https://github.com/helm/chart-releaser-action), which auto-detects charts whose version changed since the last git tag, packages them, pushes them to the OCI registry, and optionally (`CREATE_GITHUB_RELEASE: true`) creates GitHub Releases + tags and maintains a classic `index.yaml` Helm repo on a pages branch. Best for a **dedicated charts repository**, where the repository's git tags belong to the charts.

For a **monorepo** — a chart living alongside application code, where the tag namespace is dominated by app tags and chart-releaser's "latest tag" change detection is unreliable — use [`release-helm-local.yml`](./52-release-helm-local.md) instead. The two are separate workflow files rather than one workflow with a mode switch: each declares only the permissions its own logic needs, so a monorepo caller never has to grant `contents: write` for a chart-releaser code path it will never run. See [`release-helm-local.yml`](./52-release-helm-local.md#why-a-separate-workflow) for the full reasoning.

## Inputs

| Input                 | Type    | Description                                                                                                                     | Required | Default          |
| --------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| CHARTS_DIR            | string  | Directory containing the Helm charts                                                                                              | No       | ./charts         |
| CREATE_GITHUB_RELEASE | boolean | Also create a GitHub Release and git tag per changed chart and update `index.yaml` on the pages branch. Requires the pages branch to already exist. | No       | false            |
| PAGES_BRANCH          | string  | Branch that receives `index.yaml` when `CREATE_GITHUB_RELEASE` is `true`. Must already exist.                                    | No       | gh-pages         |
| HELM_REPOS            | string  | Helm repositories to add for chart dependencies (name=url, comma-separated). Optional; skipped if empty.                          | No       | -                |
| REGISTRY              | string  | OCI registry to push charts to (e.g. `ghcr.io`, `registry.gitlab.com`)                                                            | No       | ghcr.io          |
| REPOSITORY            | string  | Repository path in the OCI registry (defaults to `github.repository`)                                                             | No       | -                |
| RUNS_ON               | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                          | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                | Required |
| ----------------- | ------------------------------------------------------------------------------------------ | -------- |
| REGISTRY_USERNAME | Username for OCI registry authentication (uses `github.actor` automatically for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password for OCI registry authentication (uses `GITHUB_TOKEN` automatically for `ghcr.io`) | No       |
| APP_CLIENT_ID     | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, chart-releaser authenticates as a GitHub App. See [Authentication](./05-authentication.md) | No       |
| APP_PRIVATE_KEY   | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                            | No       |
| GH_PAT            | Personal access token, same purpose as the App credentials and resolved after them | No       |

> **Why supply App credentials here.** Releases created with `GITHUB_TOKEN` cannot fire `release:` triggers — GitHub's anti-recursion rule. If you have a workflow that should run when a chart release is published, chart-releaser needs an App token. Otherwise `GITHUB_TOKEN` is fine.
>
> `cr index --push` authenticates the `PAGES_BRANCH` push with the same token, so an App token or `GH_PAT` also lets **that** push trigger workflows. Harmless unless a workflow triggers on the pages branch — check before pointing one at it.
>
> The App token is only minted when `CREATE_GITHUB_RELEASE` is `true` — with it `false` the workflow only packages charts and pushes them to the OCI registry, so there is nothing for a write-capable token to do.
>
> `APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`.

## Permissions

| Scope    | Access | Description                                                            |
| -------- | ------ | ------------------------------------------------------------------------ |
| packages | write  | Push charts to the OCI registry (`ghcr.io`)                              |
| contents | write  | Create releases/tags and update `index.yaml` when `CREATE_GITHUB_RELEASE` is `true` (harmless to grant unconditionally if left `false`) |

## Notes

- **CREATE_GITHUB_RELEASE behavior**: When `false` (the default), the workflow only packages changed charts and pushes them to the OCI registry — **no GitHub Pages branch is required**. When `true`, it additionally creates a GitHub Release and git tag for each changed chart and updates `index.yaml` on the pages branch (e.g. `gh-pages`); this **requires that pages branch to already exist**.
- **HELM_REPOS is optional**: The "add repos" step is skipped when `HELM_REPOS` is empty. Provide it when your charts pull dependencies from external repositories.
- Detects charts via `git diff` from the latest git tag and only releases charts whose `Chart.yaml` version was bumped compared to the previous release; requires SemVer chart versions and `fetch-depth: 0` (the workflow sets it).
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

### Monorepo chart

For a chart living alongside application code, see [`release-helm-local.yml`](./52-release-helm-local.md) instead — a separate, minimal-permission workflow for exactly this case.
