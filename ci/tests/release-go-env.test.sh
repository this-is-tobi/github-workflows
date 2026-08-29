#!/usr/bin/env bash
# The one block in release-go.yml with logic of its own: turning the EXTRA_ENV
# secret into job environment.
#
# It is a secret, so nothing here may reach an argv or the log. The assertions
# below are as much about what is *absent* from the output as about what the
# step produced.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="release-go.yml"

with_github_env() {
  export GITHUB_ENV="$SANDBOX/github_env"
  : >"$GITHUB_ENV"
}

run_env_step() {
  run_block "$(extract_run "$WORKFLOW" release 'Assemble the GoReleaser environment')"
}

test_no_extra_environment_is_a_no_op() {
  with_github_env
  export EXTRA_ENV=""
  run_env_step
  assert_status 0
  assert_output_contains "No extra environment supplied"
}

test_entries_reach_the_job_environment() {
  with_github_env
  export EXTRA_ENV="HOMEBREW_TAP_TOKEN=abc123
AUR_KEY=def456"
  run_env_step
  assert_status 0
  assert_file_contains "$GITHUB_ENV" "HOMEBREW_TAP_TOKEN=abc123"
  assert_file_contains "$GITHUB_ENV" "AUR_KEY=def456"
  assert_output_contains "Loaded 2 extra environment entries"
}

# The value is a secret. It goes to the job environment and to ::add-mask::,
# and nowhere a reader of the log can see it.
test_values_are_masked_and_never_printed() {
  with_github_env
  export EXTRA_ENV="TAP_TOKEN=supersecretvalue"
  run_env_step
  assert_status 0
  assert_output_contains "::add-mask::supersecretvalue"
  # The only appearance is the mask directive itself, which is what tells
  # Actions to redact it everywhere else.
  if [ "$(grep -c 'supersecretvalue' <<<"$RUN_OUTPUT")" -ne 1 ]; then
    printf 'FAIL: the secret appears more than once in the output\n%s\n' "$RUN_OUTPUT" >&2
    exit 1
  fi
}

test_blank_lines_and_comments_are_ignored() {
  with_github_env
  export EXTRA_ENV="# a comment

KEY=value"
  run_env_step
  assert_status 0
  assert_output_contains "Loaded 1 extra environment entries"
  assert_file_contains "$GITHUB_ENV" "KEY=value"
}

# A dropped entry surfaces much later as an authentication failure inside a
# half-finished release, so a line that is not KEY=VALUE is named here instead.
test_a_malformed_line_is_refused_rather_than_dropped() {
  with_github_env
  export EXTRA_ENV="not an assignment"
  run_env_step
  assert_status 1
  assert_output_contains "EXTRA_ENV lines must be KEY=VALUE"
}

test_a_value_containing_equals_signs_survives_intact() {
  with_github_env
  export EXTRA_ENV="TOKEN=a=b=c"
  run_env_step
  assert_status 0
  assert_file_contains "$GITHUB_ENV" "TOKEN=a=b=c"
  assert_output_contains "::add-mask::a=b=c"
}

run_tests
