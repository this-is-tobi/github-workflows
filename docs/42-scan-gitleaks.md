# `scan-gitleaks.yml`

Scan the full git history for leaked secrets using [gitleaks](https://github.com/gitleaks/gitleaks) and optionally upload SARIF reports to GitHub Security.

## Inputs

| Input               | Type    | Description                                                                              | Required | Default          |
| ------------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| GITLEAKS_VERSION    | string  | Gitleaks version used to perform the scan                                                | No       | 8.30.1           |
| FORMAT              | string  | Format of the report (sarif, json, csv, junit)                                           | No       | sarif            |
| FAIL_ON_LEAKS       | boolean | Whether to fail the workflow when leaks are detected                                     | No       | true             |
| PR_NUMBER           | string  | PR number for comment posting                                                            | No       | -                |
| GITHUB_SECURITY_TAB | boolean | Whether to upload SARIF to GitHub Security Tab                                           | No       | false            |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Secrets

This workflow does not require any secrets.

## Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ---------------------------------- |
| contents        | read   | Read repository contents           |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |

## Notes

- The repository is checked out with `fetch-depth: 0` so gitleaks scans **every commit in history**, not just the current tree. This catches secrets that were committed and later removed, which remain exposed in the git history.
- Complementary to `scan-trivy.yml`: Trivy covers image vulnerabilities and configuration misconfigurations, gitleaks covers leaked credentials across the whole git history.
- Runs the MIT-licensed gitleaks CLI directly (downloaded from GitHub releases with checksum verification) instead of the official `gitleaks-action`, which requires a `GITLEAKS_LICENSE` key for organization repositories. This keeps the workflow free to use for any consumer.
- Secrets are always redacted (`--redact`) from logs and reports, so detected values are never exposed in workflow output.
- A `.gitleaks.toml` configuration file and a `.gitleaksignore` file at the repository root are picked up automatically to tune rules or ignore known false positives.
- When leaks are found, the report upload and PR comment always run before the workflow fails. Set `FAIL_ON_LEAKS: false` for a report-only mode that never blocks the pipeline.
- When `GITHUB_SECURITY_TAB: true` and `FORMAT: sarif`, uploads results to the Security tab.
- Linux runners only (x64 and arm64 are supported).

## Examples

### Simple blocking scan

Scans the whole git history and fails the workflow if any leak is detected. When `PR_NUMBER` is set, a PR comment is posted with the scan outcome.

```yaml
jobs:
  secret-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-gitleaks.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Scan with GitHub Security Tab integration

The SARIF report is uploaded to the repository's Security → Code scanning tab, and the PR comment links to it. Findings are deduplicated and tracked across runs.

```yaml
jobs:
  secret-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-gitleaks.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      GITHUB_SECURITY_TAB: true
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Report-only mode

Reports findings without ever failing the workflow, useful when first introducing secret scanning on a repository with a noisy history.

```yaml
jobs:
  secret-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-gitleaks.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      FAIL_ON_LEAKS: false
```
