#!/usr/bin/env bash
# scan-scorecard.yml never publishes its results.
#
# Scorecard's API only accepts published results from a workflow shaped like
# its own template - no top-level `defaults`, no `run` step in the scanning job
# - and this one has both, as every workflow here does. Turning
# `publish_results` on would not produce a badge: the API refuses the upload,
# the Scorecard step fails, and the Security tab report goes down with it.
# `id-token: write` only exists to sign that publication, so requesting it
# would hand every caller's job an OIDC token for nothing.

# shellcheck source=ci/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOW="$WORKFLOWS_DIR/scan-scorecard.yml"
SCORECARD_STEP='.jobs[].steps[] | select(.uses // "" | test("^ossf/scorecard-action@"))'

test_the_scorecard_step_does_not_publish() {
  local steps publish
  steps=$(yq "[$SCORECARD_STEP] | length" "$WORKFLOW")
  if [ "$steps" -ne 1 ]; then
    printf 'FAIL: expected exactly one ossf/scorecard-action step, found %s\n' "$steps" >&2
    exit 1
  fi
  publish=$(yq "$SCORECARD_STEP | .with.publish_results" "$WORKFLOW")
  if [ "$publish" != "false" ]; then
    printf 'FAIL: publish_results is %s, expected false\n' "$publish" >&2
    exit 1
  fi
}

test_no_job_requests_an_oidc_token() {
  local requested
  requested=$(yq '[.jobs | to_entries[] | select((.value.permissions["id-token"] // "none") != "none") | .key] | join(", ")' "$WORKFLOW")
  if [ -n "$requested" ]; then
    printf 'FAIL: these jobs request id-token, which only publishing needs: %s\n' "$requested" >&2
    exit 1
  fi
}

run_tests
