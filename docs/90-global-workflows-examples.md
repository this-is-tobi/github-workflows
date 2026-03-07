# CI/CD Examples

Complete, ready-to-use CI/CD pipeline compositions that combine multiple reusable workflows from this repository. Four repository types are covered: a simple single-service app, a multi-service monorepo, a Helm charts repository, and a JS library published to npm.

> These examples are intended as starting points. Adjust branch names, image names, chart repositories, SonarQube URLs, and secrets to match your project.

---

## Simple App

A single Node.js service shipped as one Docker image and deployed via an external Helm chart repository.

### CI Pipeline

Triggered on every pull request. Commit messages and code are linted in parallel, tests generate a coverage report, then a fast AMD64-only Docker image is built and both code quality and the built image are scanned.

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

jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    permissions:
      contents: read
      pull-requests: read

  lint-js:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read

  test-vitest:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      COVERAGE: true
      COVERAGE_REPORTER: lcov

  build-docker:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    needs:
    - lint-js
    - test-vitest
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/${{ github.repository }}/app
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: false

  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@v0
    needs:
    - test-vitest
    permissions:
      contents: read
      issues: write
      pull-requests: write
    with:
      SONAR_URL: https://sonarqube.example.com
      COVERAGE_IMPORT: true
      SOURCES_PATH: src
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}

  scan-trivy:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    needs:
    - build-docker
    permissions:
      contents: read
      pull-requests: write
    with:
      IMAGE: ghcr.io/${{ github.repository }}/app:pr-${{ github.event.pull_request.number }}
      PATH: ./
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}

  # Workaround for required status check in branch protection rules
  # (see https://github.com/orgs/community/discussions/13690)
  all-jobs-passed:
    name: Check jobs status
    runs-on: ubuntu-latest
    if: ${{ always() }}
    needs:
    - lint-commits
    - lint-js
    - test-vitest
    - build-docker
    - scan-sonarqube
    - scan-trivy
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

### CD Pipeline

Triggered on push to `develop` or `main`. release-please opens and manages the release PR; once merged, a multi-arch image is built and the Helm chart version is bumped in the external chart repository.

