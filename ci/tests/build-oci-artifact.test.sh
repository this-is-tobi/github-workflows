#!/usr/bin/env bash
# build-oci-artifact.yml - what each step lets through, and what it refuses.
#
# The workflow pushes an artifact that a consumer pins by version and that
# cosign later signs by digest, so the interesting behaviour is at the edges:
# a name or tag that is not a reference, a tag that is already published, an
# archive that is not the single gzipped tar the consumer expects (or that
# holds an entry outside of its root), and a push whose result does not read
# back as one layer of that type. `oras` is stubbed; the blocks under test are
# the real ones, run straight out of the YAML.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="build-oci-artifact.yml"
DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
LAYER_TYPE="application/vnd.oci.image.layer.v1.tar+gzip"

# `manifest fetch --descriptor` is the "is this tag published" probe and answers
# from STUB_ORAS_FETCH (exists | missing | name-unknown | denied); `push` prints
# the Digest line unless told to omit it; `manifest fetch` by digest answers with
# the manifest STUB_ORAS_LAYERS describes (one | two | wrongtype | extra).
install_oras_stub() {
  cat >"$SANDBOX/bin/oras" <<'STUB'
#!/usr/bin/env bash
printf 'oras|%s\n' "$*" >>"$CALL_LOG"

if [ "$1" = "manifest" ] && [ "$2" = "fetch" ]; then
  if [ "$3" = "--descriptor" ]; then
    case "${STUB_ORAS_FETCH:-missing}" in
      exists) echo '{"mediaType":"application/vnd.oci.image.manifest.v1+json"}' ;;
      missing) echo "Error response from registry: $4: not found" >&2; exit 1 ;;
      name-unknown) echo "Error response from registry: NAME_UNKNOWN: name unknown to registry" >&2; exit 1 ;;
      denied) echo "Error response from registry: unauthorized: authentication required" >&2; exit 1 ;;
    esac
  else
    case "${STUB_ORAS_LAYERS:-one}" in
      one) echo '{"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","size":10}]}' ;;
      two) echo '{"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","size":10},{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","size":10}]}' ;;
      wrongtype) echo '{"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar","size":10}]}' ;;
      extra) echo '{"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar+gzip","size":10},{"mediaType":"application/vnd.oci.image.layer.v1.tar","size":10}]}' ;;
    esac
  fi
fi
if [ "$1" = "push" ]; then
  echo "Uploaded  0123456789ab application/vnd.oci.image.manifest.v1+json"
  echo "Pushed [registry] $2"
  [ "${STUB_ORAS_PUSH_OMIT:-}" = "digest" ] || echo "Digest: ${STUB_ORAS_DIGEST:-sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef}"
fi
exit 0
STUB
  chmod +x "$SANDBOX/bin/oras"
}

in_workspace() {
  mkdir -p "$SANDBOX/work"
  cd "$SANDBOX/work" || exit 1
  export GITHUB_STEP_SUMMARY="$SANDBOX/summary"
  : >"$GITHUB_STEP_SUMMARY"
}

# The environment the workflow passes to the 'Validate inputs' step.
validate_env() {
  export INPUT_ARTIFACT_NAME="ghcr.io/my-org/my-repo/catalog"
  export ARTIFACT_TAG="1.2.3"
  export BUILD_COMMAND="true"
  export ARTIFACT_FILE="dist/catalog.tar.gz"
}

run_validate() { run_block "$(extract_run "$WORKFLOW" build 'Validate inputs')"; }
output_value() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }

# A valid archive: one file under a directory.
make_archive() {
  local file="${1:-dist/catalog.tar.gz}"
  mkdir -p "$(dirname "$file")" src/charts
  echo "apiVersion: v2" >src/charts/Chart.yaml
  tar -czf "$file" -C src .
}

# An archive holding one entry with the given name, which tar itself would not
# write.
make_archive_with_entry() {
  mkdir -p dist
  python3 - "$1" <<'PY'
import io, sys, tarfile
with tarfile.open("dist/catalog.tar.gz", "w:gz") as t:
    data = b"x"
    info = tarfile.TarInfo(sys.argv[1])
    info.size = len(data)
    t.addfile(info, io.BytesIO(data))
PY
}

