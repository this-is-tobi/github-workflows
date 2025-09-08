# `clean-cache.yml`

Delete GitHub Actions caches related to a PR/branch and optionally delete a single image from GHCR when an image reference is provided.

## Inputs

| Input       | Type   | Description                                                                                                                                                                          | Required | Default |
| ----------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| PR_NUMBER   | number | ID number of the pull request associated with the cache                                                                                                                              | No       | -       |
| BRANCH_NAME | string | Branch name associated with the cache                                                                                                                                                | No       | -       |
| IMAGE       | string | Image reference to delete (optionally with registry). Non-`ghcr.io` or missing registry are treated as GHCR. Must include a tag. Examples: `ghcr.io/org/app:1.2.3`, `org/app:1.2.3`. | No       | -       |

## Permissions

| Scope    | Access | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| packages | write  | Required to delete GHCR container package versions |
| contents | read   | Read repository contents                           |
| actions  | write  | Manage Actions caches via cache API                |

## Notes

- Cache deletion logic picks `BRANCH_NAME` if provided; otherwise derives a PR ref from `PR_NUMBER`.
- Image deletion job (`cleanup-image`) only runs when `IMAGE` is supplied.
- If `IMAGE` contains a registry different from `ghcr.io`, a warning is emitted and it is processed as if it were `ghcr.io`.
- If no registry is provided it is assumed to be `ghcr.io`.
- `IMAGE` must include a tag (e.g. `my-org/my-image:latest`); images are deleted via the GitHub Packages API.

## Examples

### Simple example

```yaml
jobs:
  cleanup:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@main
    with:
      PR_NUMBER: 123
      IMAGE: this-is-tobi/tools/debug:pr-123
```
