````markdown
# `lint-commits.yml`

Validate commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification using commitlint. Supports both pull request and push events with configurable rules.

## Inputs

| Input              | Type    | Description                                              | Required | Default                                                        |
| ------------------ | ------- | -------------------------------------------------------- | -------- | -------------------------------------------------------------- |
| COMMITS_SOURCE     | string  | Source of commits to lint (`pr` for PR, `push` for push) | No       | "pr"                                                           |
| CONFIG_FILE        | string  | Path to custom commitlint config file                    | No       | ""                                                             |
| FAIL_ON_ERROR      | boolean | Whether to fail the workflow on linting errors           | No       | true                                                           |
| ALLOWED_TYPES      | string  | Comma-separated list of allowed commit types             | No       | "feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert" |
| REQUIRE_SCOPE      | boolean | Whether to require a scope in commit messages            | No       | false                                                          |
| MAX_SUBJECT_LENGTH | number  | Maximum length of the commit subject line                | No       | 100                                                            |

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

### Simple example

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
```

### Require scope

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
    with:
      REQUIRE_SCOPE: true
```

### Custom allowed types

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
    with:
      ALLOWED_TYPES: "feat,fix,docs,chore"
      MAX_SUBJECT_LENGTH: 72
```

### Use custom config file

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
    with:
      CONFIG_FILE: ".commitlintrc.js"
```

### Non-blocking check

```yaml
jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
    with:
      FAIL_ON_ERROR: false
```

### For push events

```yaml
on:
  push:
    branches:
    - main
    - develop

jobs:
  lint-commits:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-commits.yml@main
    with:
      COMMITS_SOURCE: push
```

````
