# `lint-actions.yml`

Lint the GitHub Actions workflows of a repository with `actionlint`: schema, expression and context checks, plus `shellcheck` over every `run:` block. Findings are annotated on the file and line they point at.

## Inputs

| Input       | Type   | Description                                                                                                                | Required | Default          |
| ----------- | ------ | -------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| CONFIG_FILE | string | Path to an `actionlint` configuration file, without whitespace (uses `.github/actionlint.yaml` or `.yml` when there is one) | No       | ""               |
| RUNS_ON     | string | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'`); a Linux runner with Docker                                       | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description                 |
| -------- | ------ | --------------------------- |
| contents | read   | Read the workflow files     |

## Notes

- Runs `actionlint` from its release image (`docker://rhysd/actionlint`), pinned by digest; the version moves with this repository's releases. The image ships `shellcheck`, so the `run:` blocks are checked too.
- Lints every workflow under `.github/workflows`. There is no path input: restrict `paths` or ignore a finding in the configuration file.
- A `CONFIG_FILE` that does not exist, or that contains whitespace (the runner splits the arguments of the step on it), fails the run before `actionlint` starts. Running without the file the caller named would report the very errors it exists to silence.
- Findings are printed as `file:line:col: message [rule]` and registered with a problem matcher, so they show up as annotations on the pull request.
- `actionlint` knows a fixed list of GitHub-hosted runner labels, so a label shipped after the pinned release is reported as unknown. Declare it under `self-hosted-runner.labels` in the configuration file: the `runner-label` rule stays on, and a typo is still caught.
- `actionlint` does not resolve a remote reusable workflow's permission requests: a caller granting less than a called job declares fails at startup, and no run of this workflow sees it.
- It checks that the workflows are correct. [`scan-zizmor.yml`](./45-scan-zizmor.md) audits the same files for security issues, and the two are meant to run side by side.

## Examples

### Simple example

Lints the workflows of the repository with the configuration `actionlint` finds by itself, if any.

```yaml
jobs:
  lint-actions:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-actions.yml@v0
    permissions:
      contents: read
```

### With a configuration file and a runner

Loads a configuration kept outside `.github/`, and runs on a runner whose label the pinned `actionlint` does not know yet (declared in that configuration).

```yaml
jobs:
  lint-actions:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-actions.yml@v0
    permissions:
      contents: read
    with:
      CONFIG_FILE: ci/actionlint.yaml
      RUNS_ON: '["ubuntu-26.04"]'
```
