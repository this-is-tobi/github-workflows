# `scan-govulncheck.yml`

Scan a Go module for known vulnerabilities using [govulncheck](https://go.dev/blog/vuln), and optionally upload SARIF reports to GitHub Security.

## Inputs

| Input                | Type    | Description                                                                                                        | Required | Default          |
| --------------------- | ------- | -------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| GO_VERSION            | string  | Go version to use. Empty reads it from `go.mod`                                                                       | No       | ""               |
| WORKING_DIRECTORY     | string  | Working directory holding the module to scan                                                                          | No       | "."              |
| PACKAGES              | string  | Package pattern to scan                                                                                               | No       | "./..."          |
| GOVULNCHECK_VERSION   | string  | govulncheck version to install                                                                                        | No       | v1.7.0           |
| FORMAT                | string  | Format of the report (text, json, sarif)                                                                              | No       | text             |
| FAIL_ON_VULNS         | boolean | Whether to fail the workflow when a known vulnerability is found                                                      | No       | true             |
| PR_NUMBER             | string  | PR number for comment posting                                                                                         | No       | -                |
| GITHUB_SECURITY_TAB   | boolean | Whether to upload SARIF to GitHub Security Tab                                                                        | No       | false            |
| CATEGORY              | string  | Code scanning category for the SARIF upload. Set a distinct value per module for a caller scanning several modules   | No       | -                |
| CACHE                 | boolean | Whether to cache the module and build caches                                                                          | No       | true             |
| RUNS_ON               | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                              | No       | ["ubuntu-24.04"] |

## Secrets

This workflow does not require any secrets.

## Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ----------------------------------- |
| contents        | read   | Read repository contents           |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |

## Notes

- **Reachability, not presence.** govulncheck only reports a vulnerability in code the scanned packages can actually reach — not merely a module listed in `go.sum` — which is what keeps false positives rare enough that `FAIL_ON_VULNS` defaults on. A vulnerable function sitting in a dependency your code never calls is not reported at all; run with `-show verbose` locally if you need to see what was excluded and why.
- **Exit code 3 means findings, not failure.** Anything else nonzero (a bad `PACKAGES` pattern, a network failure reaching `vuln.go.dev`) is treated as a broken scan rather than a clean result, and fails the job regardless of `FAIL_ON_VULNS` — that input only governs the *findings* case.
- When a vulnerability is found, the report upload and PR comment always run before the workflow fails. Set `FAIL_ON_VULNS: false` for a report-only mode that never blocks the pipeline.
- `FORMAT: text` is printed into the job summary directly (truncated past the 1 MiB step-summary limit, with the complete report attached as an artifact). `json` and `sarif` are written to a file only — meant for tooling, not for a person reading the run; a `sarif` finding surfaces through the Security tab instead once uploaded.
- `GOVULNCHECK_VERSION` is exact, never `latest`: this is third-party code executed in the job, and a floating version would let a new upstream release change what runs here with no change on this repository's side.
- `CATEGORY` matters for a monorepo with more than one Go module (e.g. a caller scanning `go.mod` and several `plugins/*/go.mod` on the same run): SARIF uploads sharing a category replace one another in the Security tab, leaving only whichever leg finished last.
- The Security tab link in the PR comment is filtered on the ref the SARIF was actually uploaded against: `pr:<number>` for a `pull_request` run, `branch:<name>` for a push, and no ref filter at all for anything else (a tag). Code scanning only indexes alerts under that ref, so a caller that scans on `push` and passes `PR_NUMBER` by hand still gets a link that resolves.

## Examples

### Simple blocking scan

Scans the module and fails the workflow if any reachable vulnerability is found. When `PR_NUMBER` is set, a PR comment is posted with the scan outcome.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-govulncheck.yml@v0
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
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-govulncheck.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      FORMAT: sarif
      GITHUB_SECURITY_TAB: true
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Scanning more than one module

A caller with several Go modules (e.g. a root module plus a directory of independently-versioned plugins) scans each with its own `CATEGORY` so the SARIF uploads do not overwrite one another in the Security tab.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-govulncheck.yml@v0
    strategy:
      matrix:
        module: [plugins/foo, plugins/bar]
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      WORKING_DIRECTORY: ${{ matrix.module }}
      FORMAT: sarif
      GITHUB_SECURITY_TAB: true
      CATEGORY: govulncheck-${{ matrix.module }}
```

### Report-only mode

Reports findings without ever failing the workflow, useful when first introducing vulnerability scanning on a repository with existing findings to triage.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-govulncheck.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
    with:
      FAIL_ON_VULNS: false
```
