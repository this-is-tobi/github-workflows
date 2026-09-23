#!/usr/bin/env bash
# build-docker.yml - 'Compose image labels' and 'Create manifest list and push'
#
# Labels sit in the image config and annotations on the manifest list, which are
# written by two different jobs. Both derive from the one metadata run in
# `infos`, and what these cases hold is that they keep deriving from the same
# bytes: an index that disagrees with the images underneath it about when they
# were built is the failure this arrangement exists to prevent.

# shellcheck source=ci/tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LABELS_BLOCK=$(extract_run build-docker.yml build 'Compose image labels')
MANIFEST_BLOCK=$(extract_run build-docker.yml merge 'Create manifest list and push')

# What docker/metadata-action writes as its `json` output, trimmed to the part
# both consumers read.
METADATA=$(
  cat <<'JSON'
{"tags":["ghcr.io/owner/app:1.2.3"],"labels":{"org.opencontainers.image.created":"2026-09-24T09:00:00.000Z","org.opencontainers.image.source":"https://github.com/owner/app","org.opencontainers.image.revision":"abc123"}}
JSON
)

labels_env() {
  export METADATA_JSON="$METADATA"
  export EXTRA_LABELS=""
}

manifest_env() {
  export NORMALIZED_IMAGE="ghcr.io/owner/app"
  export METADATA_JSON="$METADATA"
  export EXTRA_ANNOTATIONS=""
  export DOCKER_METADATA_OUTPUT_JSON='{"tags":["ghcr.io/owner/app:1.2.3","ghcr.io/owner/app:latest"]}'
  # The step runs in the digest directory, one empty file per built architecture.
  mkdir -p "$SANDBOX/digests"
  : >"$SANDBOX/digests/aaa111"
  : >"$SANDBOX/digests/bbb222"
  cd "$SANDBOX/digests" || exit 1
}

test_the_standard_set_reaches_the_image_as_labels() {
  labels_env

  run_block "$LABELS_BLOCK"

  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "org.opencontainers.image.created=2026-09-24T09:00:00.000Z"
  assert_file_contains "$GITHUB_OUTPUT" "org.opencontainers.image.source=https://github.com/owner/app"
  assert_file_contains "$GITHUB_OUTPUT" "org.opencontainers.image.revision=abc123"
}

test_the_standard_set_is_absent_when_the_metadata_run_was_skipped() {
  labels_env
  # IMAGE_METADATA: false leaves the step un-run, so its json output is empty.
  export METADATA_JSON=""
  export EXTRA_LABELS="my.own=value"

  run_block "$LABELS_BLOCK"

  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "my.own=value"
  if grep -q "org.opencontainers" "$GITHUB_OUTPUT"; then
    printf 'FAIL: the standard set was stamped with IMAGE_METADATA off\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

test_a_caller_label_comes_after_the_standard_one_it_overrides() {
  labels_env
  export EXTRA_LABELS="org.opencontainers.image.source=https://example.com/mirror"

  run_block "$LABELS_BLOCK"

  assert_status 0
  # The last --label for a key is the one that survives, so a caller overriding
  # one standard value has to be written after the set, not before it.
  local standard caller
  standard=$(grep -n "source=https://github.com/owner/app" "$GITHUB_OUTPUT" | cut -d: -f1)
  caller=$(grep -n "source=https://example.com/mirror" "$GITHUB_OUTPUT" | cut -d: -f1)
  if [ -z "$standard" ] || [ -z "$caller" ] || [ "$caller" -le "$standard" ]; then
    printf 'FAIL: caller label at line %s, standard at %s; the caller must come last\n%s\n' \
      "${caller:-none}" "${standard:-none}" "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

test_caller_whitespace_and_blank_lines_never_become_a_label() {
  labels_env
  # A YAML block scalar strips the common indentation and nothing else, so a
  # caller's list arrives carrying its own leading and trailing spaces. Built
  # with printf rather than written out: trailing whitespace does not survive in
  # a source file, and trailing whitespace is the whole of what this pins.
  EXTRA_LABELS=$(printf '  my.first=one  \n\n  my.second=two\n')
  export EXTRA_LABELS

  run_block "$LABELS_BLOCK"

  assert_status 0
  assert_file_contains "$GITHUB_OUTPUT" "my.first=one"
  assert_file_contains "$GITHUB_OUTPUT" "my.second=two"
  # A blank line would reach Docker as a label with an empty name.
  if grep -qE '^\s*$' "$GITHUB_OUTPUT"; then
    printf 'FAIL: a blank line survived into the label list\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
  if grep -q "my.first=one  " "$GITHUB_OUTPUT"; then
    printf 'FAIL: a trailing space survived into a label value\n' >&2
    exit 1
  fi
}

test_the_index_is_annotated_with_the_labels_the_images_carry() {
  manifest_env

  run_block "$MANIFEST_BLOCK"

  assert_status 0
  # Index level: imagetools create accepts index and descriptor annotations
  # only, and the index is the one manifest list a caller pulls by tag.
  assert_called "--annotation index:org.opencontainers.image.created=2026-09-24T09:00:00.000Z"
  assert_called "--annotation index:org.opencontainers.image.revision=abc123"
  # The same reading of created as the labels above, from the same JSON.
  assert_called "index:org.opencontainers.image.created=2026-09-24T09:00:00.000Z"
}

test_the_tags_and_digests_still_reach_imagetools() {
  manifest_env

  run_block "$MANIFEST_BLOCK"

  assert_status 0
  assert_called "-t ghcr.io/owner/app:1.2.3"
  assert_called "-t ghcr.io/owner/app:latest"
  assert_called "ghcr.io/owner/app@sha256:aaa111"
  assert_called "ghcr.io/owner/app@sha256:bbb222"
}

test_no_annotation_argument_at_all_when_there_is_no_metadata() {
  manifest_env
  export METADATA_JSON=""

  run_block "$MANIFEST_BLOCK"

  # An empty array expanded under `set -u` is the shape that breaks here, so the
  # case is held rather than assumed: the command still runs, with no flag.
  assert_status 0
  assert_not_called "--annotation"
  assert_called "-t ghcr.io/owner/app:1.2.3"
}

test_caller_annotations_are_appended_and_trimmed() {
  manifest_env
  EXTRA_ANNOTATIONS=$(printf '  my.own=value  \n\n')
  export EXTRA_ANNOTATIONS

  run_block "$MANIFEST_BLOCK"

  assert_status 0
  assert_called "--annotation index:my.own=value"
  # The blank line must not become an annotation with an empty name.
  assert_not_called "--annotation index: "
}

run_tests
