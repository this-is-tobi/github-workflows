# `attest-helm.yml`

Attestations for Helm charts published to an OCI registry: cosign keyless signatures and SLSA build provenance. Takes the `published-charts` output of [`release-helm.yml`](./51-release-helm.md) and attests each chart by digest.

The capability inputs mirror [`attest-docker.yml`](./31-attest-docker.md), so an image and a chart are attested the same way — both flows are keyless, driven by the job's GitHub OIDC token, with no key at rest.

> **References:** [sigstore/cosign](https://github.com/sigstore/cosign) · [Helm provenance and integrity](https://helm.sh/docs/topics/provenance/)

## Why a separate workflow

Both capabilities need `id-token: write` to mint an OIDC token. GitHub validates the permissions requested by **every** job of a called workflow at parse time, regardless of each job's `if:` — so folding this into `release-helm.yml` would force every caller to grant OIDC token minting, including callers that never sign anything. Splitting it out keeps that scope with the workflow that actually uses it.

This is the same reasoning that separates [`attest-docker.yml`](./31-attest-docker.md) from [`build-docker.yml`](./30-build-docker.md), and [`release-helm-local.yml`](./52-release-helm-local.md#why-a-separate-workflow) from `release-helm.yml`. `ci/tests/permission-union.test.sh` enforces the related invariant.

## Inputs

| Input      | Type    | Description                                                                                                                                                | Required | Default          |
| ---------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ---------------- |
| CHARTS     | string  | JSON array of charts to attest, as produced by the `published-charts` output of `release-helm.yml`: `{name, version, repository, digest}` per entry. An empty array is a no-op | Yes      | -                |
| SIGN       | boolean | Sign the chart digest with cosign keyless signing                                                                                                          | No       | false            |
| PROVENANCE | boolean | Generate GitHub's standard SLSA build provenance attestation for the chart (records the calling workflow, repository and commit)                            | No       | false            |
| RUNS_ON    | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                    | No       | ["ubuntu-24.04"] |

**At least one of `SIGN` and `PROVENANCE` must be enabled.** Neither would fan out a matrix of jobs that log in to a registry and do nothing — green, and indistinguishable from a run that attested everything.

## Secrets

| Secret            | Description                                                        | Required |
| ----------------- | -------------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into the registry (not needed for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password used to login into the registry (not needed for `ghcr.io`) | No       |

## Permissions

| Scope     | Access | Description                                              |
| --------- | ------ | ---------------------------------------------------------- |
| packages     | write  | Push the signature and attestation artifacts next to the chart |
| id-token     | write  | Mint the OIDC token exchanged for a short-lived signing certificate |
| attestations | write  | Required by `actions/attest-build-provenance`               |

## Notes

- **Every entry must carry a `digest`.** The workflow rejects anything that is not a `sha256:...` value, including a tag smuggled into the field. Attesting a tag would bind the claim to whatever that tag resolves to at verification time — precisely the guarantee attestation exists to remove. Passing `published-charts` through unchanged always satisfies this.
- **An empty array is a no-op**, so the job can be wired up unconditionally: it stays green when `PUBLISH_OCI` is false or no chart changed. This relies on the job-level `if:` guard — a matrix built from an empty array does not skip a job, it fails it.
- **Several charts fan out over a matrix**, one job per chart, because `actions/attest-build-provenance` takes a single subject. `fail-fast` is off so one chart failing does not hide the state of the others; the job still fails overall.
- **All charts must share one registry.** A single login is performed per job, so a mixed list fails up front rather than at authentication time.
- **The registry is read back off the references** rather than taken as its own input — they already carry it, and a second source of truth could disagree with the charts actually being attested.
- **Provenance is not gated on signing succeeding.** Provenance establishes where a chart was built and from what, so a signing problem must never be the reason a chart ships without it — the same ordering `attest-docker.yml` uses.
- A Helm chart in an OCI registry is an ordinary OCI artifact, so both flows are the ones `attest-docker.yml` uses for images.

## What each capability gives you

| | `SIGN` | `PROVENANCE` |
| --- | --- | --- |
| Claim | *this workflow signed this artifact* | *this workflow built this artifact, from this repository and commit* |
| Produced by | cosign keyless (Fulcio certificate, logged in Rekor) | `actions/attest-build-provenance` (SLSA) |
| Verified with | `cosign verify` | `gh attestation verify` or `cosign verify-attestation` |
| Key management | keyless — no key to hold | keyless — no key to hold |

A signature says who vouched for the bytes. Provenance says where they came from. For a chart that pins application image versions, provenance is often the more useful of the two, which is why they are independent inputs rather than one switch.

## Relationship to `SIGN_CHART`

`SIGN_CHART` in [`release-helm.yml`](./51-release-helm.md#signing) covers the *other* distribution channel, and is not an alternative to anything here:

| | `release-helm.yml` `SIGN_CHART: true` | `attest-helm.yml` |
| --- | --- | --- |
| Produces | a `.prov` GPG provenance file | cosign signatures and/or SLSA provenance in the registry |
| Covers | the GitHub Release / `helm repo add` channel | the OCI channel |
| Verified with | `helm verify` / `helm install --verify` | `cosign verify` / `gh attestation verify` |
| Key management | your GPG key, as repository secrets | keyless — no key to hold |

`helm verify` implements OpenPGP only, so the classic channel cannot use the keyless flow — that is why GPG still exists here rather than being a preference. Conversely `helm push` does not carry a `.prov` file to an OCI registry, which is why `SIGN_CHART` requires `CREATE_GITHUB_RELEASE`.

If you publish only to OCI, prefer this workflow and hold no GPG key at all. A long-lived signing key is worth its key-management burden only if consumers actually run `helm verify`.

## Verifying

```bash
# Signature (SIGN)
cosign verify ghcr.io/my-org/my-repo/my-chart@sha256:... \
  --certificate-identity-regexp '^https://github.com/my-org/my-repo/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# Build provenance (PROVENANCE)
gh attestation verify oci://ghcr.io/my-org/my-repo/my-chart@sha256:... \
  --repo my-org/my-repo
```

The identity is the workflow that produced the attestation, so pin it as tightly as your setup allows — an exact `--certificate-identity` for the specific workflow file is stronger than the regexp above.

## Examples

### Sign and attest charts published by `release-helm.yml`

```yaml
jobs:
  release-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/release-helm.yml@v0
    permissions:
      contents: write
      packages: write
    with:
      # OCI only: attest-helm.yml signs OCI artifacts, and `published-charts`
      # is populated by that channel alone
      PUBLISH_OCI: true
      CREATE_GITHUB_RELEASE: false

  attest-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-helm.yml@v0
    needs:
    - release-charts
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      CHARTS: ${{ needs.release-charts.outputs.published-charts }}
      SIGN: true
      PROVENANCE: true
```

No `if:` is needed on `attest-charts` — an empty `published-charts` is a no-op.

### Provenance only

For a chart where the useful claim is where it came from rather than who signed it:

```yaml
  attest-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-helm.yml@v0
    needs:
    - release-charts
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      CHARTS: ${{ needs.release-charts.outputs.published-charts }}
      PROVENANCE: true
```

### Both channels, every mechanism

GPG provenance for the classic repository, cosign and SLSA provenance for the OCI artifacts.

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
      SIGN_CHART: true
      SIGNING_KEY_ID: "Jane Doe <jane@example.com>"
    secrets:
      GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}

  attest-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-helm.yml@v0
    needs:
    - release-charts
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      CHARTS: ${{ needs.release-charts.outputs.published-charts }}
      SIGN: true
      PROVENANCE: true
```

### Custom registry

```yaml
  attest-charts:
    uses: this-is-tobi/github-workflows/.github/workflows/attest-helm.yml@v0
    needs:
    - release-charts
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      CHARTS: ${{ needs.release-charts.outputs.published-charts }}
      SIGN: true
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```
