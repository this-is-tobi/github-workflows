#!/usr/bin/env bash
# Turning the EXTRA_ENV secret into job environment.
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

# The invariant the mask-before-write ordering exists to produce: nothing lands
# in the job environment that Actions has not been told to redact. Checked over
# whatever the step actually wrote rather than over a list repeated from the
# step, so an entry that starts being written without being masked fails here.
test_nothing_reaches_the_environment_unmasked() {
  with_github_env
  export EXTRA_ENV="FIRST=alpha
SECOND=beta
THIRD=gamma"
  run_env_step
  assert_status 0

  local line value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    value=${line#*=}
    if [[ "$RUN_OUTPUT" != *"::add-mask::$value"* ]]; then
      printf 'FAIL: %q reached GITHUB_ENV without a mask directive\n%s\n' \
        "$line" "$RUN_OUTPUT" >&2
      exit 1
    fi
  done <"$GITHUB_ENV"
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

# The shape somebody actually reaches for: a signing key pasted whole. Carried
# line by line it would arrive truncated to its first line and fail much later
# as an unreadable key, so it is refused here where the cause is visible.
test_a_multiline_value_is_refused_rather_than_truncated() {
  with_github_env
  export EXTRA_ENV="SIGNING_KEY=-----BEGIN PGP PRIVATE KEY BLOCK-----
lQOYBGYAAAABCADQ-not-a-real-key
-----END PGP PRIVATE KEY BLOCK-----"
  run_env_step
  assert_status 1
  assert_output_contains "EXTRA_ENV lines must be KEY=VALUE"
  assert_output_contains "several lines"
}

# This step exists to pass a value to GoReleaser. These names do something
# else - they change how every later step in the job runs.
test_environment_that_reconfigures_the_job_is_refused() {
  local name
  for name in PATH NODE_OPTIONS LD_PRELOAD LD_LIBRARY_PATH DYLD_INSERT_LIBRARIES \
    GITHUB_TOKEN ACTIONS_RUNNER_DEBUG RUNNER_TEMP; do
    with_github_env
    export EXTRA_ENV="$name=whatever"
    run_env_step
    assert_status 1 "EXTRA_ENV must refuse to set $name"
    assert_output_contains "must not set $name"
    if [ -s "$GITHUB_ENV" ]; then
      printf 'FAIL: %s was written to GITHUB_ENV before being refused\n' "$name" >&2
      exit 1
    fi
  done
}

# The other half of the rule above, and the half that makes it non-vacuous: the
# denylist is anchored, so a legitimate name that merely *contains* one of those
# words still gets through. GoReleaser's own Homebrew tap variable is exactly
# that name.
test_a_name_merely_containing_a_denied_word_is_accepted() {
  with_github_env
  export EXTRA_ENV="HOMEBREW_TAP_GITHUB_TOKEN=tap-token
GORELEASER_PATH_PREFIX=/opt"
  run_env_step
  assert_status 0
  assert_file_contains "$GITHUB_ENV" "HOMEBREW_TAP_GITHUB_TOKEN=tap-token"
  assert_file_contains "$GITHUB_ENV" "GORELEASER_PATH_PREFIX=/opt"
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
