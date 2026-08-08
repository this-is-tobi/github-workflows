# Changelog

## [0.22.4](https://github.com/this-is-tobi/github-workflows/compare/v0.22.3...v0.22.4) (2026-08-08)


### Code Refactoring

* **clean-cache:** move container image cleanup to clean-images.yml ([d4f6c6b](https://github.com/this-is-tobi/github-workflows/commit/d4f6c6bb9c9740ec25d67c48073051abeee1a745))
* **update-helm-chart:** move cross-repository dispatch to its own workflow ([a090325](https://github.com/this-is-tobi/github-workflows/commit/a09032567a64a3cc0e520b024e8468afd5b5f729))

## [0.22.3](https://github.com/this-is-tobi/github-workflows/compare/v0.22.2...v0.22.3) (2026-08-07)


### Bug Fixes

* **release-app:** neutralize checkout's credential before the manifest-sync push ([da59096](https://github.com/this-is-tobi/github-workflows/commit/da59096681f553818c72a58ef64458ec58af74c1))
* **release-app:** unshallow before rebasing the prerelease branch onto the release branch ([4f9b29c](https://github.com/this-is-tobi/github-workflows/commit/4f9b29c8a4ac623eeee61d10312254b0a8151e58))
* **update-helm-chart:** drop the skip-ci marker from the local-mode chart-bump commit ([05bd83a](https://github.com/this-is-tobi/github-workflows/commit/05bd83a416d9779940d4c439e0341c4ca68d5927))
* **update-helm-chart:** pass --ref explicitly in caller-mode dispatch ([0397d73](https://github.com/this-is-tobi/github-workflows/commit/0397d737bbaf1d74895fe9532e819878e698a666))

## [0.22.2](https://github.com/this-is-tobi/github-workflows/compare/v0.22.1...v0.22.2) (2026-08-07)


### Code Refactoring

* **build-docker:** drop built-in attestation, compose explicitly ([f7f4aa7](https://github.com/this-is-tobi/github-workflows/commit/f7f4aa7251bb0ee7a5015fb0d27231f4670b01bb))
* **release-helm:** split local-mode release into a dedicated workflow ([46256e5](https://github.com/this-is-tobi/github-workflows/commit/46256e5ca48462651b1b6aff10309b0859bccc75))


### Dependencies

* **deps:** update actions/attest-build-provenance to v4.2.2 ([770496f](https://github.com/this-is-tobi/github-workflows/commit/770496fac9e278950dd39544d3e7ff5de86d2ad4))

## [0.22.1](https://github.com/this-is-tobi/github-workflows/compare/v0.22.0...v0.22.1) (2026-08-06)


### Bug Fixes

* **lint-helm:** stop hardcoding 'charts' as the helm-docs scan directory ([ceaa55f](https://github.com/this-is-tobi/github-workflows/commit/ceaa55fcb57c1740564e3babaacfbe71f3d47511))

## [0.22.0](https://github.com/this-is-tobi/github-workflows/compare/v0.21.0...v0.22.0) (2026-08-06)


### Features

* **auth:** support GitHub App tokens and gate automerge explicitly ([5019093](https://github.com/this-is-tobi/github-workflows/commit/5019093b4b5f77122b6a8a63ecf09e0627598883))


### Bug Fixes

* **workflows:** close injection and integrity gaps found by security review ([bf07c4e](https://github.com/this-is-tobi/github-workflows/commit/bf07c4ea1892afdfe35037adfdabd3008d547e35))
* **workflows:** quote shell expansions and enforce shellcheck ([d7c23cf](https://github.com/this-is-tobi/github-workflows/commit/d7c23cfe2ada4f2c9308f2d8b2901f223932746f))


### Dependencies

* **deps:** update actions/attest to v4.2.2 ([172029b](https://github.com/this-is-tobi/github-workflows/commit/172029b2ea207462d75b674d3b0a5530581712ca))
* **deps:** update dorny/paths-filter to v4.0.3 ([276ddd5](https://github.com/this-is-tobi/github-workflows/commit/276ddd52518b3c07cf4f1e9d9ab23e14e5098284))
* **deps:** update sonarsource/sonarqube-quality-gate-action to v1.2.1 ([00402b1](https://github.com/this-is-tobi/github-workflows/commit/00402b13a55ebcef540dce4ac14b3d5a6f4a34a9))

## [0.21.0](https://github.com/this-is-tobi/github-workflows/compare/v0.20.0...v0.21.0) (2026-08-04)


### Features

* **attest-docker:** attest SBOMs with cosign instead of actions/attest ([24ba84e](https://github.com/this-is-tobi/github-workflows/commit/24ba84e7a51ec99ca6756d1e3b21bbc0ad16b7b3))


### Bug Fixes

* **workflows:** make FAIL_ON_ERROR actually gate in the remaining workflows ([be0a05a](https://github.com/this-is-tobi/github-workflows/commit/be0a05ac83089086146f8c19418468eeb1aa043c))

## [0.20.0](https://github.com/this-is-tobi/github-workflows/compare/v0.19.1...v0.20.0) (2026-08-04)


### Features

* **build-docker:** allow callers to choose the buildx cache export mode ([f365fc1](https://github.com/this-is-tobi/github-workflows/commit/f365fc12e21be5a63957bc0928610f52fa8581a9))


### Bug Fixes

* **attest-docker:** keep provenance when the SBOM cannot be attested ([3d05b59](https://github.com/this-is-tobi/github-workflows/commit/3d05b598a47c64970c2759c197d6c23568408220))

## [0.19.1](https://github.com/this-is-tobi/github-workflows/compare/v0.19.0...v0.19.1) (2026-08-04)


### Bug Fixes

* **scan-trivy:** keep large reports from wiping the step summary ([d6661e4](https://github.com/this-is-tobi/github-workflows/commit/d6661e43226e1e2fe413265b82051b337fa86e62))

## [0.19.0](https://github.com/this-is-tobi/github-workflows/compare/v0.18.1...v0.19.0) (2026-08-04)


### Features

* **scan-trivy:** allow callers to raise the scan timeout ([d907571](https://github.com/this-is-tobi/github-workflows/commit/d9075716ee1a04ff7fd7e6d8cbca02557e8c43b3))

## [0.18.1](https://github.com/this-is-tobi/github-workflows/compare/v0.18.0...v0.18.1) (2026-08-04)


### Bug Fixes

* **scan-trivy:** make FAIL_ON_ERROR actually gate the job ([6b8de73](https://github.com/this-is-tobi/github-workflows/commit/6b8de735b3911a460f86f9169bd0f6c4ae4f42b2))


### Dependencies

* **deps:** update github/codeql-action to v4.37.6 ([fa9d04f](https://github.com/this-is-tobi/github-workflows/commit/fa9d04fef4b186ec161cc4eed9546fa97e7f180c))

## [0.18.0](https://github.com/this-is-tobi/github-workflows/compare/v0.17.1...v0.18.0) (2026-08-04)


### Features

* **scan-trivy:** allow callers to name a Trivy ignore file ([2eee324](https://github.com/this-is-tobi/github-workflows/commit/2eee324bf6d926d67bd17640b72296b474c696cb))

## [0.17.1](https://github.com/this-is-tobi/github-workflows/compare/v0.17.0...v0.17.1) (2026-08-04)


### Bug Fixes

* **test-docker:** resolve the registry-login condition outside the step if ([7e2d8f2](https://github.com/this-is-tobi/github-workflows/commit/7e2d8f277ccfec98e136f43d0d976dcc4111a748))

## [0.17.0](https://github.com/this-is-tobi/github-workflows/compare/v0.16.1...v0.17.0) (2026-08-04)


### Features

* **docker:** add image testing, cosign signing and scan gating ([ec9bb77](https://github.com/this-is-tobi/github-workflows/commit/ec9bb777cab2d088c363834b9d5f174d41e12181))

## [0.16.1](https://github.com/this-is-tobi/github-workflows/compare/v0.16.0...v0.16.1) (2026-08-04)


### Bug Fixes

* **build-docker:** stop the digest merge picking up other images ([c990871](https://github.com/this-is-tobi/github-workflows/commit/c990871110722ca6ca252f9cf295cc696dad2b53))

## [0.16.0](https://github.com/this-is-tobi/github-workflows/compare/v0.15.4...v0.16.0) (2026-08-03)


### Features

* **build-docker:** allow building an image without pushing it ([66298d4](https://github.com/this-is-tobi/github-workflows/commit/66298d43a93d8e02466c92b02c8169c9b7b368f6))
* **scan-trivy:** allow scanning a local image tarball artifact ([79c9db7](https://github.com/this-is-tobi/github-workflows/commit/79c9db72a8e24863ff039e5a0404290d38cd0398))
* **test-kube-deployment:** allow loading local image tarball artifacts ([74ee6ba](https://github.com/this-is-tobi/github-workflows/commit/74ee6ba426408b801f35208a7aa6047f7f77e21b))


### Bug Fixes

* **scan-trivy:** keep the job green when a scan produces no report ([66d48ac](https://github.com/this-is-tobi/github-workflows/commit/66d48ac3c3f294f09b6505152b5b7ba706321151))
* **test-kube-deployment:** load images into the right kind cluster ([e4be841](https://github.com/this-is-tobi/github-workflows/commit/e4be841fe373731b7d14c2f56a031c5792732b15))


### Dependencies

* **deps:** update github/codeql-action to v4.37.5 ([6755565](https://github.com/this-is-tobi/github-workflows/commit/67555655db0a31b15073bd7ccfbdeea9b4e4cf1e))

## [0.15.4](https://github.com/this-is-tobi/github-workflows/compare/v0.15.3...v0.15.4) (2026-08-01)


### Dependencies

* **deps:** update actions/attest to v4.2.1 ([0fa8e96](https://github.com/this-is-tobi/github-workflows/commit/0fa8e96f381f8dd4aab91201c80ff5c507ac2385))
* **deps:** update docker/login-action to v4.6.0 ([4753f22](https://github.com/this-is-tobi/github-workflows/commit/4753f224d965bcff4f25c8e81e244de5a64935dd))
* **deps:** update github/codeql-action to v4.37.4 ([527c695](https://github.com/this-is-tobi/github-workflows/commit/527c695d07b9634fa413ad5724f9d418541920df))

## [0.15.3](https://github.com/this-is-tobi/github-workflows/compare/v0.15.2...v0.15.3) (2026-07-25)


### Bug Fixes

* **deps:** update docker/login-action to v4.5.1 ([de8c181](https://github.com/this-is-tobi/github-workflows/commit/de8c1812987aa70aed00b41471e732fc41d3d420))

## [0.15.2](https://github.com/this-is-tobi/github-workflows/compare/v0.15.1...v0.15.2) (2026-07-23)


### Bug Fixes

* **deps:** update docker/login-action to v4.5.0 ([8cfcdf7](https://github.com/this-is-tobi/github-workflows/commit/8cfcdf78745496755038d966c5c475662ce568e4))

## [0.15.1](https://github.com/this-is-tobi/github-workflows/compare/v0.15.0...v0.15.1) (2026-07-23)


### Bug Fixes

* **deps:** update actions/attest to v4.2.0 ([50028d7](https://github.com/this-is-tobi/github-workflows/commit/50028d7429c2e47b01d40a566137a9ccc25aafad))
* **deps:** update actions/checkout to v7.0.1 ([3a55390](https://github.com/this-is-tobi/github-workflows/commit/3a55390478ed662623722aabc685943a57987053))
* **deps:** update actions/labeler to v6.2.0 ([b96e549](https://github.com/this-is-tobi/github-workflows/commit/b96e549657c4acc7b431d68915a0c30b91aba9f3))
* **deps:** update actions/labeler to v7 ([62f68c3](https://github.com/this-is-tobi/github-workflows/commit/62f68c3bd146f1757a2ec5ffe4e66bb8d6f15259))
* **deps:** update actions/setup-node to v6.5.0 ([34c1007](https://github.com/this-is-tobi/github-workflows/commit/34c1007062055c640ab8148e5fd893c77aa52798))
* **deps:** update actions/setup-node to v7 ([6381c6c](https://github.com/this-is-tobi/github-workflows/commit/6381c6c27ad023bfcb5435ff1b21533203361aea))
* **deps:** update actions/setup-python to v7 ([666aa34](https://github.com/this-is-tobi/github-workflows/commit/666aa347f07191b9cea50105fa87e6a6377fe5af))
* **deps:** update docker/login-action to v4.4.0 ([20603e7](https://github.com/this-is-tobi/github-workflows/commit/20603e7fcf9643f41a43a7f688d4e448c95699cb))
* **deps:** update docker/metadata-action to v6.2.0 ([40f326f](https://github.com/this-is-tobi/github-workflows/commit/40f326fa4688556ee006c6a2621063f65ab8856c))
* **deps:** update docker/setup-buildx-action to v4.2.0 ([f4f4ce0](https://github.com/this-is-tobi/github-workflows/commit/f4f4ce099483f1fca21209b2259730d200d0de1f))
* **deps:** update dorny/paths-filter to v4.0.2 ([6217099](https://github.com/this-is-tobi/github-workflows/commit/621709912e110036815f3d63591cd27fced35062))
* **deps:** update github/codeql-action to v4.37.3 ([95f134f](https://github.com/this-is-tobi/github-workflows/commit/95f134fccafe24243c8788067072955adbf059e4))
* **deps:** update python to 3.14 ([44fe58d](https://github.com/this-is-tobi/github-workflows/commit/44fe58d9aeead8c7b03034082e30c4c5aee1b532))
* **deps:** update sigstore/cosign-installer to v4.1.2 ([78d3fb5](https://github.com/this-is-tobi/github-workflows/commit/78d3fb5532d5fb6994cfa2698719861d2d6ceba4))
* **deps:** update sonarsource/sonarqube-scan-action to v8.2.1 ([8184fcd](https://github.com/this-is-tobi/github-workflows/commit/8184fcd0b0dbcb1d9be0665dc5059c03aee86d3b))

## [0.15.0](https://github.com/this-is-tobi/github-workflows/compare/v0.14.0...v0.15.0) (2026-07-22)


### Features

* **scan-gitleaks:** add reusable secret scanning workflow ([1d02d65](https://github.com/this-is-tobi/github-workflows/commit/1d02d6564a3f95815a554f67b8143130d06e8282))

## [0.14.0](https://github.com/this-is-tobi/github-workflows/compare/v0.13.0...v0.14.0) (2026-07-22)


### Features

* **lint-deps:** add reusable dependency-hygiene workflow ([50832fb](https://github.com/this-is-tobi/github-workflows/commit/50832fb71cbdbf2574ac88740f006b62d69ec2a4))


### Bug Fixes

* detect JS package manager/runtime by walking up to the checkout root ([aa0d889](https://github.com/this-is-tobi/github-workflows/commit/aa0d889f614a051e1a6b690974c494dcee13bd4f))
* harmonize JS runtime and package-manager auto-detection ([b72c2c8](https://github.com/this-is-tobi/github-workflows/commit/b72c2c89dd21ffa1356751c8bd89df3ee484185c))
* validate packageManager field type before using it in detection ([f97f93c](https://github.com/this-is-tobi/github-workflows/commit/f97f93c00aca43953af8fa79ed35a5cebcfc3882))

## [0.13.0](https://github.com/this-is-tobi/github-workflows/compare/v0.12.0...v0.13.0) (2026-07-22)


### Features

* **release-helm:** add local mode for monorepo chart publishing ([7d58c96](https://github.com/this-is-tobi/github-workflows/commit/7d58c968d13c9a66e2a45b4843fc10a3717eea13))
* **update-helm-chart:** add local mode with direct commit and version outputs ([4517d9c](https://github.com/this-is-tobi/github-workflows/commit/4517d9ccf2ca5a9986a549ea264935ec53bc4a81))


### Bug Fixes

* correct and harden reusable workflows ([49d93d0](https://github.com/this-is-tobi/github-workflows/commit/49d93d04903ef711e3e3c5375f0c458647b54f44))

## [0.12.0](https://github.com/this-is-tobi/github-workflows/compare/v0.11.0...v0.12.0) (2026-07-16)


### Features

* **attest-docker:** standard SLSA provenance + generic custom predicate ([9e0602f](https://github.com/this-is-tobi/github-workflows/commit/9e0602fd3191ea24b2c95093db52306f55b471b4))

## [0.11.0](https://github.com/this-is-tobi/github-workflows/compare/v0.10.0...v0.11.0) (2026-07-15)


### Features

* **release-npm:** fall back to npm cli for bun trusted publishing ([ccb7e44](https://github.com/this-is-tobi/github-workflows/commit/ccb7e44dbaf7bd13ffe0a99ef2a2cd77f588a4a6))

## [0.10.0](https://github.com/this-is-tobi/github-workflows/compare/v0.9.3...v0.10.0) (2026-07-14)


### Features

* **attest-docker:** add cosign signing and custom provenance predicate support ([0b1a146](https://github.com/this-is-tobi/github-workflows/commit/0b1a146d700142b994108013905d51faa1b44b66))

## [0.9.3](https://github.com/this-is-tobi/github-workflows/compare/v0.9.2...v0.9.3) (2026-07-04)


### Bug Fixes

* **release-npm:** set NPM_CONFIG_TOKEN for bun publish ([d9337ac](https://github.com/this-is-tobi/github-workflows/commit/d9337ac3113678ccaded19d3c96046275ae8a190))

## [0.9.2](https://github.com/this-is-tobi/github-workflows/compare/v0.9.1...v0.9.2) (2026-07-04)


### Bug Fixes

* **clean-cache:** catch multi-tag orphans and sweep their platform images ([2472937](https://github.com/this-is-tobi/github-workflows/commit/24729374e207681ba79d99169c4379276c8b020b))

## [0.9.1](https://github.com/this-is-tobi/github-workflows/compare/v0.9.0...v0.9.1) (2026-07-03)


### Bug Fixes

* **build-docker:** build each arch on its native runner when QEMU is disabled ([5d1c3e3](https://github.com/this-is-tobi/github-workflows/commit/5d1c3e339e7bc43297a2cfb29641720c74f76d01))

## [0.9.0](https://github.com/this-is-tobi/github-workflows/compare/v0.8.0...v0.9.0) (2026-07-02)


### Features

* **build-docker:** add BUILD_SECRETS for BuildKit secret mounts ([1588e62](https://github.com/this-is-tobi/github-workflows/commit/1588e6204d68c8a4bab8a6962aada00905538881))

## [0.8.0](https://github.com/this-is-tobi/github-workflows/compare/v0.7.0...v0.8.0) (2026-07-02)


### Features

* **release-npm:** support OIDC trusted publishing, make NPM_TOKEN optional ([182b3c4](https://github.com/this-is-tobi/github-workflows/commit/182b3c48ab1029d104f15d45be286c51fc28bea5))

## [0.7.0](https://github.com/this-is-tobi/github-workflows/compare/v0.6.0...v0.7.0) (2026-07-02)


### Features

* resolve RUNTIME_VERSION default per-runtime instead of a shared literal ([de22c90](https://github.com/this-is-tobi/github-workflows/commit/de22c90b210aa533618dbb762f64a05c971d4672))


### Bug Fixes

* replace pnpm/action-setup with Corepack to avoid version conflicts ([99fd130](https://github.com/this-is-tobi/github-workflows/commit/99fd13006a4e26b0def4c68ec5db54570d7013cc))

## [0.6.0](https://github.com/this-is-tobi/github-workflows/compare/v0.5.0...v0.6.0) (2026-03-15)


### Features

* **build-docker:** optionally attest images during build ([f6530d4](https://github.com/this-is-tobi/github-workflows/commit/f6530d4b8be66444cc8a9c790f5c9b0f3da88601))

## [0.5.0](https://github.com/this-is-tobi/github-workflows/compare/v0.4.0...v0.5.0) (2026-03-14)


### Features

* **update-helm-chart:** handle auto-merge in called mode ([eb30659](https://github.com/this-is-tobi/github-workflows/commit/eb30659c176f0c22d0524a4269fdfc9753a0e528))

## [0.4.0](https://github.com/this-is-tobi/github-workflows/compare/v0.3.0...v0.4.0) (2026-03-11)


### Features

* **build-docker:** split image attestation in a dedicated workflow ([1e37dba](https://github.com/this-is-tobi/github-workflows/commit/1e37dba454842255187672c72388a855dfb77f45))


### Code Refactoring

* improve security with secret input and scope permissions ([4a8d5fb](https://github.com/this-is-tobi/github-workflows/commit/4a8d5fbf0ab5aae96bc705c1d393ed0378ee9982))

## [0.3.0](https://github.com/this-is-tobi/github-workflows/compare/v0.2.0...v0.3.0) (2026-03-08)


### Features

* **release-app:** handle additional release artifacts from previous upload ([392f77d](https://github.com/this-is-tobi/github-workflows/commit/392f77d301c93495f1887ef9f53e9fc2616d72ce))

## [0.2.0](https://github.com/this-is-tobi/github-workflows/compare/v0.1.0...v0.2.0) (2026-03-08)


### Features

* **build-docker:** handle target, attestation, sbom and cache ([a047915](https://github.com/this-is-tobi/github-workflows/commit/a0479152f80a2a0a7b034e3bfa3384b0789959d1))
* **preview-comment:** add workflow to comment the PR with preview app infos ([ecb6f14](https://github.com/this-is-tobi/github-workflows/commit/ecb6f14d8f254d7dca91b0eb33e435fb5c0b9b51))
* **release-npm:** add new workflow to publish npm packages ([80310a9](https://github.com/this-is-tobi/github-workflows/commit/80310a9e518dc6550ffbf44e4d9c15d0be4540a2))
* **test-kube-deployment:** add workflow to test deployment in kubernetes ([eb306c0](https://github.com/this-is-tobi/github-workflows/commit/eb306c0af34a5179783ff9b6e7831017a14c562c))
* **test-playwright:** add workflow to wrap playwright tests ([5f2f641](https://github.com/this-is-tobi/github-workflows/commit/5f2f6414ec43064e66cbc9575c62aa3d78384323))


### Code Refactoring

* improve security accross all workflows ([3851339](https://github.com/this-is-tobi/github-workflows/commit/3851339ffb5abb203195c59ad78491efb3d785e3))
* **test-vitest:** rename test-js workflow into test-vitest ([a0b90c7](https://github.com/this-is-tobi/github-workflows/commit/a0b90c77a87df22ac7884ae31acd4acfb5f41ad4))

## [0.1.0](https://github.com/this-is-tobi/github-workflows/compare/v0.0.1...v0.1.0) (2026-03-06)


### Features

* add lint-helm workflow ([128a483](https://github.com/this-is-tobi/github-workflows/commit/128a4831f629e877edd42e92267850d5113e6438))
* add lint-js workflow ([f3e4c1e](https://github.com/this-is-tobi/github-workflows/commit/f3e4c1ef28e592f6426408a45c2b010ed051bf86))
* add more / improve existing workflows ([2d3aac4](https://github.com/this-is-tobi/github-workflows/commit/2d3aac49409a79f94b239580690b1b2fac618511))
* add release-helm workflow ([a9a10cc](https://github.com/this-is-tobi/github-workflows/commit/a9a10ccce778624f62dd4a6b4c0b6283dfbe4b33))
* add test-helm workflow ([c0ee06b](https://github.com/this-is-tobi/github-workflows/commit/c0ee06b5302ec0c0ca958def342daa97b82b5e3c))
* add test-js workflow ([a214a1c](https://github.com/this-is-tobi/github-workflows/commit/a214a1c70d6ccd5878bbddf89d29f5257ff13afd))
* add update-helm-chart workflow ([30b37b8](https://github.com/this-is-tobi/github-workflows/commit/30b37b8fe5f77b7aeefc71d544ccec4f4de3f702))
* introduce lint-commits workflow ([2325331](https://github.com/this-is-tobi/github-workflows/commit/2325331a9e27d9d3479f685fb8fd629e1e1953df))


### Bug Fixes

* minor problems in workflows ([a98ff46](https://github.com/this-is-tobi/github-workflows/commit/a98ff46fd6ff603c7198432c94f69f16a18bbe86))
* multiple workflows to work correctly ([2cb49c0](https://github.com/this-is-tobi/github-workflows/commit/2cb49c06817cad891701de65d995038ec8477496))


### Reverts

* (cf803e5) move workflows because of incompatibility ([e208487](https://github.com/this-is-tobi/github-workflows/commit/e208487d24c73e7b200b70d56af251b51ccca20c))


### Code Refactoring

* improve clean-cache workflow ([ed0c855](https://github.com/this-is-tobi/github-workflows/commit/ed0c855e21079e6fef8954dd20553ff567871763))
* improve release-app workflow ([8ddaccb](https://github.com/this-is-tobi/github-workflows/commit/8ddaccb7657a16cc1ae4d25c2b0e060e0d247bd7))
* improve scan-sonarqube workflow ([5262138](https://github.com/this-is-tobi/github-workflows/commit/52621384e7ac0fc0fcf1de11d9e142db15328185))
* improve test-js workflow ([88f5cb4](https://github.com/this-is-tobi/github-workflows/commit/88f5cb42eb7b56e9757cd13f48e2dbb3e793afd7))
* improve workflows permissions ([dfdfab4](https://github.com/this-is-tobi/github-workflows/commit/dfdfab455c50a92eee48b488caa9ee2241b05380))
* move workflows into a dedicated catalog subfolder ([cf803e5](https://github.com/this-is-tobi/github-workflows/commit/cf803e571fada09ff030b2d89b0e777fd737e607))
* pin trivy scan action to a version ([bcb0108](https://github.com/this-is-tobi/github-workflows/commit/bcb0108561c690d2823c4a660c3708147529d23a))
* remove unsed input in clean-cache workflow ([b4900ca](https://github.com/this-is-tobi/github-workflows/commit/b4900ca9ea02a540a6712020ed5f668a2013935d))
* rename docker-build workflow to build-docker ([f1af618](https://github.com/this-is-tobi/github-workflows/commit/f1af61800952d686d5b57984b75e584ca740509b))
* rename preview-app workflow to argocd-preview ([633e8bb](https://github.com/this-is-tobi/github-workflows/commit/633e8bb7d3e0d57634504945d23694f6655b3cef))
* rename release workflow to release-app ([18f88b2](https://github.com/this-is-tobi/github-workflows/commit/18f88b2cec26d7702b4d8b26d51a068bd35608ff))
* update variable name in scan-sonarqube workflow ([46a0513](https://github.com/this-is-tobi/github-workflows/commit/46a0513cf6457f95f8e9da7a12d1ca5321170de8))
* upgrade actions and default inputs versions ([0038bef](https://github.com/this-is-tobi/github-workflows/commit/0038bef63b40ec453deb78f9c4a03fdc6687eddc))
