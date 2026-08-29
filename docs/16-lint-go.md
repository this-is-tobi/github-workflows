# `lint-go.yml`

Formatting, `go vet` and optionally golangci-lint over a Go module. Detects the module first and reports rather than passes when there is not one.

`go vet` runs once per build tag set, because a build tag produces a second binary and code that only compiles under one of them is otherwise only vetted under one.

## Inputs

| Input                 | Type    | Description                                                                                  | Required | Default            |
| --------------------- | ------- | -------------------------------------------------------------------------------------------- | -------- | ------------------ |
| GO_VERSION            | string  | Go version to use. Empty reads it from `go.mod`                                              | No       | ""                 |
| WORKING_DIRECTORY     | string  | Working directory for the module to lint                                                     | No       | "."                |
| PACKAGES              | string  | Package pattern to vet                                                                       | No       | "./..."            |
| BUILD_TAGS            | string  | Build tag sets as a JSON array of strings; one `go vet` pass each                             | No       | '[""]'             |
| FORMAT                | boolean | Whether to check formatting with gofmt                                                       | No       | true               |
| FORMAT_PATHS          | string  | Paths to check formatting in, space separated                                                | No       | "."                |
| VET                   | boolean | Whether to run `go vet`                                                                      | No       | true               |
| GOLANGCI_LINT         | string  | "true", "false", or empty to run it when a `.golangci` configuration file is present         | No       | ""                 |
| GOLANGCI_LINT_VERSION | string  | golangci-lint version to install                                                             | No       | "v2.6.2"           |
| GOLANGCI_LINT_ARGS    | string  | Extra arguments for `golangci-lint run`                                                      | No       | ""                 |
| CACHE                 | boolean | Whether to cache the module and build caches                                                 | No       | true               |
| RUNS_ON               | string  | Runner labels as JSON array                                                                  | No       | '["ubuntu-24.04"]' |
| FAIL_ON_ERROR         | boolean | Whether to fail the workflow on lint findings                                                | No       | true               |

## Permissions

| Scope    | Access | Description        |
| -------- | ------ | ------------------ |
| contents | read   | Read source files  |

## Notes

- **`gofmt -l` exits 0 whether or not it found anything**, naming the files it would rewrite on stdout. The emptiness of that output is the result, so this workflow tests the output rather than the status — a step that forwarded gofmt's exit code would pass unconditionally and look exactly like a clean tree.
- **golangci-lint is opt-in by configuration.** Empty `GOLANGCI_LINT` runs it when a `.golangci.yml`, `.yaml`, `.toml` or `.json` is present: enabling it by default would hold every caller to a linter they never chose, and defaulting it off would ignore a configuration file somebody wrote on purpose. An explicit `"true"` or `"false"` wins over the file in both directions.
- **The vet passes share one job** rather than a matrix. Vet is seconds, and a matrix would pay for a checkout and a toolchain per pass to parallelise something shorter than its own setup. A finding in any pass fails the step; a later clean pass cannot clear an earlier one.
- **The Go version comes from `go.mod`** unless `GO_VERSION` says otherwise.
- **The golangci-lint action's own cache is disabled**, because `setup-go` has already restored one and the two disagree about what is current often enough to be worth having only one.

## Usage

### Basic

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-go.yml@v0
    permissions:
      contents: read
```

### Narrowing the formatting check

Worth doing where a repository holds other modules that are formatted on their own — plugins, examples, generated trees.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-go.yml@v0
    permissions:
      contents: read
    with:
      FORMAT_PATHS: "./builtin ./cmd ./internal ./pkg"
```

### Vetting under a build tag

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-go.yml@v0
    permissions:
      contents: read
    with:
      BUILD_TAGS: '["", "ai"]'
```

### With golangci-lint

Nothing needs saying when a `.golangci.yml` is committed — it is picked up. Pass the input to run it without one, or to keep it off in a repository that has one.

```yaml
jobs:
  lint:
    uses: this-is-tobi/github-workflows/.github/workflows/lint-go.yml@v0
    permissions:
      contents: read
    with:
      GOLANGCI_LINT: "true"
      GOLANGCI_LINT_ARGS: "--timeout 5m"
```
