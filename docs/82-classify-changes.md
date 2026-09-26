# `classify-changes.yml`

Classify a pull request's changed files so a pipeline runs the gates a change can affect and skips the ones it cannot — with one API call and a pattern match, and no third-party filter action.

## Inputs

| Input          | Type   | Description                                                                                                              | Required | Default                                                                      |
| -------------- | ------ | ------------------------------------------------------------------------------------------------------------------------ | -------- | ---------------------------------------------------------------------------- |
| PROSE_PATTERNS | string | JSON array of shell patterns for the files no gate behind `code` reads. A file none of them matches is code              | No       | `'["docs/*", "*.md", "LICENSE", "NOTICE", ".release-please-manifest.json"]'` |
| GROUPS         | string | JSON object of named pattern arrays, each reported true when any changed file matches (e.g. `'{"chart": ["charts/*"]}'`) | No       | `"{}"`                                                                       |
| MODULE_ROOT    | string | Directory whose subdirectories are separate modules (e.g. `plugins/`). Empty reports every code change as shared         | No       | `""`                                                                         |
| RUNS_ON        | string | Runner labels as JSON array                                                                                              | No       | `'["ubuntu-24.04"]'`                                                         |

## Outputs

| Output  | Description                                                                                                                     |
| ------- | ------------------------------------------------------------------------------------------------------------------------------- |
| code    | `'true'` when any changed file is outside `PROSE_PATTERNS`, `'false'` when every one is prose                                   |
| groups  | JSON object naming every group in `GROUPS`, each `true` or `false` (e.g. `{"chart":true}`). Read one with `fromJSON(...).chart` |
| modules | JSON array of the modules under `MODULE_ROOT` a code file changed in, sorted and without duplicates                             |
| shared  | `'true'` when a code file outside every module changed — every module then has to be checked, not only the ones in `modules`    |

`code` is true exactly when `modules` is non-empty or `shared` is true, so a pipeline reading the finer outputs is never told less than one reading `code`.

## Permissions

| Scope         | Access | Description                             |
| ------------- | ------ | --------------------------------------- |
| pull-requests | read   | List the files the pull request changes |

## Notes

- **Why no filter action.** A change-detection action runs on every pull request and its answer decides which gates run at all, which is exactly where a supply-chain attack pays best: `tj-actions/changed-files` was compromised in March 2025 and printed the secrets of every workflow running it into public logs. This is shell over `gh api` on the pull request's own file list, and checks nothing out.
- **Every doubt resolves toward running.** A path no pattern anticipated is code. A renamed file is classified by both its names, so `main.go` moved to `docs/main.go` is still a Go file gone from the build. An event that is not a pull request, one that does not carry the pull request's file count, and a listing shorter than that count (the endpoint stops at 3000 files without saying so) all report everything as changed. A failed API call fails the job.
- **Patterns** are bash patterns in which `*` also crosses `/`: `docs/*` is the whole tree under `docs/`, and `*.md` is every Markdown file at any depth. Decide what "prose" means for the gates behind `code` — a test that reads the docs makes them code for that test.
- **Groups match every file, prose or not.** A chart's README is prose to a Go pipeline and the very file its helm-docs check reads, so both answers can be given at once.
- **Modules.** With `MODULE_ROOT: plugins/`, a code file under `plugins/<name>/` touches the module `<name>`; a code file anywhere else — including one sitting in `plugins/` itself — is shared. Prose widens nothing: a changelog edited beside one module's code does not add a second module.
- **File names are the pull request author's to choose.** The classifier never executes one and prints each JSON-encoded between `stop-commands` markers, so a name spelling a workflow command is not read as one. The `modules` output is still made of names the author chose: pass it to a step through `env:`, never through `${{ }}` inside a `run:`, and compare each name with the modules the tree actually holds before acting on it. A gate that interpolates `toJson(needs)` into its script now carries those names too — use [Check Jobs](./81-check-jobs.md), which takes the context through `env:`.
- A skipped job is the ordinary answer under this workflow, so the check a ruleset requires has to count one as a pass: [Check Jobs](./81-check-jobs.md) does, by default.
- Uses `gh`, `jq` and bash 4.4 or later, all present on GitHub-hosted runners. A self-hosted runner named through `RUNS_ON` needs them installed.

## Examples

### Skip the build on a documentation-only pull request

```yaml
jobs:
  changes:
    uses: this-is-tobi/github-workflows/.github/workflows/classify-changes.yml@v0
    permissions:
      pull-requests: read

  test:
    needs: changes
    if: ${{ needs.changes.outputs.code == 'true' }}
    uses: this-is-tobi/github-workflows/.github/workflows/test-go.yml@v0
    permissions:
      contents: read

  all-jobs-passed:
    name: Check jobs status
    if: ${{ always() }}
    needs:
    - changes
    - test
    uses: this-is-tobi/github-workflows/.github/workflows/check-jobs.yml@v0
    with:
      NEEDS: ${{ toJson(needs) }}
```

### Gates of their own for part of the tree

`full-image` needs the bracket form in an expression; a name made of letters, digits and `_` reads either way.

```yaml
jobs:
  changes:
    uses: this-is-tobi/github-workflows/.github/workflows/classify-changes.yml@v0
    permissions:
      pull-requests: read
    with:
      GROUPS: '{"chart": ["charts/*", ".github/ct.yaml"], "full-image": ["Dockerfile.full"]}'

  test-chart:
    needs: changes
    if: ${{ fromJSON(needs.changes.outputs.groups).chart }}
    uses: this-is-tobi/github-workflows/.github/workflows/test-helm.yml@v0
    permissions:
      contents: read
    with:
      CT_CONF_PATH: .github/ct.yaml

  build-full-image:
    needs: changes
    if: ${{ fromJSON(needs.changes.outputs.groups)['full-image'] }}
    # ...
```

### Check only the modules a pull request touches

```yaml
jobs:
  changes:
    uses: this-is-tobi/github-workflows/.github/workflows/classify-changes.yml@v0
    permissions:
      pull-requests: read
    with:
      MODULE_ROOT: plugins/

  test:
    needs: changes
    if: ${{ needs.changes.outputs.code == 'true' }}
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      with:
        persist-credentials: false

    - name: Test the modules the pull request touched
      env:
        MODULES: ${{ needs.changes.outputs.modules }}
        SHARED: ${{ needs.changes.outputs.shared }}
      run: |
        set -euo pipefail
        ALL=$(find plugins -mindepth 2 -maxdepth 2 -name go.mod | cut -d/ -f2 | jq -Rsc 'split("\n") | map(select(. != ""))')
        # A shared file, or a touched name that is not a module in this tree
        # (one the pull request deletes, say), checks every module.
        jq -j --argjson all "$ALL" --arg shared "$SHARED" \
          'if $shared == "true" or (. - $all) != [] then $all else . end | .[] | (., ([0] | implode))' <<<"$MODULES" |
          while IFS= read -r -d '' MODULE; do
            (cd "plugins/$MODULE" && go test ./...)
          done
```
