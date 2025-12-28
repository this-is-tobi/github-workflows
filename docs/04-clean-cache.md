# `clean-cache.yml`

Delete GitHub Actions caches related to a PR/branch and optionally delete a single image from GHCR when an image reference is provided.

## Inputs

| Input                    | Type    | Description                                                                                                  | Required | Default |
| ------------------------ | ------- | ------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| PR_NUMBER                | number  | ID number of the pull request associated with the cache                                                      | No       | -       |
| BRANCH_NAME              | string  | Branch name associated with the cache                                                                        | No       | -       |
| IMAGE                    | string  | Image reference to delete (e.g., `ghcr.io/owner/repo/service:pr-123`)                                        | No       | -       |
| CLEAN_GH_CACHE           | boolean | Whether to clean GitHub Actions cache                                                                        | No       | true    |
| CLEAN_GHCR_IMAGE         | boolean | Whether to delete the specified image from ghcr.io                                                           | No       | false   |
| CLEAN_ORPHANED_GHCR_IMAGE| boolean | Whether to delete orphaned SHA-only images from ghcr.io                                                      | No       | false   |

## Permissions

| Scope    | Access | Description                                        |
| -------- | ------ | -------------------------------------------------- |
| packages | write  | Required to delete GHCR container package versions |
| contents | read   | Read repository contents                           |
| actions  | write  | Manage Actions caches via cache API                |

## Notes

- Cache deletion logic picks `BRANCH_NAME` if provided; otherwise derives a PR ref from `PR_NUMBER`.
- Use `CLEAN_GH_CACHE`, `CLEAN_GHCR_IMAGE`, and `CLEAN_ORPHANED_GHCR_IMAGE` to control which cleanup operations run.
- Image deletion job (`cleanup-image`) only runs when `CLEAN_GHCR_IMAGE: true` and `IMAGE` is supplied.
- Orphaned image cleanup (`cleanup-orphaned-image`) deletes SHA-only tagged images (7-character hex digests) when `CLEAN_ORPHANED_GHCR_IMAGE: true`.
- Multi-arch manifest cleanup is handled automatically when deleting images.
- Uses GitHub CLI (`gh`) for improved API interactions and error handling.
- `IMAGE` must include a tag (e.g. `ghcr.io/my-org/my-image:pr-123`); images are deleted via the GitHub Packages API.

## Examples

### Clean cache and delete specific image

```yaml
jobs:
  cleanup:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@main
    with:
      PR_NUMBER: 123
      IMAGE: ghcr.io/this-is-tobi/tools/debug:pr-123
      CLEAN_GH_CACHE: true
      CLEAN_GHCR_IMAGE: true
```

### Clean orphaned SHA-only images

```yaml
jobs:
  cleanup-orphans:
    uses: this-is-tobi/github-workflows/.github/workflows/clean-cache.yml@main
    with:
      IMAGE: ghcr.io/this-is-tobi/tools/debug
      CLEAN_GH_CACHE: false
      CLEAN_ORPHANED_GHCR_IMAGE: true
```
