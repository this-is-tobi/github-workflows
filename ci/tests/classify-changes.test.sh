#!/usr/bin/env bash
# classify-changes.yml - 'Classify the pull request's changed files'
#
# Its answer decides which gates run at all, so the failure worth guarding is
# not a gate that ran for nothing but one that should have run and was told
# not to: every case below that expects `true` is guarding a skip. The other
# half is the input nobody controls but the pull request's author — file names —
# which must never be executed, never reach the log as workflow commands, and
# never split one output into two.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BLOCK=$(extract_run classify-changes.yml classify "Classify the pull request's changed files")

# The API's entries for these paths, each an ordinary change. Every path is one
# argument and nothing inside it is read as syntax: the awkward names below
# carry `=`, quotes and newlines, and a fixture that parsed any of them would
# test a pull request nobody opened.
files_json() {
  local path out="[" first=1
  for path in "$@"; do
    [ "$first" -eq 1 ] || out+=","
    first=0
    out+=$(jq -cn --arg f "$path" '{filename: $f, status: "modified"}')
  done
  printf '%s]' "$out"
}

# A pull request moving one file, from the second path to the first.
pull_request_renaming() {
  pull_request
  STUB_GH_PR_FILES_JSON=$(jq -cn --arg f "$1" --arg p "$2" \
    '[{filename: $f, previous_filename: $p, status: "renamed"}]')
  export STUB_GH_PR_FILES_JSON CHANGED_FILES=1
}

# A pull request changing these paths, classified with the workflow's defaults.
pull_request() {
  STUB_GH_PR_FILES_JSON=$(files_json "$@")
  export STUB_GH_PR_FILES_JSON
  export CHANGED_FILES="$#"
  export GH_TOKEN="gh-token" REPOSITORY="acme/app" PR_NUMBER="7"
  export PROSE_PATTERNS='["docs/*", "*.md", "LICENSE", "NOTICE", ".release-please-manifest.json"]'
  export GROUPS_JSON='{}' MODULE_ROOT=""
}

output() {
  grep "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-
}

assert_output() {
  local got
  got=$(output "$1")
  if [ "$got" != "$2" ]; then
    printf 'FAIL: output %s is %q, want %q\n---- output ----\n%s\n----------------\n' \
      "$1" "$got" "$2" "$RUN_OUTPUT" >&2
    exit 1
  fi
}

# Whatever the paths, `code` is exactly "a module or something shared
# changed". A consumer reading `modules` and `shared` must never be told less
# than one reading `code`.
assert_code_is_modules_or_shared() {
  local code modules shared
  code=$(output code)
  modules=$(output modules)
  shared=$(output shared)
  if [ "$code" = "true" ] && [ "$modules" = "[]" ] && [ "$shared" != "true" ]; then
    printf 'FAIL: code is true, and neither a module nor a shared file is reported\n' >&2
    exit 1
  fi
  if [ "$code" = "false" ] && { [ "$modules" != "[]" ] || [ "$shared" != "false" ]; }; then
    printf 'FAIL: code is false, and modules=%s shared=%s widen the check anyway\n' \
      "$modules" "$shared" >&2
    exit 1
  fi
}

test_a_pull_request_of_prose_only_is_not_code() {
  pull_request docs/10-intro.md README.md LICENSE NOTICE .release-please-manifest.json docs/img/a.png
  run_block "$BLOCK"
  assert_status 0
  assert_output code false
  assert_output shared false
  assert_output modules "[]"
  assert_code_is_modules_or_shared
}

test_one_code_file_among_prose_makes_it_code() {
  pull_request docs/10-intro.md README.md internal/app/app.go
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_code_is_modules_or_shared
}

# The rule the whole workflow leans on: nobody listed this path, so it runs
# everything rather than nothing.
test_a_path_nobody_anticipated_counts_as_code() {
  pull_request .tool-versions
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
}

# main.go moved to docs/main.go reads as documentation by its new name alone,
# and it is a Go file gone from the build.
test_a_file_moved_into_prose_counts_by_the_name_it_left() {
  pull_request_renaming docs/main.go main.go
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
}

test_a_file_moved_between_prose_paths_stays_prose() {
  pull_request_renaming docs/new.md docs/old.md
  run_block "$BLOCK"
  assert_status 0
  assert_output code false
}

test_every_declared_group_is_reported_true_or_false() {
  pull_request charts/app/values.yaml
  export GROUPS_JSON='{"chart": ["charts/*", ".github/ct.yaml"], "full-image": ["Dockerfile.full"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output groups '{"chart":true,"full-image":false}'
}

