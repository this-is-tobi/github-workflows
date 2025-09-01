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

- [Post preview links and optionally redeploy an ArgoCD preview app (`argocd-preview.yml`)](./.github/workflows/argocd-preview.yml)
- [Build docker images and push it to a registry (`build-docker.yml`)](./.github/workflows/build-docker.yml)
- [Delete GitHub action caches and optionally GHCR images (`clean-cache.yml`)](./.github/workflows/clean-cache.yml)
- [Add labels to PRs using a labeler configuration file (`label-pr.yml`)](./.github/workflows/label-pr.yml)
- [Lint Helm charts structure and validate documentation (`lint-helm.yml`)](./.github/workflows/lint-helm.yml)
- [Lint JavaScript, JSON, Markdown and YAML files using ESLint (`lint-js.yml`)](./.github/workflows/lint-js.yml)
- [Release Apps using release-please and optional automerge (`release-app.yml`)](./.github/workflows/release-app.yml)
- [Release Helm charts using chart-releaser (`release-helm.yml`)](./.github/workflows/release-helm.yml)
- [Run SonarQube analysis and quality gate check (`scan-sonarqube.yml`)](./.github/workflows/scan-sonarqube.yml)
- [Run Trivy vulnerability scans on images and config (`scan-trivy.yml`)](./.github/workflows/scan-trivy.yml)
- [Test Helm charts installation with chart-testing (`test-helm.yml`)](./.github/workflows/test-helm.yml)
- [Update or trigger Helm chart app version bump (`update-helm-chart.yml`)](./.github/workflows/update-helm-chart.yml)

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

### `build-docker.yml`

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
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@main
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: 1.2.3
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      LATEST_TAG: true
      BUILD_AMD64: true
      BUILD_ARM64: true
      USE_QEMU: false
```

### `clean-cache.yml`

Delete GitHub Actions caches related to a PR/branch and optionally delete a single image from GHCR when an image reference is provided.

#### Inputs

| Input       | Type   | Description                                                                                                                                                                          | Required | Default |
| ----------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| PR_NUMBER   | number | ID number of the pull request associated with the cache                                                                                                                              | No       | -       |
| BRANCH_NAME | string | Branch name associated with the cache                                                                                                                                                | No       | -       |
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

### `lint-helm.yml`

Comprehensive Helm chart validation with two parallel jobs: chart structure linting using `chart-testing` and documentation validation using `helm-docs`. Ensures charts follow best practices and documentation stays current.

#### Inputs

| Input             | Type    | Description                                  | Required | Default |
| ----------------- | ------- | -------------------------------------------- | -------- | ------- |
| HELM_DOCS_VERSION | string  | Version (image tag) of `jnorwood/helm-docs`  | No       | 1.14.2  |
| CT_CONF_PATH      | string  | Path to the chart-testing configuration file | Yes      | -       |
| LINT_CHARTS       | boolean | Whether to run the chart linting job         | No       | true    |
| LINT_DOCS         | boolean | Whether to run the chart docs linting job    | No       | true    |

#### Permissions

| Scope    | Access | Description               |
| -------- | ------ | ------------------------- |
| contents | read   | Read chart sources & docs |

#### Notes

- **Two conditional jobs for flexible validation:**
  - **`lint-charts`**: Uses `helm/chart-testing-action` with `ct lint` to validate chart structure, syntax, dependencies, best practices, and version increment requirements. Runs only if `LINT_CHARTS=true`.
  - **`lint-docs`**: Uses `jnorwood/helm-docs` with `--validate` flag to ensure documentation matches current chart configuration without making changes. Runs only if `LINT_DOCS=true`.
- Set `LINT_CHARTS=false` to skip chart structure validation (useful for docs-only changes).
- Set `LINT_DOCS=false` to skip documentation validation (useful for chart logic changes without doc updates).
- Chart-testing requires a configuration file (typically `.github/ct.yaml`) to define linting rules, target branch, chart directories, and validation options.
- Documentation validation mounts `./charts` read-only and exits non-zero if generated docs would differ from committed files.
- Jobs run independently when both are enabled; workflow succeeds if all enabled jobs pass.
- Consider pinning Docker images by digest for stronger supply-chain guarantees if stability is critical.
- When you modify `Chart.yaml`, `values.yaml`, or templates that affect documentation, regenerate the docs locally:
  ```bash
  docker run --rm \
    -v "$(pwd)/charts:/helm-docs" \
    -u $(id -u) \
    docker.io/jnorwood/helm-docs:1.14.2
  ```
  Then review and commit the updated `README.md` under `charts/<chart-name>/`. After committing, the `lint-docs` job should pass again.

#### Example

```yaml
jobs:
  lint-helm:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@main
    with:
      HELM_DOCS_VERSION: 1.14.2
      CT_CONF_PATH: .github/ct.yaml
