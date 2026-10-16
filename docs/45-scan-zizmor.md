# `scan-zizmor.yml`

Audit GitHub Actions workflows and actions for security issues using [zizmor](https://github.com/zizmorcore/zizmor): template injection, excessive permissions, persisted credentials, unpinned references, dangerous triggers, known-vulnerable actions and more. Findings show up as annotations on the file and line they point at.

## Inputs

| Input            | Type    | Description                                                                                                                                                        | Required | Default          |
| ---------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ---------------- |
| ZIZMOR_VERSION   | string  | Zizmor version used to perform the audit                                                                                                                           | No       | 1.31.1           |
| CONFIG_FILE      | string  | Path to a zizmor configuration file. Defaults to the one zizmor finds itself (`.github/zizmor.yml` or `zizmor.yml`), if any                                        | No       | ""               |
| SCAN_PATH        | string  | Path to audit: a repository root, a `.github/workflows` directory or a single workflow or action file                                                             | No       | .                |
| PERSONA          | string  | How much noise to accept: `regular` (minimal false positives), `pedantic` (adds code smells) or `auditor` (adds findings that may be false positives)             | No       | regular          |
| MIN_SEVERITY     | string  | Drop findings below this severity (`informational`, `low`, `medium` or `high`)                                                                                     | No       | ""               |
| MIN_CONFIDENCE   | string  | Drop findings below this confidence (`low`, `medium` or `high`)                                                                                                    | No       | ""               |
| ONLINE_AUDITS    | boolean | Whether to run the audits that query the GitHub API, using the job token                                                                                           | No       | true             |
| FAIL_ON_FINDINGS | boolean | Whether to fail the workflow when findings are reported                                                                                                            | No       | true             |
| RUNS_ON          | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                           | No       | ["ubuntu-24.04"] |

## Secrets

This workflow does not require any secrets.

## Permissions

| Scope    | Access | Description                                                      |
| -------- | ------ | ---------------------------------------------------------------- |
| contents | read   | Read workflow files, and query the GitHub API for online audits |

## Notes

- Uses `zizmor` (installed via pip, at the exact `ZIZMOR_VERSION`) rather than a floating install: a new release adds audits, and an audit that did not exist yesterday turns a green run red overnight. Bump the version deliberately - the default carries a Renovate marker, so a caller pinning it through `with:` can do the same.
- `SCAN_PATH` is **one path**, passed to zizmor as a single argument. Whitespace is part of the value, not a separator.
- The job token is handed to zizmor as `GH_TOKEN` when `ONLINE_AUDITS: true`, which switches on the audits that call the GitHub API: known-vulnerable actions, impostor commits, and refs that disagree with their version comment. With `ONLINE_AUDITS: false` the token is withheld and `--no-online-audits` is passed, leaving only the audits that read the files themselves.
- The `ref-version-mismatch` audit compares the version comment next to a SHA pin with the tags that point at that commit. A pin written against a **moving tag** (`@<sha> # v0`) goes stale the moment that tag moves, and the audit reports it until the pin is bumped, so keep the dependency bot's digest update for such pins free of any release-age cooldown.
- Zizmor's exit status is the verdict: it exits 11-14 according to the worst finding. `FAIL_ON_FINDINGS: false` adds `--no-exit-codes`, a report-only mode where findings stay visible as annotations but never block the pipeline. A run that cannot finish at all (an unreadable path, a missing `CONFIG_FILE`) fails either way.
- Accepted findings belong in `.github/zizmor.yml`, one entry per rule with the reason it is not fixed, or in an inline `# zizmor: ignore[rule]` comment for a single line. Both are honoured without any input.
- Complementary to `scan-trivy.yml`, which scans images and configuration for vulnerabilities, and to `scan-scorecard.yml`, which grades supply-chain practices repository-wide: zizmor reads the workflows themselves.
- Linux runners only.

## Examples

### Simple blocking audit

Audits every workflow and action in the repository with the `regular` persona and the online audits on, and fails when anything is found.

```yaml
jobs:
  scan-zizmor:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-zizmor.yml@v0
    permissions:
      contents: read
```

### Only what matters, from a custom configuration

Keeps `medium` and `high` findings, loads the configuration from a non-default location and audits the workflows directory only.

```yaml
jobs:
  scan-zizmor:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-zizmor.yml@v0
    permissions:
      contents: read
    with:
      CONFIG_FILE: ".config/zizmor.yml"
      SCAN_PATH: ".github/workflows"
      MIN_SEVERITY: medium
```

### Report-only on a repository that cannot reach the API

Runs the offline audits only and never fails, for a self-hosted runner with no route to `api.github.com` or for a first pass over a repository with a backlog of findings.

```yaml
jobs:
  scan-zizmor:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-zizmor.yml@v0
    permissions:
      contents: read
    with:
      ONLINE_AUDITS: false
      FAIL_ON_FINDINGS: false
      RUNS_ON: '["self-hosted", "linux"]'
```
