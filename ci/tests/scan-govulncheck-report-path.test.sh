#!/usr/bin/env bash
# scan-govulncheck.yml - where the report is written vs where it is read.
#
# 'Run govulncheck' writes govulncheck-results.<format> inside
# WORKING_DIRECTORY. Every later consumer must look there too: a step without
# the same working-directory, or an action path relative to the workspace root,
# finds nothing as soon as WORKING_DIRECTORY is not '.', and a scan that found
# vulnerabilities then fails on a missing file instead of showing them.

# shellcheck source=ci/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOW="$WORKFLOWS_DIR/scan-govulncheck.yml"

step_field() {
  yq ".jobs.\"vuln-scan\".steps[] | select(.name == \"$1\") | $2" "$WORKFLOW"
}

test_the_text_report_is_read_where_it_was_written() {
  local writer reader
  writer=$(step_field 'Run govulncheck' '."working-directory"')
  reader=$(step_field 'Print govulncheck results' '."working-directory"')

  if [ "$writer" = "null" ] || [ "$reader" != "$writer" ]; then
    printf 'FAIL: report written in %q but read in %q\n' "$writer" "$reader" >&2
    exit 1
  fi
}

test_action_paths_point_inside_the_working_directory() {
  local artifact sarif
  artifact=$(step_field 'Upload the complete govulncheck report' '.with.path')
  sarif=$(step_field 'Upload govulncheck scan results to GitHub Security tab' '.with.sarif_file')

  # shellcheck disable=SC2016 # the Actions marker is meant to stay literal
  local prefix='${{ inputs.WORKING_DIRECTORY }}/'
  for v in "$artifact" "$sarif"; do
    if [[ "$v" != "$prefix"* ]]; then
      printf 'FAIL: expected %q to start with %q - action paths resolve from the workspace root\n' "$v" "$prefix" >&2
      exit 1
    fi
  done
}

run_tests
