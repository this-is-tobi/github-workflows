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
- [Test JavaScript/Typescript codebase using Vitest (`test-js.yml`)](./.github/workflows/test-js.yml)
- [Update or trigger Helm chart app version bump (`update-helm-chart.yml`)](./.github/workflows/update-helm-chart.yml)


## Documentation

**Website:** <https://this-is-tobi.com/github-workflows/introduction>

**Table of Contents** *- md sources*:
- [ArgoCD Preview](./docs/02-argocd-preview.md) *- Preview environment deployment with ArgoCD*
- [Build Docker](./docs/03-build-docker.md.md) *- Docker image building and registry pushing*
- [Clean Cache](./docs/04-clean-cache.md) *- GitHub Actions cache and GHCR image cleanup*
- [Label PR](./docs/05-labeler-pr.md) *- Automatic pull request labeling*
- [Lint Helm](./docs/06-lint-helm.md) *- Helm chart linting and documentation validation*
- [Lint JavaScript](./docs/07-lint-js.md) *- JavaScript/TypeScript linting with ESLint*
- [Release App](./docs/08-release-app.md) *- Application releases using release-please*
- [Release Helm](./docs/09-release-helm.md) *- Helm chart releases with chart-releaser*
- [Scan SonarQube](./docs/10-scan-sonarqube.md) *- Code quality analysis with SonarQube*
- [Scan Trivy](./docs/11-scan-trivy.md) *- Vulnerability scanning for images and configs*
- [Test Helm Charts](./docs/12-test-chart.md) *- Helm chart installation testing*
- [Test JavaScript](./docs/13-test-js.md) *- JavaScript/TypeScript testing with Vitest*
- [Update Helm Chart](./docs/14-update-helm-chart.md) *- Helm chart version bumping*
- [CI/CD Examples](./docs/15-global-workflows-examples.md) *- Complete CI/CD pipeline examples*
