# Authentication

Some workflows need a GitHub credential beyond the automatic one. Three modes are supported, and they can coexist.

## Which mode do I need?

Start at the top and stop at the first row that matches.

| If you…                                                                                 | Use                            | Secrets to set                     |
| --------------------------------------------------------------------------------------- | ------------------------------ | ---------------------------------- |
| only build, test, scan, or push to GHCR                                                 | **`GITHUB_TOKEN`** — automatic | none                               |
| need release or chart pull requests to run CI                                           | **GitHub App** (or `GH_PAT`)   | `APP_CLIENT_ID`, `APP_PRIVATE_KEY` |
| need automerge                                                                          | **GitHub App** (or `GH_PAT`)   | `APP_CLIENT_ID`, `APP_PRIVATE_KEY` |
| need to dispatch a workflow in **another** repository (`update-helm-chart` caller mode) | **GitHub App** (or `GH_PAT`)   | `APP_CLIENT_ID`, `APP_PRIVATE_KEY` |
| need chart releases to fire `release:` triggers (`release-helm`)                        | **GitHub App** (or `GH_PAT`)   | `APP_CLIENT_ID`, `APP_PRIVATE_KEY` |
| hit GitHub API rate limits during Trivy scans                                           | **GitHub App** (or `GH_PAT`)   | `APP_CLIENT_ID`, `APP_PRIVATE_KEY` |
| hit GitHub API rate limits **inside a Docker build**                                    | **GitHub App** (or `GH_PAT`)   | the two above, **plus** [`BUILD_SECRET_GITHUB_TOKEN`](#what-build-docker-actually-injects) |
| already have `GH_PAT` working and don't want to change                                  | **`GH_PAT`** — still supported | `GH_PAT`                           |

Rows marked *(or `GH_PAT`)* work with either credential — set `GH_PAT` instead of the two `APP_*` secrets. The App is recommended because it is scoped per job, expires hourly and is not tied to a person; see [Trade-offs versus a GitHub App](#trade-offs-versus-a-github-app).

**All three modes are accepted by every workflow that takes a credential**, and the resolution order is normally:

```
App token  →  GH_PAT  →  GITHUB_TOKEN
```

Each step falls through only when the one before it is absent, so adding a credential never removes a capability and removing one never breaks more than it enabled. If both an App and a PAT are configured, **the App wins** — which makes migration a switch you can verify before deleting the PAT.

Supplying only one of `APP_CLIENT_ID` / `APP_PRIVATE_KEY` is never valid and **fails the job** rather than falling through; see [Both App secrets or neither](#both-app-secrets-or-neither).

### Where the chain stops early

Three cases do not run to the end of that chain, and each fails with a pointed message instead of silently doing less than you asked:

| Case                                                        | Stops at              | Why                                                                        |
| ----------------------------------------------------------- | --------------------- | -------------------------------------------------------------------------- |
| Automerge (`release-app`, `update-helm-chart`)              | App token or `GH_PAT` | `GITHUB_TOKEN` cannot merge a pull request                                 |
| Cross-repository dispatch (`update-helm-chart` caller mode) | App token or `GH_PAT` | `GITHUB_TOKEN` is scoped to its own repository                             |
| `build-docker`'s build secret                               | wherever you say      | The value is readable by everything the Dockerfile runs, so you name the credential rather than letting it fall through — see [What `build-docker` actually injects](#what-build-docker-actually-injects) |

## Why the App mode exists

`GITHUB_TOKEN` is deliberately prevented from triggering other workflows, so automation cannot loop. The side effect is that a pull request opened with `GITHUB_TOKEN` **never runs `pull_request` workflows** — release pull requests merge with no checks having run.

A GitHub App installation token is not subject to that rule, so automated pull requests behave like human ones. It also has more rate-limit headroom: 5,000 requests/hour against 1,000/hour per repository for `GITHUB_TOKEN`.

## Mode 1: `GITHUB_TOKEN`

**Create:** nothing. **Store:** nothing. **Pass:** nothing. Every job receives one automatically; the `permissions:` block is the only thing you configure.

A complete pipeline that needs no secret at all:

```yaml
name: CI

on:
  pull_request:
    branches:
    - main

jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile

  scan:
    needs: build
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-app:pr-${{ github.event.pull_request.number }}
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

What you give up by staying here:

| Limit                              | What you see                                                     |
| ---------------------------------- | ---------------------------------------------------------------- |
| Cannot trigger workflows           | Release and chart pull requests open with **no checks**          |
| 1,000 requests/hour per repository | Large build matrices fail mid-run with `403 rate limit exceeded` |
| Cannot merge pull requests         | `AUTOMERGE_*: true` fails the job                                |

If none of those bite you, stop here — this is the mode to prefer.

## Mode 2: GitHub App

Everything below is one-time setup. It works identically under a personal account and an organization.

### Step 1: Create the App

**Settings → Developer settings → GitHub Apps → New GitHub App.**

| Field                                      | Value                                                                                     |
| ------------------------------------------ | ----------------------------------------------------------------------------------------- |
| **GitHub App name**                        | Anything unique — it becomes the pull request author, e.g. `my-org-ci` → `my-org-ci[bot]` |
| **Homepage URL**                           | Any valid URL. Not used; your repository URL is fine                                      |
| **Webhook → Active**                       | **Uncheck it.** These workflows do not receive webhooks                                   |
| **Where can this GitHub App be installed** | *Only on this account*                                                                    |

**One App is enough.** Grant it the union of what your workflows need:

| Permission    | Access         | Needed for                           |
| ------------- | -------------- | ------------------------------------ |
| Metadata      | Read-only      | Mandatory for every App              |
| Contents      | Read and write | Commits, tags, releases              |
| Pull requests | Read and write | Open and merge pull requests         |
| Issues        | Read and write | release-please labels                |
| Actions       | Read and write | `update-helm-chart` caller mode only |

Each workflow then mints its own token narrowed to just what that job needs:

| Workflow                               | Token narrowed to                             | Scope                 |
| -------------------------------------- | --------------------------------------------- | --------------------- |
| `release-app.yml`                      | `contents`, `pull-requests`, `issues` = write | current repository    |
| `update-helm-chart.yml` (called/local) | `contents`, `pull-requests` = write           | current repository    |
| `update-helm-chart.yml` (caller)       | `actions: write`                              | chart repository only |
| `release-helm.yml`                     | `contents: write`                             | current repository    |
| `build-docker.yml`                     | `contents`, `metadata` = read                 | current repository    |
| `scan-trivy.yml`                       | `contents`, `metadata` = read                 | current repository    |

One App, one private key, many differently-scoped tokens.

> **The narrowing is load-bearing.** When a token is minted without `permission-*` values it inherits **every permission the installation has**. That is why `build-docker.yml` always requests `contents: read` explicitly: its token is mounted into the Docker build, where every install script, package postinstall hook and prebuilt binary the Dockerfile runs can read it. If you add a mint step, narrow it.

#### How the repository scope is decided

Permissions answer *what* a token may do. `owner` and `repositories` answer *where*. `actions/create-github-app-token` resolves them like this:

| `owner` | `repositories` | Resulting scope |
| ------- | -------------- | --------------- |
| unset | unset | **The current repository only** |
| set | unset | **Every repository in that owner's installation** ⚠️ |
| set | set | Exactly the repositories listed |

> [!CAUTION]
> **Setting `owner` without `repositories` widens the token to the whole installation** — at the installation's full permissions, not the current job's. It is the one line that turns a single-repository token into an organization-wide one, and it looks harmless.

Every same-repository mint in these workflows therefore leaves **both unset**. Only `update-helm-chart.yml` in caller mode sets them, because it genuinely targets another repository, and it sets them **together**.

That may look like relying on a default where being explicit would be safer. It is deliberate, because the failure modes are not symmetric:

- **Leaving both unset:** widening requires someone to *add* a line. An addition is visible in review and cannot happen by accident.
- **Setting both explicitly:** widening requires someone to *remove* or empty one line. A bad merge, a refactor, or an expression that renders empty silently produces an installation-wide token — and nothing fails or warns.

Accidental deletion is far likelier than accidental addition, so the unset form is the one that fails safe. There is also no clean way to write it: Actions expressions have no `split()`, and `github.repository` is `owner/repo`, so pinning `repositories` to the current repository means either `github.event.repository.name` (which depends on the triggering event's payload) or an extra `run` step per job — real complexity for a value the action already derives correctly.

**If you add a mint step, copy an existing one.** Set `permission-*` for what the job needs, and leave `owner`/`repositories` alone unless you are deliberately crossing into another repository — in which case set both.

<details>
<summary>Optional hardening: a separate build App</summary>

Per-mint narrowing bounds what a leaked *token* can do. It does not bound what a leaked *private key* can do — a key mints any permission the installation holds.

The key is never exposed to the Docker build (only the minted token is), so this is defence in depth rather than a fix for a specific hole. If you want that extra margin, create a second App with only **Metadata: read** and **Contents: read**, install it on the repositories that build images, and pass its credentials to `build-docker.yml`. A key leaked from there mints nothing but reads.

Worked example: [Two Apps: isolate the build credential](#two-apps-isolate-the-build-credential).

</details>

### Step 2: Generate a private key

At the bottom of the App's settings, **Generate a private key**. A `.pem` downloads — it cannot be retrieved again. Anyone holding it can mint tokens for every repository the App is installed on, at any permission the installation has.

### Step 3: Install it

**Install App → Only select repositories →** pick the repositories that run these workflows. Install as narrowly as you can: the installation list, not the per-mint narrowing, is what bounds a leaked private key.

### Step 4: Store the secrets

Per repository: **Settings → Secrets and variables → Actions → New repository secret.**

| Name              | Value                                                           |
| ----------------- | --------------------------------------------------------------- |
| `APP_CLIENT_ID`   | the App's **Client ID** (looks like `Iv23li…`)                  |
| `APP_PRIVATE_KEY` | the whole `.pem`, including the `-----BEGIN…`/`-----END…` lines |

> The **Client ID**, not the numeric App ID. Both appear on the App's settings page and only one of them works. Using the App ID is the single most common setup mistake — see [Troubleshooting](#troubleshooting).

The same two secrets serve every workflow.

### Step 5: Wire it up

A complete release pipeline. Every job that accepts App credentials gets the same two secrets; each one mints its own narrowed token internally.

```yaml
name: CD

on:
  push:
    branches:
    - main

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_RELEASE: true
      AUTOMERGE_METHOD: auto
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

  build:
    needs: release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: ${{ needs.release.outputs.version }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      # Raises the API budget for mise/aqua/ubi inside the build. Mints a
      # separate read-only token; see the warning under Step 1. 'app' fails
      # rather than falling back to a credential it cannot narrow.
      BUILD_SECRET_GITHUB_TOKEN: app
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

  bump-chart:
    needs: release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-app
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: patch
      AUTOMERGE_RELEASE: true
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

  release-chart:
    needs:
    - release
    - bump-chart
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CHARTS_DIR: ./charts
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

`scan-trivy.yml` takes the same two secrets and uses them only to raise Trivy's database-download budget — add them to the CI example in Mode 1 unchanged.

### Step 6: Verify

Push a commit that produces a release. Three things should be visibly different:

1. The release pull request is authored by `your-app-name[bot]`, not `github-actions[bot]`.
2. It **has checks** — the CI that never ran on release pull requests now runs.
3. Each job log shows a *Generate GitHub App token* step that ran rather than being skipped. If it was skipped, the secrets did not reach the workflow.

> **Expect the first release to surface failures.** Checks that never ran before now run, and some may have been broken for a while. That is the feature working, not the setup being wrong.

## Mode 3: Personal access token

Accepted by every workflow that takes a credential, in the same places as an App token and resolved just after it. Reach for this when you already have a PAT working, or when creating an App is not worth it for what you need.

### Step 1: Create the token

**Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token.** Scope it to *Only select repositories* and grant only the rows that match what you actually use:

| Permission    | Access         | Needed for                                                                        |
| ------------- | -------------- | --------------------------------------------------------------------------------- |
| Contents      | Read           | `build-docker` build secret, `scan-trivy` database download                       |
| Contents      | Read and write | `release-app`, `release-helm`, `update-helm-chart` — push commits, tags, releases |
| Pull requests | Read and write | Automerge in `release-app` and `update-helm-chart`                                |
| Actions       | Read and write | `update-helm-chart` caller mode only — grant on the **chart** repository          |

A classic token with the **`repo`** scope also works, but grants access to every repository the account can reach.

> **Use a read-only token for `build-docker`.** Its value is mounted into the Docker build, where every install script, package postinstall hook and prebuilt binary the Dockerfile runs can read it. `BUILD_SECRET_GITHUB_TOKEN: pat` accepts a `GH_PAT` but still refuses to fall through to the job's `GITHUB_TOKEN`, so scope the PAT to `Contents: read` and nothing more. If you have no App and no rate-limit problem to solve, leave it at `none`. See [What `build-docker` actually injects](#what-build-docker-actually-injects).

### Step 2: Store it

**Settings → Secrets and variables → Actions → New repository secret**, named `GH_PAT`.

### Step 3: Wire it up

The same pipeline as Mode 2, with one secret instead of two:

```yaml
name: CD

on:
  push:
    branches:
    - main

jobs:
  release:
    uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
    permissions:
      contents: write
      issues: write
      pull-requests: write
    with:
      TAG_MAJOR_AND_MINOR: true
      AUTOMERGE_RELEASE: true
      AUTOMERGE_METHOD: auto
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}

  build:
    needs: release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ghcr.io/my-org/my-app
      IMAGE_TAG: ${{ needs.release.outputs.version }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      # 'pat' accepts GH_PAT but still refuses to fall through to the job's
      # GITHUB_TOKEN. Use 'job-token' if you deliberately want that fallback.
      BUILD_SECRET_GITHUB_TOKEN: pat
    # Read-only token here — see the warning under Step 1.
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}

  bump-chart:
    needs: release
    if: ${{ needs.release.outputs.release-created == 'true' }}
    uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
    permissions:
      contents: write
      pull-requests: write
    with:
      RUN_MODE: called
      CHART_NAME: my-app
      APP_VERSION: ${{ needs.release.outputs.version }}
      UPGRADE_TYPE: patch
      AUTOMERGE_RELEASE: true
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}

  release-chart:
    needs:
    - release
    - bump-chart
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CHARTS_DIR: ./charts
    secrets:
      GH_PAT: ${{ secrets.GH_PAT }}
```

### Trade-offs versus a GitHub App

A PAT is functionally equivalent — it triggers workflows, so release pull requests do get CI, and it raises the rate limit the same way. What differs:

- It acts as **you**. Every commit, tag and merge is attributed to your account, and it carries your access to every selected repository.
- It shares one 5,000 requests/hour budget across everything you do on GitHub, rather than getting its own per-installation budget.
- It expires. Fine-grained tokens last at most a year and the pipeline breaks the day they lapse. App tokens are minted per job and expire in an hour by design; the private key behind them does not expire at all.
- It cannot be narrowed per job. An App mints a token carrying only what that job needs; a PAT carries everything it was created with, everywhere it is used.

## Advanced

### Cross-repository dispatch (`update-helm-chart` caller mode)

Caller mode dispatches a workflow in a **different** repository, so the token is minted scoped to that repository — which means the App must be installed on the **chart** repository, not the one running the workflow.

```yaml
trigger-chart-update:
  uses: this-is-tobi/github-workflows/.github/workflows/update-helm-chart.yml@v0
  # Caller mode needs no GITHUB_TOKEN scopes: the dispatch is authenticated
  # entirely by the App token (or GH_PAT), which the job mints itself.
  permissions: {}
  with:
    RUN_MODE: caller
    WORKFLOW_NAME: update-app-version.yml
    CHART_REPO: my-org/helm-charts
    CHART_NAME: my-app
    APP_VERSION: 1.4.0
    UPGRADE_TYPE: minor
  secrets:
    APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
    APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

Checklist for this one:

|                   |                                                           |
| ----------------- | --------------------------------------------------------- |
| App installed on  | `my-org/helm-charts` (the value of `CHART_REPO`)          |
| App permission    | **Actions: Read and write**                               |
| Secrets stored in | the repository running this job, not the chart repository |
| Token scope       | `CHART_REPO` only — never the current repository          |
| `CHART_REPO` form | `owner/repository` — a bare name fails validation          |

#### `AUTOMERGE_METHOD` across the dispatch

Caller mode does not merge anything itself; it hands the work to the chart repository, which runs `update-helm-chart.yml` in `called` mode and merges there. `AUTOMERGE_METHOD` is forwarded with the dispatch so the choice still belongs to the caller.

That requires the chart repository's entry-point workflow to **declare an `AUTOMERGE_METHOD` input**. If it does not, GitHub rejects the whole dispatch (`422 Unexpected inputs provided`) rather than ignoring the extra value. So the caller retries once without it and warns:

```
::warning::'update-app-version.yml' in 'my-org/helm-charts' does not declare an
AUTOMERGE_METHOD input, so the chart repository's own default applies
```

The dispatch still succeeds — the chart repository just uses its own default (`auto`). To control the method from the app side, add the input to the entry-point workflow; the template in [Global workflow examples](./90-global-workflows-examples.md#update-app-version-workflow) already includes it.

### Two Apps: isolate the build credential

Optional hardening from Step 1. Create a second App with only **Metadata: read** and **Contents: read**, store its credentials under different secret names, and map them at each call site:

```yaml
release:
  uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
  permissions:
    contents: write
    issues: write
    pull-requests: write
  secrets:
    APP_CLIENT_ID: ${{ secrets.RELEASE_APP_CLIENT_ID }}
    APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

build:
  uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
  permissions:
    packages: write
    contents: read
    id-token: write
    attestations: write
  with:
    IMAGE_NAME: ghcr.io/my-org/my-app
    IMAGE_CONTEXT: ./
    IMAGE_DOCKERFILE: ./Dockerfile
    BUILD_SECRET_GITHUB_TOKEN: app
    # Different App: a key leaked from the build mints nothing but reads.
  secrets:
    APP_CLIENT_ID: ${{ secrets.BUILD_APP_CLIENT_ID }}
    APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

The workflow input names never change — only which secret you map into them.

### Migrating from a PAT

The App takes precedence when both are present, so you can verify the switch before removing anything. Pass both for one release:

```yaml
release:
  uses: this-is-tobi/github-workflows/.github/workflows/release-app.yml@v0
  permissions:
    contents: write
    issues: write
    pull-requests: write
  with:
    AUTOMERGE_RELEASE: true
  secrets:
    APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
    APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
    # Kept for one run only. Unused while the App credentials resolve.
    GH_PAT: ${{ secrets.GH_PAT }}
```

Confirm the pull request author changed to `your-app-name[bot]`, then delete the `GH_PAT:` line and the secret. If anything goes wrong, removing the two `APP_*` lines falls straight back to the PAT with no other change.

## Automerge

Automerge runs when `AUTOMERGE_RELEASE` / `AUTOMERGE_PRERELEASE` is true. It is gated on those inputs alone — adding App credentials never switches merging on by itself. If automerge is enabled and no credential is supplied, the job **fails** rather than silently not merging.

`AUTOMERGE_METHOD` chooses how:

| Value            | Behaviour                                                                      | Requirement                                        |
| ---------------- | ------------------------------------------------------------------------------ | -------------------------------------------------- |
| `auto` (default) | Queues the PR; GitHub merges it once required status checks pass               | **Allow auto-merge** enabled in Settings → General |
| `admin`          | Merges immediately, **bypassing branch protection and required status checks** | The actor must be able to bypass protection        |

`auto` is the default because the point of App authentication is that release pull requests finally run CI — merging with `admin` would ignore the result. There is no automatic fallback between them: if `auto` is selected and auto-merge is not enabled on the repository, the job fails with a message telling you which setting to flip.

## The thing that trips everyone up

**Job `permissions:` do not apply to the App token.**

```yaml
permissions:
  contents: write # governs GITHUB_TOKEN only
```

That block controls `GITHUB_TOKEN`. An App token's authority comes from what the App installation was granted, narrowed by the `permission-*` values the workflow requests. Widening `permissions:` will never fix an App-token permission error. Two separate systems, same word — when you hit a permission error, check the App's installation settings, not the workflow YAML.

## Troubleshooting

| Symptom                                               | Cause                                                                  | Fix                                                                            |
| ----------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `Input required and not supplied: private-key`        | Secrets not passed through the calling job's `secrets:` block          | Reusable workflows do not inherit secrets automatically — pass them explicitly |
| `Resource not accessible by integration`              | The App lacks the permission, or is not installed on the repository    | Check the **installation**, not job `permissions:`                             |
| `HttpError: Not Found` when minting                   | App not installed on the owner/repository requested                    | Install it, or correct `CHART_REPO`                                            |
| Automerge fails asking for 'Allow auto-merge'         | `AUTOMERGE_METHOD=auto` with the repository setting off                | Enable it in Settings → General, or set `AUTOMERGE_METHOD: admin`              |
| `Automerge is enabled but no credential was supplied` | `AUTOMERGE_*` is true with no App or PAT                               | Supply credentials, or set `AUTOMERGE_*: false`                                |
| Token works, then fails ~an hour later                | Installation tokens expire after 1 hour                                | They are minted per job; never pass one between jobs                           |
| Nothing changed after adding secrets                  | Wrong secret name, or the numeric App ID used instead of the Client ID | Check the "Generate GitHub App token" step ran instead of being skipped        |
| `APP_CLIENT_ID and APP_PRIVATE_KEY must be supplied together` | One of the two is missing, empty, or misspelled at the call site | Pass both, or neither — see [Both App secrets or neither](#both-app-secrets-or-neither) |
| `CHART_REPO must be 'owner/repository'`               | `CHART_REPO` given without an owner, e.g. `helm-charts`                | Use the full `owner/repo` form                                                 |
| Caller mode warns that `AUTOMERGE_METHOD` is not declared | The chart repository's entry-point workflow predates the input     | Add `AUTOMERGE_METHOD` to its `workflow_dispatch`/`workflow_call` inputs        |

### Both App secrets or neither

`APP_CLIENT_ID` and `APP_PRIVATE_KEY` are only useful together. Supplying exactly one is always a mistake — a typo at the call site, or a secret that was never created — and the resolution order would quietly answer it with `GH_PAT` or `GITHUB_TOKEN` instead. You would get a green run that authenticated as something other than the App, which is the failure mode this whole page exists to avoid.

Every job that mints a token therefore **fails immediately** when exactly one is present, before any work happens:

```
::error::APP_CLIENT_ID and APP_PRIVATE_KEY must be supplied together, but only one was.
```

Supplying **neither** is a supported configuration, not an error: that is Mode 1 or Mode 3.

## What `build-docker` actually injects

`BUILD_SECRET_GITHUB_TOKEN` mounts a credential at `/run/secrets/github_token`, readable by every install script, package postinstall hook and prebuilt binary the Dockerfile runs. This is the one place where the usual App → `GH_PAT` → `GITHUB_TOKEN` fallback would be actively harmful, because **the three are not equally tight and the last one is the widest**. So here you name the credential instead:

| Value       | Resolves to                                    | Narrowed to                                               | Narrowed by                   |
| ----------- | ---------------------------------------------- | --------------------------------------------------------- | ----------------------------- |
| `none`      | nothing injected *(default)*                   | —                                                          | —                             |
| `app`       | App token; **fails** if absent                 | `contents: read` + `metadata: read`, this repository only | This workflow, at mint time   |
| `pat`       | App token, else `GH_PAT`; **fails** if neither | Whatever you granted the PAT                              | You                           |
| `job-token` | App token, else `GH_PAT`, else `GITHUB_TOKEN`  | **Nothing** — the calling job's whole `permissions:` block | Nobody; it cannot be narrowed |

A job calling `build-docker.yml` normally grants `packages: write`, `id-token: write` and `attestations: write`, so `job-token` can hand a registry-push credential to everything in the build. A compromised transitive build dependency could publish an image with it. The workflow emits a `::warning::` whenever that mode actually falls through to the job token.

**Can't `GITHUB_TOKEN` just be narrowed for this?** No. Its permissions are fixed when the job starts, from the `permissions:` block intersected with what the caller granted, and there is no API to attenuate it for a single step. The build job needs `packages: write` to push the image, so that is what the token carries. Minting a separate, narrower App token is the only way to inject something read-only — which is exactly what `app` does.

Preference order: **`app` → `pat` (read-only) → `none`.** Reach for `job-token` only deliberately.

## Loop safety

**App tokens and PATs both trigger workflows** — that is the point, and it is also the risk. `GITHUB_TOKEN` is the only mode this section does not apply to. Three rules the workflows follow, worth knowing if you modify them:

- **`actions/checkout` keeps `GITHUB_TOKEN`.** These workflows push tags, prerelease branches and chart bumps with `git`. Under a credential that can trigger workflows, those pushes would re-enter the caller's CD pipeline. Only the steps that genuinely need the elevated credential receive it.
- **The chart bump commit carries `[skip ci]`.** In `local` mode the chart bump is pushed straight to the branch CD triggers on. `[skip ci]` is read from the commit message, so it holds regardless of which credential pushed — the one guard that does not depend on token choice.
- **`release-helm.yml` pushes the pages branch with the same token it creates releases with.** Supplying either elevated credential lets that push trigger workflows too, not only the release creation. Check nothing triggers on your `PAGES_BRANCH` first.

### What the checkout rule does *not* cover

Keeping `GITHUB_TOKEN` on `actions/checkout` bounds **`git` pushes only**. Anything an action creates through the API uses that action's own token, and under App or PAT auth those events fire normally:

| Created by                                     | Credential           | Triggers workflows?         |
| ---------------------------------------------- | -------------------- | --------------------------- |
| `git push` of the `v1` / `v1.2` tags           | Checkout's token     | No                          |
| `git push` of the prerelease branch            | Checkout's token     | No                          |
| `git push` of the `local`-mode chart bump      | Checkout's token     | No — and `[skip ci]` on top |
| release-please's `vX.Y.Z` tag and Release      | App token / `GH_PAT` | **Yes**                     |
| The release pull request                       | App token / `GH_PAT` | **Yes** — this is the point |
| The chart update pull request                  | App token / `GH_PAT` | **Yes** — this is the point |
| The push of the chart update *branch* itself   | App token / `GH_PAT` | **Yes**                     |

So before switching a repository to an App or a PAT, check what it triggers on. `on: pull_request:` is what you are turning on deliberately. `on: push: tags:` and `on: release:` will start firing too, and that is easy to miss — under `GITHUB_TOKEN` they never did.

The last row is the one that surprises people: `create-pull-request` pushes the `<chart-name>-v<version>` branch with the same token it opens the pull request with, so a workflow triggering on `push:` with a broad branch pattern (`'**'`, or anything matching that name) starts firing once you supply an elevated credential. Scope such patterns to the branches you actually mean.

## Security notes

- The private key is long-lived, usable outside Actions, and mints tokens for every repository the App is installed on. Its reach is **narrower than a classic PAT** but **wider than `GITHUB_TOKEN`** — install narrowly and keep the key in as few repositories as possible.
- Tokens are minted per job, scoped to the current repository, and narrowed with `permission-*` to what that job needs — a token omitting `permission-*` would inherit every permission the installation holds. They are never written to `GITHUB_OUTPUT`, `GITHUB_ENV`, or job outputs.
- Repository scope comes from leaving `owner` and `repositories` unset, which the action resolves to the current repository. Setting `owner` alone would widen a token to the entire installation — see [How the repository scope is decided](#how-the-repository-scope-is-decided) before adding or editing a mint step.
- Fork pull requests receive no repository secrets, so no App credential can reach a fork-triggered build. Adding `pull_request_target` or `secrets: inherit` to a fork-reachable job would break that guarantee.
- Rotate by generating a second private key, updating the secret, then deleting the first. Both are valid in between, so there is no downtime.
