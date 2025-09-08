# `argocd-preview.yml`

Comment on PRs with preview URLs and optionally trigger an ArgoCD redeploy for preview environments.

## Inputs

| Input                        | Type   | Description                                          | Required | Default |
| ---------------------------- | ------ | ---------------------------------------------------- | -------- | ------- |
| APP_URL_TEMPLATE             | string | Template that can include `<pr_number>`              | Yes      | -       |
| PR_NUMBER                    | number | Pull request number                                  | Yes      | -       |
| ARGOCD_APP_NAME_TEMPLATE     | string | ArgoCD app name template (may include `<pr_number>`) | Yes      | -       |
| ARGOCD_SYNC_PAYLOAD_TEMPLATE | string | ArgoCD sync payload template                         | Yes      | -       |
| ARGOCD_URL                   | string | URL of the Argo-CD server                            | Yes      | -       |

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

- The redeploy step runs only when the PR has the `preview` label and `PR_NUMBER` is provided. `ARGOCD_TOKEN` must be set to authenticate redeploy requests. Template inputs accept the `<pr_number>` placeholder.

## Examples

### Simple example

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
