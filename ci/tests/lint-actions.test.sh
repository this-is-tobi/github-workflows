#!/usr/bin/env bash
# lint-actions.yml - what the workflow assembles around actionlint: the
# arguments it is handed, the pin of its image, and the problem matcher that
# turns its findings into annotations. actionlint itself is not run.
#
# CONFIG_FILE reaches actionlint as a single word of a `docker://` step's
# `args`, which the runner splits on whitespace; a path that would split, or
# that does not exist, has to stop the run. Running without a config file the
# caller asked for would report the very errors it exists to silence (an unknown
# runner label, say) and point away from the real cause.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="lint-actions.yml"
JOB="lint-actions"

run_args() { run_block "$(extract_run "$WORKFLOW" "$JOB" 'Prepare the actionlint arguments')"; }
run_matcher() { run_block "$(extract_run "$WORKFLOW" "$JOB" 'Register the problem matcher')"; }

# The steps read the caller's files relative to the working directory.
in_workspace() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

step_field() {
  yq ".jobs.\"$JOB\".steps[] | select(.name == \"$1\") | $2" "$WORKFLOWS_DIR/$WORKFLOW"
}

assert_args() {
  local actual
  # An empty value still has to be written: the next step reads it.
  if ! grep -q '^args=' "$GITHUB_OUTPUT"; then
    printf 'FAIL: the step wrote no args output\n' >&2
    exit 1
  fi
  actual=$(sed -n 's/^args=//p' "$GITHUB_OUTPUT")
  if [ "$actual" != "$1" ]; then
    printf 'FAIL: expected args %q, got %q\n---- output ----\n%s\n----------------\n' \
      "$1" "$actual" "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

assert_equals() {
  if [ "$1" != "$2" ]; then
    printf 'FAIL: expected %q, got %q\n' "$1" "$2" >&2
    exit 1
  fi
}

# --- the arguments -----------------------------------------------------------

test_runs_without_arguments_when_no_config_file_is_given() {
  in_workspace
  export CONFIG_FILE=""

  run_args

  assert_status 0
  # actionlint finds .github/actionlint.yaml by itself.
  assert_args ""
}

test_hands_the_config_file_to_actionlint() {
  in_workspace
  mkdir -p ci && : >ci/actionlint.yaml
  export CONFIG_FILE="ci/actionlint.yaml"

  run_args

  assert_status 0
  assert_args "-config-file ci/actionlint.yaml"
}

test_stops_on_a_config_file_that_does_not_exist() {
  in_workspace
  export CONFIG_FILE="ci/actionlint.yaml"

  run_args

  assert_status 1
  assert_output_contains "CONFIG_FILE 'ci/actionlint.yaml' does not exist"
}

test_refuses_a_config_file_path_that_would_be_split() {
  in_workspace
  mkdir -p "my ci" && : >"my ci/actionlint.yaml"
  export CONFIG_FILE="my ci/actionlint.yaml"

  run_args

  assert_status 1
  assert_output_contains "whitespace"
}

# --- the wiring ----------------------------------------------------------------

# A tag can be repointed and a digest cannot: the image runs with the job's
# token in reach of the checkout, and a linter that changes under the caller's
# feet turns a green run red overnight.
test_pins_the_actionlint_image_by_digest() {
  local ref
  ref=$(step_field "Run actionlint" ".uses")

  if [[ ! "$ref" =~ ^docker://rhysd/actionlint@sha256:[0-9a-f]{64}$ ]]; then
    printf 'FAIL: expected the actionlint image to be pinned by digest, got %q\n' "$ref" >&2
    exit 1
  fi
}

# The step can assemble the right arguments while the workflow never hands them
# on, and every test above would still pass.
test_hands_the_prepared_arguments_to_actionlint() {
  local args
  args=$(step_field "Run actionlint" ".with.args")

  # shellcheck disable=SC2016 # the Actions marker is meant to stay literal
  if [ "$args" != '${{ steps.args.outputs.args }}' ]; then
    printf 'FAIL: expected the prepared arguments to reach actionlint, got %q\n' "$args" >&2
    exit 1
  fi
  assert_equals "args" "$(step_field "Prepare the actionlint arguments" ".id")"
}

# --- the annotations -----------------------------------------------------------

# Findings as actionlint 1.7.12 prints them, captured from a real run. The
# first holds `:1:30:` of its own, which a greedy file group would swallow.
FINDING_SHELLCHECK='.github/workflows/ci.yml:7:7: shellcheck reported issue in this script: SC2086:info:1:30: Double quote to prevent globbing and word splitting [shellcheck]'
FINDING_SYNTAX='.github/workflows/ci.yml:2:1: unexpected key "foo" for "workflow" section. expected one of "concurrency", "defaults", "env", "jobs", "name", "on", "permissions", "run-name" [syntax-check]'

# file, line, column, message, code - tab separated, as the matcher reads them.
matched() {
  jq -rn --arg line "$1" --arg re "$(jq -r '.problemMatcher[0].pattern[0].regexp' "$RUNNER_TEMP/actionlint-matcher.json")" \
    '$line | match($re).captures | map(.string) | @tsv'
}

test_registers_the_problem_matcher() {
  export RUNNER_TEMP="$SANDBOX/runner-temp"
  mkdir -p "$RUNNER_TEMP"

  run_matcher

  assert_status 0
  assert_output_contains "::add-matcher::$RUNNER_TEMP/actionlint-matcher.json"
  jq -e '.problemMatcher[0].owner == "actionlint"' "$RUNNER_TEMP/actionlint-matcher.json" >/dev/null
}

test_the_problem_matcher_reads_a_finding_with_colons_in_its_message() {
  export RUNNER_TEMP="$SANDBOX/runner-temp"
  mkdir -p "$RUNNER_TEMP"
  run_matcher

  assert_equals \
    $'.github/workflows/ci.yml\t7\t7\tshellcheck reported issue in this script: SC2086:info:1:30: Double quote to prevent globbing and word splitting\tshellcheck' \
    "$(matched "$FINDING_SHELLCHECK")"
}

test_the_problem_matcher_reads_a_finding_with_quotes_and_commas_in_its_message() {
  export RUNNER_TEMP="$SANDBOX/runner-temp"
  mkdir -p "$RUNNER_TEMP"
  run_matcher

  assert_equals \
    $'.github/workflows/ci.yml\t2\t1\tunexpected key "foo" for "workflow" section. expected one of "concurrency", "defaults", "env", "jobs", "name", "on", "permissions", "run-name"\tsyntax-check' \
    "$(matched "$FINDING_SYNTAX")"
}

run_tests
