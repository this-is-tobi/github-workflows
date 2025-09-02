# `release-helm.yml`

Release Helm charts using `chart-releaser-action`. Automatically creates GitHub releases and publishes chart packages when chart versions are updated.

## Inputs

| Input      | Type   | Description                                          | Required | Default  |
| ---------- | ------ | ---------------------------------------------------- | -------- | -------- |
| CHARTS_DIR | string | Directory containing the Helm charts                 | No       | ./charts |
| HELM_REPOS | string | Helm repositories to add (name=url, comma-separated) | No       | -        |

## Permissions

| Scope    | Access | Description                                       |
| -------- | ------ | ------------------------------------------------- |
| contents | write  | Create releases, tags, and publish chart packages |

## Notes

- Uses `helm/chart-releaser-action` to automatically detect chart version changes and create corresponding GitHub releases.
- Only creates releases for charts that have version bumps compared to the previous release.
- Chart packages are uploaded as release assets and indexed for use as a Helm repository.
- If `HELM_REPOS` is provided, adds external repositories before packaging (useful for charts with dependencies).
- Repository must have GitHub Pages enabled to serve the chart repository index.
- Requires chart versions to follow semantic versioning.
- Automatically configures Git user as `github-actions[bot]` for any commits made during the release process.

## Examples

#### Simple example

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@main
    with:
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
```