# --- Validate inputs --------------------------------------------------------

test_validate_normalizes_the_name_and_builds_the_reference() {
  validate_env
  export INPUT_ARTIFACT_NAME="ghcr.io/My-Org/My_Repo/Catalog"

  run_validate

  assert_status 0
  [ "$(output_value image)" = "ghcr.io/my-org/my-repo/catalog" ] || { echo "FAIL: image=$(output_value image)" >&2; exit 1; }
  [ "$(output_value registry)" = "ghcr.io" ] || { echo "FAIL: registry=$(output_value registry)" >&2; exit 1; }
  [ "$(output_value reference)" = "ghcr.io/my-org/my-repo/catalog:1.2.3" ] || { echo "FAIL: reference=$(output_value reference)" >&2; exit 1; }
}

test_validate_accepts_a_registry_port() {
  validate_env
  export INPUT_ARTIFACT_NAME="localhost:5000/catalog/bundle"

  run_validate

  assert_status 0
  [ "$(output_value registry)" = "localhost:5000" ] || { echo "FAIL: registry=$(output_value registry)" >&2; exit 1; }
}

test_validate_refuses_names_that_are_not_a_repository_reference() {
  local name
  for name in "ghcr.io/my-org/catalog:1.2.3" "ghcr.io/my-org/catalog@sha256:abc" "ghcr.io" "ghcr.io/My Org/catalog" "ghcr.io//catalog" ""; do
    validate_env
    export INPUT_ARTIFACT_NAME="$name"
    : >"$GITHUB_OUTPUT"
    run_validate
    assert_status 1 "name '$name'"
    assert_output_contains "ARTIFACT_NAME must be"
  done
}

test_validate_accepts_version_like_tags() {
  local tag
  for tag in "1.2.3" "v1.2.3" "0.0.0-rc.1" "catalog-v0.2.0" "latest" "a"; do
    validate_env
    export ARTIFACT_TAG="$tag"
    run_validate
    assert_status 0 "tag '$tag'"
  done
}

test_validate_refuses_tags_that_are_not_oci_tags() {
  local tag
  for tag in "" "-1.0" ".1.0" "1.0/x" "1 0" "1.0+build" "$(printf 'a%.0s' $(seq 1 129))"; do
    validate_env
    export ARTIFACT_TAG="$tag"
    run_validate
    assert_status 1 "tag '$tag'"
    assert_output_contains "ARTIFACT_TAG must be"
  done
}

test_validate_refuses_an_empty_build_command() {
  validate_env
  export BUILD_COMMAND=""

  run_validate

  assert_status 1
  assert_output_contains "BUILD_COMMAND must not be empty"
}

test_validate_keeps_the_archive_inside_the_repository() {
  local file
  for file in "/tmp/catalog.tar.gz" "../catalog.tar.gz" "dist/../../catalog.tar.gz" "dist/catalog.zip" "dist/catalog" "catalog.tar.gz/" "" "dist/my catalog.tar.gz"; do
    validate_env
    export ARTIFACT_FILE="$file"
    run_validate
    assert_status 1 "file '$file'"
    assert_output_contains "ARTIFACT_FILE must be a relative path"
  done
}

test_validate_accepts_nested_archives() {
  local file
  for file in "catalog.tgz" "dist/catalog.tar.gz" "out/deep/er/catalog-1.2.tar.gz"; do
    validate_env
    export ARTIFACT_FILE="$file"
    run_validate
    assert_status 0 "file '$file'"
  done
}

# --- Validate registry credentials --------------------------------------------

run_credentials() { run_block "$(extract_run "$WORKFLOW" build 'Validate registry credentials')"; }

test_credentials_ghcr_needs_none() {
  export REGISTRY="ghcr.io" HAS_REGISTRY_AUTH="false"

  run_credentials

  assert_status 0
}

test_credentials_another_registry_needs_them() {
  export REGISTRY="registry.gitlab.com" HAS_REGISTRY_AUTH="false"

  run_credentials

  assert_status 1
  assert_output_contains "REGISTRY_USERNAME and REGISTRY_PASSWORD are required"
}