```yaml
name: CD

on:
  push:
    branches:
    - develop
    - main
  workflow_dispatch:

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: true
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_PRERELEASE: true
      AUTOMERGE_RELEASE: true
      PRERELEASE_BRANCH: develop
      RELEASE_BRANCH: main
      REBASE_PRERELEASE_BRANCH: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}

  build-docker:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    if: ${{ needs.release.outputs.release-created == 'true' }}
    needs:
    - release
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/${{ github.repository }}/app
      IMAGE_TAG: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: true
      LATEST_TAG: ${{ github.ref_name == 'main' }}
      TAG_MAJOR_AND_MINOR: true

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    if: ${{ needs.release.outputs.release-created == 'true' }}
    needs:
    - release
    - build-docker
    permissions:
      contents: write
      pull-requests: write
      actions: write
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: my-org/helm-charts
      CHART_NAME: my-app
      APP_VERSION: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

---

## Monorepo App

Multiple applications (`apps/`) and shared packages (`packages/`) compiled into separate Docker images. Lint and test jobs run unconditionally across the full repository; Docker builds fan out via a matrix strategy and are gated on both passing.

### CI Pipeline

Commit linting, code linting, and tests run in parallel on every non-draft PR. SonarQube consumes the coverage artifact produced by the test job. Each service gets its own Trivy image scan in a separate matrix job.

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
  IMAGE_TAG: ${{ github.event.pull_request.number || github.sha }}

jobs:
  expose-vars:
    runs-on: ubuntu-latest
    if: ${{ !github.event.pull_request.draft }}
    outputs:
      IMAGE_TAG: ${{ env.IMAGE_TAG }}
    steps:
    - name: Exposing env vars
      run: echo "Exposing env vars"

  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    if: ${{ !github.event.pull_request.draft }}
    permissions:
      contents: read
      pull-requests: read

  lint-js:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    if: ${{ !github.event.pull_request.draft }}
    permissions:
      contents: read

  test-vitest:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    if: ${{ !github.event.pull_request.draft }}
    permissions:
      contents: read
    with:
      COVERAGE: true
      COVERAGE_REPORTER: lcov

  build-docker:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    needs:
    - expose-vars
    - lint-js
    - test-vitest
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
      IMAGE_NAME: ghcr.io/${{ github.repository }}/${{ matrix.service.name }}
      IMAGE_TAG: pr-${{ needs.expose-vars.outputs.IMAGE_TAG }}
      IMAGE_CONTEXT: ${{ matrix.service.context }}
      IMAGE_DOCKERFILE: ${{ matrix.service.dockerfile }}
      BUILD_AMD64: true
      BUILD_ARM64: false

  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@v0
    needs:
    - test-vitest
    permissions:
      contents: read
      issues: write
      pull-requests: write
    with:
      SONAR_URL: https://sonarqube.example.com
      COVERAGE_IMPORT: true
      SOURCES_PATH: apps,packages
      SONAR_EXTRA_ARGS: >-
        -Dsonar.coverage.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue,**/assets/**
        -Dsonar.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}

  scan-trivy-conf:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    needs:
    - build-docker
    permissions:
      contents: read
    with:
      PATH: ./

  scan-trivy-images:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    needs:
    - expose-vars
    - build-docker
    permissions:
      contents: read
      pull-requests: write
    strategy:
      matrix:
        service:
        - name: api
        - name: client
        - name: docs
    with:
      IMAGE: ghcr.io/${{ github.repository }}/${{ matrix.service.name }}:pr-${{ needs.expose-vars.outputs.IMAGE_TAG }}
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}

  all-jobs-passed:
    name: Check jobs status
    runs-on: ubuntu-latest
    if: ${{ always() }}
    needs:
    - lint-commits
    - lint-js
    - test-vitest
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

### CD Pipeline

A single release-please run covers the whole monorepo. When a new release is created, all service images are rebuilt with the release version tag and the external Helm chart is bumped.

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
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
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
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
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
      IMAGE_NAME: ghcr.io/${{ github.repository }}/${{ matrix.service.name }}
      IMAGE_TAG: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      IMAGE_CONTEXT: ${{ matrix.service.context }}
      IMAGE_DOCKERFILE: ${{ matrix.service.dockerfile }}
      BUILD_AMD64: ${{ needs.expose-vars.outputs.BUILD_AMD64 == 'true' }}
      BUILD_ARM64: ${{ needs.expose-vars.outputs.BUILD_ARM64 == 'true' }}
      LATEST_TAG: ${{ needs.expose-vars.outputs.LATEST_TAG == 'true' }}
      USE_QEMU: ${{ needs.expose-vars.outputs.USE_QEMU == 'true' }}

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    needs:
    - expose-vars
    - release
    - build-docker
    if: ${{ needs.release.outputs.release-created == 'true' }}
    permissions:
      contents: write
      pull-requests: write
      actions: write
    with:
      RUN_MODE: caller
      WORKFLOW_NAME: update-app-version.yml
      CHART_REPO: my-org/helm-charts
      CHART_NAME: my-project
      APP_VERSION: ${{ format('{0}.{1}.{2}', needs.release.outputs.major-tag, needs.release.outputs.minor-tag, needs.release.outputs.patch-tag) }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

---

## Helm Charts Repository

A repository whose sole purpose is to host and release Helm charts. No application code is built.

### CI Pipeline

Triggered on pull requests that touch `charts/**`. All four lint jobs run in parallel; the install test waits for all of them to pass first.

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
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    needs:
    - expose-vars
    permissions:
      contents: read
    with:
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}
      LINT_CHARTS: false
      LINT_DOCS: true

  lint-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm.yml@v0
    needs:
    - expose-vars
    permissions:
      contents: read
    with:
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}
      LINT_CHARTS: true
      LINT_DOCS: false

  lint-helm-schema:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-helm-schema.yml@v0
    needs:
    - expose-vars
    permissions:
      contents: read
    with:
      CHARTS_DIR: ./charts

  lint-yaml:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-yaml.yml@v0
    needs:
    - expose-vars
    permissions:
      contents: read

  test-helm-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@v0
    needs:
    - expose-vars
    - lint-helm-docs
    - lint-helm-charts
    - lint-helm-schema
    - lint-yaml
    with:
      CT_CONF_PATH: ${{ needs.expose-vars.outputs.CT_CONF_PATH }}

  all-jobs-passed:
    name: Check jobs status
    runs-on: ubuntu-latest
    if: ${{ always() }}
    needs:
    - lint-helm-docs
    - lint-helm-charts
    - lint-helm-schema
    - lint-yaml
    - test-helm-charts
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

### CD Pipeline

Triggered on push to `main`. chart-releaser detects which charts had their version bumped and creates the corresponding GitHub Releases; charts are also pushed to the OCI registry.

```yaml
name: CD

on:
  push:
    branches:
    - main
  workflow_dispatch:

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

### Update App Version Workflow

The chart repository exposes a `workflow_call` + `workflow_dispatch` entry-point so external application repositories can trigger a chart version bump via the `update-helm-chart` caller workflow. Store this file as `.github/workflows/update-app-version.yml` in the **chart repository**.

```yaml
name: Update chart

on:
  workflow_call:
    inputs:
      RUN_MODE:
        description: Execution mode — 'caller' (trigger remote repo) or 'called' (update chart locally)
        required: false
        type: string
        default: called
      CHART_NAME:
        description: Name of the chart directory under charts/
        required: true
        type: string
      APP_VERSION:
        description: Application version to inject into Chart.yaml
        required: true
        type: string
      UPGRADE_TYPE:
        description: SemVer part to increment — major, minor, patch, or prerelease
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
        description: Execution mode — 'caller' or 'called'
        required: false
        type: choice
        options:
        - caller
        - called
        default: called
      CHART_NAME:
        description: Name of the chart directory under charts/
        required: true
        type: choice
        options:
        - my-project
      APP_VERSION:
        description: Application version to inject into Chart.yaml
        required: true
        type: string
      UPGRADE_TYPE:
        description: SemVer part to increment
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
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
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

---

## JS Library / npm Package

A TypeScript or JavaScript package without Docker images or Helm charts. The CD pipeline focuses solely on versioning and changelog generation.

### CI Pipeline

Commit messages, code style, and tests run in parallel on every pull request. SonarQube consumes the coverage artifact produced by the test job. No Docker build is involved.

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

jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    permissions:
      contents: read
      pull-requests: read

  lint-js:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-js.yml@v0
    permissions:
      contents: read
    with:
      LINT_PATHS: "src tests"

  test-vitest:
    uses: this-is-tobi/github-workflows/.github/workflows/test-vitest.yml@v0
    permissions:
      contents: read
    with:
      COVERAGE: true
      COVERAGE_REPORTER: lcov

  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@v0
    needs:
    - test-vitest
    permissions:
      contents: read
      issues: write
      pull-requests: write
    with:
      SONAR_URL: https://sonarqube.example.com
      COVERAGE_IMPORT: true
      SOURCES_PATH: src
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}

  all-jobs-passed:
    name: Check jobs status
    runs-on: ubuntu-latest
    if: ${{ always() }}
    needs:
    - lint-commits
    - lint-js
    - test-vitest
    - scan-sonarqube
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

### CD Pipeline

Triggered on push to `develop` or `main`. release-please manages the CHANGELOG and version tag; no build or push step is required since publishing to npm happens outside this workflow.

```yaml
name: CD

on:
  push:
    branches:
    - develop
    - main
  workflow_dispatch:

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      ENABLE_PRERELEASE: true
      TAG_MAJOR_AND_MINOR: false
      AUTOMERGE_PRERELEASE: true
      AUTOMERGE_RELEASE: true
      PRERELEASE_BRANCH: develop
      RELEASE_BRANCH: main
      REBASE_PRERELEASE_BRANCH: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```
