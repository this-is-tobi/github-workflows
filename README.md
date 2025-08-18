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
      SONAR_URL: ${{ vars.SONAR_URL }}
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```

## Using Reusable Workflows from Private Repositories

You can use reusable workflows from a private repository, but there are important requirements and limitations:

- **Repository Access:** Both the caller and the reusable workflow repository must be private, or both must be internal to the same organization.
- **Authentication:** The workflow caller must use a `GITHUB_TOKEN` or a personal access token (PAT) with `actions:read` permission to access the private reusable workflow repository.
- **Reference Format:** Always reference the reusable workflow using the full path: `owner/repo/.github/workflows/workflow.yml@ref`.
- **User Permissions:** The user or GitHub App triggering the workflow must have access to both repositories.
- **Organization Scope:** For cross-repository usage, both repositories should belong to the same organization for seamless access.
- **Token Permissions:** The token used must have at least `actions:read` permission on the reusable workflow repository.

__Example:__

```yaml
jobs:
  example:
    uses: org/private-workflows/.github/workflows/build.yml@main
    secrets:
      GH_TOKEN: ${{ secrets.GH_TOKEN }}
```

> For more details, see: [GitHub Docs – Reusing workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows#using-a-workflow-from-a-private-repository)

## Available workflows

- [Delete GitHub action caches and optionally GHCR images (`clean-cache.yml`)](./.github/workflows/clean-cache.yml)
- [Build docker images and push it to a registry (`docker-build.yml`)](./.github/workflows/docker-build.yml)
- [Add labels to PRs using a labeler configuration file (`label-pr.yml`)](./.github/workflows/label-pr.yml)
- [Post preview links and optionally redeploy an ArgoCD preview app (`preview-app.yml`)](./.github/workflows/preview-app.yml)
- [Create releases using release-please and optional automerge (`release.yml`)](./.github/workflows/release.yml)
- [Run SonarQube analysis and quality gate check (`scan-sonarqube.yml`)](./.github/workflows/scan-sonarqube.yml)
- [Run Trivy vulnerability scans on images and config (`scan-trivy.yml`)](./.github/workflows/scan-trivy.yml)

### `clean-cache.yml`

Delete GitHub Actions caches related to a PR/branch and optionally delete images from GHCR.

#### Inputs

| Input        | Type    | Description                                         | Required | Default |
| ------------ | ------- | --------------------------------------------------- | -------- | ------- |
| PR_NUMBER    | number  | ID number of the pull request associated with cache | No       | -       |
| BRANCH_NAME  | string  | Branch name associated with the cache               | No       | -       |
| COMMIT_SHA   | string  | Commit SHA associated with the cache                | No       | -       |
| CLEAN_IMAGES | boolean | Delete images from ghcr.io                          | No       | false   |

#### Permissions

| Scope    | Access | Description                                                        |
| -------- | ------ | ------------------------------------------------------------------ |
| packages | write  | Manage GHCR packages (used when deleting images with CLEAN_IMAGES) |
| contents | read   | Read repository contents                                           |
| actions  | write  | Manage Actions caches via gh-actions-cache extension               |

#### Notes

- This workflow is now reusable via `workflow_call`.
- The `cleanup-cache` job deletes GitHub Actions caches for a branch or PR.
- The `infos` job generates a build matrix from `./ci/matrix/docker.json`.
- The `cleanup-image` job deletes images from GHCR using a script, only if `CLEAN_IMAGES` is true.
- Requires `GITHUB_TOKEN` for cache/image deletion.
- The image cleanup job only runs when the repository variable `CLEAN_IMAGES` is set to `true`.

#### Example

```yaml
jobs:
  cleanup:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@main
    with:
      BRANCH_NAME: 'refs/heads/feature/xyz'
      CLEAN_IMAGES: true
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
      BUILD_ARM64: false
      USE_QEMU: false
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
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
      CONF_PATH: .github/labeler.yml
```

### `preview-app.yml`

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

#### Notes

- The redeploy step runs only when the PR has the `preview` label and `PR_NUMBER` is provided. `ARGOCD_TOKEN` must be set to authenticate redeploy requests. Template inputs accept the `<pr_number>` placeholder.

#### Example

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/preview-app.yml@main
    with:
      APP_URL_TEMPLATE: 'https://preview.example.com/pr-<pr_number>'
      PR_NUMBER: 123
      ARGOCD_APP_NAME_TEMPLATE: 'preview-app-<pr_number>'
      ARGOCD_SYNC_PAYLOAD_TEMPLATE: '{"force":true}'
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

| Secret | Description                                  | Required | Default |
| ------ | -------------------------------------------- | -------- | ------- |
| GH_PAT | GitHub Personal Access Token (for automerge) | No       | -       |

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

- Reusable via `workflow_call`; reference with `uses:` from other repositories.
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
```

### `scan-sonarqube.yml`

Run SonarQube static analysis and check the quality gate. The workflow optionally downloads a coverage artifact and passes it to SonarQube.

#### Inputs

| Input             | Type    | Description                                  | Required | Default             |
| ----------------- | ------- | -------------------------------------------- | -------- | ------------------- |
| COV_IMPORT        | boolean | Whether to download a coverage artifact      | No       | false               |
| COV_ARTIFACT_NAME | string  | Name of the coverage artifact                | No       | unit-tests-coverage |
| COV_ARTIFACT_PATH | string  | Path where to download the coverage artifact | No       | ./coverage          |
| SONAR_EXTRA_ARGS  | string  | Additional SonarQube scanner arguments       | No       | -                   |
| SONAR_URL         | string  | URL of the SonarQube server                  | Yes      | -                   |

#### Secrets

| Secret            | Description                      | Required | Default |
| ----------------- | -------------------------------- | -------- | ------- |
| SONAR_TOKEN       | SonarQube token                  | Yes      | -       |
| SONAR_PROJECT_KEY | SonarQube project identifier key | Yes      | -       |

#### Example

```yaml
jobs:
  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@main
    with:
      SONAR_URL: ${{ vars.SONAR_URL }}
      COV_IMPORT: true
      COV_ARTIFACT_NAME: unit-tests-coverage
      COV_ARTIFACT_PATH: ./coverage
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
      PATH: ./
```
