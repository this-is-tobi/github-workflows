# Github workflows 🤖

This repository serves as a centralized location for reusable GitHub workflows. By defining shared workflows here, we streamline the process of maintaining consistency and quality across all repositories.

This repository contains reusable GitHub workflows intended to be referenced from other repositories via the `uses: owner/repo/.github/workflows/<file>@<ref>` mechanism.

## How to reference these workflows

In your repository, use a `uses:` reference under `jobs` to call a reusable workflow. 

__Example:__

```yaml
jobs:
  example:
    permissions:
      contents: read
      issues: write
      pull-requests: write
    uses: this-is-tobi/github-workflows/.github/workflows/scan-sonarqube.yml@v0
    with:
      SONAR_URL: "https://sonarqube.example.com"
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

- [Validate commit messages follow Conventional Commits (`lint-commits.yml`)](../.github/workflows/lint-commits.yml)
- [Lint Helm charts structure and validate documentation (`lint-helm.yml`)](../.github/workflows/lint-helm.yml)
- [Validate Helm chart values against a JSON schema (`lint-helm-schema.yml`)](../.github/workflows/lint-helm-schema.yml)
- [Lint JavaScript, JSON, Markdown and YAML files using ESLint (`lint-js.yml`)](../.github/workflows/lint-js.yml)
- [Lint dependency hygiene with knip and publint (`lint-deps.yml`)](../.github/workflows/lint-deps.yml)
- [Lint YAML files using yamllint (`lint-yaml.yml`)](../.github/workflows/lint-yaml.yml)

**Test**

- [Test Helm charts installation with chart-testing (`test-helm.yml`)](../.github/workflows/test-helm.yml)
- [Test JavaScript/Typescript codebase using Vitest (`test-vitest.yml`)](../.github/workflows/test-vitest.yml)
- [Test Kubernetes deployments in an ephemeral Kind cluster (`test-kube-deployment.yml`)](../.github/workflows/test-kube-deployment.yml)
- [Run end-to-end Playwright tests across a browser matrix (`test-playwright.yml`)](../.github/workflows/test-playwright.yml)
- [Run a command inside a built Docker image (`test-docker.yml`)](../.github/workflows/test-docker.yml)

**Build**

- [Build docker images and optionally push it to a registry (`build-docker.yml`)](../.github/workflows/build-docker.yml)
- [Generate and attach security attestations to a Docker image (`attest-docker.yml`)](../.github/workflows/attest-docker.yml)

**Scan**

- [Run SonarQube analysis and quality gate check (`scan-sonarqube.yml`)](../.github/workflows/scan-sonarqube.yml)
- [Run Trivy vulnerability scans on images and config (`scan-trivy.yml`)](../.github/workflows/scan-trivy.yml)
- [Scan git history for leaked secrets using gitleaks (`scan-gitleaks.yml`)](../.github/workflows/scan-gitleaks.yml)

**Release**

- [Release Apps using release-please and optional automerge (`release-app.yml`)](../.github/workflows/release-app.yml)
- [Release Helm charts using chart-releaser (`release-helm.yml`)](../.github/workflows/release-helm.yml)
- [Publish packages to any NPM-compatible registry (`release-npm.yml`)](../.github/workflows/release-npm.yml)
- [Update or trigger Helm chart app version bump (`update-helm-chart.yml`)](../.github/workflows/update-helm-chart.yml)

**Deploy**

- [Post preview links and optionally redeploy an ArgoCD preview app (`argocd-preview.yml`)](../.github/workflows/argocd-preview.yml)
- [Post or update a PR comment with preview environment URLs (`preview-comment.yml`)](../.github/workflows/preview-comment.yml)

**Utility**

- [Delete GitHub action caches and optionally GHCR images (`clean-cache.yml`)](../.github/workflows/clean-cache.yml)
- [Add labels to PRs using a labeler configuration file (`label-pr.yml`)](../.github/workflows/label-pr.yml)
