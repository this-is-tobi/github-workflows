# Github workflows 🤖

This repository serves as a centralized location for reusable GitHub workflows. By defining shared workflows here, we streamline the process of maintaining consistency and quality across all repositories.

This repository contains reusable GitHub workflows intended to be referenced from other repositories via the `uses: owner/repo/.github/workflows/<file>@<ref>` mechanism.

## How to reference these workflows

In your repository, use a `uses:` reference under `jobs` to call a reusable workflow. 

__Example:__

```yaml
jobs:
  example:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@main
    with:
      SONAR_URL: 'https://sonarqube.example.com'
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

## Using Reusable Workflows from Private Repositories

You can use reusable workflows from a private repository, but there are important requirements and limitations:

- **Repository Access:** Both the caller and the reusable workflow repository must be internal to the same user / organization.
- **Reference Format:** Always reference the reusable workflow using the full path: `owner/repo/.github/workflows/workflow.yml@ref`.

For more details, see: 
- [GitHub Docs – Reusing workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [GitHub Docs – Share across private repositories](https://docs.github.com/en/actions/how-tos/reuse-automations/share-across-private-repositories)
- [GitHub Docs – Share with your organization](https://docs.github.com/en/actions/how-tos/reuse-automations/share-with-your-organization)

## Available workflows

- [Delete GitHub action caches and optionally GHCR images (`clean-cache.yml`)](./.github/workflows/clean-cache.yml)
- [Build docker images and push it to a registry (`docker-build.yml`)](./.github/workflows/docker-build.yml)
- [Add labels to PRs using a labeler configuration file (`label-pr.yml`)](./.github/workflows/label-pr.yml)
- [Post preview links and optionally redeploy an ArgoCD preview app (`argocd-preview.yml`)](./.github/workflows/argocd-preview.yml)
- [Create releases using release-please and optional automerge (`release.yml`)](./.github/workflows/release.yml)
- [Run SonarQube analysis and quality gate check (`scan-sonarqube.yml`)](./.github/workflows/scan-sonarqube.yml)
- [Run Trivy vulnerability scans on images and config (`scan-trivy.yml`)](./.github/workflows/scan-trivy.yml)
- [Update or trigger Helm chart app version bump (`update-helm-chart.yml`)](./.github/workflows/update-helm-chart.yml)

### `clean-cache.yml`

Delete GitHub Actions caches related to a PR/branch and optionally delete a single image from GHCR when an image reference is provided.

#### Inputs

| Input       | Type   | Description                                                                                                                                                                          | Required | Default |
| ----------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| PR_NUMBER   | number | ID number of the pull request associated with the cache                                                                                                                              | No       | -       |
| BRANCH_NAME | string | Branch name associated with the cache                                                                                                                                                | No       | -       |
| COMMIT_SHA  | string | Commit SHA associated with the cache (alternative selector)                                                                                                                          | No       | -       |
| IMAGE       | string | Image reference to delete (optionally with registry). Non-`ghcr.io` or missing registry are treated as GHCR. Must include a tag. Examples: `ghcr.io/org/app:1.2.3`, `org/app:1.2.3`. | No       | -       |

#### Permissions

| Scope    | Access | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| packages | write  | Required to delete GHCR container package versions |
| contents | read   | Read repository contents                           |
| actions  | write  | Manage Actions caches via cache API                |

#### Notes

- Cache deletion logic picks `BRANCH_NAME` if provided; otherwise derives a PR ref from `PR_NUMBER`.
- Image deletion job (`cleanup-image`) only runs when `IMAGE` is supplied.
- If `IMAGE` contains a registry different from `ghcr.io`, a warning is emitted and it is processed as if it were `ghcr.io`.
- If no registry is provided it is assumed to be `ghcr.io`.
- `IMAGE` must include a tag (e.g. `my-org/my-image:latest`); images are deleted via the GitHub Packages API.

#### Example

```yaml
jobs:
  cleanup:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@main
    with:
      PR_NUMBER: 123
      IMAGE: this-is-tobi/tools/debug:pr-123
