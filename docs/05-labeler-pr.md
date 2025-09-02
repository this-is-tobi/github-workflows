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

## Examples

### Simple example

```yaml
jobs:
  label:
    uses: this-is-tobi/github-workflows/.github/workflows/label-pr.yml@main
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