```

Example chart-testing configuration (`.github/ct.yaml`):

```yaml
# See https://github.com/helm/chart-testing/blob/main/doc/ct_lint.md
target-branch: main
chart-dirs:
  - charts
helm-extra-args: --timeout 600s
check-version-increment: true
validate-maintainers: false
excluded-charts:
  - unstable-chart
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
```

#### Example *(docs-only validation)*

```yaml
jobs:
  lint-helm-docs-only:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@main
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: false
      LINT_DOCS: true
```

#### Example *(charts-only validation)*

```yaml
jobs:
  lint-helm-charts-only:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@main
    with:
      CT_CONF_PATH: .github/ct.yaml
      LINT_CHARTS: true
      LINT_DOCS: false
```

### `lint-js.yml`

Comprehensive JavaScript/TypeScript file linting using ESLint with automatic runtime and package manager detection. Supports Node.js and Bun runtimes with npm, pnpm, yarn, and bun package managers. Automatically sets up `@antfu/eslint-config` if no ESLint configuration exists.

#### Inputs

| Input              | Type    | Description                                     | Required | Default                |
| ------------------ | ------- | ----------------------------------------------- | -------- | ---------------------- |
| RUNTIME_VERSION    | string  | Runtime version to use (Node.js or Bun version) | No       | "22"                   |
| PACKAGE_MANAGER    | string  | Package manager to use (npm, pnpm, yarn, bun)   | No       | "npm"                  |
| RUNTIME            | string  | JavaScript runtime to use (node, bun)           | No       | "node"                 |
| ESLINT_CONFIG      | string  | ESLint config package to use                    | No       | "@antfu/eslint-config" |
| WORKING_DIRECTORY  | string  | Working directory for the project               | No       | "."                    |
| LINT_PATHS         | string  | Paths to lint (space or comma-separated)        | No       | "."                    |
| ESLINT_CONFIG_FILE | string  | Path to custom ESLint config file               | No       | ""                     |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on linting errors  | No       | true                   |

#### Permissions

| Scope    | Access | Description                   |
| -------- | ------ | ----------------------------- |
| contents | read   | Read source files for linting |

#### Notes

- **Automatic Detection**: Intelligently detects package manager and runtime based on lock files and configuration files.
- **Multi-Runtime Support**: Works with Node.js and Bun runtimes.
- **Multi-Package Manager Support**: Supports npm, pnpm, yarn, and bun package managers.
- **Auto-Configuration**: Automatically installs and configures `@antfu/eslint-config` if no ESLint config exists.
- **File Type Support**: Lints JavaScript, TypeScript, JSON, JSONC, Markdown, and YAML files.
- **Package Manager Detection**: Looks for `bun.lockb`/`bun.lock` → uses Bun, `pnpm-lock.yaml` → uses pnpm, `yarn.lock` → uses Yarn, falls back to npm.
- **Runtime Detection**: Looks for Bun lock files → uses Bun, falls back to Node.js.
- **ESLint Config Detection**: Checks for existing ESLint config files, creates `eslint.config.js` with `@antfu/eslint-config` if none found.
- The workflow creates a temporary ESLint configuration using `@antfu/eslint-config` if no configuration is detected.
- The default configuration enables linting for JS, TS, JSON, JSONC, YAML, and Markdown files.
- Custom ESLint configurations take precedence over the auto-generated one.

#### Example

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      RUNTIME_VERSION: "18"
      PACKAGE_MANAGER: "pnpm"
      LINT_PATHS: "src tests"
```

#### Example *(Bun runtime)*

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      RUNTIME: "bun"
      PACKAGE_MANAGER: "bun"
      LINT_PATHS: "src,tests,docs"
```

#### Example *(Custom ESLint config)*

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      ESLINT_CONFIG: "@company/eslint-config"
      LINT_PATHS: "apps packages"
```

#### Example *(Monorepo with working directory)*

```yaml
jobs:
  lint-frontend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      WORKING_DIRECTORY: "packages/frontend"
      LINT_PATHS: "src components"
      
  lint-backend:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      WORKING_DIRECTORY: "packages/backend"
      PACKAGE_MANAGER: "pnpm"
      LINT_PATHS: "src,tests"
```

