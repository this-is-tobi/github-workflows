# Changelog

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
