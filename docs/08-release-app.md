# `release-app.yml`

Create releases using `release-please`, optionally tag major/minor versions, and support automerge of generated PRs.

## Inputs

| Input                    | Type    | Description                                        | Required | Default                          |
| ------------------------ | ------- | -------------------------------------------------- | -------- | -------------------------------- |
| ENABLE_PRERELEASE        | boolean | Enable prerelease functionality                    | No       | false                            |
| TAG_MAJOR_AND_MINOR      | boolean | Tag major and minor versions                       | No       | false                            |
| AUTOMERGE_PRERELEASE     | boolean | Automatically merge the prerelease PR              | No       | false                            |
| AUTOMERGE_RELEASE        | boolean | Automatically merge the release PR                 | No       | false                            |
| PRERELEASE_BRANCH        | string  | Branch to create the prerelease on                 | No       | develop                          |
| RELEASE_BRANCH           | string  | Branch to create the release on                    | No       | main                             |
| REBASE_PRERELEASE_BRANCH | boolean | Rebase prerelease branch on release after release  | No       | false                            |
| RELEASE_CONFIG_FILE      | string  | Release-please config file for release branch      | No       | release-please-config.json       |
| RELEASE_MANIFEST_FILE    | string  | Release-please manifest file for release branch    | No       | .release-please-manifest.json    |
| PRERELEASE_CONFIG_FILE   | string  | Release-please config file for prerelease branch   | No       | release-please-config-rc.json    |
| PRERELEASE_MANIFEST_FILE | string  | Release-please manifest file for prerelease branch | No       | .release-please-manifest-rc.json |

## Secrets

| Secret | Description                                           | Required | Default |
| ------ | ----------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (required for automerge) | No       | -       |

## Outputs

| Output          | Description                               |
| --------------- | ----------------------------------------- |
| release-created | Whether a release was created in this run |
| version         | Full semver value (e.g., `1.2.3`)         |
| major-tag       | Major version tag (e.g., `1`)             |
| minor-tag       | Minor version tag (e.g., `2`)             |
| patch-tag       | Patch version tag (e.g., `3`)             |

## Permissions

| Scope         | Access | Description                                       |
| ------------- | ------ | ------------------------------------------------- |
| contents      | write  | Create tags/commits and update manifest files     |
| issues        | write  | Create or update issues opened by release tooling |
| pull-requests | write  | Create, update, and optionally merge release PRs  |

## Notes

- Set `ENABLE_PRERELEASE: false` to disable all prerelease functionality and work only with release branches.
- Config and manifest files are configurable via inputs, with sensible defaults for both release and prerelease workflows.
- On `RELEASE_BRANCH` (default `main`), uses the files specified by `RELEASE_CONFIG_FILE` and `RELEASE_MANIFEST_FILE`.
- On `PRERELEASE_BRANCH` (default `develop`), uses the files specified by `PRERELEASE_CONFIG_FILE` and `PRERELEASE_MANIFEST_FILE` (only when `ENABLE_PRERELEASE: true`).
- If `TAG_MAJOR_AND_MINOR: true`, tags `v<major>` and `v<major>.<minor>` after a release is created.
- If `AUTOMERGE_*` is enabled and a PAT is provided, attempts to automerge the release PR.
- Optionally rebases `PRERELEASE_BRANCH` onto `RELEASE_BRANCH` after a release when `REBASE_PRERELEASE_BRANCH: true` (only when `ENABLE_PRERELEASE: true`).

## Examples

### Simple example

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@main
    with:
      ENABLE_PRERELEASE: true
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_PRERELEASE: true
      AUTOMERGE_RELEASE: true
      REBASE_PRERELEASE_BRANCH: true
      # Optional: customize config and manifest files
      RELEASE_CONFIG_FILE: custom-release-config.json
      PRERELEASE_CONFIG_FILE: custom-prerelease-config.json
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Release-only workflow

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@main
    with:
      ENABLE_PRERELEASE: false
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_RELEASE: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```
