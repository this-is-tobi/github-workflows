# `scan-scorecard.yml`

Audit a repository's supply-chain security practices with [OpenSSF Scorecard](https://github.com/ossf/scorecard) and report the findings in the GitHub Security tab.

## Inputs

| Input               | Type    | Description                                                                                          | Required | Default            |
| ------------------- | ------- | ---------------------------------------------------------------------------------------------------- | -------- | ------------------ |
| GITHUB_SECURITY_TAB | boolean | Whether to upload the SARIF report to the GitHub Security tab (Code scanning)                        | No       | `true`             |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`). Linux only | No       | `["ubuntu-24.04"]` |

## Secrets

This workflow does not require any secrets: it runs with the workflow's `GITHUB_TOKEN`, which is what Scorecard recommends.

## Permissions

| Scope           | Access | Description                                                                  |
| --------------- | ------ | ---------------------------------------------------------------------------- |
| contents        | read   | Read the repository and its workflows                                        |
| issues          | read   | Read issues (required on private repositories)                               |
| pull-requests   | read   | Read pull requests and their reviews (required on private repositories)      |
| checks          | read   | Read check runs, used by the CI-Tests and SAST checks (private repositories) |
| security-events | write  | Upload the SARIF report to code scanning                                     |

## Notes

- **What it checks.** Scorecard scores about twenty practices from 0 to 10: pinned dependencies, token permissions, dangerous workflow patterns, branch protection, code review, SAST, signed releases, known vulnerabilities, and more. Each finding becomes a code scanning alert with Scorecard's remediation advice, and the full SARIF report is also uploaded as the `scorecard-report` artifact (kept 7 days).
- **Results are never published** (`publish_results: false`), so there is no badge and no entry on scorecard.dev. Scorecard's API refuses published results from a workflow with top-level `defaults` or with `run` steps in the scanning job, and every workflow in this repository has both. A repository that wants the badge needs its own local workflow following [Scorecard's template](https://github.com/ossf/scorecard-action#workflow-example).
- **When to call it.** Scorecard scores the repository as it stands on its default branch, not a pull request's changes: call it on `push` to the default branch and on a weekly `schedule`, plus `branch_protection_rule` to re-score when protection changes. Upstream supports `pull_request` and `workflow_dispatch` only experimentally.
- **Branch protection.** The default token reads [repository rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets), but not classic branch protection, which needs an admin token: with classic protection the Branch-Protection check comes back inconclusive. Migrating to rulesets is Scorecard's own recommendation.
- **Private repositories.** The read permissions beyond `contents` are what Scorecard queries there (commits over GraphQL, pull requests, check runs); on a public repository they are harmless. Uploading to code scanning on a private repository needs GitHub Code Security: without it the upload fails with a warning in the job summary, and the report stays available as the artifact. Set `GITHUB_SECURITY_TAB: false` to skip the upload altogether.
- **Some checks score low by design on small projects.** Code-Review expects another person to approve each change, and Contributors, Fuzzing and CII-Best-Practices measure things a solo-maintained repository rarely has. Dismiss those alerts once rather than chasing the score.
- The checkout does not persist the job token (`persist-credentials: false`): nothing in the job talks to git.
- Linux runners only: the Scorecard action runs in a container.

## Examples

### Weekly and on every push to the default branch

A standalone workflow, since Scorecard runs on its own triggers rather than alongside the CI pipeline.

```yaml
name: Scorecard

on:
  push:
    branches:
    - main
  schedule:
  - cron: "0 5 * * 1"
  branch_protection_rule:

permissions: {}

jobs:
  scorecard:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-scorecard.yml@v0
    permissions:
      checks: read
      contents: read
      issues: read
      pull-requests: read
      security-events: write
```

### Without code scanning

For a private repository without GitHub Code Security: the report is only kept as the `scorecard-report` workflow artifact. `security-events: write` is still granted: GitHub validates the permissions a called workflow's jobs request at parse time, whatever its inputs.

```yaml
jobs:
  scorecard:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-scorecard.yml@v0
    permissions:
      checks: read
      contents: read
      issues: read
      pull-requests: read
      security-events: write
    with:
      GITHUB_SECURITY_TAB: false
```
