# `scan-sonarqube.yml`

Run SonarQube static analysis and check the quality gate. The workflow optionally downloads a coverage artifact and passes it to SonarQube.

## Inputs

| Input                  | Type    | Description                                                            | Required | Default             |
| ---------------------- | ------- | ---------------------------------------------------------------------- | -------- | ------------------- |
| COVERAGE_IMPORT        | boolean | Whether to download a coverage artifact                                | No       | false               |
| COVERAGE_ARTIFACT_NAME | string  | Name of the coverage artifact                                          | No       | unit-tests-coverage |
| COVERAGE_ARTIFACT_PATH | string  | Path where to download the coverage artifact                           | No       | ./coverage          |
| SONAR_EXTRA_ARGS       | string  | Additional SonarQube scanner arguments                                 | No       | -                   |
| SOURCES_PATH           | string  | Paths to the source code that should be analyzed (eg. 'apps,packages') | Yes      | -                   |
| SONAR_URL              | string  | URL of the SonarQube server                                            | Yes      | -                   |

## Secrets

| Secret            | Description                      | Required | Default |
| ----------------- | -------------------------------- | -------- | ------- |
| SONAR_TOKEN       | SonarQube token                  | Yes      | -       |
| SONAR_PROJECT_KEY | SonarQube project identifier key | Yes      | -       |

## Permissions

| Scope         | Access | Description                                 |
| ------------- | ------ | ------------------------------------------- |
| contents      | read   | Read source code for analysis               |
| issues        | write  | Create/update issues raised by integrations |
| pull-requests | write  | Publish PR decorations and status summaries |

## Notes

- When `COVERAGE_IMPORT` is `true` the workflow downloads the artifact using `COVERAGE_ARTIFACT_NAME` into `COVERAGE_ARTIFACT_PATH` before running the SonarQube scan; when `COVERAGE_IMPORT` is `false` no download is attempted. For pull requests, it passes PR decoration args; otherwise it analyzes the current branch. Default sources are `apps,packages`; override or extend via `SONAR_EXTRA_ARGS` (e.g., `-Dsonar.sources=.`).
- Requires `SONAR_TOKEN` and `SONAR_PROJECT_KEY` to authenticate with SonarQube.
- Fails the workflow if the SonarQube quality gate fails.
- Uses `sonarsource/sonarcloud-github-action` for SonarQube analysis.
- Supports JavaScript/TypeScript, Python, Java, Go, C#, and more.

## Examples

#### Simple example

```yaml
jobs:
  scan-sonarqube:
    uses: this-is-tobi/github-workflows/.github/workflows/catalog/scan-sonarqube.yml@main
    with:
      SONAR_URL: https://sonarqube.example.com
      COVERAGE_IMPORT: true
      COVERAGE_ARTIFACT_NAME: unit-tests-coverage
      COVERAGE_ARTIFACT_PATH: ./coverage
      SOURCES_PATH: apps,packages
      SONAR_EXTRA_ARGS: -Dsonar.javascript.lcov.reportPaths=./coverage/apps/api/lcov.info,./coverage/apps/client/lcov.info,./coverage/packages/shared/lcov.info -Dsonar.coverage.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue,**/assets/** -Dsonar.exclusions=**/*.spec.js,**/*.spec.ts,**/*.vue
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_PROJECT_KEY: ${{ secrets.SONAR_PROJECT_KEY }}
```
