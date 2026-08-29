#!/usr/bin/env bash
# The three checks lint-proto.yml runs, and the argv each one builds.
#
# Every one of them has a way of passing without checking: `buf format --diff`
# prints the diff and exits 0 without --exit-code, and `buf breaking` with no
# --against compares nothing and exits 0. Both are green runs that gated
# nothing, so the argv is asserted rather than the exit status alone.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="lint-proto.yml"

# Records its argv and exits with STUB_BUF_EXIT, so a test can make any check
# report findings without needing proto files or a real buf.
install_buf_stub() {
  cat >"$SANDBOX/bin/buf" <<'STUB'
#!/usr/bin/env bash
printf 'buf|%s\n' "$*" >>"$CALL_LOG"
exit "${STUB_BUF_EXIT:-0}"
STUB
  chmod +x "$SANDBOX/bin/buf"
}

default_env() {
  install_buf_stub
  export WORKING_DIRECTORY="proto" PATHS="" FAIL_ON_ERROR="true"
  export AGAINST=".git#branch=origin/main,subdir=proto"
  export STUB_BUF_EXIT=0
}

run_step() {
  run_block "$(extract_run "$WORKFLOW" lint "$1")"
}

argv_of() {
  grep '^buf|' "$CALL_LOG" | tail -1 | cut -d'|' -f2-
}

# **Without --exit-code, `buf format --diff` prints what it would change and
# exits 0.** The step would show the work and report success.
test_the_format_check_asks_for_an_exit_code() {
  default_env
  run_step 'Check formatting'
  assert_status 0
  local argv
  argv=$(argv_of)
  if [[ "$argv" != *"--exit-code"* ]]; then
    printf 'FAIL: format argv lacks --exit-code: %q\n' "$argv" >&2
    exit 1
  fi
  if [[ "$argv" != *"--diff"* ]]; then
    printf 'FAIL: format argv lacks --diff: %q\n' "$argv" >&2
    exit 1
  fi
}

test_a_formatting_finding_fails_the_step() {
  default_env
  export STUB_BUF_EXIT=1
  run_step 'Check formatting'
  assert_status 1
  assert_output_contains "buf format needed"
}

test_a_formatting_finding_is_survivable_when_asked() {
  default_env
  export STUB_BUF_EXIT=1 FAIL_ON_ERROR="false"
  run_step 'Check formatting'
  assert_status 0
  assert_output_contains "FAIL_ON_ERROR is false"
}

test_a_lint_finding_fails_the_step() {
  default_env
  export STUB_BUF_EXIT=1
  run_step 'Run buf lint'
  assert_status 1
  assert_output_contains "buf lint reported findings"
}

test_a_lint_finding_is_survivable_when_asked() {
  default_env
  export STUB_BUF_EXIT=1 FAIL_ON_ERROR="false"
  run_step 'Run buf lint'
  assert_status 0
  assert_output_contains "FAIL_ON_ERROR is false"
}

test_the_breaking_check_passes_the_resolved_target() {
  default_env
  run_step 'Run buf breaking'
  assert_status 0
  local argv
  argv=$(argv_of)
  if [[ "$argv" != *"--against .git#branch=origin/main,subdir=proto"* ]]; then
    printf 'FAIL: breaking argv does not carry the target: %q\n' "$argv" >&2
    exit 1
  fi
}

# **`buf breaking` with no --against compares nothing and exits 0.** Reaching
# this step with an unresolved target has to be an error, not a run of buf.
test_the_breaking_check_refuses_to_run_without_a_target() {
  default_env
  export AGAINST=""
  run_step 'Run buf breaking'
  assert_status 1
  assert_output_contains "no comparison target was resolved"
  if [ -s "$CALL_LOG" ]; then
    printf 'FAIL: buf was invoked with no target:\n%s\n' "$(cat "$CALL_LOG")" >&2
    exit 1
  fi
}

test_a_breaking_finding_fails_the_step() {
  default_env
  export STUB_BUF_EXIT=1
  run_step 'Run buf breaking'
  assert_status 1
  assert_output_contains "incompatible changes"
}

# The escape hatch has to work here too - a repository mid-migration needs the
# report without the gate.
test_a_breaking_finding_is_survivable_when_asked() {
  default_env
  export STUB_BUF_EXIT=1 FAIL_ON_ERROR="false"
  run_step 'Run buf breaking'
  assert_status 0
  assert_output_contains "FAIL_ON_ERROR is false"
}

# Every check runs from the repository root with the directory as buf's input,
# so `.git` keeps its ordinary path and the breaking target needs no `../`.
test_every_check_passes_the_working_directory_as_bufs_input() {
  local step
  for step in 'Check formatting' 'Run buf lint' 'Run buf breaking'; do
    default_env
    run_step "$step"
    assert_status 0 "$step"
    if [[ "$(argv_of)" != *" proto"* ]]; then
      printf 'FAIL: %s does not pass the working directory: %q\n' "$step" "$(argv_of)" >&2
      exit 1
    fi
  done
}

test_paths_are_forwarded_to_every_check() {
  local step
  for step in 'Check formatting' 'Run buf lint' 'Run buf breaking'; do
    default_env
    export PATHS="proto/a proto/b"
    run_step "$step"
    assert_status 0 "$step"
    local argv
    argv=$(argv_of)
    if [[ "$argv" != *"--path proto/a"* || "$argv" != *"--path proto/b"* ]]; then
      printf 'FAIL: %s did not forward PATHS: %q\n' "$step" "$argv" >&2
      exit 1
    fi
  done
}

run_tests
