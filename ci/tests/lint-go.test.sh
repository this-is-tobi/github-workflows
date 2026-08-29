#!/usr/bin/env bash
# The three checks lint-go.yml runs, and the detection that decides which.
#
# The gofmt step is the one worth testing hardest: `gofmt -l` names the files it
# would rewrite and exits 0 whether or not it found any, so the emptiness of its
# output *is* the result. A step that forwarded gofmt's status instead would
# pass unconditionally and look exactly like a clean tree.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="lint-go.yml"

# gofmt answers from STUB_GOFMT_UNFORMATTED - the file list it would rewrite -
# and exits 0 regardless, which is what the real one does.
install_gofmt_stub() {
  cat >"$SANDBOX/bin/gofmt" <<'STUB'
#!/usr/bin/env bash
printf 'gofmt|%s\n' "$*" >>"$CALL_LOG"
printf '%s' "${STUB_GOFMT_UNFORMATTED:-}"
exit 0
STUB
  chmod +x "$SANDBOX/bin/gofmt"
}

install_go_stub() {
  cat >"$SANDBOX/bin/go" <<'STUB'
#!/usr/bin/env bash
args="$*"
printf 'go|%s\n' "$args" >>"$CALL_LOG"
if [ -n "${STUB_GO_FAIL_ON:-}" ] && [[ "$args" == *"${STUB_GO_FAIL_ON}"* ]]; then
  printf 'stub go: forced failure\n' >&2
  exit 1
fi
exit 0
STUB
  chmod +x "$SANDBOX/bin/go"
}

in_module_dir() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

run_format() { run_block "$(extract_run "$WORKFLOW" lint 'Check formatting')"; }
run_vet()    { run_block "$(extract_run "$WORKFLOW" lint 'Run go vet')"; }
run_detect() { run_block "$(extract_run "$WORKFLOW" detect-setup 'Detect module and linter configuration')"; }

# --- formatting -------------------------------------------------------------

test_a_formatted_tree_passes() {
  install_gofmt_stub
  export FORMAT_PATHS="." FAIL_ON_ERROR="true"
  run_format
  assert_status 0
  assert_output_contains "All files are formatted"
}

# The whole point of the step: gofmt exits 0 here, so only the output says no.
test_an_unformatted_file_fails_even_though_gofmt_exits_zero() {
  install_gofmt_stub
  export FORMAT_PATHS="." FAIL_ON_ERROR="true" STUB_GOFMT_UNFORMATTED="internal/app/mcp.go"
  run_format
  assert_status 1
  assert_output_contains "gofmt needed"
  assert_output_contains "internal/app/mcp.go"
}

test_unformatted_files_are_reported_without_failing_when_asked() {
  install_gofmt_stub
  export FORMAT_PATHS="." FAIL_ON_ERROR="false" STUB_GOFMT_UNFORMATTED="a.go"
  run_format
  assert_status 0
  assert_output_contains "gofmt needed"
  assert_output_contains "Workflow will continue"
}

# A repository holding other modules formats them on their own, so the paths
# have to reach gofmt as separate arguments rather than as one string.
test_several_format_paths_are_passed_separately() {
  install_gofmt_stub
  export FORMAT_PATHS="./builtin ./cmd ./internal" FAIL_ON_ERROR="true"
  run_format
  assert_status 0
  assert_called "gofmt|-l ./builtin ./cmd ./internal"
}

# --- vet --------------------------------------------------------------------

test_vet_runs_once_per_tag_set() {
  install_go_stub
  export PACKAGES="./..." BUILD_TAGS_JSON='["", "ai"]' FAIL_ON_ERROR="true"
  run_vet
  assert_status 0
  assert_called "go|vet ./..."
  assert_called "go|vet -tags ai ./..."
}

test_vet_passes_no_tags_flag_for_the_empty_set() {
  install_go_stub
  export PACKAGES="./..." BUILD_TAGS_JSON='[""]' FAIL_ON_ERROR="true"
  run_vet
  assert_status 0
  assert_called "go|vet ./..."
  assert_not_called "-tags"
}

# A finding under one tag set is a finding: the loop must not let a later clean
# pass overwrite an earlier failure.
test_a_finding_under_one_tag_set_fails_the_step() {
  install_go_stub
  export PACKAGES="./..." BUILD_TAGS_JSON='["", "ai"]' FAIL_ON_ERROR="true" \
    STUB_GO_FAIL_ON="vet -tags ai"
  run_vet
  assert_status 1
  assert_output_contains "go vet reported findings"
}

# **The half that actually distinguishes the rule.** Above, the failing pass is
# also the last one, so "any pass failing" and "the last pass deciding" give the
# same answer and the assertion cannot tell them apart. Here the *first* pass
# fails and a clean one follows, which only stays failed if each pass can raise
# the status and none can lower it.
test_an_early_finding_is_not_cleared_by_a_later_clean_pass() {
  install_go_stub
  export PACKAGES="./..." BUILD_TAGS_JSON='["", "ai"]' FAIL_ON_ERROR="true" \
    STUB_GO_FAIL_ON="vet ./..."
  run_vet
  assert_status 1
  assert_called "go|vet -tags ai ./..."
  assert_output_contains "go vet reported findings"
}

test_a_finding_can_be_reported_without_failing() {
  install_go_stub
  export PACKAGES="./..." BUILD_TAGS_JSON='[""]' FAIL_ON_ERROR="false" \
    STUB_GO_FAIL_ON="vet"
  run_vet
  assert_status 0
  assert_output_contains "Workflow will continue"
}

# --- detection --------------------------------------------------------------

test_golangci_is_enabled_by_a_configuration_file() {
  in_module_dir
  export GOLANGCI_INPUT="" BUILD_TAGS_INPUT='[""]'
  printf 'module example.com/x\n' >go.mod
  printf 'linters:\n' >.golangci.yml
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "golangci=true"
}

test_golangci_stays_off_without_a_configuration_file() {
  in_module_dir
  export GOLANGCI_INPUT="" BUILD_TAGS_INPUT='[""]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "golangci=false"
}

# An explicit answer wins over the file, in both directions.
test_an_explicit_false_overrides_a_configuration_file() {
  in_module_dir
  export GOLANGCI_INPUT="false" BUILD_TAGS_INPUT='[""]'
  printf 'module example.com/x\n' >go.mod
  printf 'linters:\n' >.golangci.yml
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "golangci=false"
}

test_an_explicit_true_needs_no_configuration_file() {
  in_module_dir
  export GOLANGCI_INPUT="true" BUILD_TAGS_INPUT='[""]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "golangci=true"
}

test_an_unrecognised_golangci_value_is_refused() {
  in_module_dir
  export GOLANGCI_INPUT="yes" BUILD_TAGS_INPUT='[""]'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 1
  assert_output_contains 'GOLANGCI_LINT must be'
}

test_a_directory_with_no_module_is_reported() {
  in_module_dir
  export GOLANGCI_INPUT="" BUILD_TAGS_INPUT='[""]'
  run_detect
  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "has-module=false"
}

test_build_tags_must_be_a_list_of_strings() {
  in_module_dir
  export GOLANGCI_INPUT="" BUILD_TAGS_INPUT='"ai"'
  printf 'module example.com/x\n' >go.mod
  run_detect
  assert_status 1
  assert_output_contains "BUILD_TAGS must be a non-empty JSON array of strings"
}

run_tests
