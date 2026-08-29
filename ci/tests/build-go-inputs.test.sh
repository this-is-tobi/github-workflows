#!/usr/bin/env bash
# build-go.yml runs one of two GoReleaser commands, and they do not take the
# same flags. `--single-target` and `--id` belong to `goreleaser build`; the
# PACKAGE path runs `goreleaser release --snapshot`, which has neither.
#
# The point of the guard is that the combination is refused rather than ignored:
# a caller who sets SINGLE_TARGET alongside PACKAGE and gets a green run would
# read it as having built one target when the whole matrix was built.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="build-go.yml"

# The defaults, which every test below then varies one value of.
guard_env() {
  export PACKAGE="false"
  export SINGLE_TARGET="false"
  export IDS=""
}

run_guard() {
  run_block "$(extract_run "$WORKFLOW" build 'Validate inputs')"
}

test_the_defaults_are_accepted() {
  guard_env
  run_guard
  assert_status 0
}

test_the_build_flags_are_accepted_without_package() {
  guard_env
  export SINGLE_TARGET="true"
  export IDS="cli,agent"
  run_guard
  assert_status 0
}

test_package_alone_is_accepted() {
  guard_env
  export PACKAGE="true"
  run_guard
  assert_status 0
}

test_single_target_with_package_is_refused() {
  guard_env
  export PACKAGE="true"
  export SINGLE_TARGET="true"
  run_guard
  assert_status 1
  assert_output_contains "SINGLE_TARGET is not available with PACKAGE"
}

test_ids_with_package_is_refused() {
  guard_env
  export PACKAGE="true"
  export IDS="cli"
  run_guard
  assert_status 1
  assert_output_contains "IDS is not available with PACKAGE"
}

# Both flags are wrong at once, and the caller should learn about a flag rather
# than about whichever one the guard happened to check first - so the message
# names one of them and the run stops, instead of reporting neither.
test_both_flags_with_package_still_names_one() {
  guard_env
  export PACKAGE="true"
  export SINGLE_TARGET="true"
  export IDS="cli"
  run_guard
  assert_status 1
  assert_output_contains "not available with PACKAGE"
}

# The workflow's own structure, not its shell: the two GoReleaser steps are
# mutually exclusive and between them cover every value of PACKAGE. A pair of
# `if:` conditions that both evaluated false would produce a green run that
# built nothing at all.
test_exactly_one_goreleaser_build_step_runs_for_any_package_value() {
  local conditions
  conditions=$(yq -o=json -I=0 '
    .jobs.build.steps[]
    | select(.name == "Build the binaries" or .name == "Build the full distribution")
    | {"name": .name, "if": .if}
  ' "$WORKFLOWS_DIR/$WORKFLOW")

  if [ "$(grep -c . <<<"$conditions")" -ne 2 ]; then
    printf 'FAIL: expected two build steps, found:\n%s\n' "$conditions" >&2
    exit 1
  fi
  # shellcheck disable=SC2016 # the Actions marker is meant to stay literal
  if [[ "$conditions" != *'"if":"${{ !inputs.PACKAGE }}"'* ]]; then
    printf 'FAIL: the binaries step is not gated on !PACKAGE:\n%s\n' "$conditions" >&2
    exit 1
  fi
  # shellcheck disable=SC2016 # the Actions marker is meant to stay literal
  if [[ "$conditions" != *'"if":"${{ inputs.PACKAGE }}"'* ]]; then
    printf 'FAIL: the distribution step is not gated on PACKAGE:\n%s\n' "$conditions" >&2
    exit 1
  fi
}

# Neither build step may take a GitHub credential. That is the whole argument
# for this workflow existing apart from release-go.yml: it publishes nothing, so
# a caller can run it on a pull request under `contents: read`.
test_no_step_receives_a_github_token() {
  local envs
  envs=$(yq -o=json -I=0 '.jobs.build.steps[] | (.env // {})' "$WORKFLOWS_DIR/$WORKFLOW")
  if [[ "$envs" == *"GITHUB_TOKEN"* || "$envs" == *"github.token"* || "$envs" == *"GH_PAT"* ]]; then
    printf 'FAIL: a step in %s takes a GitHub credential:\n%s\n' "$WORKFLOW" "$envs" >&2
    exit 1
  fi

  local perms
  perms=$(yq -o=json -I=0 '.jobs.build.permissions' "$WORKFLOWS_DIR/$WORKFLOW")
  if [ "$perms" != '{"contents":"read"}' ]; then
    printf 'FAIL: %s asks for more than contents:read: %s\n' "$WORKFLOW" "$perms" >&2
    exit 1
  fi
}

run_tests
