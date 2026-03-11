# `argocd-preview.yml`

Comment on PRs with preview URLs and optionally trigger an ArgoCD redeploy for preview environments.

## Inputs

| Input                        | Type   | Description                                                              | Required | Default |
| ---------------------------- | ------ | ------------------------------------------------------------------------ | -------- | ------- |
| APP_URL_TEMPLATE             | string | Template for the preview app URL (can include `<pr_number>` placeholder) | Yes      | -       |
| PR_NUMBER                    | number | Pull request number                                                      | Yes      | -       |
| ARGOCD_APP_NAME_TEMPLATE     | string | ArgoCD app name template (may include `<pr_number>`)                     | Yes      | -       |
| ARGOCD_SYNC_PAYLOAD_TEMPLATE | string | ArgoCD sync payload template                                             | Yes      | -       |
| ARGOCD_URL                   | string | URL of the Argo-CD server                                                | Yes      | -       |

## Secrets

| Secret       | Description                           | Required | Default |
| ------------ | ------------------------------------- | -------- | ------- |
| ARGOCD_TOKEN | Token used to redeploy the ArgoCD app | Yes      | -       |

## Permissions

| Scope         | Access | Description                  |
| ------------- | ------ | ---------------------------- |
| pull-requests | write  | Required to post PR comments |
| contents      | read   | Read repository (templates)  |

## Notes

- Both `preview-comment` and `preview-sync` jobs only trigger when the PR carries the `preview` label; add the label to activate preview behaviour.
- `APP_URL_TEMPLATE`, `ARGOCD_APP_NAME_TEMPLATE`, and `ARGOCD_SYNC_PAYLOAD_TEMPLATE` all support the `<pr_number>` placeholder, which is replaced at runtime with the actual PR number.
- `ARGOCD_TOKEN` is required to authenticate the sync API call; store it as a repository secret.
- The sync request is sent to `<ARGOCD_URL>/api/v1/applications/<app-name>/sync` with the provided JSON payload. Non-200 responses are reported but do not fail the workflow (the step uses `continue-on-error: true`).
- Useful pattern: pair with a path-filter job so previews are only rebuilt when relevant files change.

## Examples

The first example shows a minimal static call with hardcoded values. The second demonstrates a complete pull-request workflow where the PR number is passed dynamically from the event payload.

### Simple example

Minimal static call with all values hardcoded. The sync payload targets two specific Deployments in the preview namespace; update the `resources` array to match your own workloads.

```yaml
jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/argocd-preview.yml@v0
    permissions:
      pull-requests: write
    with:
      APP_URL_TEMPLATE: https://app-name.pr-<pr_number>.example.com
      PR_NUMBER: 123
      ARGOCD_APP_NAME_TEMPLATE: app-name-pr-<pr_number>
      ARGOCD_SYNC_PAYLOAD_TEMPLATE: '{"appNamespace":"argocd","prune":true,"dryRun":false,"strategy":{"hook":{"force":true}},"resources":[{"group":"apps","version":"v1","kind":"Deployment","namespace":"app-name-pr-<pr_number>","name":"app-name-pr-<pr_number>-client"},{"group":"apps","version":"v1","kind":"Deployment","namespace":"app-name-pr-<pr_number>","name":"app-name-pr-<pr_number>-server"}],"syncOptions":{"items":["Replace=true"]}}'
      ARGOCD_URL: https://argo-cd.example.com
    secrets:
      ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
```

### Full PR workflow integration

Typical usage inside a pull-request workflow, passing the PR number dynamically:

```yaml
on:
  pull_request:
    types:
    - opened
    - reopened
    - synchronize
    - labeled

jobs:
  preview:
    uses: this-is-tobi/github-workflows/.github/workflows/argocd-preview.yml@v0
    permissions:
      pull-requests: write
    with:
      APP_URL_TEMPLATE: https://my-app.pr-<pr_number>.example.com
      PR_NUMBER: ${{ github.event.pull_request.number }}
      ARGOCD_APP_NAME_TEMPLATE: my-app-pr-<pr_number>
      ARGOCD_SYNC_PAYLOAD_TEMPLATE: '{"appNamespace":"argocd","prune":true,"dryRun":false,"strategy":{"hook":{"force":true}},"syncOptions":{"items":["Replace=true"]}}'
      ARGOCD_URL: https://argo-cd.example.com
    secrets:
      ARGOCD_TOKEN: ${{ secrets.ARGOCD_TOKEN }}
```
