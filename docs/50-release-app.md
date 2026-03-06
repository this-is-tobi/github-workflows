# `release-app.yml`

Create releases using [`release-please`](https://github.com/googleapis/release-please), optionally tag major/minor versions, and support automerge of generated PRs.

> **References:** [googleapis/release-please-action](https://github.com/googleapis/release-please-action) · [googleapis/release-please](https://github.com/googleapis/release-please)

## Inputs

| Input                        | Type    | Description                                                                                                       | Required | Default                          |
| ---------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------- | -------- | -------------------------------- |
| ENABLE_PRERELEASE            | boolean | Enable prerelease functionality                                                                                   | No       | false                            |
| TAG_MAJOR_AND_MINOR          | boolean | Tag major and minor versions                                                                                      | No       | false                            |
| AUTOMERGE_PRERELEASE         | boolean | Automatically merge the prerelease PR                                                                             | No       | false                            |
| AUTOMERGE_RELEASE            | boolean | Automatically merge the release PR                                                                                | No       | false                            |
| PRERELEASE_BRANCH            | string  | Branch to create the prerelease on                                                                                | No       | develop                          |
| RELEASE_BRANCH               | string  | Branch to create the release on                                                                                   | No       | main                             |
| REBASE_PRERELEASE_BRANCH     | boolean | Rebase prerelease branch on release after release                                                                 | No       | false                            |
| RELEASE_CONFIG_FILE          | string  | Release-please config file for release branch                                                                     | No       | release-please-config.json       |
| RELEASE_MANIFEST_FILE        | string  | Release-please manifest file for release branch                                                                   | No       | .release-please-manifest.json    |
| PRERELEASE_CONFIG_FILE       | string  | Release-please config file for prerelease branch                                                                  | No       | release-please-config-rc.json    |
| PRERELEASE_MANIFEST_FILE     | string  | Release-please manifest file for prerelease branch                                                                | No       | .release-please-manifest-rc.json |
| ADDITIONAL_RELEASE_ARTIFACTS | string  | Comma-separated list of additional release artifacts to upload (e.g., `artifact/build.zip,artifact/other.tar.gz`) | No       | -                                |
| RUNS_ON                      | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                          | No       | ["ubuntu-24.04"]                 |

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

## Configuration

Release-please requires a config file and a manifest file in the repository root. The manifest tracks the current version and is updated automatically on each release.

### Release config (`release-please-config.json`)

Minimal config for a single-package repository using the `node` release type (adjusts `package.json` version). See the [release-please docs](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md) for all available options and release types.

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "release-type": "node",
      "initial-version": "0.0.1",
      "include-component-in-tag": false,
      "versioning": "prerelease",
      "prerelease": false,
      "prerelease-type": "",
      "extra-files": []
    }
  }
}
```

### Release manifest (`.release-please-manifest.json`)

Tracks the current version for each package path. Release-please updates this file automatically — set the initial version to your current release.

```json
{
  ".": "0.0.1"
}
```

### Prerelease config (`release-please-config-rc.json`)

Used when `ENABLE_PRERELEASE: true`. Identical structure to the release config but adds `prerelease-type` to control the prerelease identifier appended to the version.

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "node",
  "prerelease-type": "rc",
  "packages": {
    ".": {
      "release-type": "node",
      "initial-version": "0.0.1",
      "include-component-in-tag": false,
      "versioning": "prerelease",
      "prerelease": true,
      "prerelease-type": "rc",
      "extra-files": []
    }
  }
}
```

### Prerelease manifest (`.release-please-manifest-rc.json`)

```json
{
  ".": "0.0.1"
}
```

## Examples

The examples cover the main release scenarios: a full setup with prerelease support, a release-only flow, and a build that attaches compiled binaries to the GitHub Release.

### Simple example

Full two-branch setup with `develop` for prereleases and `main` for stable releases. `AUTOMERGE_*: true` requires a PAT with sufficient permissions to bypass branch protection rules. `REBASE_PRERELEASE_BRANCH: true` keeps `develop` rebased onto `main` automatically after each stable release.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
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

Single-branch workflow targeting only `main`. No prerelease config files are required. `TAG_MAJOR_AND_MINOR: true` adds convenience aliases (`v1`, `v1.2`) to each stable release tag.

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    with:
      ENABLE_PRERELEASE: false
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_RELEASE: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Attach build artifacts to the release

Use `ADDITIONAL_RELEASE_ARTIFACTS` to upload extra files (binaries, archives, etc.) to the GitHub Release after it is created:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v6
    - name: Build
      run: make build
    - uses: actions/upload-artifact@v7
      with:
        name: release-artifacts
        path: dist/

  release:
    needs: build
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    with:
      ENABLE_PRERELEASE: false
      ADDITIONAL_RELEASE_ARTIFACTS: "dist/my-app-linux-amd64,dist/my-app-darwin-amd64"
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```
