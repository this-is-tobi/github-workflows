# `build-oci-artifact.yml`

Build a gzipped tar archive with a command of your choice and push it to an OCI registry (e.g. `ghcr.io`) as an artifact with **one layer**: the archive, under the media type `application/vnd.oci.image.layer.v1.tar+gzip`. It is the shape [Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/oci/) expects for an OCI source (manifests, Helm charts or Kustomize bases in a directory tree), and a convenient one for any consumer that wants a versioned, signed bundle of files rather than a container image or a single Helm chart.

Use [`build-docker.yml`](./30-build-docker.md) for an image and [`release-helm-local.yml`](./52-release-helm-local.md) for a Helm chart: both have their own media types and tooling. This workflow is for everything that is a tree of files.

It returns the digest of what it pushed, so [`attest-docker.yml`](./31-attest-docker.md) can sign it and attest its provenance the same way it does for an image: pass it the `image` and `digest` outputs, with `SIGN` and `PROVENANCE` (an SBOM is generated for a container image and has little to say about an archive).

## Inputs

| Input                | Type    | Description                                                                                                                                                                                                                 | Required | Default          |
| -------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------- |
| ARTIFACT_NAME        | string  | Full name of the artifact, registry and path without tag (e.g. `ghcr.io/my-org/my-repo/catalog`). Normalized automatically (lowercase, underscores replaced by dashes).                                                      | Yes      | -                |
| ARTIFACT_TAG         | string  | Tag to push the artifact under, e.g. a version. Must be a valid OCI tag.                                                                                                                                                    | Yes      | -                |
| BUILD_COMMAND        | string  | Command that builds the archive, run with `bash -eo pipefail` from the root of the checked-out repository, like a `run:` step. It must write the file named by `ARTIFACT_FILE`.                                              | Yes      | -                |
| ARTIFACT_FILE        | string  | Path, relative to the root of the repository, of the gzipped tar archive (`.tar.gz` or `.tgz`) the command writes. It becomes the single layer of the artifact.                                                              | Yes      | -                |
| SETUP_HELM           | boolean | Install Helm before building, for builds that run `helm`.                                                                                                                                                                   | No       | false            |
| ARTIFACT_TYPE        | string  | Media type recorded as the `artifactType` of the manifest (e.g. `application/vnd.example.catalog.v1`). Left empty, ORAS records its default.                                                                                 | No       | -                |
| ARTIFACT_METADATA    | boolean | Stamp `org.opencontainers.image.source`, `.revision` and `.version` as annotations on the manifest (the repository, the commit and the tag). The source annotation is what links a GHCR package to its repository.             | No       | true             |
| ARTIFACT_ANNOTATIONS | string  | Newline-separated list of extra manifest annotations (e.g. `my.annotation=value`), applied after the standard set.                                                                                                           | No       | -                |
| ALLOW_OVERWRITE      | boolean | Push over a tag that already exists. Off by default: a consumer that pins a version expects it to keep meaning the same content, and a registry tag can be re-pushed.                                                       | No       | false            |
| RUNS_ON              | string  | Runner labels as JSON array (e.g., `'["ubuntu-24.04"]'` or `'["self-hosted", "linux"]'`)                                                                                                                                     | No       | ["ubuntu-24.04"] |

## Secrets

| Secret            | Description                                                                                                                                          | Required |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| REGISTRY_USERNAME | Username used to login into the registry (uses `github.actor` automatically for `ghcr.io`). **Required** when the registry is not `ghcr.io`          | No       |
| REGISTRY_PASSWORD | Password used to login into the registry (uses `GITHUB_TOKEN` automatically for `ghcr.io`). **Required** alongside `REGISTRY_USERNAME` in that case  | No       |

## Outputs

| Output | Description                                                                                                       |
| ------ | ------------------------------------------------------------------------------------------------------------------- |
| digest | Digest of the pushed artifact (`sha256:...`), read from ORAS's own output and checked against the registry          |
| image  | Normalized artifact name (lowercase, registry-compatible), without tag. Feed it to `attest-docker.yml` with `digest` |

## Permissions

| Scope    | Access | Description                                 |
| -------- | ------ | --------------------------------------------- |
| contents | read   | Checkout only                                 |
| packages | write  | Push the artifact to the registry (`ghcr.io`) |

## What it checks

- **The name and the tag** are held to reference shape before anything runs: they are joined into the reference that is pushed and that cosign signs.
- **A tag that is already published is refused**, unless `ALLOW_OVERWRITE` is set. Only an answer of "not found" lets the push go ahead: an authentication or network error says nothing about the tag, and stops the run instead of reading as "not published yet". A package that does not exist yet (the first publication) counts as not found.
- **The archive** must be a non-empty gzipped tar, and none of its entries may be an absolute path or contain a `..` component, since a consumer extracts it.
- **The pushed artifact is read back** from the registry by digest and must hold exactly one layer of type `application/vnd.oci.image.layer.v1.tar+gzip`, which is all Argo CD accepts.

A `BUILD_COMMAND` that fails, even half way, fails the run: it is run with `-e` and `pipefail`, like a `run:` step.

## Example

```yaml
jobs:
  catalog:
    uses: this-is-tobi/github-workflows/.github/workflows/build-oci-artifact.yml@v0
    permissions:
      contents: read
      packages: write
    with:
      ARTIFACT_NAME: ghcr.io/my-org/my-repo/catalog
      ARTIFACT_TAG: 1.2.3
      SETUP_HELM: true
      BUILD_COMMAND: scripts/build-catalog.sh dist
      ARTIFACT_FILE: dist/catalog.tar.gz

  attest-catalog:
    needs: catalog
    uses: this-is-tobi/github-workflows/.github/workflows/attest-docker.yml@v0
    permissions:
      packages: write
      id-token: write
      attestations: write
    with:
      IMAGE_NAME: ${{ needs.catalog.outputs.image }}
      DIGEST: ${{ needs.catalog.outputs.digest }}
      PROVENANCE: true
      SIGN: true
```

A consumer pins the artifact by tag or by digest. In Argo CD:

```yaml
sources:
- repoURL: oci://ghcr.io/my-org/my-repo/catalog
  targetRevision: 1.2.3
  path: charts/my-chart
```
