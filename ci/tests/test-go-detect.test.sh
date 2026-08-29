#!/usr/bin/env bash
# What test-go.yml decides before it runs anything: whether there is a module,
# whether there are tests, and what the matrix expands to.
#
# The two detections exist because both of their negatives are silent. `go test
# ./...` over a module with no _test.go files exits 0, and a WORKING_DIRECTORY
# pointing somewhere without a go.mod fails in a way that reads like a toolchain
# problem. A green run that tested nothing is the failure this guards.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="test-go.yml"

# The step runs in the module directory, so each test builds one.
in_module_dir() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

default_env() {
  export RUNNERS_INPUT="" RUNS_ON_INPUT='["ubuntu-24.04"]' BUILD_TAGS_INPUT='[""]'
}

run_detect() {
  run_block "$(extract_run "$WORKFLOW" detect-setup 'Detect module and resolve the matrix')"
}

test_a_module_with_tests_is_detected() {
  in_module_dir
  default_env
  printf 'module example.com/x\n' >go.mod
  printf 'package x\n' >x_test.go
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-module=true"
  assert_file_contains "$GITHUB_OUTPUT" "has-tests=true"
}

test_a_directory_with_no_module_is_reported() {
  in_module_dir
  default_env
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-module=false"
}

# The one that matters most: a module whose tests were never written, or whose
# test files were moved, reports it rather than passing.
test_a_module_without_test_files_is_reported() {
  in_module_dir
  default_env
  printf 'module example.com/x\n' >go.mod
  printf 'package x\n' >x.go
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-module=true"
  assert_file_contains "$GITHUB_OUTPUT" "has-tests=false"
}

# A vendored dependency's tests are not this module's tests, and counting them
# would make the check above always pass.
test_vendored_test_files_do_not_count() {
  in_module_dir
  default_env
  printf 'module example.com/x\n' >go.mod
  mkdir -p vendor/example.com/dep
  printf 'package dep\n' >vendor/example.com/dep/dep_test.go
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-tests=false"
}

test_an_absent_runners_input_wraps_runs_on_into_a_one_entry_matrix() {
  in_module_dir
  default_env
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" 'runners=[["ubuntu-24.04"]]'
}

test_an_explicit_runners_input_is_used_as_given() {
  in_module_dir
  default_env
  export RUNNERS_INPUT='[["ubuntu-24.04"],["macos-15"]]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" 'runners=[["ubuntu-24.04"],["macos-15"]]'
}

# Both matrix inputs reach a shell argument or a `runs-on`, so a malformed one
# is refused here with a message rather than inside the matrix expansion, where
# the failure names nothing a caller can act on.
test_a_malformed_runners_input_is_refused_with_a_message() {
  in_module_dir
  default_env
  export RUNNERS_INPUT='not json'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 1
  assert_output_contains "RUNNERS must be a non-empty JSON array"
}

test_an_empty_runners_array_is_refused() {
  in_module_dir
  default_env
  export RUNNERS_INPUT='[]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 1
  assert_output_contains "RUNNERS must be a non-empty JSON array"
}

test_build_tags_must_be_a_list_of_strings() {
  in_module_dir
  default_env
  export BUILD_TAGS_INPUT='[{"tags":"ai"}]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 1
  assert_output_contains "BUILD_TAGS must be a non-empty JSON array of strings"
}

test_the_default_tag_set_is_one_untagged_pass() {
  in_module_dir
  default_env
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" 'tags=[""]'
}

test_several_tag_sets_are_passed_through() {
  in_module_dir
  default_env
  export BUILD_TAGS_INPUT='["", "ai"]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" 'tags=["", "ai"]'
}

run_tests