# A chart's README is generated from its values, so a *.md under charts/ is
# prose to one pipeline and the very file another one checks. Groups are
# matched on every file, prose or not, so both answers can be given at once.
test_a_group_matches_a_file_the_prose_patterns_also_match() {
  pull_request charts/app/README.md
  export GROUPS_JSON='{"chart": ["charts/*"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output code false
  assert_output groups '{"chart":true}'
}

test_no_groups_reports_an_empty_object() {
  pull_request main.go
  run_block "$BLOCK"
  assert_status 0
  assert_output groups '{}'
}

test_the_prose_patterns_are_the_callers_to_set() {
  pull_request charts/app/values.yaml
  export PROSE_PATTERNS='["charts/*"]'
  run_block "$BLOCK"
  assert_status 0
  assert_output code false
}

test_the_modules_a_change_touches_are_named_and_nothing_is_shared() {
  pull_request plugins/s3/object.go plugins/s3/object_test.go plugins/pg/dump.go
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_output modules '["pg","s3"]'
  assert_output shared false
  assert_code_is_modules_or_shared
}

test_a_code_file_outside_every_module_is_shared() {
  pull_request plugins/s3/object.go .rta-version
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules '["s3"]'
  assert_output shared true
}

test_a_file_in_the_module_root_itself_belongs_to_no_module() {
  pull_request plugins/go.work.example
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules "[]"
  assert_output shared true
}

# A changelog beside one module's code must not add a second module to check,
# and prose at the root must not turn a narrow check into a full one.
test_prose_widens_neither_the_modules_nor_the_shared_set() {
  pull_request plugins/s3/object.go plugins/pg/CHANGELOG.md CHANGELOG.md
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules '["s3"]'
  assert_output shared false
}

test_a_module_moved_away_from_counts_as_touched() {
  pull_request_renaming plugins/kube/list.go plugins/pg/list.go
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules '["kube","pg"]'
}

test_the_module_root_is_the_same_directory_however_it_is_spelled() {
  local root
  for root in plugins plugins/ ./plugins ./plugins/; do
    : >"$GITHUB_OUTPUT"
    pull_request plugins/s3/object.go plugins-old/x.go
    export MODULE_ROOT="$root"
    run_block "$BLOCK"
    assert_status 0 "MODULE_ROOT=$root"
    assert_output modules '["s3"]'
    # plugins-old/ shares a prefix with plugins and is not inside it.
    assert_output shared true
  done
}

test_a_nested_module_root_works() {
  pull_request go/plugins/s3/a.go go/b.go
  export MODULE_ROOT="go/plugins"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules '["s3"]'
  assert_output shared true
}

# A root that could never prefix an API path would report every module file as
# shared, which looks exactly like a working configuration.
test_a_module_root_that_can_match_nothing_is_refused() {
  local root
  for root in /plugins . ./ ../plugins plugins/../x "plugins//x"; do
    pull_request plugins/s3/object.go
    export MODULE_ROOT="$root"
    run_block "$BLOCK"
    assert_status 1 "MODULE_ROOT=$root"
    assert_output_contains "MODULE_ROOT must name a directory relative to the repository root"
  done
}

test_no_module_root_makes_every_code_change_shared() {
  pull_request plugins/s3/object.go
  run_block "$BLOCK"
  assert_status 0
  assert_output modules "[]"
  assert_output shared true
}

# Outside a pull request there is no file list, and the answer that cannot skip
# a gate is "everything".
test_off_a_pull_request_everything_counts_as_changed() {
  pull_request docs/a.md
  export PR_NUMBER="" CHANGED_FILES=""
  export GROUPS_JSON='{"chart": ["charts/*"], "full-image": ["Dockerfile.full"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_output shared true
  assert_output modules "[]"
  assert_output groups '{"chart":true,"full-image":true}'
  assert_output_contains "not for a pull request"
  assert_not_called "gh|"
}

# The endpoint stops at 3000 files without saying so. What it left out could be
# the one file that matters.
test_a_listing_shorter_than_the_pull_request_is_not_classified() {
  pull_request docs/a.md docs/b.md
  export CHANGED_FILES="3001"
  export GROUPS_JSON='{"chart": ["charts/*"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_output shared true
  assert_output groups '{"chart":true}'
  assert_output_contains "changes 3001 files and the API listed 2"
}

test_every_page_of_the_listing_is_read() {
  pull_request
  STUB_GH_PR_FILES_JSON="$(files_json docs/a.md)$(files_json plugins/pg/a.go)"
  export STUB_GH_PR_FILES_JSON CHANGED_FILES=2 MODULE_ROOT="plugins"
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_output modules '["pg"]'
  assert_called "api repos/acme/app/pulls/7/files?per_page=100 --paginate"
}

