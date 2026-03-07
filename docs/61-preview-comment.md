# `preview-comment.yml`

Post (or update) a pull request comment containing a table of preview environment URLs.

Supports multiple services, a `<pr_number>` placeholder in URLs, optional label gating, and customisable header/footer text. Subsequent runs update the same comment instead of creating duplicates.

## Inputs

| Input          | Type   | Description                                                                                               | Required | Default                                                     |
| -------------- | ------ | --------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------- |
| SERVICES       | string | JSON object mapping service names to URL templates. Use `<pr_number>` as a placeholder for the PR number. | Yes      | -                                                           |
| PR_NUMBER      | number | Pull request number (used to replace `<pr_number>` in URL templates and to target the comment)            | Yes      | -                                                           |
| LABEL          | string | PR label that must be present for the comment to be posted. Leave empty to always post.                   | No       | -                                                           |
| MESSAGE_HEADER | string | Custom markdown header line for the comment                                                               | No       | `🤖 Hey !`                                                   |
| MESSAGE_FOOTER | string | Custom markdown footer for the comment                                                                    | No       | `Please be patient, deployment may take a few minutes. […]` |
| COMMENT_TAG    | string | Unique tag used to identify and update this comment on subsequent runs (prevents duplicate comments)      | No       | `preview`                                                   |
| RUNS_ON        | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                  | No       | `["ubuntu-24.04"]`                                          |

## Permissions

| Scope         | Access | Description                     |
| ------------- | ------ | ------------------------------- |
| pull-requests | write  | Create or update the PR comment |

## Notes

- The `<pr_number>` placeholder in every service URL value is replaced with the actual `PR_NUMBER` input before the comment is posted.
- When `LABEL` is set, the entire job is skipped unless the PR carries that label — useful for on-demand preview environments that are only deployed when a specific label is applied.
- `COMMENT_TAG` is passed to `thollander/actions-comment-pull-request` which finds an existing comment with the same tag and edits it. This means re-running the workflow (e.g., after redeploying) updates the comment in-place instead of spamming the thread.
- The comment body is written to a temp file to correctly handle multiline `MESSAGE_FOOTER` values.
- The `SERVICES` value is a JSON string, not a YAML map — it must be passed as a single-quoted JSON string in the `with:` block.

## Examples

### Single service

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/preview-comment.yml@v0
    permissions:
      pull-requests: write
    with:
      SERVICES: '{"App": "https://app-pr-<pr_number>.example.com"}'
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Multiple services with label gate

The comment is only posted when the PR has the `preview` label, matching a workflow that only deploys preview environments when that label is present.

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/preview-comment.yml@v0
    permissions:
      pull-requests: write
    with:
      SERVICES: '{"API": "https://api-pr-<pr_number>.example.com", "Docs": "https://docs-pr-<pr_number>.example.com"}'
      PR_NUMBER: ${{ github.event.pull_request.number }}
      LABEL: preview
```

### Custom header and footer

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/preview-comment.yml@v0
    permissions:
      pull-requests: write
    with:
      SERVICES: '{"API": "https://api-pr-<pr_number>.example.com"}'
      PR_NUMBER: ${{ github.event.pull_request.number }}
      MESSAGE_HEADER: "🚀 Preview deployed!"
      MESSAGE_FOOTER: "*Auto-cleanup on PR close.*"
```

## ArgoCD preview environment context

This workflow is designed as the notification layer in a broader ArgoCD pull request preview pattern. The full setup works as follows:

### How it works

ArgoCD's [Pull Request Generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Pull-Request/) watches a repository's open PRs via the GitHub API. When a PR matches the configured filter (typically carrying a specific label such as `preview`), the ApplicationSet controller automatically creates a dedicated ArgoCD `Application` — and therefore a full preview environment — for that PR. When the label is removed or the PR is closed/merged, ArgoCD destroys the environment.

```
┌─────────────┐   adds label    ┌─────────────────────┐   detects label   ┌───────────────────┐
│  Developer  │ ──────────────► │   Pull Request (GH) │ ────────────────► │  ArgoCD AppSet    │
└─────────────┘                 └─────────────────────┘                   │  (PR Generator)   │
                                         │                                └────────┬──────────┘
                                         │ labeled event                           │ creates
                                         ▼                                         ▼
                                ┌──────────────────────┐                   ┌───────────────────┐
                                │  preview-comment.yml │                   │  Preview App +    │
                                │  (posts URL comment) │                   │  Namespace in K8s │
                                └──────────────────────┘                   └───────────────────┘
```

### ApplicationSet example

The ApplicationSet below uses the Pull Request Generator to watch a GitHub repository for PRs labelled `preview`, and deploys each one to its own namespace:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-preview
  namespace: argocd
spec:
  generators:
  - pullRequest:
      github:
        owner: my-org
        repo: my-app
        tokenRef:
          secretName: github-token
          key: token
        labels:
        - preview
      requeueAfterSeconds: 60
  template:
    metadata:
      name: "my-app-pr-{{number}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/my-org/my-app.git
        targetRevision: "{{head_sha}}"
        path: helm/my-app
        helm:
          valueFiles:
          - values.yaml
          values: |
            image:
              tag: "pr-{{number}}"
            ingress:
              host: "my-app-pr-{{number}}.example.com"
      destination:
        server: https://kubernetes.default.svc
        namespace: "my-app-pr-{{number}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

> For the full ApplicationSet template, see [github-appset.yaml](https://github.com/this-is-tobi/tools/blob/main/devops/argo-cd-app-preview/github-appset.yaml).

### End-to-end GitHub Actions workflow

This is a complete pull-request workflow that triggers on label events, builds and pushes a preview image, then posts the comment. The `LABEL: preview` input on `preview-comment` ensures the comment step is skipped if the workflow was triggered for a different label.

```yaml
on:
  pull_request:
    types:
    - labeled
    - synchronize

jobs:
  build:
    if: ${{ contains(github.event.pull_request.labels.*.name, 'preview') }}
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      BUILD_AMD64: true
      BUILD_ARM64: false

  comment:
    needs: build
    uses: this-is-tobi/github-workflows/.github/workflows/preview-comment.yml@v0
    permissions:
      pull-requests: write
    with:
      SERVICES: '{"App": "https://my-app-pr-<pr_number>.example.com"}'
      PR_NUMBER: ${{ github.event.pull_request.number }}
      LABEL: preview
```