#### Example *(Non-blocking linting)*

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      FAIL_ON_ERROR: false
      LINT_PATHS: "src tests docs"
```

#### Example *(Custom config file)*

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@main
    with:
      ESLINT_CONFIG_FILE: ".eslintrc.custom.js"
      LINT_PATHS: "apps,packages,tools"
```

### `release-app.yml`

Create releases using `release-please`, optionally tag major/minor versions, and support automerge of generated PRs.

#### Inputs

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

- Set `ENABLE_PRERELEASE: false` to disable all prerelease functionality and work only with release branches.
- Config and manifest files are configurable via inputs, with sensible defaults for both release and prerelease workflows.
- On `RELEASE_BRANCH` (default `main`), uses the files specified by `RELEASE_CONFIG_FILE` and `RELEASE_MANIFEST_FILE`.
- On `PRERELEASE_BRANCH` (default `develop`), uses the files specified by `PRERELEASE_CONFIG_FILE` and `PRERELEASE_MANIFEST_FILE` (only when `ENABLE_PRERELEASE: true`).
- If `TAG_MAJOR_AND_MINOR: true`, tags `v<major>` and `v<major>.<minor>` after a release is created.
- If `AUTOMERGE_*` is enabled and a PAT is provided, attempts to automerge the release PR.
- Optionally rebases `PRERELEASE_BRANCH` onto `RELEASE_BRANCH` after a release when `REBASE_PRERELEASE_BRANCH: true` (only when `ENABLE_PRERELEASE: true`).

#### Example

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

#### Example *(Release-only workflow)*

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

### `release-helm.yml`

Release Helm charts using `chart-releaser-action`. Automatically creates GitHub releases and publishes chart packages when chart versions are updated.

#### Inputs

| Input      | Type   | Description                                          | Required | Default  |
| ---------- | ------ | ---------------------------------------------------- | -------- | -------- |
| CHARTS_DIR | string | Directory containing the Helm charts                 | No       | ./charts |
| HELM_REPOS | string | Helm repositories to add (name=url, comma-separated) | No       | -        |

#### Permissions

| Scope    | Access | Description                                       |
| -------- | ------ | ------------------------------------------------- |
| contents | write  | Create releases, tags, and publish chart packages |

#### Notes

- Uses `helm/chart-releaser-action` to automatically detect chart version changes and create corresponding GitHub releases.
- Only creates releases for charts that have version bumps compared to the previous release.
- Chart packages are uploaded as release assets and indexed for use as a Helm repository.
- If `HELM_REPOS` is provided, adds external repositories before packaging (useful for charts with dependencies).
- Repository must have GitHub Pages enabled to serve the chart repository index.
- Requires chart versions to follow semantic versioning.
- Automatically configures Git user as `github-actions[bot]` for any commits made during the release process.

#### Example

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@main
    with:
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
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

### `test-helm.yml`

Test Helm charts by installing them in a Kubernetes cluster using `chart-testing`. Creates a temporary Kind cluster and attempts to install charts to verify they work correctly.

#### Inputs

| Input        | Type   | Description                                  | Required | Default |
| ------------ | ------ | -------------------------------------------- | -------- | ------- |
| CT_CONF_PATH | string | Path to the chart-testing configuration file | Yes      | -       |

#### Permissions

| Scope    | Access | Description                    |
| -------- | ------ | ------------------------------ |
| contents | read   | Read chart sources for testing |

#### Notes

- Uses `helm/chart-testing-action` with `ct install` to test chart installations in a real Kubernetes environment.
- Creates a temporary Kind (Kubernetes in Docker) cluster using `helm/kind-action` for testing.
- Dynamically selects target branch: uses PR head branch (`github.head_ref`) when testing pull requests, otherwise falls back to repository default branch.
- Chart-testing configuration file defines which charts to test, dependencies, and installation parameters.
- Requires charts to have valid `values.yaml` and proper Kubernetes manifests that can be deployed.
- Consider adding integration tests or custom validation scripts in your chart-testing configuration.

#### Example

```yaml
jobs:
  test-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@main
    with:
      CT_CONF_PATH: .github/ct.yaml
```

Example chart-testing configuration for testing (`.github/ct.yaml`):