```

### `docker-build.yml`

Build and push container images using Docker Buildx with optional multi-arch support.

#### Inputs

| Input             | Type    | Description                            | Required | Default |
| ----------------- | ------- | -------------------------------------- | -------- | ------- |
| IMAGE_NAME        | string  | Name of the image to build             | Yes      | -       |
| IMAGE_TAG         | string  | Tag used to build image                | Yes      | -       |
| LATEST_TAG        | boolean | Whether to tag the image with 'latest' | No       | false   |
| IMAGE_DOCKERFILE  | string  | Path of the Dockerfile                 | Yes      | -       |
| IMAGE_CONTEXT     | string  | Path of the build context              | Yes      | -       |
| BUILD_AMD64       | boolean | Build for amd64                        | No       | true    |
| BUILD_ARM64       | boolean | Build for arm64                        | No       | true    |
| USE_QEMU          | boolean | Use QEMU emulator for arm64            | No       | false   |
| REGISTRY_USERNAME | string  | Username used to login into registry   | No       | -       |
| REGISTRY_PASSWORD | string  | Password used to login into registry   | No       | -       |

#### Permissions

| Scope    | Access | Description                         |
| -------- | ------ | ----------------------------------- |
| packages | write  | Push images to GHCR when applicable |
| contents | read   | Read repository to build context    |

#### Notes 

- Supports Ubuntu 24.04 and ARM runners for matrix builds.
- `LATEST_TAG` input allows tagging images as `latest`.
- Registry login logic: uses GitHub token for `ghcr.io`, otherwise uses provided credentials.
- Digest artifacts are uploaded and merged for multi-arch images.
- Manifest list is created and pushed after build.

#### Example

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/docker-build.yml@main
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      BUILD_AMD64: true
      BUILD_ARM64: true
      USE_QEMU: false
```

### `label-pr.yml`

Add or sync labels on pull requests using a configuration file.

#### Inputs

| Input     | Type   | Description                              | Required | Default |
| --------- | ------ | ---------------------------------------- | -------- | ------- |
| CONF_PATH | string | Path to the `labeler` configuration file | Yes      | -       |

#### Permissions

| Scope         | Access | Description               |
| ------------- | ------ | ------------------------- |
| pull-requests | write  | Required to add PR labels |

#### Example

```yaml
jobs:
  label:
    uses: this-is-tobi/github-workflows/.github/workflows/label-pr.yml@main
    with:
      CONF_PATH: .github/labeler-conf.yml
```

Example configuration file (`.github/labeler-conf.yml`):

```yaml
doc:
- changed-files:
  - any-glob-to-any-file:
    - "docs/**"
api:
- changed-files:
  - any-glob-to-any-file: 
    - "apps/api/**"
client:
- changed-files:
  - any-glob-to-any-file: 
    - "apps/client/**"
ci:
- changed-files:
  - any-glob-to-any-file: 
    - ".github/**"
    - "ci/**"
```

