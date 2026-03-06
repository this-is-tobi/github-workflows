# `lint-commits.yml`

Validate commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification using commitlint. Supports both pull request and push events with configurable rules.

## Inputs

| Input              | Type    | Description                                                                              | Required | Default                                                        |
| ------------------ | ------- | ---------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------- |
| COMMITS_SOURCE     | string  | Source of commits to lint (`pr` for PR, `push` for push)                                 | No       | "pr"                                                           |
| CONFIG_FILE        | string  | Path to custom commitlint config file                                                    | No       | ""                                                             |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on linting errors                                           | No       | true                                                           |
| ALLOWED_TYPES      | string  | Comma-separated list of allowed commit types                                             | No       | "feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert" |
| REQUIRE_SCOPE      | boolean | Whether to require a scope in commit messages                                            | No       | false                                                          |
| MAX_SUBJECT_LENGTH | number  | Maximum length of the commit subject line                                                | No       | 100                                                            |
| RUNS_ON            | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"]                                               |

## Permissions

| Scope         | Access | Description                          |
| ------------- | ------ | ------------------------------------ |
| contents      | read   | Read commit history                  |
| pull-requests | read   | Read PR information for commit range |

## Notes

- **Conventional Commits Format**: `<type>(<scope>): <subject>`
- **Default Types**: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
- Uses Bun runtime for fast package installation and execution.
- Uses `@commitlint/cli` with `@commitlint/config-conventional` as the base configuration.
- Automatically generates a commitlint config if no custom config file is provided.
- Produces a summary table in the GitHub Actions workflow summary showing each commit's status.
- For PRs, lints all commits between the base and head branches.
- For push events, lints commits between the previous and current SHA.
- Custom configuration files (e.g., `commitlint.config.js`) take precedence over auto-generated config.

## Examples

The following examples cover basic commit linting, scope enforcement, custom allowed types, external config files, non-blocking mode, and linting push events instead of pull requests.

### Simple example

Lints all PR commits against the default Conventional Commits ruleset with no extra configuration. The 11 standard types are accepted and no scope is required.

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
```

### Require scope

`REQUIRE_SCOPE: true` makes the `(scope)` part of the format mandatory — `feat: add feature` fails, while `feat(auth): add feature` passes.

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    with:
      REQUIRE_SCOPE: true
```

### Custom allowed types

Restricts the accepted types to a minimal set and lowers the subject line limit to 72 characters — a common Git convention that fits in standard terminal widths.

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    with:
      ALLOWED_TYPES: "feat,fix,docs,chore"
      MAX_SUBJECT_LENGTH: 72
```

### Use custom config file

Loads the full commitlint configuration from `.commitlintrc.js`. All inline inputs (`ALLOWED_TYPES`, `REQUIRE_SCOPE`, `MAX_SUBJECT_LENGTH`) are overridden by the config file.

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    with:
      CONFIG_FILE: ".commitlintrc.js"
```

### Non-blocking check

Violations appear in the workflow summary table without failing the job. Useful when rolling out Conventional Commits on a repository that already has non-conforming commit history.

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    with:
      FAIL_ON_ERROR: false
```

### For push events

`COMMITS_SOURCE: push` switches the commit range from the PR context to the push SHA range (`before` → `after`). The workflow should be triggered on `push` events rather than `pull_request`.

```yaml
on:
  push:
    branches:
    - main
    - develop

jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@v0
    with:
      COMMITS_SOURCE: push
```
