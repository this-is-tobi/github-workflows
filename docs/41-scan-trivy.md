# `scan-trivy.yml`

Run Trivy vulnerability scans on container images and/or configuration files and upload SARIF reports to GitHub Security.

## Inputs

| Input               | Type    | Description                                                                              | Required | Default          |
| ------------------- | ------- | ---------------------------------------------------------------------------------------- | -------- | ---------------- |
| IMAGE               | string  | Image used to perform scan (e.g., docker.io/debian:latest)                               | No       | -                |
| IMAGE_ARTIFACT      | string  | Artifact holding an image tarball to scan locally instead of pulling `IMAGE`             | No       | -                |
| IMAGE_ARTIFACT_FILE | string  | Name of the tarball file inside `IMAGE_ARTIFACT`                                         | No       | image.tar        |
| PATH                | string  | Path used to perform config scan                                                         | No       | -                |
| FORMAT              | string  | Format of the report (sarif, table, json, ...)                                           | No       | table            |
| PR_NUMBER           | string  | PR number for comment posting                                                            | No       | -                |
| GITHUB_SECURITY_TAB | boolean | Whether to upload SARIF to GitHub Security Tab                                           | No       | false            |
| CATEGORY            | string  | Code scanning category for the SARIF upload (set one per target in a matrix)             | No       | -                |
| SEVERITY            | string  | Comma separated severities to report (e.g., `CRITICAL,HIGH`)                             | No       | all severities   |
| FAIL_ON_ERROR       | boolean | Whether to fail the workflow when vulnerabilities are found                              | No       | false            |
| TIMEOUT             | string  | Trivy scan timeout as a Go duration (e.g. `15m`)                                         | No       | 5m (Trivy's)     |
| TRIVYIGNORES        | string  | Comma separated paths to Trivy ignore files, relative to the repository root (e.g. `.trivyignore.yaml`). Trivy auto-detects a plain `.trivyignore`; the YAML form — the only one supporting per-path scoping and a documented reason per entry — has to be named explicitly | No | -                |
| RUNS_ON             | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`) | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                     | Required |
| ----------------- | --------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into registry (not needed for `ghcr.io`) | No       |
| REGISTRY_PASSWORD | Password used to login into registry (not needed for `ghcr.io`) | No       |
| APP_CLIENT_ID     | GitHub App **Client ID** (not the numeric App ID). With `APP_PRIVATE_KEY`, raises the API budget for Trivy's database download. See [Authentication](./05-authentication.md) | No |
| APP_PRIVATE_KEY   | GitHub App private key (PEM). Required alongside `APP_CLIENT_ID` | No       |
| GH_PAT            | Personal access token, same purpose as the App credentials and resolved after them. Read-only access is sufficient | No       |

> **Why supply a credential here.** Trivy fetches its vulnerability database through the GitHub API, which is limited to 1,000 requests/hour per repository under `GITHUB_TOKEN`. An App token or a `GH_PAT` raises that to 5,000 — worth setting if scans intermittently fail to download the DB. Either way read-only access is enough; nothing about the scan needs write, and the App token is minted `contents: read` + `metadata: read`.
>
> `APP_CLIENT_ID` and `APP_PRIVATE_KEY` must be supplied **together**. Setting only one fails the job rather than falling back to `GH_PAT` or `GITHUB_TOKEN`.

## Permissions

| Scope           | Access | Description                        |
| --------------- | ------ | ---------------------------------- |
| contents        | read   | Read repository contents           |
| security-events | write  | Upload SARIF to code scanning      |
| pull-requests   | write  | Post a comment on the pull request |
| packages        | read   | Pull images from GHCR              |

## Notes

- `images-scan` runs if either `IMAGE` or `IMAGE_ARTIFACT` is provided; `config-scan` runs only if `PATH` is provided.
- `IMAGE_ARTIFACT` scans an image that was never pushed to a registry. The artifact is downloaded from the current workflow run and handed to Trivy in tarball mode (`--input`), so the scan needs no registry access at all. This pairs with `build-docker.yml` used with `PUSH: false`, letting you gate publication on the scan result instead of scanning after the fact.
- `IMAGE_ARTIFACT` takes precedence over `IMAGE` when both are set — the local tarball is scanned and nothing is pulled.
- The artifact must have been produced by the **same workflow run**; downloading from another run is not supported.
- `FORMAT` controls output format: `table` (default) prints results to workflow summary, `sarif` enables GitHub Security Tab integration.
- When `GITHUB_SECURITY_TAB: true` and `FORMAT: sarif`, uploads results to the Security tab.
- PR comments link to either the GitHub Security Tab (when `GITHUB_SECURITY_TAB: true`) or the Workflow Summary page.
- The Security tab link in the PR comment is filtered on the ref the SARIF was actually uploaded against: `pr:<number>` for a `pull_request` run, `branch:<name>` for a push, and no ref filter at all for anything else (a tag). Code scanning only indexes alerts under that ref, so a caller that scans on `push` and passes `PR_NUMBER` by hand still gets a link that resolves - a hardcoded `pr:` filter would land on an empty tab there.
- Registry authentication: uses GitHub token for `ghcr.io`, otherwise uses provided credentials.
- Skips common directories via `skip-dirs: **/node_modules` in config scan.
- `CATEGORY` matters whenever one repository uploads more than one SARIF report: uploads sharing a category **replace one another**, so a matrix scanning several images without it leaves only whichever leg finished last visible in the Security tab.
- `FAIL_ON_ERROR` defaults to `false`, unlike the same-named input elsewhere in this repository. This workflow has always been report-only, so defaulting to `true` would start failing every existing caller on findings that predate the input. Set it explicitly to gate.
- `SEVERITY` pairs naturally with `FAIL_ON_ERROR`: gate on a narrow set (`CRITICAL`) and report on a wider one from a scheduled run.
- With `FAIL_ON_ERROR: true` the report is still written to the workflow summary before the job fails — a non-zero exit is precisely when there is something worth reading.
- With `FORMAT: table` the report goes to the workflow summary, which GitHub caps at **1 MiB** and drops *whole* rather than trimming when exceeded — a broad scan of a large image would otherwise lose its entire summary. The report is truncated to fit, with a note, and the complete file is attached to the run as a `trivy-report-<target>` artifact (7-day retention). Nothing is uploaded when the report fits.
- `TIMEOUT` is worth setting for large images. Trivy's 5m default is per-scan, not per-file, and a single big statically linked binary can consume it — the scan then aborts with `semaphore acquire: context deadline exceeded` and writes **no report at all**, so the target silently goes unscanned while faster images in the same matrix look fine.
- The scan covers `os,library`, and `library` includes binaries the image did not build. On an image full of third-party release binaries, `ignore-unfixed` filters less than it looks: a Go stdlib CVE counts as fixed once Go ships the fix, even though the vulnerable artifact is somebody else's prebuilt binary that only a new upstream release can change. Gate accordingly, or the check fails on findings no change to your repository can address.

## Examples

The examples show the two main output modes: a quick table-format scan for direct feedback, and GitHub Security Advisory integration to populate the repository's Security tab.

### Simple scan with table output

Runs both an image scan and a configuration path scan in parallel. Results are printed as a table in the workflow summary. When `PR_NUMBER` is set, a PR comment is posted linking back to the summary page.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Scan with GitHub Security Tab integration

`FORMAT: sarif` produces a SARIF report that is uploaded to the repository's Security → Code scanning tab when `GITHUB_SECURITY_TAB: true`. Findings are deduplicated and tracked across runs; the PR comment links to the Security tab instead of the workflow summary.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-image:1.2.3
      PATH: ./apps/api
      FORMAT: sarif
      GITHUB_SECURITY_TAB: true
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Scan an image that was built but not pushed

Pair with `build-docker.yml` using `PUSH: false` to scan the image **before** it is published. The build exports the image as a tarball artifact, and Trivy scans it locally in tarball mode — no registry involved, so a vulnerable image never reaches the registry in the first place.

```yaml
jobs:
  build:
    uses: this-is-tobi/github-workflows/.github/workflows/build-docker.yml@v0
    permissions:
      packages: write
      contents: read
    with:
      IMAGE_NAME: ghcr.io/my-org/my-image
      IMAGE_TAG: pr-${{ github.event.pull_request.number }}
      IMAGE_CONTEXT: ./
      IMAGE_DOCKERFILE: ./Dockerfile
      PUSH: false
      BUILD_ARM64: false

  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    needs:
    - build
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE_ARTIFACT: ${{ needs.build.outputs.artifact-prefix }}-amd64
      PATH: ./
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}
```

### Custom (non-GHCR) registry

For images hosted outside `ghcr.io`, provide explicit credentials as secrets:

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE: registry.example.com/my-org/my-image:1.2.3
      FORMAT: table
      PR_NUMBER: ${{ github.event.pull_request.number }}
    secrets:
      REGISTRY_USERNAME: ${{ secrets.REGISTRY_USERNAME }}
      REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
```

### Gate a pull request on critical findings

`FAIL_ON_ERROR` turns the scan into a blocking check. Pair it with a narrow `SEVERITY` so the gate stays actionable — a wide threshold on a broad image tends to fail every PR on findings unrelated to the change.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    with:
      IMAGE: ghcr.io/my-org/my-image:pr-${{ github.event.pull_request.number }}
      FORMAT: table
      SEVERITY: CRITICAL
      FAIL_ON_ERROR: true
```

### Scan several images without clobbering the Security tab

Each matrix leg needs its own `CATEGORY`, otherwise every upload replaces the previous one.

```yaml
jobs:
  vuln-scan:
    uses: this-is-tobi/github-workflows/.github/workflows/scan-trivy.yml@v0
    permissions:
      contents: read
      security-events: write
      pull-requests: write
      packages: read
    strategy:
      fail-fast: false
      matrix:
        image: [api, web, worker]
    with:
      IMAGE: ghcr.io/my-org/${{ matrix.image }}:latest
      FORMAT: sarif
      SEVERITY: CRITICAL,HIGH
      GITHUB_SECURITY_TAB: true
      CATEGORY: trivy-${{ matrix.image }}
```
