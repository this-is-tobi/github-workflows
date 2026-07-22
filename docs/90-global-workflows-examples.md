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

A single release-please run covers the whole monorepo. When a new release is created, all service images are rebuilt with the release version tag and the Helm chart is bumped. This example bumps a chart in an **external** charts repository via `update-helm-chart` (caller mode); if the chart instead lives **inside** the monorepo (e.g. `charts/my-app`), release it in the same pipeline with `release-helm` in `local` mode — see [Releasing an in-repo chart (local mode)](#releasing-an-in-repo-chart-local-mode) below.

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

### Releasing an in-repo chart (local mode)

When the Helm chart is part of the monorepo (e.g. `charts/my-app`) rather than a separate charts repository, keep **two decoupled version streams**:

- the **app** version, driven by release-please (`release-app`);
- the **chart** version, driven by `update-helm-chart` in `local` mode — bumped when the app releases (with the new `appVersion` injected), or on its own for chart-only changes.

`chart-releaser`'s tag-based change detection is unreliable here (the tag namespace is full of app tags like `v1.2.3`), so the chart is published by `release-helm` in **`local` mode**, which simply packages the committed `Chart.yaml` and pushes it to the OCI registry.

**App release path** — replace the `bump-chart` (caller mode) job of the CD pipeline above with this pair: after each app release, the chart is bumped on its own lifecycle (`prerelease` on `develop`, `patch` on `main` — the existing prerelease `x.y.z-rc.n` graduates automatically), committed directly on the branch, and published in the same run:

```yaml
jobs:
  # ... 'release' and 'build-docker' jobs from the CD pipeline above ...

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    needs:
    - release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: local
      CHART_NAME: my-app
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      MODE: local
      CHARTS_DIR: ./charts
      CHART_NAME: my-app
      # Package exactly the bump commit pushed by update-helm-chart
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

> The bump commit is pushed with `GITHUB_TOKEN`, and such pushes never trigger new workflow runs — no CD loop, which is precisely why the chart must be released in the same run via the `commit-sha` output.

**Chart-only path** — a chart fix must ship without waiting for an app release. Add a dedicated workflow triggered only by chart changes (human pushes — the bot's own bump commits don't retrigger it). The guard job skips the bump when the pushed commit already changed `version:` in `Chart.yaml` (e.g. a developer bumped it manually in the PR), releasing it as-is instead:

```yaml
name: CD - chart

on:
  push:
    branches:
    - develop
    - main
    paths:
    - "charts/**"

jobs:
  chart-infos:
    name: Check chart version bump
    runs-on: ubuntu-latest
    outputs:
      version-bumped: ${{ steps.check.outputs.BUMPED }}
    steps:
    - name: Checks-out repository
      uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
      with:
        fetch-depth: 2

    - name: Check whether the push already bumped the chart version
      id: check
      run: |
        if git diff HEAD^ HEAD -- charts/my-app/Chart.yaml | grep -q '^+version:'; then
          echo "BUMPED=true" >> "$GITHUB_OUTPUT"
        else
          echo "BUMPED=false" >> "$GITHUB_OUTPUT"
        fi

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    needs:
    - chart-infos
    if: ${{ needs.chart-infos.outputs.version-bumped == 'false' }}
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: local
      CHART_NAME: my-app
      # APP_VERSION omitted: chart-only release, appVersion stays untouched
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    needs:
    - chart-infos
    - bump-chart
    # Run whether the bump happened (fresh commit) or was already pushed (skip)
    if: ${{ !cancelled() && needs.chart-infos.result == 'success' && (needs.bump-chart.result == 'success' || needs.bump-chart.result == 'skipped') }}
    permissions:
      contents: read
      packages: write
    with:
      MODE: local
      CHARTS_DIR: ./charts
      CHART_NAME: my-app
      # Empty when bump-chart was skipped -> packages the pushed commit as-is
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

**Scaling to more release trains** (`alpha` → `beta` → `main`): `release-app` already supports it — point `PRERELEASE_BRANCH` at the current branch and select a per-branch release-please config, and mirror the train on the chart side with `PRERELEASE_IDENTIFIER`:

```yaml
jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    with:
      ENABLE_PRERELEASE: true
      RELEASE_BRANCH: main
      PRERELEASE_BRANCH: ${{ github.ref_name }}
      PRERELEASE_CONFIG_FILE: release-please-config-${{ github.ref_name }}.json
      PRERELEASE_MANIFEST_FILE: .release-please-manifest-${{ github.ref_name }}.json

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    with:
      RUN_MODE: local
      CHART_NAME: my-app
      UPGRADE_TYPE: ${{ github.ref_name == 'main' && 'patch' || 'prerelease' }}
      PRERELEASE_IDENTIFIER: ${{ github.ref_name }}
```

The chart bump logic handles the whole train natively: `0.4.1-alpha.3` → (push to `beta`) `0.4.1-beta` → `0.4.1-beta.1` → (push to `main`) `0.4.1`. On the ArgoCD side, point each environment at the matching stream with a semver constraint on `targetRevision`: stable environments use e.g. `1.x` (semver ranges exclude prereleases by default), pre-production environments use a prerelease-inclusive range such as `>=0.0.0-0`, and the per-train identifiers (`-alpha.n`, `-beta.n`) keep the streams distinguishable.

The chart is then pullable with `helm pull oci://ghcr.io/<owner>/<repo>/my-app --version <version>`. See [`release-helm.yml` → Modes](./51-release-helm.md#modes) and [`update-helm-chart.yml`](./52-update-helm-chart.md) for the full details.

---

## Helm Chart Release Patterns

Whatever the topology, releasing a chart is always the **same two building blocks**:

1. **The bump brain** — [`update-helm-chart.yml`](./52-update-helm-chart.md) computes the next chart version on the chart's own lifecycle. The *style* knob is its mode: `called` opens a **pull request** (release-please style, human gate or automerge) while `local` **commits directly** and the release continues in the same run.
2. **The publisher** — [`release-helm.yml`](./51-release-helm.md) in `local` mode packages the committed `Chart.yaml` and pushes it to the OCI registry. Direct style feeds it the bump commit via `CHECKOUT_REF`; PR style lets the merge trigger a chart CD workflow whose guard job detects the already-bumped version and publishes as-is.

**The repo that hosts the chart owns the style** — in a monorepo the app repo's CD picks the mode; with a dedicated chart repository its entry-point workflow does. The topology only changes *where* the two jobs run:

| Release style                       | Monorepo (chart in app repo)                                                                                            | Dedicated chart repository                                                                                                                                   |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **PR-gated** (release-please style) | App CD → `update-helm-chart` (`called`, PR on same repo) → merge triggers the chart CD guard → `release-helm` (`local`) | App CD → `update-helm-chart` (`caller`) → chart repo entry-point (`called`, PR) → merge triggers the chart CD → `release-helm` (`local` or `chart-releaser`) |
| **Direct** (in-pipeline)            | App CD → `update-helm-chart` (`local`) → `release-helm` (`local`, same run)                                             | App CD → `update-helm-chart` (`caller`) → chart repo entry-point (`local`) → `release-helm` (`local`, same run)                                              |

Shared guarantees across all four quadrants:

- Chart and app versions stay **decoupled** (`appVersion` tracks the app; chart `version` follows its own stream, including chart-only releases with `APP_VERSION` empty).
- Loop safety is identical: direct bump commits are pushed with `GITHUB_TOKEN` and never retrigger workflows; PR merges (human or PAT automerge) do trigger the chart CD, whose guard prevents any re-bump.
- `release-helm`'s `chart-releaser` mode remains the classic alternative for dedicated chart repositories that want auto-detection, GitHub Releases and a `gh-pages` `index.yaml` on top of the OCI push.

The **monorepo direct** flow is shown [above](#releasing-an-in-repo-chart-local-mode); the **monorepo PR-gated** variant only swaps the `bump-chart` job (the publisher stays the chart CD guard workflow shown above, which the merged PR triggers):

```yaml
jobs:
  # ... 'release' and 'build-docker' jobs from the CD pipeline above ...
  # No in-run 'release-chart' job here: the chart CD guard workflow publishes
  # the chart when the bump PR merges.

  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    needs:
    - release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-app
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: ${{ github.ref_name == 'develop' && 'prerelease' || 'patch' }}
      PRERELEASE_IDENTIFIER: rc
      # Open the bump PR against the branch being released
      BASE_BRANCH: ${{ github.ref_name }}
      AUTOMERGE_RELEASE: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

> GitHub limitation: PRs opened with `GITHUB_TOKEN` don't auto-trigger PR CI checks — merge via automerge (`GH_PAT`) or manually. The dedicated-repo variants of both styles are shown in the [Update App Version Workflow](#update-app-version-workflow) templates below.

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
    - "charts/**"
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
      CHART_PATH: ./charts

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

Triggered on push to `main`. chart-releaser detects which charts had their version bumped and pushes them to the OCI registry (optionally creating GitHub Releases with `CREATE_GITHUB_RELEASE: true`).

> Harmonized alternative: instead of chart-releaser's tag-based detection, you can reuse the exact same guard + `release-helm` `local` chart CD as the monorepo (`on: push: paths: charts/**` — see [Helm Chart Release Patterns](#helm-chart-release-patterns)). Keep `chart-releaser` mode when you want auto-detection across many charts, GitHub Releases, or a classic `gh-pages` `index.yaml`.

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

This entry-point is where the chart repository **owns its release style** (see [Helm Chart Release Patterns](#helm-chart-release-patterns)): the first template below is **PR-gated** (`called` — bump PR, then the CD pipeline releases on merge), the second is **direct** (`local` — bump commit and OCI publish in the same run). The app-side caller is identical either way.

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

#### Direct style variant

Same triggers and inputs (keep the `on:` block from the template above — the `RUN_MODE` input must stay declared because the caller forwards it, but the entry-point deliberately ignores it: the chart repository owns its style). The bump is committed straight to the default branch and the chart is published in the same run — mirroring the [monorepo direct flow](#releasing-an-in-repo-chart-local-mode) exactly:

```yaml
jobs:
  bump-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      # Style is fixed by the chart repo, not by the caller
      RUN_MODE: local
      CHART_NAME: ${{ inputs.CHART_NAME }}
      APP_VERSION: ${{ inputs.APP_VERSION }}
      UPGRADE_TYPE: ${{ inputs.UPGRADE_TYPE }}
      PRERELEASE_IDENTIFIER: ${{ inputs.PRERELEASE_IDENTIFIER }}

  release-chart:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    needs:
    - bump-chart
    permissions:
      contents: read
      packages: write
    with:
      MODE: local
      CHART_NAME: ${{ inputs.CHART_NAME }}
      # Package exactly the bump commit pushed by update-helm-chart
      CHECKOUT_REF: ${{ needs.bump-chart.outputs.commit-sha }}
```

> Direct pushes to the default branch must be allowed for `github-actions[bot]` (no "require a pull request" rule); keep the PR-gated template otherwise. With this variant the CD pipeline above is only needed for charts modified directly by PRs in the chart repository — its guard-based alternative is described in [Helm Chart Release Patterns](#helm-chart-release-patterns).

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
      LINT_PATHS: src tests

  lint-deps:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-deps.yml@v0
    permissions:
      contents: read
    with:
      # publint inspects the built package, so build first via PRE_COMMAND
      PRE_COMMAND: npm run build
      KNIP_COMMAND: npx knip
      PUBLINT_COMMAND: npx publint

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
    - lint-deps
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