test_credentials_another_registry_with_them_passes() {
  export REGISTRY="registry.gitlab.com" HAS_REGISTRY_AUTH="true"

  run_credentials

  assert_status 0
}

# --- Refuse to overwrite a published tag ----------------------------------------

run_overwrite_guard() { run_block "$(extract_run "$WORKFLOW" build 'Refuse to overwrite a published tag')"; }

test_a_published_tag_is_refused() {
  install_oras_stub
  export REFERENCE="ghcr.io/my-org/my-repo/catalog:1.2.3" STUB_ORAS_FETCH="exists"

  run_overwrite_guard

  assert_status 1
  assert_output_contains "is already published"
  assert_output_contains "ALLOW_OVERWRITE"
}

test_a_missing_tag_passes() {
  install_oras_stub
  export REFERENCE="ghcr.io/my-org/my-repo/catalog:1.2.3" STUB_ORAS_FETCH="missing"

  run_overwrite_guard

  assert_status 0
}

# The first publication of a package answers with an unknown repository, not a
# missing tag.
test_a_repository_that_does_not_exist_yet_passes() {
  install_oras_stub
  export REFERENCE="ghcr.io/my-org/my-repo/catalog:1.2.3" STUB_ORAS_FETCH="name-unknown"

  run_overwrite_guard

  assert_status 0
}

# A failure that is not "it is not there" says nothing about the tag, and must
# not read as permission to push over it.
test_an_error_that_is_not_a_missing_tag_stops_the_run() {
  install_oras_stub
  export REFERENCE="ghcr.io/my-org/my-repo/catalog:1.2.3" STUB_ORAS_FETCH="denied"

  run_overwrite_guard

  assert_status 1
  assert_output_contains "Could not tell whether"
  assert_output_contains "unauthorized"
}

test_the_guard_only_runs_when_overwriting_is_not_allowed() {
  local condition
  condition=$(yq '.jobs.build.steps[] | select(.name == "Refuse to overwrite a published tag") | .if' "$WORKFLOWS_DIR/$WORKFLOW")
  # shellcheck disable=SC2016 # the Actions markers are meant to stay literal
  if [ "$condition" != '${{ !inputs.ALLOW_OVERWRITE }}' ]; then
    printf 'FAIL: the guard is not gated on !inputs.ALLOW_OVERWRITE, got %q\n' "$condition" >&2
    exit 1
  fi
}

# --- Build the artifact -----------------------------------------------------------

run_build() { run_block "$(extract_run "$WORKFLOW" build 'Build the artifact')"; }

build_env() {
  export ARTIFACT_FILE="dist/catalog.tar.gz"
  export BUILD_COMMAND="mkdir -p dist src && echo x > src/f && tar -czf dist/catalog.tar.gz -C src ."
}

test_build_accepts_the_archive_the_command_writes() {
  in_workspace
  build_env

  run_build

  assert_status 0
}

test_build_runs_the_command_with_bash_from_the_workspace() {
  in_workspace
  build_env
  # shellcheck disable=SC2016 # the command is meant to reach bash unexpanded
  export BUILD_COMMAND='pwd > where; arr=(a b); echo "${arr[1]}" > second; mkdir -p dist src; echo x > src/f; tar -czf dist/catalog.tar.gz -C src .'

  run_build

  assert_status 0
  [ "$(cat where)" = "$SANDBOX/work" ] || { echo "FAIL: ran in $(cat where)" >&2; exit 1; }
  [ "$(cat second)" = "b" ] || { echo "FAIL: not run by bash" >&2; exit 1; }
}

test_build_fails_when_the_command_fails() {
  in_workspace
  build_env
  export BUILD_COMMAND="echo broken >&2; exit 3"

  run_build

  assert_status 3
}

test_build_stops_at_the_first_failing_command_of_the_script() {
  in_workspace
  build_env
  export BUILD_COMMAND="false; mkdir -p dist src; echo x > src/f; tar -czf dist/catalog.tar.gz -C src ."

  run_build

  assert_status 1 "a build that fails half way must not publish what it left behind"
}

