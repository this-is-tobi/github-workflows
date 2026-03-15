# Github workflows 🤖

This repository serves as a centralized location for reusable GitHub workflows. By defining shared workflows here, we streamline the process of maintaining consistency and quality across all repositories.

This repository contains reusable GitHub workflows intended to be referenced from other repositories via the `uses: owner/repo/.github/workflows/<file>@<ref>` mechanism.

## How to reference these workflows

In your repository, use a `uses:` reference under `jobs` to call a reusable workflow. 

__Example:__

```yaml
jobs:
  example:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@v0
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

**Lint**

- [Validate commit messages follow Conventional Commits (`lint-commits.yml`)](./.github/workflows/lint-commits.yml)
- [Lint Helm charts structure and validate documentation (`lint-helm.yml`)](./.github/workflows/lint-helm.yml)
- [Validate Helm chart values against a JSON schema (`lint-helm-schema.yml`)](./.github/workflows/lint-helm-schema.yml)
- [Lint JavaScript, JSON, Markdown and YAML files using ESLint (`lint-js.yml`)](./.github/workflows/lint-js.yml)
- [Lint YAML files using yamllint (`lint-yaml.yml`)](./.github/workflows/lint-yaml.yml)

**Test**

- [Test Helm charts installation with chart-testing (`test-helm.yml`)](./.github/workflows/test-helm.yml)
- [Test JavaScript/Typescript codebase using Vitest (`test-vitest.yml`)](./.github/workflows/test-vitest.yml)
- [Test Kubernetes deployments in an ephemeral Kind cluster (`test-kube-deployment.yml`)](./.github/workflows/test-kube-deployment.yml)
- [Run end-to-end Playwright tests across a browser matrix (`test-playwright.yml`)](./.github/workflows/test-playwright.yml)

**Build**

- [Build docker images and push it to a registry (`build-docker.yml`)](./.github/workflows/build-docker.yml)
- [Generate and attach security attestations to a Docker image (`attest-docker.yml`)](./.github/workflows/attest-docker.yml)

**Scan**

- [Run SonarQube analysis and quality gate check (`scan-sonarqube.yml`)](./.github/workflows/scan-sonarqube.yml)
- [Run Trivy vulnerability scans on images and config (`scan-trivy.yml`)](./.github/workflows/scan-trivy.yml)

**Release**

- [Release Apps using release-please and optional automerge (`release-app.yml`)](./.github/workflows/release-app.yml)
- [Release Helm charts using chart-releaser (`release-helm.yml`)](./.github/workflows/release-helm.yml)
- [Publish packages to any NPM-compatible registry (`release-npm.yml`)](./.github/workflows/release-npm.yml)
- [Update or trigger Helm chart app version bump (`update-helm-chart.yml`)](./.github/workflows/update-helm-chart.yml)

**Deploy**

- [Post preview links and optionally redeploy an ArgoCD preview app (`argocd-preview.yml`)](./.github/workflows/argocd-preview.yml)
- [Post or update a PR comment with preview environment URLs (`preview-comment.yml`)](./.github/workflows/preview-comment.yml)

**Utility**

- [Delete GitHub action caches and optionally GHCR images (`clean-cache.yml`)](./.github/workflows/clean-cache.yml)
- [Add labels to PRs using a labeler configuration file (`label-pr.yml`)](./.github/workflows/label-pr.yml)


## Documentation

**Website:** <https://this-is-tobi.com/github-workflows/introduction>

**Table of Contents** *- md sources*:
- [Lint Commits](./docs/10-lint-commits.md) *- Conventional commits validation*
- [Lint Helm](./docs/11-lint-helm.md) *- Helm chart linting and documentation validation*
- [Lint Helm Schema](./docs/12-lint-helm-schema.md) *- Helm chart values JSON schema validation*
- [Lint JavaScript](./docs/13-lint-js.md) *- JavaScript/TypeScript linting with ESLint*
- [Lint YAML](./docs/14-lint-yaml.md) *- YAML linting with yamllint*
- [Test Helm Charts](./docs/20-test-chart.md) *- Helm chart installation testing*
- [Test JavaScript](./docs/21-test-vitest.md) *- JavaScript/TypeScript testing with Vitest*
- [Test Kube Deployment](./docs/22-test-kube-deployment.md) *- Kubernetes deployment testing with Kind*
- [Test Playwright](./docs/23-test-playwright.md) *- End-to-end Playwright testing across browsers*
- [Build Docker](./docs/30-build-docker.md) *- Docker image building and registry pushing*
- [Attest Docker](./docs/31-attest-docker.md) *- SLSA provenance and SBOM attestations for Docker images*
- [Scan SonarQube](./docs/40-scan-sonarqube.md) *- Code quality analysis with SonarQube*
- [Scan Trivy](./docs/41-scan-trivy.md) *- Vulnerability scanning for images and configs*
- [Release App](./docs/50-release-app.md) *- Application releases using release-please*
- [Release Helm](./docs/51-release-helm.md) *- Helm chart releases with chart-releaser*
- [Update Helm Chart](./docs/52-update-helm-chart.md) *- Helm chart version bumping*
- [Release NPM](./docs/53-release-npm.md) *- NPM package publishing with multi-runtime and multi-registry support*
- [ArgoCD Preview](./docs/60-argocd-preview.md) *- Preview environment deployment with ArgoCD*
- [Preview Comment](./docs/61-preview-comment.md) *- Post or update PR comments with preview environment URLs*
- [Clean Cache](./docs/70-clean-cache.md) *- GitHub Actions cache and GHCR image cleanup*
- [Label PR](./docs/71-labeler-pr.md) *- Automatic pull request labeling*
- [CI/CD Examples](./docs/90-global-workflows-examples.md) *- Complete CI/CD pipeline examples*
