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
| RUNS_ON           | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                  | No       | ["ubuntu-24.04"] |

## Permissions

| Scope    | Access | Description                          |
| -------- | ------ | ------------------------------------ |
| contents | write  | Push the rebased prerelease branch   |

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
```

### By repository shape

| Repository shape              | Commits on the release branch after the release job | This job |
| ----------------------------- | ---------------------------------------------------- | -------- |
| App only (no chart)           | none                                                 | `needs: [release]` |
| App + local chart (monorepo)  | the chart bump                                       | `needs: [..., bump-chart-local]` |
| App + chart in another repo   | none — the bump lands in the *other* repository       | `needs: [release]` |
| Chart repository, single branch | —                                                  | not needed |

## Hotfix on the release branch

An urgent fix flows through the existing setup, no dedicated procedure:

1. Branch `hotfix/...` from the release branch, fix, open the pull request against it and merge.
2. The release branch's CD publishes the fix (e.g. `1.4.1`), and this job resynchronises the prerelease branch: the rebase replays the unreleased work on top of the fix.
3. On the next push to the prerelease branch, release-please starts from the fixed base — the next prerelease (e.g. `1.5.0-rc.2`) contains the fix.

The only possible friction is a conflict between the fix and the prerelease branch's work in progress: the job then fails explicitly instead of leaving the branch stale (see Notes), and the conflict is resolved by hand once.

## Safety net

Forgetting this job, or forgetting an entry in its `needs:`, would stay invisible until a version came out wrong. [`release-app.yml`](./50-release-app.md#prerelease-sync-assertion) therefore **asserts the invariant** at the start of every prerelease run, before any version is computed, and fails naming it. Nothing to configure.

## Notes

- **Only runs from the release branch.** Put the `if:` on the caller (see the example above): there is nothing to propagate when it runs from the prerelease branch itself.
- **In the steady state the rebase is a plain fast-forward.** The promotion put the prerelease branch's commits into the release branch, so `RELEASE_BRANCH..PRERELEASE_BRANCH` is empty and nothing is replayed. It only does real work when the prerelease branch moved while the release was running — possible whenever the caller's `concurrency` group is keyed on the branch — and that is exactly the case a plain `git push` would reject.
- **This assumes the promotion preserves commits** — as ancestors (merge) or as patch-identical copies (rebase-merge, where the rebase recognises each already-applied commit and drops it). A **squash** merge of `PRERELEASE_BRANCH` → `RELEASE_BRANCH` breaks that property: the N original commits are melted into one that none of them is patch-identical to, the rebase replays them all, and conflicts become the norm.
- **A conflict fails the job** rather than leaving the branch stale — the version regression would otherwise be silent.
- **The push uses the checkout's `GITHUB_TOKEN`**, which cannot trigger workflow runs, so moving the prerelease branch does not re-enter the caller's CD. Do not give this workflow an App token or a PAT.
- `RELEASE_BRANCH` and `PRERELEASE_BRANCH` must differ — otherwise the job fails rather than rebasing a branch onto itself and never synchronising anything.