# The count is what tells a complete listing from a truncated one, so an event
# that does not carry it cannot have its listing trusted either.
test_a_pull_request_event_without_a_count_is_not_classified() {
  pull_request docs/a.md
  export CHANGED_FILES=""
  export GROUPS_JSON='{"chart": ["charts/*"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output code true
  assert_output shared true
  assert_output groups '{"chart":true}'
  assert_output_contains "cannot be checked for completeness"
  assert_not_called "gh|"
}

# Classifying an empty list would report that nothing changed, and skip every
# gate behind it.
test_a_failed_api_call_fails_rather_than_reporting_no_changes() {
  pull_request main.go
  export STUB_GH_FAIL_ON="/pulls/7/files"
  run_block "$BLOCK"
  assert_status 1
  if grep -q '^code=' "$GITHUB_OUTPUT"; then
    printf 'FAIL: an output was written after the API call failed\n' >&2
    exit 1
  fi
}

# The same failure one step later. The listing is read through a process
# substitution, whose exit status bash drops: a jq that died after the first
# file would end the loop early, and the files it never handed over — main.go
# here — would be reported as unchanged. `wait $!` after the loop is what
# fails the step instead, and it reads like a line nobody needs.
test_a_jq_that_dies_partway_through_the_listing_fails_rather_than_classifying_less() {
  REAL_JQ=$(command -v jq)
  export REAL_JQ
  # The real jq, except for the pass that walks the listing file by file (the
  # one defining module_name): that one hands over its first file's three
  # fields and dies.
  cat >"$SANDBOX/bin/jq" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == *module_name* ]]; then
    "$REAL_JQ" "$@" | {
      for _ in 1 2 3; do IFS= read -r -d '' field && printf '%s\0' "$field"; done
    }
    exit 1
  fi
done
exec "$REAL_JQ" "$@"
STUB
  chmod +x "$SANDBOX/bin/jq"
  pull_request docs/a.md main.go
  run_block "$BLOCK"
  assert_status 1
  assert_output_contains '"docs/a.md"'
  if grep -q '^code=' "$GITHUB_OUTPUT"; then
    printf 'FAIL: an output was written from a listing read short\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

test_the_patterns_must_be_a_json_array_of_strings() {
  local bad
  for bad in 'docs/*' '{"docs": 1}' '[1, 2]'; do
    pull_request main.go
    export PROSE_PATTERNS="$bad"
    run_block "$BLOCK"
    assert_status 1 "PROSE_PATTERNS=$bad"
    assert_output_contains "PROSE_PATTERNS is not a JSON array of strings"
  done
}

test_the_groups_must_be_a_json_object_of_string_arrays() {
  local bad
  for bad in '["charts/*"]' '{"chart": "charts/*"}' '{"chart": [1]}'; do
    pull_request main.go
    export GROUPS_JSON="$bad"
    run_block "$BLOCK"
    assert_status 1 "GROUPS=$bad"
    assert_output_contains "GROUPS is not a JSON object of string arrays"
  done
}

# bash keeps GROUPS for the user's group IDs and ignores an inherited value, so
# the input travels under another name. Were it renamed back, the script would
# read numbers, fail the JSON check above, and every caller would break.
test_the_groups_do_not_travel_under_the_name_bash_reserves() {
  if yq '.jobs.classify.steps[0].env | has("GROUPS")' \
    "$WORKFLOWS_DIR/classify-changes.yml" | grep -q true; then
    printf 'FAIL: the step passes GROUPS through the environment, which bash ignores\n' >&2
    exit 1
  fi
}

# **File names are the pull request author's to choose.** Spaces, quotes, a
# newline, a command substitution: each is one path, classified as one path,
# and none of it runs.
test_awkward_file_names_are_classified_and_never_executed() {
  local nl=$'\n'
  pull_request "docs/with space.md" "docs/it's \"quoted\".md" "docs/new${nl}line.md" \
    "docs/\$(touch $SANDBOX/pwned).md" "docs/\`touch $SANDBOX/pwned\`.md"
  run_block "$BLOCK"
  assert_status 0
  assert_output code false
  if [ -e "$SANDBOX/pwned" ]; then
    printf 'FAIL: a file name was executed\n' >&2
    exit 1
  fi
}

test_a_newline_in_a_file_name_does_not_hide_a_code_file() {
  local nl=$'\n'
  pull_request "docs/a.md${nl}main.go"
  run_block "$BLOCK"
  assert_status 0
  # One path, under docs/, whatever it contains after the newline.
  assert_output code false
}