```yaml
# See https://github.com/helm/chart-testing/blob/main/doc/ct_install.md
target-branch: main
chart-dirs:
  - charts
helm-extra-args: --timeout 600s
check-version-increment: false  # Usually false for install testing
validate-maintainers: false
excluded-charts:
  - unstable-chart
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
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

#### Example *(caller mode – prerelease bump)*

```yaml
jobs:
  bump-chart-prerelease:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-service
      APP_VERSION: 1.4.0-rc.1
      UPGRADE_TYPE: prerelease
      PRERELEASE_IDENTIFIER: rc
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

## CI/CD Examples

Here are two example workflows that combine multiple reusable workflows from this repository to create a CI/CD pipeline for a monorepo with multiple apps and packages.

### Example 1 - App *(Basic CI Pipeline)*

```yaml
name: CI

on:
  pull_request:
    types:
    - opened
    - reopened
    - synchronize
    - ready_for_review
    branches:
    - "**"
  workflow_dispatch:

env:
  BUILD_AMD64: true
  BUILD_ARM64: true
  LATEST_TAG: false
  USE_QEMU: false
  IMAGE_TAG: ${{ github.event.pull_request.number || github.event.number || github.sha }}

jobs:
  path-filter:
    runs-on: ubuntu-latest
    if: ${{ !github.event.pull_request.draft }}
    outputs:
      apps: ${{ steps.filter.outputs.apps }}
      packages: ${{ steps.filter.outputs.packages }}
      ci: ${{ steps.filter.outputs.ci }}
    steps:
    - name: Checks-out repository
      uses: actions/checkout@v4

    - name: Check updated files paths
      uses: dorny/paths-filter@v2
      id: filter
      with:
        filters: |
          apps:
            - 'apps/**'
          packages:
            - 'packages/**'
          ci:
            - '.github/workflows/**'

  expose-vars:
    runs-on: ubuntu-latest
    if: ${{ !github.event.pull_request.draft }}
    outputs:
      BUILD_AMD64: ${{ env.BUILD_AMD64 }}
      BUILD_ARM64: ${{ env.BUILD_ARM64 }}
      LATEST_TAG: ${{ env.LATEST_TAG }}
      USE_QEMU: ${{ env.USE_QEMU }}
      IMAGE_TAG: ${{ env.IMAGE_TAG }}
    steps:
    - name: Exposing env vars
      run: echo "Exposing env vars"

  build-docker:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@main
    needs:
    - expose-vars
    permissions:
      packages: write
      contents: read
    strategy:
      matrix:
        service:
        - name: api
          context: ./apps/api
          dockerfile: ./apps/api/Dockerfile
        - name: client
          context: ./apps/client
          dockerfile: ./apps/client/Dockerfile
        - name: docs
          context: ./apps/docs
          dockerfile: ./apps/docs/Dockerfile
    with:
      IMAGE_NAME: ghcr.io/${{ github.repository}}/${{ matrix.service.name }}
      IMAGE_TAG: ${{ needs.expose-vars.outputs.IMAGE_TAG }}
      IMAGE_CONTEXT: ${{ matrix.service.context }}
      IMAGE_DOCKERFILE: ${{ matrix.service.dockerfile }}
      BUILD_AMD64: ${{ needs.expose-vars.outputs.BUILD_AMD64 == 'true' }}
      BUILD_ARM64: ${{ needs.expose-vars.outputs.BUILD_ARM64 == 'true' }}
      LATEST_TAG: ${{ needs.expose-vars.outputs.LATEST_TAG == 'true' }}
      USE_QEMU: ${{ needs.expose-vars.outputs.USE_QEMU == 'true' }}

  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@main
    needs:
    - expose-vars
    - build-docker
    permissions:
      issues: write
      pull-requests: write
      contents: read
    with:
      SONAR_URL: https://sonarqube.example.com
      SOURCES_PATH: apps,packages
      SONAR_EXTRA_ARGS: -Dsonar.coverage.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue,**/assets/** -Dsonar.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}

  scan-trivy-conf:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    needs:
    - expose-vars
    - build-docker
    permissions:
      contents: read
    with:
      PATH: ./

  scan-trivy-images:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    needs:
    - expose-vars
    - build-docker
    permissions:
      contents: read
    strategy:
      matrix:
        service:
        - name: api
          context: ./apps/api
          dockerfile: ./apps/api/Dockerfile
        - name: client
          context: ./apps/client
          dockerfile: ./apps/client/Dockerfile
        - name: docs
          context: ./apps/docs
          dockerfile: ./apps/docs/Dockerfile
    with:
      IMAGE: ghcr.io/${{ github.repository}}/${{ matrix.service.name }}:${{ needs.expose-vars.outputs.IMAGE_TAG }}

  # Workaround for required status check in protection branches (see. https://github.com/orgs/community/discussions/13690)
  all-jobs-passed:
    name: Check jobs status
    runs-on: ubuntu-latest
    if: ${{ always() }}
    needs:
    - path-filter
    - expose-vars
    - build-docker
    - scan-sonarqube
    - scan-trivy-conf
    - scan-trivy-images
    steps:
    - name: Check status of all required jobs
      run: |-
        NEEDS_CONTEXT='${{ toJson(needs) }}'
        JOB_IDS=$(echo "$NEEDS_CONTEXT" | jq -r 'keys[]')
        for JOB_ID in $JOB_IDS; do
          RESULT=$(echo "$NEEDS_CONTEXT" | jq -r ".[\"$JOB_ID\"].result")
          echo "$JOB_ID job result: $RESULT"
          if [[ $RESULT != "success" && $RESULT != "skipped" ]]; then
            echo "***"
            echo "Error: The $JOB_ID job did not pass."
            exit 1
          fi
        done
        echo "All jobs passed or were skipped."
```

