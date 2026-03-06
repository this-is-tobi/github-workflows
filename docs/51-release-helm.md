# `release-helm.yml`

Release Helm charts using `chart-releaser-action`. Automatically creates GitHub releases and publishes chart packages when chart versions are updated.

## Inputs

| Input             | Type   | Description                                                                                | Required | Default          |
| ----------------- | ------ | ------------------------------------------------------------------------------------------ | -------- | ---------------- |
| CHARTS_DIR        | string | Directory containing the Helm charts                                                       | No       | ./charts         |
| HELM_REPOS        | string | Helm repositories to add (name=url, comma-separated)                                       | No       | -                |
| REGISTRY          | string | OCI registry to push charts to (e.g. `ghcr.io`, `registry.gitlab.com`)                     | No       | ghcr.io          |
| REPOSITORY        | string | Repository path in the OCI registry (defaults to `github.repository`)                      | No       | -                |
| REGISTRY_USERNAME | string | Username for OCI registry authentication (uses `github.actor` automatically for `ghcr.io`) | No       | -                |
| REGISTRY_PASSWORD | string | Password for OCI registry authentication (uses `GITHUB_TOKEN` automatically for `ghcr.io`) | No       | -                |
| RUNS_ON           | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)   | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description                                       |
| -------- | ------ | ------------------------------------------------- |
| contents | write  | Create releases, tags, and publish chart packages |
| packages | write  | Push charts to OCI registry (ghcr.io)             |

## Notes

- Uses `helm/chart-releaser-action` to automatically detect chart version changes and create corresponding GitHub releases.
- Only creates releases for charts that have version bumps compared to the previous release.
- **Charts are published to the OCI registry** (`ghcr.io/<owner>/<repo>`) in addition to GitHub releases.
- If `HELM_REPOS` is provided, adds external repositories before packaging (useful for charts with dependencies).
- Requires chart versions to follow semantic versioning.
- Automatically configures Git user as `github-actions[bot]` for any commits made during the release process.
- Charts can be pulled using: `helm pull oci://ghcr.io/<owner>/<repo>/<chart-name> --version <version>`

## Examples

The examples show releasing to the default GitHub Packages (ghcr.io) OCI registry, publishing to a custom registry with explicit credentials, and a minimal setup that relies entirely on workflow defaults.

#### Simple example

`HELM_REPOS` pre-registers external repositories so that chart dependencies can be resolved at packaging time. Charts are released both as GitHub Release assets and pushed to the OCI registry (`ghcr.io/<owner>/<repo>`).

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    with:
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
```

#### Custom OCI registry

To push charts to a registry other than `ghcr.io`, supply credentials explicitly:

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    with:
      CHARTS_DIR: ./charts
      REGISTRY: registry.example.com
      REPOSITORY: my-org/helm-charts
      REGISTRY_USERNAME: ${{ vars.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

#### Minimal (GitHub Packages only)

When all defaults are acceptable (ghcr.io, charts in `./charts`, no external repos):

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
```
