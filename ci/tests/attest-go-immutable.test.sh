#!/usr/bin/env bash
# attest-go.yml on a repository with immutable releases: 'Check the release
# still takes assets', which stops SBOM/SIGN before they sign or upload anything
# for a release that can no longer take them, and 'Publish draft release', which
# publishes the release last so everything is attached before it locks.

# shellcheck source=ci/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKFLOW="$WORKFLOWS_DIR/attest-go.yml"
CHECK=$(extract_run attest-go.yml attest "Check the release still takes assets")
PUBLISH=$(extract_run attest-go.yml attest "Publish draft release")

release_env() {
  export GH_TOKEN="test-token"
  export GH_REPO="my-org/my-repo"
  export TAG="v1.2.3"
}

step_names() {
  yq '.jobs.attest.steps[].name' "$WORKFLOW"
}

step_field() { # step name, yq path under the step
  yq -r ".jobs.attest.steps[] | select(.name == \"$1\") | $2" "$WORKFLOW"
}

# --- Check the release still takes assets ----------------------------------

test_check_rejects_a_published_immutable_release() {
  release_env
  export STUB_GH_RELEASE_VIEW_JSON='{"isDraft":false,"isImmutable":true}'

  run_block "$CHECK"

  assert_status 1
  assert_output_contains "already published and immutable"
  assert_output_contains "PUBLISH_DRAFT_RELEASE"
}

# The chain this workflow supports there: the release reaches it as a draft.
# A draft already carries the setting that will lock it on publication.
test_check_accepts_a_draft_on_an_immutable_repository() {
  release_env
  export STUB_GH_RELEASE_VIEW_JSON='{"isDraft":true,"isImmutable":true}'

  run_block "$CHECK"

  assert_status 0
}

# Without immutable releases a published release still takes uploads, which is
# how this workflow has always been used.
test_check_accepts_a_published_mutable_release() {
  release_env
  export STUB_GH_RELEASE_VIEW_JSON='{"isDraft":false,"isImmutable":false}'

  run_block "$CHECK"

  assert_status 0
}

test_check_fails_when_the_release_cannot_be_read() {
  release_env
  export STUB_GH_FAIL_ON="release view"

  run_block "$CHECK"

  # Not "could not tell, so carry on": that is the case the guard is for.
  assert_status 1
}

test_check_runs_for_sbom_or_sign_and_before_either_uploads() {
  local condition names
  condition=$(step_field "Check the release still takes assets" .if)
  if [ "$condition" != "\${{ inputs.SBOM || inputs.SIGN }}" ]; then
    printf 'FAIL: the check must run exactly when SBOM or SIGN is on; got %q\n' "$condition" >&2
    return 1
  fi

  names=$(step_names)
  for later in "Sign the checksums file" "Upload the SBOM as a release asset"; do
    if [ "$(grep -n -x "Check the release still takes assets" <<<"$names" | cut -d: -f1)" -gt \
         "$(grep -n -x "$later" <<<"$names" | cut -d: -f1)" ]; then
      printf 'FAIL: the check must run before %q\n' "$later" >&2
      return 1
    fi
  done
}

# --- Publish draft release -------------------------------------------------

test_publish_publishes_a_draft() {
  release_env
  export STUB_GH_RELEASE_VIEW_JSON='{"isDraft":true,"isImmutable":true}'

  run_block "$PUBLISH"

  assert_status 0
  assert_called "release edit v1.2.3 --draft=false"
}

test_publish_leaves_a_published_release_alone() {
  release_env
  export STUB_GH_RELEASE_VIEW_JSON='{"isDraft":false,"isImmutable":true}'

  run_block "$PUBLISH"

  assert_status 0
  assert_output_contains "already published"
  assert_not_called "release edit"
}

# A failed lookup must not read as "already published" and leave a green run
# behind a release that is still a draft.
test_publish_fails_when_the_release_cannot_be_read() {
  release_env
  export STUB_GH_FAIL_ON="release view"

  run_block "$PUBLISH"

  assert_status 1
  assert_not_called "release edit"
}

test_publish_is_the_last_step_and_needs_every_step_before_it() {
  local last condition
  last=$(step_names | tail -n 1)
  if [ "$last" != "Publish draft release" ]; then
    printf 'FAIL: publishing must come last, after every upload; the last step is %q\n' "$last" >&2
    return 1
  fi

  # The default success(): an always() or !cancelled() would publish a release
  # missing its SBOM or signature, which immutable releases make permanent.
  condition=$(step_field "Publish draft release" .if)
  if [ "$condition" != "\${{ inputs.PUBLISH_DRAFT_RELEASE }}" ]; then
    printf 'FAIL: the publish step must run only when asked and only on success; got %q\n' "$condition" >&2
    return 1
  fi
}

# Publishing is what fires `release: published`, and only an App token or a
# PAT can trigger workflows. Every other gh call keeps the job's own token.
test_publish_prefers_the_app_token_then_the_pat() {
  local token
  token=$(step_field "Publish draft release" .env.GH_TOKEN)
  if [ "$token" != "\${{ steps.app-token.outputs.token || secrets.GH_PAT || github.token }}" ]; then
    printf 'FAIL: unexpected publishing token expression: %q\n' "$token" >&2
    return 1
  fi
}

test_the_app_token_is_only_minted_to_publish() {
  local condition
  condition=$(step_field "Generate GitHub App token" .if)
  if [ "$condition" != "\${{ env.HAS_APP_AUTH == 'true' && inputs.PUBLISH_DRAFT_RELEASE }}" ]; then
    printf 'FAIL: the App token must be minted only for PUBLISH_DRAFT_RELEASE; got %q\n' "$condition" >&2
    return 1
  fi
}

run_tests
