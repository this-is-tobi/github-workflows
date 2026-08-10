# `release-helm.yml`

Release Helm charts using [`chart-releaser-action`](https://github.com/helm/chart-releaser-action), which auto-detects charts whose version changed since the last git tag and packages them. From there, two **independent distribution channels** can be enabled — see [Distribution channels](#distribution-channels):

- `CREATE_GITHUB_RELEASE` (**`true` by default**) — attach the packages to a GitHub Release per chart and maintain a classic `index.yaml` Helm repo on a pages branch.
- `PUBLISH_OCI` (`false` by default) — push the packages to an OCI registry (e.g. `ghcr.io`).

**At least one must be enabled**, otherwise the run fails. The classic channel is on by default because this workflow serves a **dedicated charts repository**, where the git tags belong to the charts: it is chart-releaser's native output and the only one any Helm 3 can consume. It does assume the `PAGES_BRANCH` (`gh-pages` by default) **already exists** — see [Pages branch prerequisite](#pages-branch-prerequisite), and [Private repositories](#private-repositories-prefer-the-oci-channel) before enabling it on a private repo.

For a **monorepo** — a chart living alongside application code, where the tag namespace is dominated by app tags and chart-releaser's "latest tag" change detection is unreliable — use [`release-helm-local.yml`](./52-release-helm-local.md) instead. The two are separate workflow files rather than one workflow with a mode switch: each declares only the permissions its own logic needs, so a monorepo caller never has to grant `contents: write` for a chart-releaser code path it will never run. See [`release-helm-local.yml`](./52-release-helm-local.md#why-a-separate-workflow) for the full reasoning.

## Inputs

| Input                 | Type    | Description                                                                                                                     | Required | Default          |
| --------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| CHARTS_DIR            | string  | Directory containing the Helm charts                                                                                              | No       | ./charts         |
| CREATE_GITHUB_RELEASE | boolean | Create a GitHub Release and git tag per changed chart and update `index.yaml` on the pages branch. Requires the pages branch to already exist. Default channel of a dedicated charts repository. | No       | true             |
| PUBLISH_OCI           | boolean | Push the packaged charts to the OCI registry (see `REGISTRY`/`REPOSITORY`). Independent of `CREATE_GITHUB_RELEASE`; at least one of the two must be enabled | No       | false            |
| PAGES_BRANCH          | string  | Branch that receives `index.yaml` when `CREATE_GITHUB_RELEASE` is `true`. Must already exist.                                    | No       | gh-pages         |
| SIGN_CHART            | boolean | GPG-sign each packaged chart, producing the `.prov` file `helm verify` checks. Requires `CREATE_GITHUB_RELEASE`, `SIGNING_KEY_ID` and the GPG secrets — see [Signing](#signing) | No       | false            |
| SIGNING_KEY_ID        | string  | Identity of the GPG key to sign with, as it appears in the keyring (e.g. `Jane Doe <jane@example.com>`). Required with `SIGN_CHART`                | No       | -                |
| HELM_REPOS            | string  | Helm repositories to add for chart dependencies (name=url, comma-separated). Optional; skipped if empty.                          | No       | -                |
| REGISTRY              | string  | OCI registry to push charts to (e.g. `ghcr.io`, `registry.gitlab.com`)                                                            | No       | ghcr.io          |
| REPOSITORY            | string  | Repository path in the OCI registry (defaults to `github.repository`)                                                             | No       | -                |
| RUNS_ON               | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                          | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                | Required |
| ----------------- | ------------------------------------------------------------------------------------------ | -------- |
| REGISTRY_USERNAME | Username for OCI registry authentication (uses `github.actor` automatically for `ghcr.io`). **Required** with `PUBLISH_OCI: true` when `REGISTRY` is not `ghcr.io` | No       |
| REGISTRY_PASSWORD | Password for OCI registry authentication (uses `GITHUB_TOKEN` automatically for `ghcr.io`). **Required** alongside `REGISTRY_USERNAME` under the same conditions | No       |
| APP_CLIENT_ID     | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, chart-releaser authenticates as a GitHub App. See [Authentication](./05-authentication.md) | No       |
| APP_PRIVATE_KEY   | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID`                            | No       |
| GH_PAT            | Personal access token, same purpose as the App credentials and resolved after them | No       |
| GPG_PRIVATE_KEY   | ASCII-armored GPG private key used to sign chart packages. Required with `SIGN_CHART` | No       |
| GPG_PASSPHRASE    | Passphrase for `GPG_PRIVATE_KEY`. Pass an empty value only if the key genuinely has none | No       |

> **Why supply App credentials here.** Releases created with `GITHUB_TOKEN` cannot fire `release:` triggers — GitHub's anti-recursion rule. If you have a workflow that should run when a chart release is published, chart-releaser needs an App token. Otherwise `GITHUB_TOKEN` is fine.
>
> `cr index --push` authenticates the `PAGES_BRANCH` push with the same token, so an App token or `GH_PAT` also lets **that** push trigger workflows. Harmless unless a workflow triggers on the pages branch — check before pointing one at it.
>
> The App token is only minted when `CREATE_GITHUB_RELEASE` is `true` — with it `false` nothing in the run writes through that token (chart-releaser only packages, and the OCI push authenticates against the registry instead), so there is nothing for a write-capable token to do.
>
> `APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`.

## Permissions

| Scope    | Access | Description                                                            |
| -------- | ------ | ------------------------------------------------------------------------ |
| packages | write  | Push charts to the OCI registry (`ghcr.io`) when `PUBLISH_OCI` is `true`  |
| contents | write  | Create releases/tags and update `index.yaml` when `CREATE_GITHUB_RELEASE` is `true` (harmless to grant unconditionally if left `false`) |

> **On the unused grant.** The workflow declares both scopes on its job, and GitHub Actions' `permissions:` key accepts no expressions — so `packages: write` is granted even with `PUBLISH_OCI: false`, where nothing uses it. Narrowing it would mean splitting the two channels into separate workflow files, doubling the file count to remove a scope that no step in that configuration ever calls.

## Distribution channels

The workflow packages charts once and can ship them through two channels, enabled independently:

| | `CREATE_GITHUB_RELEASE` (default `true`) | `PUBLISH_OCI` (default `false`) |
| --- | --- | --- |
| Consumers run | `helm repo add <name> https://<owner>.github.io/<repo>` | `helm pull oci://<registry>/<repo>/<chart>` |
| Needs | any Helm 3 | Helm 3.8+ |
| Repo prerequisites | the `PAGES_BRANCH` (default `gh-pages`) must already exist | none |
| Private charts | GitHub Release assets follow repo visibility, but the pages site is public — see below | registry auth |
| Extra permission used | `contents: write` | `packages: write` |
| [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) | **not compatible** — see the warning below | compatible (creates no GitHub Release) |

Enabling both is fine and publishes the same packages through both paths.

**Both left `false` fails the run.** The workflow would otherwise package charts, publish them nowhere, and still report success — a green run that shipped nothing is harder to notice than a red one, so the validation step stops it up front with a message naming both inputs. `CREATE_GITHUB_RELEASE` being `true` by default, reaching that case means it was explicitly disabled without enabling the other channel.

> **And in a monorepo?** [`release-helm-local.yml`](./52-release-helm-local.md) is the counterpart for a chart living alongside application code, and exposes neither input: OCI is its only possible channel. The GitHub Releases and git tags there belong to the application, so the chart cannot claim them.

### Pages branch prerequisite

With `CREATE_GITHUB_RELEASE` on by default, `chart-releaser` pushes `index.yaml` to `PAGES_BRANCH` (`gh-pages` by default) and **does not create it** — `cr index --push` fails outright when it is missing ([chart-releaser-action#111](https://github.com/helm/chart-releaser-action/issues/111)). On a fresh repository, create it once:

```sh
git switch --orphan gh-pages
git commit --allow-empty -m "chore: initialise the helm repo pages branch"
git push -u origin gh-pages
```

Then, for `helm repo add https://<owner>.github.io/<repo>` to resolve, enable GitHub Pages on that branch under *Settings > Pages*. With no pages branch, prefer the OCI channel alone (`PUBLISH_OCI: true`, `CREATE_GITHUB_RELEASE: false`).

### Private repositories: prefer the OCI channel

> [!WARNING]
> **A GitHub Pages site is public even when its repository is private.** Enabling Pages on a private charts repository therefore publishes `index.yaml` — the catalogue of your chart names, versions and descriptions — to the open internet. Restricting access to a Pages site requires **GitHub Enterprise Cloud**; Pages on a private repository already requires at least **GitHub Pro**.

The `.tgz` files themselves stay private (they are Release assets and follow repo visibility), but that is also what makes the classic channel awkward here: the index is served from `<owner>.github.io` and the packages from `github.com/<owner>/<repo>/releases/download/...`, two different hosts, so credentials attached to the `helm repo add` entry do not carry through to the chart download.

On a private repository, three options, best first:

1. **OCI channel alone** (`PUBLISH_OCI: true`, `CREATE_GITHUB_RELEASE: false`) — the ghcr.io package follows the repository's visibility, consumers run `helm registry login ghcr.io` then `helm pull oci://ghcr.io/<owner>/<repo>/<chart> --version X`. No branch prerequisite, no plan requirement. Needs Helm 3.8+.
2. **Classic channel with an unpublished pages branch** — `PAGES_BRANCH` is only a branch name; nothing requires enabling Pages on it. Pointing it at `PAGES_BRANCH: charts-index` and leaving *Settings > Pages* off gives the GitHub Releases, the git tags and an `index.yaml` readable only with repo access — at the cost of `helm repo add https://...`, which no longer exists.
3. **Classic channel with Pages enabled** — only if a public catalogue is acceptable, or under GitHub Enterprise Cloud with an access-controlled site.

> The two channels do not decouple any further: `chart-releaser-action` gates `cr index` on `skip_upload` alone, and that flag also suppresses `cr upload`. Creating the GitHub Releases without pushing an `index.yaml` is not expressible — hence option 2, which pushes the index to a branch nobody serves.

## Outputs

| Output           | Description                                                                                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| published-charts | JSON array of the charts pushed to the OCI registry — `{name, version, repository, digest}` per entry. Empty array when `PUBLISH_OCI` is false or no chart changed |

`repository` and `digest` are kept apart so they can be fed straight to [`attest-helm.yml`](./56-attest-helm.md), which passes them on as cosign's subject and as the `subject-name`/`subject-digest` pair `actions/attest-build-provenance` expects — the same shape `attest-docker.yml` consumes for images. The name and version are read back from `helm push`'s own output rather than parsed out of the package file name, which cannot be split reliably: a prerelease version contains dashes of its own (`my-chart-1.2.3-rc.1.tgz`).

## Signing

The two channels are signed by different mechanisms, and they are complementary rather than alternatives:

| | `SIGN_CHART: true` (here) | [`attest-helm.yml`](./56-attest-helm.md) |
| --- | --- | --- |
| Produces | a `.prov` GPG provenance file | cosign signatures and/or SLSA build provenance in the registry |
| Covers | the GitHub Release / `helm repo add` channel | the OCI channel |
| Verified with | `helm verify`, `helm install --verify` | `cosign verify` / `gh attestation verify` |
| Key management | your GPG key, as repository secrets | keyless — no key to hold |

**`SIGN_CHART` requires `CREATE_GITHUB_RELEASE`.** The `.prov` file is published as a release asset; `helm push` does not carry it to an OCI registry, so on the OCI channel alone it would be generated and silently discarded. The workflow fails rather than let that happen — use `attest-helm.yml` for the OCI side.

```yaml
with:
  CREATE_GITHUB_RELEASE: true
  SIGN_CHART: true
  SIGNING_KEY_ID: "Jane Doe <jane@example.com>"
secrets:
  GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
  GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
```

Export the key with `gpg --armor --export-secret-keys <key-id>` and store it as `GPG_PRIVATE_KEY`. Consumers verify with `helm verify my-chart-1.2.3.tgz` once they have imported the matching public key.

Missing pieces fail up front rather than producing unsigned charts: chart-releaser does not treat a missing key as fatal, it simply packages without a signature — so an empty `GPG_PRIVATE_KEY`, an empty `SIGNING_KEY_ID`, or a key that fails to export all stop the run.

## Notes

- **CREATE_GITHUB_RELEASE behavior**: When `true`, creates a GitHub Release and git tag for each changed chart and updates `index.yaml` on the pages branch (e.g. `gh-pages`); this **requires that pages branch to already exist**. When `false`, no GitHub Pages branch is required.
- **PUBLISH_OCI behavior**: When `true`, logs in to `REGISTRY` and pushes each packaged chart. The login is skipped entirely when `false`, so no registry credential is read or needed.
- **Registry credentials are validated up front**: with `PUBLISH_OCI: true` and a `REGISTRY` other than `ghcr.io`, missing `REGISTRY_USERNAME`/`REGISTRY_PASSWORD` fail the run with an explicit message rather than reaching `helm registry login` with an empty password and failing on an opaque authentication error.
- **Credentials are cleared afterwards**: a `helm registry logout` step runs whenever the login succeeded, including after a failed push. Hosted runners are ephemeral so this is a no-op there, but `RUNS_ON` also supports self-hosted runners, where Helm's registry config would otherwise outlive the job.
- **HELM_REPOS is optional**: The "add repos" step is skipped when `HELM_REPOS` is empty. Provide it when your charts pull dependencies from external repositories.
- Detects charts via `git diff` from the latest git tag and only releases charts whose `Chart.yaml` version was bumped compared to the previous release; requires SemVer chart versions and `fetch-depth: 0` (the workflow sets it).
- Charts can be pulled using: `helm pull oci://ghcr.io/<owner>/<repo>/<chart-name> --version <version>`

> [!WARNING]
> **`CREATE_GITHUB_RELEASE: true` is not compatible with [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).** `chart-releaser` creates the GitHub Release and then attaches the chart `.tgz` in two separate API calls, with no way to go through a draft; on a repository with immutable releases enabled the second call is rejected and the release is left incomplete. Upstream support is tracked in [helm/chart-releaser#591](https://github.com/helm/chart-releaser/issues/591).
>
> The OCI channel on its own (`PUBLISH_OCI: true`, `CREATE_GITHUB_RELEASE: false`) creates no GitHub Release and is unaffected — so on a repository with immutable releases enabled, that is the channel to use.

## Examples

Every example enables at least one distribution channel — the workflow fails if both are left `false`. They cover OCI on the default `ghcr.io` registry, OCI on a custom registry with explicit credentials, the classic GitHub Pages repo on its own, and both channels together.

### OCI registry (GitHub Packages)

Packages the changed charts and pushes them to `ghcr.io`. No GitHub Pages branch needed. External repositories are optionally pre-registered via `HELM_REPOS`.

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      PUBLISH_OCI: true
      CHARTS_DIR: ./charts
      HELM_REPOS: "bitnami=https://charts.bitnami.com/bitnami,jetstack=https://charts.jetstack.io"
```

### Custom OCI registry

To push charts to a registry other than `ghcr.io`, supply credentials as secrets — they are required, and the run fails up front without them:

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      PUBLISH_OCI: true
      CHARTS_DIR: ./charts
      REGISTRY: registry.example.com
      REPOSITORY: my-org/helm-charts
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Classic Helm repo only (no OCI)

Creates a GitHub Release and git tag per chart and maintains an `index.yaml` Helm repo on the pages branch, without pushing anything to an OCI registry. Consumers use `helm repo add`. The `PAGES_BRANCH` (default `gh-pages`) **must already exist** in the repository.

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      CREATE_GITHUB_RELEASE: true
      PAGES_BRANCH: gh-pages
```

### Both channels

Publishes the same packages to the OCI registry *and* through the classic pages repo:

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      PUBLISH_OCI: true
      CREATE_GITHUB_RELEASE: true
      PAGES_BRANCH: gh-pages
```

### Monorepo chart

For a chart living alongside application code, see [`release-helm-local.yml`](./52-release-helm-local.md) instead — a separate, minimal-permission workflow for exactly this case.
