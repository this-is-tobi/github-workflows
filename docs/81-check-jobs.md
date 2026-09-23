# `check-jobs.yml`

Aggregate the results of every job in a workflow into the single status check a ruleset can require.

## Inputs

| Input         | Type    | Description                                                                                       | Required | Default              |
| ------------- | ------- | ------------------------------------------------------------------------------------------------- | -------- | -------------------- |
| NEEDS         | string  | The calling job's own `needs` context, serialised with `toJson`                                    | Yes      | -                    |
| ALLOW_SKIPPED | boolean | Whether a skipped job counts as a pass — required for a path-filtered pipeline                     | No       | `true`               |
| RUNS_ON       | string  | Runner labels as JSON array                                                                       | No       | `'["ubuntu-24.04"]'` |

## Permissions

| Scope | Access | Description                                                     |
| ----- | ------ | --------------------------------------------------------------- |
| -     | -      | None. The job reads the results it is given and nothing else |

## Notes

- **Why this exists.** Branch protection names the checks it requires, and a required check that never reports blocks a merge forever. A pipeline with path filters, a matrix, or a job behind an `if` therefore cannot have its real jobs required individually — the set that runs varies per pull request. One job that always runs, standing for all of them, is the way out.
- **The calling job keeps the two halves only it can know**: `if: ${{ always() }}`, so the gate runs even when something upstream failed, and a `needs` list naming the jobs. A reusable workflow cannot see the workflow that called it, let alone that workflow's job graph, which is why the context arrives as an input.
- **List every job in `needs`, not only the last ones.** A skipped job counts as a pass, and a job that was skipped *because something it needed failed* also reports `skipped` — the two are indistinguishable from inside this workflow. That is safe only while the failing dependency is in the list too and fails on its own account. Leave a job out and its failure can reach the gate as a skip.
- **An empty context is a failure, not a pass.** A calling job that omits `needs:` passes `{}`, which would otherwise report success having verified nothing. The gate refuses it and says so.
- Every job's result is printed, and every failing one is named before the step exits — a run with three broken jobs says three rather than stopping at the first. `failure`, `cancelled` and `timed_out` are reported by name, because a cancellation and a timeout are not read the way a failure is.
- `ALLOW_SKIPPED: false` suits a pipeline where every job is expected to run; a skip then fails the gate rather than passing it.
- Uses `jq`, which is present on GitHub-hosted runners. A self-hosted runner named through `RUNS_ON` needs it installed.

## Migrating an inline gate

The status check this reports is named **`<calling job's name> / Required jobs`** — a reusable workflow's checks are always prefixed with the calling job's name. A hand-written gate job reports under its own name alone, so moving to this workflow **renames the check**, and a ruleset still requiring the old name will block every pull request waiting for a check that no longer reports.

Change the workflow and the ruleset together, in that order:

1. Merge the workflow change, and let one pull request run so the new check name is registered.
2. Update the ruleset's required status checks to the new name.

## Examples

### Simple example

```yaml
jobs:
  lint:
    # ...
  test:
    # ...
  build:
    # ...

  all-jobs-passed:
    name: Check jobs status
    if: ${{ always() }}
    needs:
    - lint
    - test
    - build
    uses: this-is-tobi/github-workflows/.github/workflows/check-jobs.yml@v0
    with:
      NEEDS: ${{ toJson(needs) }}
```

The required status check is then `Check jobs status / Required jobs`.

### Every job is expected to run

With no path filters and nothing behind an `if`, a skip is a surprise rather than the ordinary answer:

```yaml
  all-jobs-passed:
    name: Check jobs status
    if: ${{ always() }}
    needs:
    - lint
    - test
    uses: this-is-tobi/github-workflows/.github/workflows/check-jobs.yml@v0
    with:
      NEEDS: ${{ toJson(needs) }}
      ALLOW_SKIPPED: false
```
