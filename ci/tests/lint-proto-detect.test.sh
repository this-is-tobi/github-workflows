#!/usr/bin/env bash
# What lint-proto.yml decides before it runs anything: whether there is a buf
# configuration, and what the breaking check compares against.
#
# The second is the one worth testing. A comparison target that does not resolve
# fails inside buf with `exit status 128` and names nothing, and a target that
# resolves to the branch under test passes without having compared anything.
# Both are silent, and both are decided here.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="lint-proto.yml"

# The step runs at the repository root, so each test builds one.
in_repo() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

with_config_in() {
  mkdir -p "$SANDBOX/work/$1"
  printf 'version: v2\n' >"$SANDBOX/work/$1/buf.yaml"
}

default_env() {
  export WORKING_DIRECTORY="." BREAKING="true" BREAKING_AGAINST="" BREAKING_BRANCH=""
  export BASE_REF="main" DEFAULT_BRANCH="main" CURRENT_REF="feature/x"
}

run_detect() {
  run_block "$(extract_run "$WORKFLOW" detect-setup 'Detect buf configuration and resolve the comparison target')"
}

target_of() {
  grep '^breaking-against=' "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-
}

test_a_buf_config_is_detected() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-config=true"
}

test_a_directory_with_no_config_is_reported() {
  in_repo
  default_env
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-config=false"
}

test_a_config_in_a_subdirectory_is_found_where_it_was_pointed() {
  in_repo
  default_env
  export WORKING_DIRECTORY="proto"
  with_config_in proto
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-config=true"
}

# **The one that would otherwise only fail in CI.** A checkout leaves the base
# branch as a remote-tracking ref and no local branch of that name, so buf's
# `branch=main` form clones the local repository looking for a branch that is
# not there and exits 128 without naming a cause. `branch=origin/main` resolves.
# Verified against buf 1.47 before this was written.
test_the_comparison_target_names_the_remote_tracking_ref() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  run_detect
  assert_status 0

  local target
  target=$(target_of)
  if [[ "$target" != *"branch=origin/main"* ]]; then
    printf 'FAIL: target is %q, want it to name origin/main\n' "$target" >&2
    exit 1
  fi
}

test_a_module_at_the_root_carries_no_subdir() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  run_detect
  assert_status 0
  if [[ "$(target_of)" == *"subdir"* ]]; then
    printf 'FAIL: a root module got a subdir: %q\n' "$(target_of)" >&2
    exit 1
  fi
}

test_a_module_in_a_subdirectory_carries_a_subdir() {
  in_repo
  default_env
  export WORKING_DIRECTORY="proto"
  with_config_in proto
  run_detect
  assert_status 0
  if [[ "$(target_of)" != *"subdir=proto"* ]]; then
    printf 'FAIL: target is %q, want subdir=proto\n' "$(target_of)" >&2
    exit 1
  fi
}

# A caller comparing against a registry module or a tag has a shape this cannot
# derive, so an explicit value is passed through rather than adjusted.
test_an_explicit_target_is_passed_through_untouched() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export BREAKING_AGAINST="buf.build/acme/petapis:v1"
  run_detect
  assert_status 0
  if [ "$(target_of)" != "buf.build/acme/petapis:v1" ]; then
    printf 'FAIL: explicit target was rewritten to %q\n' "$(target_of)" >&2
    exit 1
  fi
}

test_the_branch_input_wins_over_the_pull_requests_base() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export BREAKING_BRANCH="release/v1" BASE_REF="main"
  run_detect
  assert_status 0
  if [[ "$(target_of)" != *"branch=origin/release/v1"* ]]; then
    printf 'FAIL: BREAKING_BRANCH was ignored: %q\n' "$(target_of)" >&2
    exit 1
  fi
}

# Outside a pull request there is no base_ref, and the repository default is
# what the comparison means.
test_the_default_branch_is_used_off_a_pull_request() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export BASE_REF="" DEFAULT_BRANCH="trunk"
  run_detect
  assert_status 0
  if [[ "$(target_of)" != *"branch=origin/trunk"* ]]; then
    printf 'FAIL: the default branch was not used: %q\n' "$(target_of)" >&2
    exit 1
  fi
}

test_no_base_at_all_is_refused() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export BASE_REF="" DEFAULT_BRANCH="" BREAKING_BRANCH=""
  run_detect
  assert_status 1
  assert_output_contains "Cannot work out what to compare against"
}

# buf's own failure here is `exit status 128` with no explanation, which reads
# like a broken tool rather than a shallow clone.
test_a_base_missing_from_the_clone_is_named_rather_than_left_to_buf() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export STUB_GIT_FAIL_ON="rev-parse --verify --quiet origin/main"
  run_detect
  assert_status 1
  assert_output_contains "No origin/main in this clone"
  assert_output_contains "FETCH_DEPTH"
}

# Comparing a branch with itself always passes, so the gate would report success
# without having compared anything.
test_a_run_on_the_base_branch_says_it_compares_nothing() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export CURRENT_REF="main" BASE_REF="" DEFAULT_BRANCH="main"
  run_detect
  assert_status 0
  assert_output_contains "::warning::"
  assert_output_contains "nothing to detect"
}

test_a_pull_request_run_does_not_warn() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  run_detect
  assert_status 0
  assert_output_lacks "nothing to detect"
}

# With BREAKING off there is nothing to resolve, and resolving anyway would fail
# runs that never asked for the check.
test_no_target_is_resolved_when_breaking_is_off() {
  in_repo
  default_env
  printf 'version: v2\n' >buf.yaml
  export BREAKING="false" BASE_REF="" DEFAULT_BRANCH=""
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "breaking-against="
  if [ -n "$(target_of)" ]; then
    printf 'FAIL: a target was resolved with BREAKING off: %q\n' "$(target_of)" >&2
    exit 1
  fi
}

run_tests