# A module's name is a path segment, so it is as untrusted as the path. It
# must arrive as one JSON string on one line of GITHUB_OUTPUT: a raw newline
# would start a second `key=value` the author wrote.
test_an_awkward_module_name_stays_one_json_string_on_one_line() {
  local nl=$'\n'
  pull_request "plugins/a${nl}shared=false${nl}x/main.go" "plugins/it's/main.go"
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_call_count "gh|" 1
  if [ "$(grep -c '^modules=' "$GITHUB_OUTPUT")" -ne 1 ] || [ "$(grep -c '^shared=' "$GITHUB_OUTPUT")" -ne 1 ]; then
    printf 'FAIL: a module name split the outputs\n---- GITHUB_OUTPUT ----\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
  local modules
  modules=$(output modules)
  if [ "$(jq -r 'length' <<<"$modules")" != "2" ] ||
    [ "$(jq -r '.[0]' <<<"$modules")" != "a${nl}shared=false${nl}x" ] ||
    [ "$(jq -r '.[1]' <<<"$modules")" != "it's" ]; then
    printf 'FAIL: modules is %s\n' "$modules" >&2
    exit 1
  fi
}

# A directory name is the author's, and one spelled like a jq option is still a
# name. Handed to jq as an argument, `--indent 3` is an instruction, and spreads
# the output over several lines of GITHUB_OUTPUT.
test_a_module_named_like_an_option_stays_a_name() {
  pull_request "plugins/--indent/main.go" "plugins/3/main.go" "plugins/-e/main.go" \
    "plugins/--rawfile/main.go"
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0
  assert_output modules '["--indent","--rawfile","-e","3"]'
  if [ "$(wc -l <"$GITHUB_OUTPUT" | tr -d ' ')" -ne 4 ]; then
    printf 'FAIL: the outputs are not four lines\n---- GITHUB_OUTPUT ----\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

# Groups are told apart by position, so no name can be mistaken for "no group
# matched yet" — the empty one included.
test_a_group_with_an_empty_name_is_matched_like_any_other() {
  pull_request main.go
  export GROUPS_JSON='{"": ["*.go"], "chart": ["charts/*"]}'
  run_block "$BLOCK"
  assert_status 0
  assert_output groups '{"":true,"chart":false}'
}

# The runner acts on `##[...]` anywhere in a line and on `::...` at the start of
# one, and both are valid in a path. Every name is printed JSON-encoded between
# stop-commands markers, so the runner reads none of it as a command.
test_file_names_reach_the_log_only_while_commands_are_stopped() {
  local nl=$'\n'
  pull_request "docs/##[set-output name=code;]false.md" "docs/x${nl}::error::forged.md" main.go
  export MODULE_ROOT="plugins/"
  run_block "$BLOCK"
  assert_status 0

  local stop token resume
  stop=$(grep -n '^::stop-commands::' <<<"$RUN_OUTPUT" | head -1)
  token=${stop#*::stop-commands::}
  if [ -z "$stop" ] || [ "${#token}" -lt 32 ]; then
    printf 'FAIL: no stop-commands marker with a random token\n%s\n' "$RUN_OUTPUT" >&2
    exit 1
  fi
  resume=$(grep -n "^::${token}::\$" <<<"$RUN_OUTPUT" | head -1)
  if [ -z "$resume" ]; then
    printf 'FAIL: commands are never resumed\n%s\n' "$RUN_OUTPUT" >&2
    exit 1
  fi

  local stop_line=${stop%%:*} resume_line=${resume%%:*} line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    if [[ "$line" == *'##['* || "$line" == *'error::forged'* ]]; then
      if [ "$n" -le "$stop_line" ] || [ "$n" -ge "$resume_line" ]; then
        printf 'FAIL: line %d carries a file name outside the stopped region: %s\n' "$n" "$line" >&2
        exit 1
      fi
    fi
    # No line of the report may start a v2 command of the author's making.
    if [[ "$line" == ::error::* ]]; then
      printf 'FAIL: a file name started a line of its own: %s\n' "$line" >&2
      exit 1
    fi
  done <<<"$RUN_OUTPUT"
  assert_output_contains '"docs/x\n::error::forged.md"'
}

test_each_run_stops_commands_with_a_different_token() {
  pull_request main.go
  run_block "$BLOCK"
  local first second
  first=$(grep '^::stop-commands::' <<<"$RUN_OUTPUT")
  : >"$GITHUB_OUTPUT"
  run_block "$BLOCK"
  second=$(grep '^::stop-commands::' <<<"$RUN_OUTPUT")
  if [ "$first" = "$second" ]; then
    printf 'FAIL: two runs used the same token: %s\n' "$first" >&2
    exit 1
  fi
}

test_each_file_is_reported_with_its_kind_and_groups() {
  pull_request charts/app/README.md main.go
  export GROUPS_JSON='{"chart": ["charts/*", "*.md"], "go": ["*.go"]}'
  run_block "$BLOCK"
  assert_status 0
  # Matched by both of the chart group's patterns, and named once.
  assert_output_contains '  prose "charts/app/README.md"  [chart]'
  assert_output_contains '  code  "main.go"  [go]'
}

run_tests