test_build_fails_when_the_archive_is_missing() {
  in_workspace
  build_env
  export BUILD_COMMAND="true"

  run_build

  assert_status 1
  assert_output_contains "did not write dist/catalog.tar.gz"
}

test_build_fails_when_the_archive_is_empty() {
  in_workspace
  build_env
  export BUILD_COMMAND="mkdir -p dist; : > dist/catalog.tar.gz"

  run_build

  assert_status 1
  assert_output_contains "did not write dist/catalog.tar.gz"
}

test_build_fails_when_the_file_is_not_gzip() {
  in_workspace
  build_env
  export BUILD_COMMAND="mkdir -p dist; echo plain text > dist/catalog.tar.gz"

  run_build

  assert_status 1
  assert_output_contains "is not a gzipped tar archive"
}

test_build_fails_when_the_gzip_is_not_a_tar() {
  in_workspace
  build_env
  export BUILD_COMMAND="mkdir -p dist; echo plain text | gzip > dist/catalog.tar.gz"

  run_build

  assert_status 1
  assert_output_contains "is not a gzipped tar archive"
}

test_build_refuses_an_entry_outside_of_the_root() {
  local entry
  for entry in "../evil" "/abs/evil" "a/../../evil" ".."; do
    in_workspace
    build_env
    make_archive_with_entry "$entry"
    export BUILD_COMMAND="true"

    run_build

    assert_status 1 "entry '$entry'"
    assert_output_contains "absolute path or a '..' component"
  done
}

test_build_accepts_names_that_merely_contain_dots() {
  in_workspace
  build_env
  make_archive_with_entry "./a..b/..c/d.."
  export BUILD_COMMAND="true"

  run_build

  assert_status 0
}

# --- Push the artifact ------------------------------------------------------------

run_push() { run_block "$(extract_run "$WORKFLOW" build 'Push the artifact')"; }

push_env() {
  export REFERENCE="ghcr.io/my-org/my-repo/catalog:1.2.3"
  export ARTIFACT_FILE="dist/catalog.tar.gz"
  export ARTIFACT_TYPE=""
  export ARTIFACT_TAG="1.2.3"
  export ARTIFACT_METADATA="true"
  export ARTIFACT_ANNOTATIONS=""
  export GITHUB_SERVER_URL="https://github.com"
  export GITHUB_REPOSITORY="my-org/my-repo"
  export GITHUB_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
}

test_push_sends_the_archive_as_the_single_layer() {
  install_oras_stub
  in_workspace
  push_env

  run_push

  assert_status 0
  assert_called "oras|push ghcr.io/my-org/my-repo/catalog:1.2.3 dist/catalog.tar.gz:$LAYER_TYPE"
}

test_push_stamps_the_standard_annotations() {
  install_oras_stub
  in_workspace
  push_env

  run_push

  assert_status 0
  assert_called "--annotation org.opencontainers.image.source=https://github.com/my-org/my-repo"
  assert_called "--annotation org.opencontainers.image.revision=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  assert_called "--annotation org.opencontainers.image.version=1.2.3"
}

test_push_without_metadata_stamps_no_standard_annotation() {
  install_oras_stub
  in_workspace
  push_env
  export ARTIFACT_METADATA="false"

  run_push

  assert_status 0
  assert_not_called "org.opencontainers.image.source"
  assert_not_called "org.opencontainers.image.revision"
  assert_not_called "org.opencontainers.image.version"
}

test_push_adds_the_extra_annotations_and_the_artifact_type() {
  install_oras_stub
  in_workspace
  push_env
  export ARTIFACT_TYPE="application/vnd.example.catalog.v1"
  export ARTIFACT_ANNOTATIONS=$'my.annotation=one\n\nother.annotation=two words'

  run_push

  assert_status 0
  assert_called "--artifact-type application/vnd.example.catalog.v1"
  assert_called "--annotation my.annotation=one"
  assert_called "--annotation other.annotation=two words"
}

test_push_works_with_nothing_to_add_to_the_manifest() {
  install_oras_stub
  in_workspace
  push_env
  export ARTIFACT_METADATA="false"

  run_push

  assert_status 0
}

