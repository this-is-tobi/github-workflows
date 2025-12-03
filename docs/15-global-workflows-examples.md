# CI/CD Examples

Here are two example workflows that combine multiple reusable workflows from this repository to create a CI/CD pipeline for a monorepo with multiple apps and packages.

## Examples

### App *(Basic CI Pipeline)*

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
      uses: actions/checkout@v5

    - name: Check updated files paths
      uses: dorny/paths-filter@v3
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

### App *(Basic CD Pipeline)*

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

### Helm Charts *(Basic CI Pipeline)*

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

### Helm Charts *(Basic CD Pipeline)*

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

### Helm Charts *(Basic update app version Pipeline)*

```yaml
name: Update chart

on:
  workflow_call:
    inputs:
      RUN_MODE:
        description: Execution mode 'caller' (trigger remote repo workflow) or 'called' (update chart in current repo)
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
        description: Execution mode 'caller' (trigger remote repo workflow) or 'called' (update chart in current repo)
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
      UPGRADE_TYPE: ${{ inputs.UPGRADE_TYPE }}
      PRERELEASE_IDENTIFIER: ${{ inputs.PRERELEASE_IDENTIFIER }}
```