### Example 2 - App *(Basic CD Pipeline)*

```yaml
name: CD

on:
  push:
    branches:
    - develop
    - main
  workflow_dispatch:

env:
  BUILD_AMD64: true
  BUILD_ARM64: true
  LATEST_TAG: ${{ github.ref_name == 'main' }}
  USE_QEMU: false
  TAG_MAJOR_AND_MINOR: false
  AUTOMERGE_PRERELEASE: true
  AUTOMERGE_RELEASE: true
  PRERELEASE_BRANCH: develop
  RELEASE_BRANCH: main
  REBASE_PRERELEASE_BRANCH: true

jobs:
  expose-vars:
    runs-on: ubuntu-latest
    outputs:
      BUILD_AMD64: ${{ env.BUILD_AMD64 }}
      BUILD_ARM64: ${{ env.BUILD_ARM64 }}
      LATEST_TAG: ${{ env.LATEST_TAG }}
      USE_QEMU: ${{ env.USE_QEMU }}
      TAG_MAJOR_AND_MINOR: ${{ env.TAG_MAJOR_AND_MINOR }}
      AUTOMERGE_PRERELEASE: ${{ env.AUTOMERGE_PRERELEASE }}
      AUTOMERGE_RELEASE: ${{ env.AUTOMERGE_RELEASE }}
      PRERELEASE_BRANCH: ${{ env.PRERELEASE_BRANCH }}
      RELEASE_BRANCH: ${{ env.RELEASE_BRANCH }}
      REBASE_PRERELEASE_BRANCH: ${{ env.REBASE_PRERELEASE_BRANCH }}
    steps:
    - name: Exposing env vars
      run: echo "Exposing env vars"

  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@main
    needs:
    - expose-vars
    permissions:
      issues: write
      pull-requests: write
      contents: write
    with:
      TAG_MAJOR_AND_MINOR: ${{ needs.expose-vars.outputs.TAG_MAJOR_AND_MINOR == 'true' }}
      AUTOMERGE_PRERELEASE: ${{ needs.expose-vars.outputs.AUTOMERGE_PRERELEASE == 'true' }}
      AUTOMERGE_RELEASE: ${{ needs.expose-vars.outputs.AUTOMERGE_RELEASE == 'true' }}
      PRERELEASE_BRANCH: ${{ needs.expose-vars.outputs.PRERELEASE_BRANCH }}
      RELEASE_BRANCH: ${{ needs.expose-vars.outputs.RELEASE_BRANCH }}
      REBASE_PRERELEASE_BRANCH: ${{ needs.expose-vars.outputs.REBASE_PRERELEASE_BRANCH == 'true' }}
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}

  build-docker:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@main
    if: ${{ needs.release.outputs.release-created == 'true' }}
    needs:
    - expose-vars
    - release
    permissions:
      packages: write
      contents: read
    strategy:
      matrix:
        service:
        - name: api
          context: ./apps/api
          dockerfile: ./apps/api/Dockerfile
        - name: client
          context: ./apps/client
          dockerfile: ./apps/client/Dockerfile
        - name: docs
          context: ./apps/docs
          dockerfile: ./apps/docs/Dockerfile
    with:
      IMAGE_NAME: ghcr.io/${{ github.repository}}/${{ matrix.service.name }}
      IMAGE_TAG: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      IMAGE_CONTEXT: ${{ matrix.service.context }}
      IMAGE_DOCKERFILE: ${{ matrix.service.dockerfile }}
      BUILD_AMD64: ${{ needs.expose-vars.outputs.BUILD_AMD64 == 'true' }}
      BUILD_ARM64: ${{ needs.expose-vars.outputs.BUILD_ARM64 == 'true' }}
      LATEST_TAG: ${{ needs.expose-vars.outputs.LATEST_TAG == 'true' }}
      USE_QEMU: ${{ needs.expose-vars.outputs.USE_QEMU == 'true' }}

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
    needs:
    - expose-vars
    - release
    - build-docker
    if: ${{ needs.release.outputs.release-created == 'true' }}
    permissions:
      issues: write
      pull-requests: write
      contents: write
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: this-is-tobi/helm-charts
      CHART_NAME: my-project
      APP_VERSION: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || github.ref_name == 'main' && 'patch' }}
      PRERELEASE_IDENTIFIER: rc
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Example 3 - Helm Charts *(Basic CI Pipeline)*

```yaml
name: CI

