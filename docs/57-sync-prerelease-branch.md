# `sync-prerelease-branch.yml`

Re-synchronise the prerelease branch onto the release branch after a release, by rebasing it.

This workflow maintains a single invariant:

> **The prerelease branch is the release branch plus only the work that has not been released yet.**

## Why a separate workflow

A release lands commits on the release branch that the prerelease branch does not have:

- release-please's `chore(main): release X.Y.Z` — edits the manifest and `CHANGELOG.md`
- [`update-helm-chart.yml`](./53-update-helm-chart.md)'s `chore(chart): release ...` in `local` mode — edits `Chart.yaml` and the chart README

The prerelease branch edits **those same files** on its own `rc` cycle. If it never receives them, both branches write competing lines from a common ancestor, and two things break:

1. Versions computed on the prerelease branch start from a stale base — and can fall **below** the version already published.
2. The next rebase and the next promotion conflict on those files.

The only thing that decides when it is correct to re-synchronise is "has the release branch stopped moving?", and **only the caller's job graph knows that**. Hence a job you place last, rather than an input on a workflow that cannot see the graph — that second form is silently wrong for any pipeline that commits to the release branch after its release job, a monorepo chart bump being the usual case.

## Inputs

| Input             | Type    | Description                                                                                                                              | Required | Default          |
| ----------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| RELEASE_BRANCH    | string  | Branch releases are cut on, and the branch to synchronise **from**                                                                        | No       | main             |
| PRERELEASE_BRANCH | string  | Branch prereleases are cut on, and the branch being synchronised                                                                          | No       | develop          |
| CREATE_IF_MISSING | boolean | Create `PRERELEASE_BRANCH` from `RELEASE_BRANCH` when it does not exist yet, rather than skipping. Bootstraps a repository adopting the two-branch flow. | No       | true             |
| PRERELEASE_CONFIG_FILE | string | Release-please config of the prerelease branch, **the same value as [`release-app.yml`](./50-release-app.md)'s input**. It lists the files release-please rewrites, and records the release anchor ([see below](#release-anchor-after-a-rebase)) | No | release-please-config-rc.json |
| PRERELEASE_MANIFEST_FILE | string | Release-please manifest of the prerelease branch, the same value as `release-app.yml`'s input | No | .release-please-manifest-rc.json |
| RELEASE_MANIFEST_FILE | string | Release-please manifest of the release branch, the same value as `release-app.yml`'s input | No | .release-please-manifest.json |
| MANAGED_FILES     | string  | Files a release rewrites on the release branch that the prerelease branch also rewrites on its own cycle, one path or glob per line, beyond what the release-please config already lists (manifests, changelogs, `extra-files`): the version file the `release-type` itself bumps (`version.txt` for `simple`, `package.json` for `node`, `Chart.yaml` for `helm`), and `Chart.yaml` and the chart README when the chart lives in the repository. See [Conflicts on files a release rewrites](#conflicts-on-files-a-release-rewrites) | No | empty |
| RUNS_ON           | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                  | No       | ["ubuntu-24.04"] |

## Secrets

None is required: by default the push goes out with the job's `GITHUB_TOKEN`.

| Secret          | Description                                                                                                         | Required |
| --------------- | ------------------------------------------------------------------------------------------------------------------- | -------- |
| APP_CLIENT_ID   | GitHub App Client ID (`Iv23li...`, not the numeric App ID). Supply with `APP_PRIVATE_KEY`                            | No       |
| APP_PRIVATE_KEY | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                                                    | No       |

Supplying them makes the push go out with an App token, see [When rulesets reject `GITHUB_TOKEN`](#when-rulesets-reject-github_token). Supplying only one of the two fails the job rather than silently falling back to `GITHUB_TOKEN`.

## Permissions

| Scope    | Access | Description                          |
| -------- | ------ | ------------------------------------ |
| contents | write  | Push the rebased prerelease branch   |

With an App, the minted token is narrowed to `contents: write` on the current repository.

## When rulesets reject `GITHUB_TOKEN`

The push (creating the prerelease branch, or `--force-with-lease` after the rebase) is subject to the rulesets of that branch. A ruleset that requires a pull request for every push, forbids non-fast-forward pushes, requires a linear history or required status checks — including on creation — rejects `GITHUB_TOKEN`, which cannot be named in a bypass list. Only a GitHub App can.

In that case, pass the credentials of an App that is in the bypass list:

```yaml
  sync-prerelease-branch:
    uses: this-is-tobi/github-workflows/.github/workflows/sync-prerelease-branch.yml@v0
    # needs, if, permissions, with: as above
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

**The trade-off: the push can start the caller's CD.** An App token, unlike `GITHUB_TOKEN`, triggers workflows. Moving the prerelease branch then starts the workflows that run on it. Only do it if a CD run on that branch that finds nothing new to release is harmless for your pipeline — which release-please, being idempotent, is.

## Where to put it

**Last**, with a `needs:` listing **exactly** the jobs that commit to the release branch — all of them, and nothing else. That is the whole rule.

Missing one leaves the prerelease branch stale. Adding one that commits nothing does not make it safer: it only lets that job's failure skip the sync.

```yaml
  sync-prerelease-branch:
    uses: this-is-tobi/github-workflows/.github/workflows/sync-prerelease-branch.yml@v0
    needs:
    - release            # commits `chore(main): release ...`
    - bump-chart-local   # commits `chore(chart): release ...`
    # build-docker and release-charts are deliberately absent: they commit
    # nothing, and listing them would let a failed build or a failed publish
    # skip the sync. Ordering still holds - bump-chart-local already needs
    # build-docker.
    if: ${{ github.ref_name == 'main' && needs.release.outputs.release-created == 'true' }}
    permissions:
      contents: write
    with:
      RELEASE_BRANCH: main
      PRERELEASE_BRANCH: develop
      # The same values as the ones passed to release-app.yml, when they are not the defaults:
      # PRERELEASE_CONFIG_FILE: .github/releases/release-please-config-prerelease.json
      # PRERELEASE_MANIFEST_FILE: .github/releases/.release-please-manifest-prerelease.json
      # RELEASE_MANIFEST_FILE: .github/releases/.release-please-manifest.json
      # A chart in the repository: bump-chart-local rewrites these files on the release branch
      # MANAGED_FILES: |
      #   charts/my-app/Chart.yaml
      #   charts/my-app/README.md
```

### By repository shape

| Repository shape              | Commits on the release branch after the release job | This job |
| ----------------------------- | ---------------------------------------------------- | -------- |
| App only (no chart)           | none                                                 | `needs: [release]` |
| App + local chart (monorepo)  | the chart bump                                       | `needs: [..., bump-chart-local]` |
| App + chart in another repo   | none — the bump lands in the *other* repository       | `needs: [release]` |
| Chart repository, single branch | —                                                  | not needed |

## Conflicts on files a release rewrites

When the release branch has moved (a hotfix and its release, say), the rebase replays the unreleased work on top. The prerelease branch's release commits — `chore(develop): release 1.1.0-rc.1`, the chart bump — rewrite the same lines as those of the release branch: manifests, `CHANGELOG.md`, the version in `Chart.yaml`. Those conflicts are structural: they are on bookkeeping lines whose right value is known in advance, the prerelease branch's, since its next versions are computed from that state.

The job therefore settles by itself the conflicts **confined to those files**: both manifests, the changelog, the `extra-files` listed in `PRERELEASE_CONFIG_FILE`, and what the caller adds through `MANAGED_FILES`. The merge is done **hunk by hunk** (`git merge-file` on the three stages of the file), not by taking a whole side: what the release branch changed *outside* the conflicting hunks — a dependency fixed by the hotfix in the same file, a changelog section — is kept. For the conflicting hunks:

| File | Side kept |
| --- | --- |
| prerelease manifest, `extra-files`, `MANAGED_FILES` files | the prerelease branch |
| changelog (`changelog-path` of the config, or any file called `*changelog*`) | both sides: a history is not chosen from. The prerelease sections go above the release branch's, newest first, with the blank line between sections that the merge itself would trim |
| release manifest (`RELEASE_MANIFEST_FILE`) | the release branch: it records what it published |

**Nothing is dropped without a trace.** Taking a side drops the other side's lines in the conflicting hunk: a hotfix edit on the very line the prerelease branch also changed would otherwise vanish. Each such hunk is written to the job log (a group named after the number of hunks), reported as a `notice` annotation on the run, and listed in the job summary as a diff: `-` lines were dropped, `+` lines kept in their place, under a header naming the file, the line and the commit being replayed. For version lines that is the expected swap (`- 1.0.1` / `+ 1.1.0-rc.1`); anything else in there is worth reading before the next promotion. A changelog keeps both sides and drops nothing. The summary lists the first 400 lines; the log has all of them. What is printed is the content of files already in the repository, readable by whoever can read the logs.

A conflict on **any other file** is real work to reconcile by hand: silently keeping a side would drop the fix. The job then fails naming the file, with the rebase aborted and nothing pushed. So does a file **deleted on one side**: there is no side to take. Paths are read as names, never as patterns (a file called `[id].tsx` selects nothing else); a `MANAGED_FILES` entry applies first as a literal path, then as a glob.

**release-please rewrites more than the config names.** The version file of the `release-type` — `version.txt` for `simple`, `package.json` and `package-lock.json` for `node`, `Chart.yaml` for `helm` — is not in `extra-files`: list it in `MANAGED_FILES`, or its conflict fails the job (the error says so). The same goes for a chart bumped by [`update-helm-chart.yml`](./53-update-helm-chart.md): list its files.

## Release anchor after a rebase

On the prerelease branch, release-please starts from the release named after the version in the prerelease manifest (`1.1.0-rc.1`), found by its tag, and reads the branch history down to that tag's commit.

A rebase replays the commits under new SHAs, the release ones included. The tag still points to the original commit, which is no longer in the branch: release-please never finds its stop, reads the 500 most recent commits and proposes a wrong version — a major bump from an old breaking commit (`4.0.0-rc.4` instead of `3.5.0-rc.5`) — with a changelog repeating everything already released. Nothing says so before the pull request is opened.

Moving the tag is not an option: registries and mirrors build versions from tags, and a version must keep meaning the commit it was built from. `last-release-sha` in the prerelease config tells release-please to start from another commit instead; this job sets it **after every rebase that took a tag out of the branch**:

1. it reads the version in the prerelease manifest and finds its tag: `v<version>` or `<version>`, else the one tag ending in the version (a component prefix); several candidates (lockstep chart and application versions) are ambiguous, the job says so and sets nothing;
2. if that tag is no longer in the branch, it finds the replayed release commit: same subject **and same author date** (a rebase, a cherry-pick and a rebase-merge keep both), among the commits replayed onto the release branch; or, after a rebase-merge promotion that copied the whole series onto the release branch, the rebase replays nothing (everything is already upstream) and the copy of that commit on the release branch is used;
3. it commits `chore(develop): anchor release-please on 1.1.0-rc.1`, setting `last-release-sha` to that commit in `PRERELEASE_CONFIG_FILE`, before the single push.

The key has to be in a commit of the branch because release-please reads its config from GitHub, not from a workspace. Once the next prerelease is tagged, release-please reaches that tag before the anchor commit and the key is inert; the next rebase that takes a tag out refreshes it.

- **A single-package prerelease manifest.** The key is one commit for the whole repository: it cannot be the starting point of several packages. Beyond one, the job says so and sets nothing.
- **Idempotent.** Without a new rebase, or if the key already names the replayed commit, no commit is added.
- **The config is edited, not re-serialised.** The key is replaced on its line or inserted as the first property, so a formatted file keeps its layout and a JSON linter has nothing to say about the anchor commit. Only a file the edit cannot be checked against (an object that does not open on a line of its own) is rewritten with `jq`.
- **One anchor commit per rebase that takes a tag out.** Earlier ones are replayed with the rest and stack up: one more small `chore` commit per resynchronised hotfix, which reaches the release branch at the promotion, where the key is inert.
- **`jq` must be on the runner** (it is on GitHub-hosted ones; install it on a self-hosted runner).
- **In the steady state, nothing to do**: after a promotion the manifest holds the stable version, whose tag is on the release branch.

[`release-app.yml`](./50-release-app.md#release-anchor-assertion) checks the result on every prerelease run and fails if neither the tag nor `last-release-sha` is in the branch.

## Hotfix on the release branch

An urgent fix flows through the existing setup, no dedicated procedure:

1. Branch `hotfix/...` from the release branch, fix, open the pull request against it and merge.
2. The release branch's CD publishes the fix (e.g. `1.4.1`), and this job resynchronises the prerelease branch: the rebase replays the unreleased work on top of the fix, settles the conflicts on the files a release rewrites ([above](#conflicts-on-files-a-release-rewrites)) and anchors release-please on the replayed release commit ([above](#release-anchor-after-a-rebase)).
3. On the next push to the prerelease branch, release-please starts from the fixed base — the next prerelease (e.g. `1.5.0-rc.2`) contains the fix, and only it appears in its changelog.

The only possible friction is a conflict between the fix and the prerelease branch's work in progress **on a file a release does not rewrite**: the job then fails explicitly instead of leaving the branch stale (see Notes), and the conflict is resolved by hand once.

## Safety net

Forgetting this job, or forgetting an entry in its `needs:`, would stay invisible until a version came out wrong. [`release-app.yml`](./50-release-app.md#prerelease-sync-assertion) therefore **asserts the invariant** at the start of every prerelease run, before any version is computed, and fails naming it. A second assertion checks that release-please's starting point is in the branch ([anchor](./50-release-app.md#release-anchor-assertion)), which catches a missing or old sync job after a rebase. Nothing to configure.

## Notes

- **Only runs from the release branch.** Put the `if:` on the caller (see the example above): there is nothing to propagate when it runs from the prerelease branch itself.
- **In the steady state the rebase is a plain fast-forward.** The promotion put the prerelease branch's commits into the release branch, so `RELEASE_BRANCH..PRERELEASE_BRANCH` is empty and nothing is replayed. It only does real work when the prerelease branch moved while the release was running — possible whenever the caller's `concurrency` group is keyed on the branch — and that is exactly the case a plain `git push` would reject.
- **This assumes the promotion preserves commits** — as ancestors (merge) or as patch-identical copies (rebase-merge, where the rebase recognises each already-applied commit and drops it). A **squash** merge of `PRERELEASE_BRANCH` → `RELEASE_BRANCH` breaks that property: the N original commits are melted into one that none of them is patch-identical to, the rebase replays them all, and conflicts become the norm.
- **The push names the tip it may replace** — the one read before the rebase: a commit that landed meanwhile is rejected, not overwritten. Tags are fetched on their own, without touching the remote-tracking branches.
- **A conflict outside the files a release rewrites fails the job** rather than leaving the branch stale — the version regression would otherwise be silent. Conflicts on the files a release rewrites are settled (see above).
- **The push uses the checkout's `GITHUB_TOKEN` by default**, which cannot trigger workflow runs, so moving the prerelease branch does not re-enter the caller's CD. Only supply an App token when a ruleset rejects that push (see above). PATs are not accepted.
- `RELEASE_BRANCH` and `PRERELEASE_BRANCH` must differ — otherwise the job fails rather than rebasing a branch onto itself and never synchronising anything.
