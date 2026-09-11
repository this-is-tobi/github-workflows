#!/usr/bin/env bash
# release-helm-local.yml - 'Package and push chart(s)': the published-charts
# output that attest-helm.yml consumes.
#
# The interesting part is where each entry's name and version come from. They
# are read back out of helm's own `Pushed:` line rather than split off the
# package filename, because '<name>-<version>.tgz' is ambiguous the moment a
# version carries a dash of its own - 'my-chart-1.2.3-rc.1.tgz' splits three
# different ways and only one of them is right. The stub therefore returns a
# prerelease reference throughout, so a regression to filename parsing fails
# here instead of shipping an attestation against the wrong version.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="release-helm-local.yml"

# `package` writes a real (empty) file so the glob that follows it has something
# to find; `push` answers from STUB_HELM_PUSHED/STUB_HELM_DIGEST, and omits
# either line on demand to exercise the guard.
install_helm_stub() {
  cat >"$SANDBOX/bin/helm" <<'STUB'
#!/usr/bin/env bash
printf 'helm|%s\n' "$*" >>"$CALL_LOG"

case "$1" in
  package)
    chart="$2"
    dest="."
    prev=""
    for arg in "$@"; do
      [ "$prev" = "--destination" ] && dest="$arg"
      prev="$arg"
    done
    mkdir -p "$dest"
    : >"$dest/$(basename "$chart")-${STUB_HELM_PACKAGE_VERSION:-1.2.3-rc.1}.tgz"
    ;;
  push)
    [ "${STUB_HELM_PUSH_OMIT:-}" = "reference" ] || \
      printf 'Pushed: %s\n' "${STUB_HELM_PUSHED:-ghcr.io/owner/repo/my-chart:1.2.3-rc.1}"
    [ "${STUB_HELM_PUSH_OMIT:-}" = "digest" ] || \
      printf 'Digest: %s\n' "${STUB_HELM_DIGEST:-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}"
    ;;
esac
exit 0
STUB
  chmod +x "$SANDBOX/bin/helm"
}

# The step packages relative to the working directory and writes into
# .cr-release-packages, so every test runs inside its own sandbox rather than
# the checkout.
in_workspace() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
}

make_chart() {
  mkdir -p "charts/$1"
  printf 'apiVersion: v2\nname: %s\nversion: 0.1.0\n' "$1" >"charts/$1/Chart.yaml"
}

publish_env() {
  export CHARTS_DIR="./charts"
  export CHART_NAME="my-chart"
  export CHART_VERSION=""
  export APP_VERSION=""
  export REGISTRY="ghcr.io"
  export OCI_REPOSITORY=""
  export GITHUB_REPOSITORY="owner/repo"
}

run_publish() { run_block "$(extract_run "$WORKFLOW" release 'Package and push chart(s)')"; }

# Reads the published-charts value back out of the step's GITHUB_OUTPUT.
published() {
  sed -n 's/^published-charts=//p' "$GITHUB_OUTPUT"
}

assert_entry() {
  local field="$1" expected="$2" actual
  actual=$(published | jq -r ".[0].$field")
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: expected .%s to be %q, got %q\n---- published ----\n%s\n-------------------\n' \
      "$field" "$expected" "$actual" "$(published)" >&2
    exit 1
  fi
}

# --- what each entry records ------------------------------------------------

test_reads_name_and_version_from_helm_not_the_filename() {
  install_helm_stub
  in_workspace
  make_chart my-chart
  publish_env

  run_publish

  assert_status 0
  # Splitting 'my-chart-1.2.3-rc.1.tgz' on the last dash would yield version
  # '1' and name 'my-chart-1.2.3-rc'; on the first, name 'my'.
  assert_entry name "my-chart"
  assert_entry version "1.2.3-rc.1"
}

test_keeps_repository_and_digest_apart() {
  install_helm_stub
  in_workspace
  make_chart my-chart
  publish_env

  run_publish

  assert_status 0
  # attest-helm.yml feeds these to actions/attest-build-provenance as separate
  # subject-name and subject-digest inputs, so a pre-joined 'repo@sha256:...'
  # would have to be taken apart again there.
  assert_entry repository "ghcr.io/owner/repo/my-chart"
  assert_entry digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

test_publishes_every_chart_when_no_chart_name_is_given() {
  install_helm_stub
  in_workspace
  make_chart first
  make_chart second
  publish_env
  export CHART_NAME=""

  run_publish

  assert_status 0
  local count
  count=$(published | jq 'length')
  if [ "$count" != "2" ]; then
    printf 'FAIL: expected 2 published charts, got %s\n---- published ----\n%s\n-------------------\n' \
      "$count" "$(published)" >&2
    exit 1
  fi
}

# --- the guard --------------------------------------------------------------

# A digest is the whole point of the output: attesting a tag would bind the
# claim to whatever that tag resolves to at verification time. An entry without
# one must stop the run, not reach attest-helm.yml to be rejected there.
test_fails_when_helm_reports_no_digest() {
  install_helm_stub
  in_workspace
  make_chart my-chart
  publish_env
  export STUB_HELM_PUSH_OMIT="digest"

  run_publish

  assert_status 1
  assert_output_contains "Could not read the reference and digest"
}

test_fails_when_helm_reports_no_reference() {
  install_helm_stub
  in_workspace
  make_chart my-chart
  publish_env
  export STUB_HELM_PUSH_OMIT="reference"

  run_publish

  assert_status 1
  assert_output_contains "Could not read the reference and digest"
}

# --- the wiring -------------------------------------------------------------

# The step can keep writing a perfectly good published-charts to GITHUB_OUTPUT
# while the workflow forgets to surface it, and every test above would still
# pass with the output invisible to callers.
test_surfaces_published_charts_to_callers() {
  local declared
  declared=$(yq '
    [.on.workflow_call.outputs."published-charts".value, .jobs.release.outputs."published-charts"]
    | join(" ")
  ' "$WORKFLOWS_DIR/$WORKFLOW")

  # shellcheck disable=SC2016 # the Actions markers are meant to stay literal
  if [ "$declared" != '${{ jobs.release.outputs.published-charts }} ${{ steps.publish.outputs.published-charts }}' ]; then
    printf 'FAIL: published-charts is not wired from the publish step to the workflow output, got %q\n' \
      "$declared" >&2
    exit 1
  fi
}

run_tests
