#!/usr/bin/env bash
# cd.yml - 'Classify the pushed files'
#
# Its answer decides whether a release runs at all, so the failure worth
# guarding is not a release run for nothing but one that should have run and
# was told not to: every case below expecting `true` is guarding a skip.
#
# The diff is real git over a real repository rather than the recording stub,
# because which names `git diff` prints — for a moved file above all — is the
# behaviour under test, and a stub would only repeat what the test told it.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BLOCK=$(extract_run cd.yml path-filter "Classify the pushed files")

# A repository holding what this one does, committed once, with BEFORE at that
# commit. git runs with its own defaults rather than this machine's: rename
# detection is on by default, and a global config turning it off would let
# the moved-file case pass without the flag that makes it pass on a runner.
repo() {
  rm -f "$SANDBOX/bin/git"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=ci GIT_AUTHOR_EMAIL=ci@example.com
  export GIT_COMMITTER_NAME=ci GIT_COMMITTER_EMAIL=ci@example.com
  cd "$SANDBOX" || exit 1
  git init -q -b main repo
  cd repo || exit 1
  touch_files .github/workflows/ci.yml .github/workflows/cd.yml \
    .github/workflows/build-go.yml .release-please-manifest.json \
    CHANGELOG.md README.md docs/01-readme.md
  commit "initial"
  BEFORE=$AFTER
  export BEFORE
}

touch_files() {
  local file
  for file in "$@"; do
    mkdir -p "$(dirname "$file")"
    printf 'line\n' >>"$file"
  done
}

commit() {
  git add -A
  git commit -q -m "$1"
  AFTER=$(git rev-parse HEAD)
  export AFTER
}

output() {
  grep "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-
}

assert_output() {
  local got
  got=$(output "$1")
  if [ "$got" != "$2" ]; then
    printf 'FAIL: output %s is %q, want %q\n---- output ----\n%s\n----------------\n' \
      "$1" "$got" "$2" "$RUN_OUTPUT" >&2
    exit 1
  fi
}

assert_failed_with_no_output() {
  if [ "$RUN_STATUS" -eq 0 ]; then
    printf 'FAIL: the step succeeded\n---- output ----\n%s\n----------------\n' "$RUN_OUTPUT" >&2
    exit 1
  fi
  if [ -s "$GITHUB_OUTPUT" ]; then
    printf 'FAIL: a failed step still answered:\n%s\n' "$(cat "$GITHUB_OUTPUT")" >&2
    exit 1
  fi
}

test_a_reusable_workflow_changed_is_a_release() {
  repo
  touch_files .github/workflows/build-go.yml
  commit "change a reusable workflow"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
  assert_output release false
}

# ci.yml and cd.yml are this repository's pipeline, which no caller runs.
test_the_repositorys_own_pipeline_alone_releases_nothing() {
  repo
  touch_files .github/workflows/ci.yml .github/workflows/cd.yml
  commit "change the pipeline"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows false
  assert_output release false
}

test_the_pipeline_beside_a_reusable_workflow_is_a_release() {
  repo
  touch_files .github/workflows/ci.yml .github/workflows/lint-go.yml
  commit "change both"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
}

# The filter action's pattern was `.github/workflows/**`, which crosses `/`.
test_a_file_below_a_subdirectory_of_workflows_counts_as_a_workflow() {
  repo
  touch_files .github/workflows/shared/setup.yml
  commit "add a file below workflows"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
}

test_prose_alone_releases_nothing() {
  repo
  touch_files README.md docs/01-readme.md ci/tests/new.test.sh
  commit "change prose and tests"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows false
  assert_output release false
}

test_a_merged_release_pull_request_is_a_release() {
  repo
  touch_files .release-please-manifest.json CHANGELOG.md
  commit "chore(main): release 1.2.3"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows false
  assert_output release true
}

# A pull request rebased onto main lands every commit it held, and the one
# changing a workflow need not be the last.
test_every_commit_of_the_push_counts_not_only_the_last() {
  repo
  touch_files .github/workflows/build-go.yml
  commit "first of the push"
  touch_files docs/01-readme.md
  commit "last of the push"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
}

# By its new name alone this is documentation, and it is a workflow gone from
# what a release ships.
test_a_workflow_moved_out_of_workflows_counts_by_the_name_it_left() {
  repo
  git mv .github/workflows/build-go.yml docs/build-go.yml
  commit "move a workflow"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
}

test_a_push_that_created_the_branch_says_everything_changed() {
  repo
  touch_files docs/01-readme.md
  commit "change prose"
  export BEFORE=0000000000000000000000000000000000000000
  run_block "$BLOCK"
  assert_status 0
  assert_output_contains "names no commit it replaced"
  assert_output workflows true
  assert_output release true
}

test_a_push_naming_no_previous_commit_says_everything_changed() {
  repo
  touch_files docs/01-readme.md
  commit "change prose"
  export BEFORE=""
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
  assert_output release true
}

# A force push can replace a commit that no ref holds any more.
test_a_replaced_commit_no_history_holds_says_everything_changed() {
  repo
  touch_files docs/01-readme.md
  commit "change prose"
  export BEFORE=0123456789abcdef0123456789abcdef01234567
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows true
  assert_output release true
}

test_a_diff_that_fails_fails_the_step() {
  repo
  touch_files .github/workflows/build-go.yml
  commit "change a reusable workflow"
  # A commit id the repository does not hold: the diff itself fails.
  export AFTER=0123456789abcdef0123456789abcdef01234567
  run_block "$BLOCK"
  assert_failed_with_no_output
}

test_a_pushed_commit_that_is_not_an_id_is_never_handed_to_git() {
  repo
  touch_files README.md
  commit "change prose"
  export AFTER="--output=$SANDBOX/written"
  run_block "$BLOCK"
  assert_failed_with_no_output
  if [ -e "$SANDBOX/written" ]; then
    printf 'FAIL: the pushed commit reached git as an option\n' >&2
    exit 1
  fi
}

# A merged pull request's author chose these names, and a valid path can
# spell a workflow command.
test_a_file_name_reaches_the_log_encoded_and_between_stop_commands() {
  repo
  touch_files $'docs/x\n::error::forged'
  commit "add an awkward name"
  run_block "$BLOCK"
  assert_status 0
  assert_output workflows false
  assert_output_contains '"docs/x\n::error::forged"'
  if printf '%s\n' "$RUN_OUTPUT" | grep -q '^::error::forged'; then
    printf 'FAIL: a file name started a log line of its own\n---- output ----\n%s\n' "$RUN_OUTPUT" >&2
    exit 1
  fi
  local stop names
  stop=$(printf '%s\n' "$RUN_OUTPUT" | grep -n '^::stop-commands::' | cut -d: -f1)
  names=$(printf '%s\n' "$RUN_OUTPUT" | grep -n 'forged' | cut -d: -f1)
  if [ -z "$stop" ] || [ "$names" -le "$stop" ]; then
    printf 'FAIL: the names were printed outside stop-commands\n---- output ----\n%s\n' "$RUN_OUTPUT" >&2
    exit 1
  fi
}

run_tests
