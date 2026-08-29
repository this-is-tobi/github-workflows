#!/usr/bin/env bash
# The `go test` invocation test-go.yml assembles, and the detection that
# decides whether it runs at all.
#
# The flags here are not stylistic. -count=1 is what makes a green run mean the
# tests actually ran rather than that a cache remembered them; -race and
# -shuffle=on are the two that catch what a laptop does not. A workflow that
# silently dropped one would still be green, which is why each is asserted
# rather than assumed.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="test-go.yml"

# Records every `go` invocation, and can be told to fail so FAIL_ON_ERROR has
# something to react to.
install_go_stub() {
  cat >"$SANDBOX/bin/go" <<'STUB'
#!/usr/bin/env bash
args="$*"
printf 'go|%s\n' "$args" >>"$CALL_LOG"
if [ -n "${STUB_GO_FAIL:-}" ]; then
  printf 'stub go: forced failure\n' >&2
  exit "${STUB_GO_FAIL}"
fi
exit 0
STUB
  chmod +x "$SANDBOX/bin/go"
}

# The defaults every caller gets unless it says otherwise.
default_env() {
  export PACKAGES="./..." BUILD_TAGS="" RACE="true" SHUFFLE="true" \
    COUNT="1" TIMEOUT="10m" TEST_COMMAND="" TEST_PRECOMMAND="" \
    COVERAGE="false" COVERAGE_PACKAGES="" COVERAGE_ARTIFACT_PATH="./coverage.out" \
    FAIL_ON_ERROR="true"
}

run_tests_step() {
  run_block "$(extract_run "$WORKFLOW" test 'Run tests')"
}

test_default_invocation_carries_the_flags_that_make_a_pass_mean_something() {
  install_go_stub
  default_env
  run_tests_step
  assert_status 0
  assert_called "go|test -count=1 -race -shuffle=on -timeout=10m ./..."
  assert_output_contains "All tests passed"
}

test_race_and_shuffle_can_be_turned_off() {
  install_go_stub
  default_env
  export RACE="false" SHUFFLE="false"
  run_tests_step
  assert_status 0
  assert_not_called "-race"
  assert_not_called "-shuffle=on"
}

# A build tag produces a second binary, so the tag has to reach the command.
test_build_tags_reach_the_invocation() {
  install_go_stub
  default_env
  export BUILD_TAGS="ai"
  run_tests_step
  assert_status 0
  assert_called "-tags ai"
}

test_no_tags_flag_when_the_tag_set_is_empty() {
  install_go_stub
  default_env
  run_tests_step
  assert_status 0
  assert_not_called "-tags"
}

test_coverage_adds_the_profile_and_coverpkg() {
  install_go_stub
  default_env
  export COVERAGE="true" COVERAGE_PACKAGES="./..."
  run_tests_step
  assert_status 0
  assert_called "-coverpkg=./... -coverprofile=./coverage.out"
}

test_coverpkg_is_omitted_when_not_asked_for() {
  install_go_stub
  default_env
  export COVERAGE="true"
  run_tests_step
  assert_status 0
  assert_called "-coverprofile=./coverage.out"
  assert_not_called "-coverpkg"
}

test_a_failing_suite_fails_the_workflow() {
  install_go_stub
  default_env
  export STUB_GO_FAIL="1"
  run_tests_step
  assert_status 1
  assert_output_contains "Failing the workflow"
}

test_fail_on_error_false_reports_and_continues() {
  install_go_stub
  default_env
  export STUB_GO_FAIL="1" FAIL_ON_ERROR="false"
  run_tests_step
  assert_status 0
  assert_output_contains "Workflow will continue"
}

test_a_custom_command_replaces_the_assembled_one() {
  install_go_stub
  default_env
  export TEST_COMMAND="go run ./tools/mytest"
  run_tests_step
  assert_status 0
  assert_called "go|run ./tools/mytest"
  assert_not_called "-shuffle=on"
}

# A pre-command that fails has produced no test result, so continuing would
# report on a tree that was never generated.
test_a_failing_precommand_stops_before_the_tests() {
  install_go_stub
  default_env
  export TEST_PRECOMMAND="go generate ./..." STUB_GO_FAIL="2"
  run_tests_step
  assert_status 1
  assert_output_contains "Pre-command failed"
  assert_not_called "go|test"
}

# The one shape that behaves differently, pinned so it is a known answer rather
# than a surprise: `eval` runs in this shell, so a pre-command calling `exit`
# ends the step directly and the diagnostic above never prints. The step still
# fails, with the pre-command'"'"'s own status. Running it in a subshell would make
# the message uniform and would also throw away every export and `cd` a
# pre-command exists to make, which is the more useful half.
test_a_precommand_that_exits_ends_the_step_with_its_own_status() {
  install_go_stub
  default_env
  export TEST_PRECOMMAND="exit 3"
  run_tests_step
  assert_status 3
  assert_not_called "go|test"
}

test_a_passing_precommand_runs_before_the_tests() {
  install_go_stub
  default_env
  export TEST_PRECOMMAND="go generate ./..."
  run_tests_step
  assert_status 0
  assert_called_before "go|generate ./..." "go|test"
}

run_tests
