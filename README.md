# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

## Formatting

[`.github/workflows/format.yml`](.github/workflows/format.yml) fixes and checks Kotlin formatting
with the `com.embarrasdf.gradle.plugin.lint` plugin from gradle-plugins. On a pull request it runs
`embarrasdfFormat`, commits the fixes to the branch ("🤖 Apply formatting"), then runs
`embarrasdfFormatCheck`. Anything left needs a manual fix: the job fails and lists the issues in a
comment on the pull request, which it updates on later runs. Pushes and pull requests from forks
are only checked.

To add it to a repo:

1. Apply the lint plugin to the root project (the convention plugins already apply it to modules):
   `alias(libs.plugins.embarrasdf.lint)`.
2. Add `.github/workflows/format.yml` (copy uievent's):

   ```yaml
   name: Format
   on:
     pull_request:
     push:
       branches: [main]
   concurrency:
     group: ${{ github.workflow }}-${{ github.ref }}
     cancel-in-progress: true
   jobs:
     format:
       uses: embarrasdf/devops/.github/workflows/format.yml@main
       permissions: { contents: write, pull-requests: write }
   ```

   Optional inputs: `java-version` (default 17) and `gradle-args`, for example
   `--no-configuration-cache`.

The job shares the `auto-commit-<ref>` concurrency group with screenshot and baseline-profile
jobs, so their commits don't race. Commits pushed with `GITHUB_TOKEN` don't start other workflows,
so the formatting commit isn't re-tested by the repo's other checks until the next push.

## Files

```
actions/format/             fixes, commits and checks Kotlin formatting
.github/workflows/
  format.yml                reusable: repos call this to fix and check formatting
```
