# `scan-trivy.yml`

Run Trivy vulnerability scans on container images and/or configuration files and upload SARIF reports to GitHub Security.

## Inputs

| Input               | Type    | Description                                                | Required | Default |
| ------------------- | ------- | ---------------------------------------------------------- | -------- | ------- |
| IMAGE               | string  | Image used to perform scan (e.g., docker.io/debian:latest) | No       | -       |
| REGISTRY_USERNAME   | string  | Username used to login into registry                       | No       | -       |
| REGISTRY_PASSWORD   | string  | Password used to login into registry                       | No       | -       |
| PATH                | string  | Path used to perform config scan                           | No       | -       |
| FORMAT              | string  | Format of the report (sarif, table, json, ...)             | No       | table   |
| PR_NUMBER           | string  | PR number for comment posting                              | No       | -       |
| GITHUB_SECURITY_TAB | boolean | Whether to upload SARIF to GitHub Security Tab             | No       | false   |

## Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ---------------------------------- |
| contents        | read   | Read repository contents           |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |
| packages        | read   | Pull images from GHCR              |

## Notes

- `images-scan` runs only if `IMAGE` is provided; `config-scan` runs only if `PATH` is provided.
- `FORMAT` controls output format: `table` (default) prints results to workflow summary, `sarif` enables GitHub Security Tab integration.
- When `GITHUB_SECURITY_TAB: true` and `FORMAT: sarif`, uploads results to the Security tab.
- PR comments link to either the GitHub Security Tab (when `GITHUB_SECURITY_TAB: true`) or the Workflow Summary page.
- Registry authentication: uses GitHub token for `ghcr.io`, otherwise uses provided credentials.
- Skips common directories via `skip-dirs: **/node_modules` in config scan.

## Examples

### Simple scan with table output

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Scan with GitHub Security Tab integration

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
      FORMAT: sarif
      GITHUB_SECURITY_TAB: true
      PR_NUMBER: ${{ github.event.pull_request.number }}
```