test_push_outputs_the_digest_oras_reported() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_DIGEST="sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"

  run_push

  assert_status 0
  [ "$(output_value digest)" = "$STUB_ORAS_DIGEST" ] || { echo "FAIL: digest=$(output_value digest)" >&2; exit 1; }
}

test_push_reads_the_pushed_manifest_back_by_digest() {
  install_oras_stub
  in_workspace
  push_env

  run_push

  assert_status 0
  assert_called_before "oras|push" "oras|manifest fetch ghcr.io/my-org/my-repo/catalog@$DIGEST"
}

test_push_fails_without_a_digest() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_PUSH_OMIT="digest"

  run_push

  assert_status 1
  assert_output_contains "Could not read the digest"
  [ -z "$(output_value digest)" ] || { echo "FAIL: a digest was output" >&2; exit 1; }
}

test_push_fails_on_a_digest_that_is_not_one() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_DIGEST="sha256:short"

  run_push

  assert_status 1
  assert_output_contains "Could not read the digest"
}

test_push_fails_when_the_artifact_has_more_than_one_layer() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_LAYERS="two"

  run_push

  assert_status 1
  assert_output_contains "must hold exactly one"
  [ -z "$(output_value digest)" ] || { echo "FAIL: a digest was output" >&2; exit 1; }
}

test_push_fails_when_the_layer_has_another_media_type() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_LAYERS="wrongtype"

  run_push

  assert_status 1
  assert_output_contains "must hold exactly one"
}

test_push_fails_when_another_layer_comes_with_the_right_one() {
  install_oras_stub
  in_workspace
  push_env
  export STUB_ORAS_LAYERS="extra"

  run_push

  assert_status 1
  assert_output_contains "must hold exactly one"
}

test_push_writes_a_summary() {
  install_oras_stub
  in_workspace
  push_env

  run_push

  assert_status 0
  assert_file_contains "$GITHUB_STEP_SUMMARY" "ghcr.io/my-org/my-repo/catalog:1.2.3"
  assert_file_contains "$GITHUB_STEP_SUMMARY" "$DIGEST"
}

# --- The wiring ----------------------------------------------------------------------

# The steps can keep writing perfectly good outputs while the workflow forgets
# to surface them, and every test above would still pass with the outputs
# invisible to callers.
test_surfaces_the_digest_and_the_image_to_callers() {
  local declared
  declared=$(yq '
    [.on.workflow_call.outputs.digest.value, .jobs.build.outputs.digest,
     .on.workflow_call.outputs.image.value, .jobs.build.outputs.image]
    | join(" ")
  ' "$WORKFLOWS_DIR/$WORKFLOW")

  # shellcheck disable=SC2016 # the Actions markers are meant to stay literal
  if [ "$declared" != '${{ jobs.build.outputs.digest }} ${{ steps.push.outputs.digest }} ${{ jobs.build.outputs.image }} ${{ steps.validate.outputs.image }}' ]; then
    printf 'FAIL: digest and image are not wired from their steps to the workflow outputs, got %q\n' "$declared" >&2
    exit 1
  fi
}

test_the_job_asks_for_no_more_than_it_uses() {
  local perms
  perms=$(yq '.jobs.build.permissions | to_entries | map(.key + ":" + .value) | sort | join(" ")' "$WORKFLOWS_DIR/$WORKFLOW")
  if [ "$perms" != "contents:read packages:write" ]; then
    printf 'FAIL: expected contents:read and packages:write only, got %q\n' "$perms" >&2
    exit 1
  fi
}

# The tag guard has to run before anything is pushed or built: a refusal after
# the build wastes it, and one after the push is too late.
test_the_steps_run_in_the_order_that_keeps_the_guards_meaningful() {
  local order
  order=$(yq '[.jobs.build.steps[].name] | join("|")' "$WORKFLOWS_DIR/$WORKFLOW")
  local expected="Validate inputs|Validate registry credentials|Checks-out repository|Install Helm|Install ORAS|Login to registry|Refuse to overwrite a published tag|Build the artifact|Push the artifact"
  if [ "$order" != "$expected" ]; then
    printf 'FAIL: unexpected step order\n  expected: %s\n  actual:   %s\n' "$expected" "$order" >&2
    exit 1
  fi
}

run_tests