on:
  pull_request:
    types:
      - opened
      - reopened
      - synchronize
      - ready_for_review
    paths:
      - 'charts/**'
  workflow_dispatch:

env:
  CT_CONF_PATH: .github/ct.yaml

jobs:
  expose-vars:
    runs-on: ubuntu-latest
    outputs:
      CT_CONF_PATH: ${{ env.CT_CONF_PATH }}
    steps:
    - name: Exposing env vars
      run: echo "Exposing env vars"

  lint-helm-docs:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@main
    needs:
    - expose-vars
    permissions:
      contents: read
    with:
      HELM_DOCS_VERSION: 1.14.2
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}
      LINT_CHARTS: false
      LINT_DOCS: true

  lint-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@main
    needs:
    - expose-vars
    permissions:
      contents: read
    with:
      HELM_DOCS_VERSION: 1.14.2
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}
      LINT_CHARTS: true
      LINT_DOCS: false

  test-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@main
    needs:
    - expose-vars
    with:
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}
```

### Example 4 - Helm Charts *(Basic CD Pipeline)*

```yaml
name: CD

on:
  push:
    branches:
    - develop
    - main
  workflow_dispatch:

jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@main
    permissions:
      contents: write
    with:
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
```

### Example 5 - Helm Charts *(Basic update app version Pipeline)*

```yaml
name: Update chart

on:
  workflow_call:
    inputs:
      RUN_MODE:
        description: Execution mode: 'caller' (trigger remote repo workflow) or 'called' (update chart in current repo)
        required: false
        type: string
        default: called
      CHART_NAME:
        description: Name of the folder chart (in /charts)
        required: true
        type: string
      APP_VERSION:
        description: The app version to inject in Chart.yaml
        required: true
        type: string
      UPGRADE_TYPE:
        description: Should update 'major', 'minor', 'patch' or 'prerelease'
        required: false
        type: string
        default: patch
      PRERELEASE_IDENTIFIER:
        description: Identifier used when UPGRADE_TYPE=prerelease (e.g. rc)
        required: false
        type: string
        default: rc
  workflow_dispatch:
    inputs:
      RUN_MODE:
        description: Execution mode: 'caller' (trigger remote repo workflow) or 'called' (update chart in current repo)
        required: false
        type: choice
        options:
        - caller
        - called
        default: called
      CHART_NAME:
        description: Name of the folder chart (in /charts)
        required: true
        type: choice
        options:
        - my-project
      APP_VERSION:
        description: The app version to inject in Chart.yaml
        required: true
        type: string
      UPGRADE_TYPE:
        description: Should update 'major', 'minor' or 'patch'
        required: false
        type: choice
        options:
          - major
          - minor
          - patch
          - prerelease
        default: patch
      PRERELEASE_IDENTIFIER:
        description: Identifier used when UPGRADE_TYPE=prerelease (e.g. rc)
        required: false
        type: string
        default: rc

jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@main
    permissions:
      issues: write
      pull-requests: write
      contents: write
    with:
      RUN_MODE: ${{ inputs.RUN_MODE }}
      CHART_NAME: ${{ inputs.CHART_NAME }}
      APP_VERSION: ${{ inputs.APP_VERSION }}
      UPGRADE_TYPE: ${{ inputs.UPDATE_TYPE }}
      PRERELEASE_IDENTIFIER: ${{ inputs.PRERELEASE_IDENTIFIER }}
```
