# `lint-proto.yml`

Lints Protocol Buffers with [buf](https://buf.build): formatting, style rules, and — the one that matters — backward compatibility against the branch you are merging into.

Nothing here is language-specific. buf reads `.proto` files, and what a repository generates from them is its own business; a Go server and a TypeScript client sharing a schema call the same workflow.

## Inputs

| Input             | Type    | Description                                                                             | Required | Default            |
| ----------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ------------------ |
| WORKING_DIRECTORY | string  | Directory holding the buf configuration                                                 | No       | "."                |
| BUF_VERSION       | string  | buf version to install. Empty uses the action's own default                             | No       | ""                 |
| FORMAT            | boolean | Whether to check formatting with `buf format`                                           | No       | true               |
| LINT              | boolean | Whether to run `buf lint`                                                               | No       | true               |
| BREAKING          | boolean | Whether to run `buf breaking`                                                           | No       | true               |
| BREAKING_AGAINST  | string  | buf input to compare against, verbatim. Empty derives it from the base branch           | No       | ""                 |
| BREAKING_BRANCH   | string  | Branch to compare against. Empty uses the pull request's base, then the repo default    | No       | ""                 |
| PATHS             | string  | Limit every check to these paths, space separated                                       | No       | ""                 |
| FETCH_DEPTH       | number  | Checkout depth. The breaking check reads the base branch out of the local clone         | No       | 0                  |
| RUNS_ON           | string  | Runner labels as JSON array                                                             | No       | '["ubuntu-24.04"]' |
| FAIL_ON_ERROR     | boolean | Whether to fail the workflow on findings                                                | No       | true               |

## Permissions

| Scope    | Access | Description                  |
| -------- | ------ | ---------------------------- |
| contents | read   | Read the checked-out sources |

## Notes

- **`buf breaking` is the reason to run this.** Formatting and style rules are conveniences; compatibility is a contract. A field renumbered in a published schema breaks every client already compiled against it, and it breaks them at runtime, in a way that compiles clean and passes every test on both sides.
- **The comparison target names `origin/<branch>`, not `<branch>`.** A checkout leaves the base branch as a remote-tracking ref with no local branch of that name, so buf's `branch=main` form clones the local repository looking for a branch that is not there and fails with `exit status 128`, naming nothing. `branch=origin/main` resolves. This is the shape a hand-written version gets wrong, because the naive form works on a laptop where the local branch exists.
- **A missing base ref is named rather than left to buf.** If `origin/<branch>` is not in the clone the job says so, and says which input to look at, instead of letting a 128 read like a broken tool.
- **A run on the base branch says it compared nothing.** Comparing a branch with itself always passes, so on a push to `main` the check is green without having detected anything. It emits a warning rather than looking like a result — the gate is meant to run on pull requests.
- **buf runs from the repository root with the directory as its input**, rather than entering it with `cd`. That keeps `.git` at its ordinary path, so the comparison target needs no `../` and does not change shape with how deeply the module is nested.
- **`--exit-code` is what makes the format step a check.** Without it `buf format --diff` prints the diff it wants applied and exits 0, so the step would display the work and report success.
- **`BREAKING` with no resolvable target is an error, not a run.** `buf breaking` without `--against` compares nothing and exits 0, which is the exact shape this gate exists not to have.
- **The install uses `bufbuild/buf-action` with `setup_only`.** The action is the maintained one — `buf-setup-action` has not been released since January 2025 — and `setup_only` keeps each check a step somebody can read and gate, rather than a flag on one opaque action.

## Usage

### On every pull request

```yaml
name: CI

on:
  pull_request:
    branches:
    - "**"

jobs:
  lint-proto:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-proto.yml@v0
    permissions:
      contents: read
```

### A schema in a subdirectory

The common case: the module lives under `proto/` and the generated code lives elsewhere.

```yaml
jobs:
  lint-proto:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-proto.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: proto
```

### Comparing against a fixed branch

For a repository whose published contract is a release branch rather than whatever a pull request happens to target.

```yaml
jobs:
  lint-proto:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-proto.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: proto
      BREAKING_BRANCH: release/v1
```

### Comparing against a published module

`BREAKING_AGAINST` is passed to buf untouched, so any input buf accepts works — a registry module, a tag, an archive.

```yaml
jobs:
  lint-proto:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-proto.yml@v0
    permissions:
      contents: read
    with:
      BREAKING_AGAINST: buf.build/acme/petapis:v1
```

### Style and formatting only

For a repository that is still shaping its schema and has no published contract to keep.

```yaml
jobs:
  lint-proto:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-proto.yml@v0
    permissions:
      contents: read
    with:
      BREAKING: false
```