> For more details on the configuration file format, see the [labeler action documentation](https://github.com/actions/labeler).

### `argocd-preview.yml`

Comment on PRs with preview URLs and optionally trigger an ArgoCD redeploy for preview environments.

#### Inputs

| Input                        | Type   | Description                                          | Required | Default |
| ---------------------------- | ------ | ---------------------------------------------------- | -------- | ------- |
| APP_URL_TEMPLATE             | string | Template that can include `<pr_number>`              | Yes      | -       |
| PR_NUMBER                    | number | Pull request number                                  | Yes      | -       |
| ARGOCD_APP_NAME_TEMPLATE     | string | ArgoCD app name template (may include `<pr_number>`) | Yes      | -       |
| ARGOCD_SYNC_PAYLOAD_TEMPLATE | string | ArgoCD sync payload template                         | Yes      | -       |
| ARGOCD_URL                   | string | URL of the Argo-CD server                            | Yes      | -       |

#### Secrets

| Secret       | Description                           | Required | Default |
| ------------ | ------------------------------------- | -------- | ------- |
| ARGOCD_TOKEN | Token used to redeploy the ArgoCD app | Yes      | -       |

#### Permissions

| Scope         | Access | Description                  |
| ------------- | ------ | ---------------------------- |
| pull-requests | write  | Required to post PR comments |
| contents      | read   | Read repository (templates)  |

#### Notes

- The redeploy step runs only when the PR has the `preview` label and `PR_NUMBER` is provided. `ARGOCD_TOKEN` must be set to authenticate redeploy requests. Template inputs accept the `<pr_number>` placeholder.

#### Example

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/argocd-preview.yml@main
    with:
      APP_URL_TEMPLATE: https://app-name.pr-<pr_number>.example.com
      PR_NUMBER: 123
      ARGOCD_APP_NAME_TEMPLATE: app-name-pr-<pr_number>
      ARGOCD_SYNC_PAYLOAD_TEMPLATE: '{"appNamespace":"argocd","prune":true,"dryRun":false,"strategy":{"hook":{"force":true}},"resources":[{"group":"apps","version":"v1","kind":"Deployment","namespace":"app-name-pr-<pr_number>","name":"app-name-pr-<pr_number>-client"},{"group":"apps","version":"v1","kind":"Deployment","namespace":"app-name-pr-<pr_number>","name":"app-name-pr-<pr_number>-server"}],"syncOptions":{"items":["Replace=true"]}}'
      ARGOCD_URL: https://argo-cd.example.com
    secrets:
      ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
```

### `release.yml`

Create releases using `release-please`, optionally tag major/minor versions, and support automerge of generated PRs.

#### Inputs

| Input                    | Type    | Description                                       | Required | Default |
| ------------------------ | ------- | ------------------------------------------------- | -------- | ------- |
| TAG_MAJOR_AND_MINOR      | boolean | Tag major and minor versions                      | No       | false   |
| AUTOMERGE_PRERELEASE     | boolean | Automatically merge the prerelease PR             | No       | false   |
| AUTOMERGE_RELEASE        | boolean | Automatically merge the release PR                | No       | false   |
| PRERELEASE_BRANCH        | string  | Branch to create the prerelease on                | No       | develop |
| RELEASE_BRANCH           | string  | Branch to create the release on                   | No       | main    |
| REBASE_PRERELEASE_BRANCH | boolean | Rebase prerelease branch on release after release | No       | false   |

#### Secrets

| Secret | Description                                           | Required | Default |
| ------ | ----------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (required for automerge) | No       | -       |

#### Outputs

| Output          | Description                               |
| --------------- | ----------------------------------------- |
| release-created | Whether a release was created in this run |
| major-tag       | Major version tag (e.g., `1`)             |
| minor-tag       | Minor version tag (e.g., `2`)             |
| patch-tag       | Patch version tag (e.g., `3`)             |

#### Permissions

| Scope         | Access | Description                                       |
| ------------- | ------ | ------------------------------------------------- |
| contents      | write  | Create tags/commits and update manifest files     |
| issues        | write  | Create or update issues opened by release tooling |
| pull-requests | write  | Create, update, and optionally merge release PRs  |

#### Notes

- On `RELEASE_BRANCH` (default `main`), uses `release-please-config.json` and `.release-please-manifest.json`. On `PRERELEASE_BRANCH` (default `develop`), uses `release-please-config-rc.json` and `.release-please-manifest-rc.json`.
- If `TAG_MAJOR_AND_MINOR: true`, tags `v<major>` and `v<major>.<minor>` after a release is created.
- If `AUTOMERGE_*` is enabled and a PAT is provided, attempts to automerge the release PR.
- Optionally rebases `PRERELEASE_BRANCH` onto `RELEASE_BRANCH` after a release when `REBASE_PRERELEASE_BRANCH: true`.

#### Example

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release.yml@main
    with:
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_PRERELEASE: true
      AUTOMERGE_RELEASE: true
      REBASE_PRERELEASE_BRANCH: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### `scan-sonarqube.yml`

Run SonarQube static analysis and check the quality gate. The workflow optionally downloads a coverage artifact and passes it to SonarQube.

#### Inputs

| Input             | Type    | Description                                                            | Required | Default             |
| ----------------- | ------- | ---------------------------------------------------------------------- | -------- | ------------------- |
| COV_IMPORT        | boolean | Whether to download a coverage artifact                                | No       | false               |
| COV_ARTIFACT_NAME | string  | Name of the coverage artifact                                          | No       | unit-tests-coverage |
| COV_ARTIFACT_PATH | string  | Path where to download the coverage artifact                           | No       | ./coverage          |
| SONAR_EXTRA_ARGS  | string  | Additional SonarQube scanner arguments                                 | No       | -                   |
| SOURCES_PATH      | string  | Paths to the source code that should be analyzed (eg. 'apps,packages') | Yes      | -                   |
| SONAR_URL         | string  | URL of the SonarQube server                                            | Yes      | -                   |

#### Secrets

| Secret            | Description                      | Required | Default |
| ----------------- | -------------------------------- | -------- | ------- |
| SONAR_TOKEN       | SonarQube token                  | Yes      | -       |
| SONAR_PROJECT_KEY | SonarQube project identifier key | Yes      | -       |

#### Permissions

| Scope         | Access | Description                                 |
| ------------- | ------ | ------------------------------------------- |
| contents      | read   | Read source code for analysis               |
| issues        | write  | Create/update issues raised by integrations |
| pull-requests | write  | Publish PR decorations and status summaries |

#### Example

```yaml
jobs:
  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@main
    with:
      SONAR_URL: https://sonarqube.example.com
      COV_IMPORT: true
      COV_ARTIFACT_NAME: unit-tests-coverage
      COV_ARTIFACT_PATH: ./coverage
      SOURCES_PATH: apps,packages
      SONAR_EXTRA_ARGS: -Dsonar.javascript.lcov.reportPaths=./coverage/apps/api/lcov.info,./coverage/apps/client/lcov.info,./coverage/packages/shared/lcov.info -Dsonar.coverage.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue,**/assets/** -Dsonar.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

#### Notes

- When `COV_IMPORT` is `true` the workflow downloads the artifact using `COV_ARTIFACT_NAME` into `COV_ARTIFACT_PATH` before running the SonarQube scan; when `COV_IMPORT` is `false` no download is attempted. For pull requests, it passes PR decoration args; otherwise it analyzes the current branch. Default sources are `apps,packages`; override or extend via `SONAR_EXTRA_ARGS` (e.g., `-Dsonar.sources=.`).

### `scan-trivy.yml`

Run Trivy vulnerability scans on container images and/or configuration files and upload SARIF reports to GitHub Security.

#### Inputs

| Input | Type   | Description                                              | Required | Default |
| ----- | ------ | -------------------------------------------------------- | -------- | ------- |
| IMAGE | string | Image used to perform scan (eg. docker.io/debian:latest) | No       | -       |
| PATH  | string | Path used to perform config scan                         | No       | -       |

#### Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ---------------------------------- |
| contents        | write  | General repo operations by jobs    |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |

#### Notes

- `images-scan` runs only if `IMAGE` is provided; `config-scan` runs only if `PATH` is provided
- Uploads SARIF results to the Security tab; on pull requests, posts a comment linking to the Security panel when both `IMAGE` and `PATH` are set
- Skips common directories via `skip-dirs: **/node_modules` in config scan

#### Example

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
```

### `update-helm-chart.yml`

Trigger a chart update workflow in a remote Helm charts repository (caller mode) or update a chart in-place (called mode) by incrementing its version and regenerating documentation.

#### Inputs

| Input                 | Type   | Description                                                                                        | Required | Default                |
| --------------------- | ------ | -------------------------------------------------------------------------------------------------- | -------- | ---------------------- |
| RUN_MODE              | string | Execution mode: `caller` (trigger remote repo workflow) or `called` (update chart in current repo) | Yes      | -                      |
| WORKFLOW_NAME         | string | Workflow file name in chart repo to trigger (caller mode)                                          | No       | update-app-version.yml |
| CHART_REPO            | string | Target chart repository (`owner/repo`) when in caller mode                                         | No       | -                      |
| CHART_NAME            | string | Name of the chart directory under `charts/`                                                        | Yes      | -                      |
| APP_VERSION           | string | Application version to set in `Chart.yaml` (appVersion)                                            | Yes      | -                      |
| UPGRADE_TYPE          | string | Which SemVer part to increment: `major`, `minor`, `patch`, or `prerelease`                         | No       | patch                  |
| PRERELEASE_IDENTIFIER | string | Identifier used when `UPGRADE_TYPE=prerelease` (e.g. `rc`)                                         | No       | rc                     |

#### Secrets

| Secret | Description                                                                  | Required | Default |
| ------ | ---------------------------------------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (needed to trigger remote workflow / create PR) | No       | -       |

#### Permissions

| Scope         | Access | Description                           |
| ------------- | ------ | ------------------------------------- |
| pull-requests | write  | Create/update the chart update PR     |
| contents      | write  | Commit modified chart & docs          |
| actions       | write  | Trigger remote workflow (caller mode) |

#### Notes

- `RUN_MODE=caller`: Validates `CHART_REPO` is provided, then invokes `gh workflow run <WORKFLOW_NAME>` in the target repo, forwarding: `CHART_NAME`, `APP_VERSION`, `UPGRADE_TYPE`, `PRERELEASE_IDENTIFIER`, and forcing `RUN_MODE=called` in the remote execution.
- `RUN_MODE=called`: Reads current chart `version` from `charts/<CHART_NAME>/Chart.yaml` (via `yq`), computes `NEXT_VERSION` using `npx semver -i <UPGRADE_TYPE>` (adding `--preid <PRERELEASE_IDENTIFIER>` when `UPGRADE_TYPE=prerelease`), updates both `version` and `appVersion`, regenerates docs with `helm-docs`, and creates/updates a PR containing the bump.
- Branch naming pattern: `<chart-name>-v<NEXT_VERSION>`.
- Tooling requirements: `yq`, `node` (for `npx semver`), and `docker` (for `jnorwood/helm-docs`). Use an image / setup step that provides them.
- `UPGRADE_TYPE=prerelease` increments the prerelease component (e.g. `1.2.3` -> `1.2.4-rc`, subsequent runs -> `1.2.4-rc.1`, etc.).
- No explicit outputs are exposed; derive the new version from the PR title or branch name if needed.

#### Example *(caller mode)*

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

#### Example *(called mode)*

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

#### Example *(called mode – prerelease bump)*

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
    with:
      RUN_MODE: called
      CHART_NAME: my-service
      APP_VERSION: 1.4.0-rc.1
      UPGRADE_TYPE: prerelease
      PRERELEASE_IDENTIFIER: rc
```
