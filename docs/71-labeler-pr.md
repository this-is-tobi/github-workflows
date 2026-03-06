# `label-pr.yml`

Add or sync labels on pull requests using a configuration file.

## Inputs

| Input     | Type   | Description                              | Required | Default |
| --------- | ------ | ---------------------------------------- | -------- | ------- |
| CONF_PATH | string | Path to the `labeler` configuration file | Yes      | -       |

## Permissions

| Scope         | Access | Description               |
| ------------- | ------ | ------------------------- |
| pull-requests | write  | Required to add PR labels |

## Notes

- Uses the official `actions/labeler` action under the hood.
- The configuration file maps label names to file glob patterns; a label is applied whenever any of its patterns matches a changed file in the PR.
- Labels are kept in sync on each push to the PR: labels whose patterns no longer match are removed.
- Requires `pull-requests: write` permission on the calling workflow.
- The configuration file must be committed to the repository before the workflow runs.

## Examples

The example below shows a minimal invocation alongside a sample `labeler` configuration file that maps label names to file-path glob patterns.

### Simple example

```yaml
jobs:
  label:
    uses: this-is-tobi/github-workflows/.github/workflows/label-pr.yml@v0
    with:
      CONF_PATH: .github/labeler-conf.yml
```

Example configuration file (`.github/labeler-conf.yml`):

```yaml
doc:
- changed-files:
  - any-glob-to-any-file:
    - "docs/**"
api:
- changed-files:
  - any-glob-to-any-file: 
    - "apps/api/**"
client:
- changed-files:
  - any-glob-to-any-file: 
    - "apps/client/**"
ci:
- changed-files:
  - any-glob-to-any-file: 
    - ".github/**"
    - "ci/**"
```

> For more details on the configuration file format, see the [labeler action documentation](https://github.com/actions/labeler).
