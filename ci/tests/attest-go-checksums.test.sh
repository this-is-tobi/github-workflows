#!/usr/bin/env bash
# attest-go.yml - 'Validate inputs' and 'Download the checksums file': the
# guard against an unnamed release or no capability enabled, and the guard
# against a downloaded-but-missing checksums file. Every capability this
# workflow offers reads that one file (as the attestation subject list, or as
# the blob to sign), so its absence is diagnosed once here with one clear
# message, rather than as three different opaque failures further down.

# shellcheck source=ci/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VALIDATE=$(extract_run attest-go.yml attest "Validate inputs")
DOWNLOAD=$(extract_run attest-go.yml attest "Download the checksums file")

validate_env() {
  export TAG="v1.2.3"
  export PROVENANCE="false"
  export SBOM="false"
  export SIGN="true"
}

test_validate_rejects_an_empty_tag() {
  validate_env
  export TAG=""

  run_block "$VALIDATE"

  assert_status 1
  assert_output_contains "TAG must name the release"
}

test_validate_rejects_no_capability_enabled() {
  validate_env
  export SIGN="false"

  run_block "$VALIDATE"

  # Would otherwise download the checksums file and do nothing with it -
  # green, and indistinguishable from a run that attested everything.
  assert_status 1
  assert_output_contains "Nothing to attest"
}

test_validate_accepts_sign_alone() {
  validate_env

  run_block "$VALIDATE"

  assert_status 0
}

test_validate_accepts_provenance_alone() {
  validate_env
  export SIGN="false"
  export PROVENANCE="true"

  run_block "$VALIDATE"

  assert_status 0
}

test_validate_accepts_every_capability_together() {
  validate_env
  export PROVENANCE="true"
  export SBOM="true"

  run_block "$VALIDATE"

  assert_status 0
}

# The download step writes to a relative 'release-assets/' directory, so each
# test runs from a sandboxed work directory rather than the suite's own CWD.
in_work_dir() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

download_env() {
  export GH_TOKEN="test-token"
  export GH_REPO="my-org/my-repo"
  export TAG="v1.2.3"
  export CHECKSUMS_FILE="checksums.txt"
}

test_download_finds_the_checksums_file() {
  in_work_dir
  download_env

  run_block "$DOWNLOAD"

  assert_status 0
  assert_called "release download v1.2.3"
  [ -f "release-assets/checksums.txt" ] || {
    echo "FAIL: expected release-assets/checksums.txt to exist"
    exit 1
  }
}

test_download_respects_a_custom_checksums_file_name() {
  in_work_dir
  download_env
  export CHECKSUMS_FILE="rta_checksums.txt"

  run_block "$DOWNLOAD"

  assert_status 0
  assert_called "--pattern rta_checksums.txt"
}

test_download_fails_loudly_when_the_release_has_no_such_asset() {
  in_work_dir
  download_env
  export STUB_GH_RELEASE_DOWNLOAD_FAIL="true"

  run_block "$DOWNLOAD"

  assert_status 1
}

# The narrower case a workflow cannot assume away: gh exits 0 (a real
# 'gh release download' can report success for a pattern that matched
# nothing), so the step's own existence check - not gh's exit code - is what
# has to catch it.
test_download_fails_loudly_when_gh_reports_success_but_wrote_nothing() {
  in_work_dir
  download_env
  export STUB_GH_RELEASE_DOWNLOAD_EMPTY="true"

  run_block "$DOWNLOAD"

  assert_status 1
  assert_output_contains "is not an asset of release"
}

run_tests
