#!/usr/bin/env bash
# The registry half of release-go.yml's input validation.
#
# The App-credential half is covered for every guarded workflow at once in
# credential-validation.test.sh; this suite covers the rule that is release-go's
# own. It exists so a caller learns before anything is built that the login
# ahead cannot succeed, rather than from an opaque `docker login` failure
# partway through a release.

set -uo pipefail
# shellcheck source=ci/tests/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

WORKFLOW="release-go.yml"

# The defaults, which every test below then varies one value of.
guard_env() {
  export HAS_PARTIAL_APP_AUTH="false"
  export HAS_APP_AUTH="false"
  export HAS_REGISTRY_AUTH="false"
  export REGISTRY=""
}

run_guard() {
  run_block "$(extract_run "$WORKFLOW" release 'Validate inputs')"
}

# The default: no registry at all, no login step, nothing to validate.
test_no_registry_needs_no_registry_credentials() {
  guard_env
  run_guard
  assert_status 0
}

# ghcr.io accepts the job's own token, so a caller pushing there supplies
# nothing. Requiring secrets for it would reject the common case.
test_ghcr_needs_no_registry_credentials() {
  guard_env
  export REGISTRY="ghcr.io"
  run_guard
  assert_status 0
}

test_another_registry_without_credentials_is_refused() {
  guard_env
  export REGISTRY="docker.io"
  run_guard
  assert_status 1
  assert_output_contains "REGISTRY_USERNAME and REGISTRY_PASSWORD are required"
  # Named, because a caller reading only the message has to know which of the
  # several registries in their configuration this is about.
  assert_output_contains "docker.io"
}

test_another_registry_with_credentials_is_accepted() {
  guard_env
  export REGISTRY="docker.io"
  export HAS_REGISTRY_AUTH="true"
  run_guard
  assert_status 0
}

# Both guards live in one step, and the App one runs first. A caller who has
# half-configured the App *and* forgotten the registry secrets should be told
# about the credential downgrade rather than about the registry, because the
# credential downgrade is the one that would otherwise happen silently.
test_partial_app_credentials_are_reported_before_the_registry() {
  guard_env
  export HAS_PARTIAL_APP_AUTH="true"
  export REGISTRY="docker.io"
  run_guard
  assert_status 1
  assert_output_contains "must be supplied together"
  assert_output_lacks "REGISTRY_USERNAME and REGISTRY_PASSWORD are required"
}

run_tests
