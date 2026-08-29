# `test-go.yml`

Runs a Go module's test suite, across an optional operating-system matrix and an optional set of build tags. Detects the module and its test files first, and reports rather than passes when either is missing.

The defaults are the flags that make a green run mean something: `-count=1` (so the result cache cannot answer for a suite that never ran), `-race`, and `-shuffle=on`. Each can be turned off; none is off by default.

## Inputs

| Input                  | Type    | Description                                                                                        | Required | Default             |
| ---------------------- | ------- | -------------------------------------------------------------------------------------------------- | -------- | ------------------- |
| GO_VERSION             | string  | Go version to use. Empty reads it from `go.mod`                                                    | No       | ""                  |
| WORKING_DIRECTORY      | string  | Working directory for the module under test                                                        | No       | "."                 |
| PACKAGES               | string  | Package pattern to test                                                                            | No       | "./..."             |
| BUILD_TAGS             | string  | Build tag sets as a JSON array of strings; one pass each, `""` meaning no tags                     | No       | '[""]'              |
| RUNNERS                | string  | Runner label sets to test across, as a JSON array of JSON arrays. Empty uses `RUNS_ON` alone       | No       | ""                  |
| RUNS_ON                | string  | Runner labels as JSON array                                                                        | No       | '["ubuntu-24.04"]'  |
| RACE                   | boolean | Whether to run with the race detector                                                              | No       | true                |
| SHUFFLE                | boolean | Whether to randomise test order                                                                    | No       | true                |
| COUNT                  | string  | Value for `-count`. "1" disables the test result cache                                             | No       | "1"                 |
| TIMEOUT                | string  | Value for `-timeout`                                                                               | No       | "10m"               |
| TEST_COMMAND           | string  | Custom command, replacing the assembled `go test` invocation entirely                              | No       | ""                  |
| TEST_PRECOMMAND        | string  | Command to run before the tests                                                                    | No       | ""                  |
| COVERAGE               | boolean | Whether to collect coverage                                                                        | No       | false               |
| COVERAGE_PACKAGES      | string  | Value for `-coverpkg`                                                                              | No       | ""                  |
| COVERAGE_ARTIFACT_NAME | string  | Artifact name for the coverage profile                                                             | No       | go-tests-coverage   |
| COVERAGE_ARTIFACT_PATH | string  | Path of the coverage profile                                                                       | No       | ./coverage.out      |
| CACHE                  | boolean | Whether to cache the module and build caches                                                       | No       | true                |
| FAIL_ON_ERROR          | boolean | Whether to fail the workflow on test failures                                                      | No       | true                |

## Permissions

| Scope    | Access | Description                 |
| -------- | ------ | --------------------------- |
| contents | read   | Read source files for tests |

## Notes

- **The Go version comes from `go.mod` by default.** The module already declares the version it is meant to build with, and a default pinned in this workflow would silently disagree with it. `GO_VERSION` overrides.
- **Two silent negatives are detected rather than assumed.** `go test ./...` over a module with no `_test.go` files exits 0 without testing anything, and a `WORKING_DIRECTORY` pointing somewhere without a `go.mod` fails in a way that reads like a toolchain problem. Both get their own job saying so. Test files under `vendor/` do not count — a dependency's tests are not this module's.
- **`BUILD_TAGS` is a list because a build tag produces a second binary.** A change that compiles under one tag set and not another is exactly what a tagged tree makes easy to miss, so `'["", "ai"]'` runs the suite both ways.
- **`RUNNERS` keeps `RUNS_ON`'s meaning.** `RUNS_ON` is the label set for one runner, as everywhere else in this repository; `RUNNERS` is a list of such label sets. Leaving `RUNNERS` empty wraps `RUNS_ON` into a one-entry matrix, so both paths run through the same job rather than through two that drift.
- **`fail-fast` is off.** One operating system failing is a result about that operating system, and cancelling the others throws away the comparison that makes it readable.
- **The coverage profile is uploaded once**, from the first matrix entry: identical artifact names across a matrix collide, and the profiles are the same measurement taken on different machines.
- **`TEST_PRECOMMAND` runs in the test step's own shell**, so it can export a variable or change directory for the tests that follow. A pre-command calling `exit` directly therefore ends the step there, with its own status and without the workflow's own message — it still fails, just more quietly.

## Usage

### Basic

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
```

### Across two operating systems

A suite reads the machine it runs on — data directories, `$PATH`, `/etc` — and a bug in that isolation looks exactly like a passing test until somebody else's machine is different. A second operating system is what notices.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      RUNNERS: '[["ubuntu-24.04"], ["macos-15"]]'
```

### With a build tag

Runs the suite twice: once untagged, once with `-tags ai`.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      BUILD_TAGS: '["", "ai"]'
```

### With coverage

`COVERAGE_PACKAGES` is worth setting where most of a module is exercised from other packages' tests, which otherwise reads as untested when it is not.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      COVERAGE: true
      COVERAGE_PACKAGES: "./..."
```

### A Makefile instead of the assembled command

`TEST_COMMAND` replaces the `go test` invocation entirely, for a project whose gate already lives in a Makefile.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      TEST_COMMAND: "make hard"
      RUNNERS: '[["ubuntu-24.04"], ["macos-15"]]'
```

### A module in a subdirectory

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      WORKING_DIRECTORY: services/api
```

### Non-blocking tests

The job succeeds even when tests fail. Useful while a suite is being introduced into an existing project with known failures.

```yaml
jobs:
  test:
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read
    with:
      FAIL_ON_ERROR: false
```
