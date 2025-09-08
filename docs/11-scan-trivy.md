# `scan-trivy.yml`

Run Trivy vulnerability scans on container images and/or configuration files and upload SARIF reports to GitHub Security.

## Inputs

| Input | Type   | Description                                              | Required | Default |
| ----- | ------ | -------------------------------------------------------- | -------- | ------- |
| IMAGE | string | Image used to perform scan (eg. docker.io/debian:latest) | No       | -       |
| PATH  | string | Path used to perform config scan                         | No       | -       |

## Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ---------------------------------- |
| contents        | write  | General repo operations by jobs    |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |

## Notes

- `images-scan` runs only if `IMAGE` is provided; `config-scan` runs only if `PATH` is provided
- Uploads SARIF results to the Security tab; on pull requests, posts a comment linking to the Security panel when both `IMAGE` and `PATH` are set
- Skips common directories via `skip-dirs: **/node_modules` in config scan

## Examples

### Simple example

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@main
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
```
