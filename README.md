# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

## CI workflows

Repos keep only their triggers and call these reusable workflows; the header of
each shows the call.

| Workflow | Jobs |
| --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | Linux and iOS tests, Paparazzi screenshot tests, formatting |
| [`publish.yml`](.github/workflows/publish.yml) | Maven Central, GitHub release |
| [`build-apps.yml`](.github/workflows/build-apps.yml) | Android, iOS, web and desktop builds of one app |
| [`deploy-pages.yml`](.github/workflows/deploy-pages.yml) | Builds one app's web app and deploys it to GitHub Pages |
| [`firebase-distribute.yml`](.github/workflows/firebase-distribute.yml) | Firebase App Distribution of one app |
| [`firebase-test-lab.yml`](.github/workflows/firebase-test-lab.yml) | Instrumented tests, benchmarks, baseline profiles |
| [`format.yml`](.github/workflows/format.yml) | Formatting on its own |

Every job starts with [`actions/gradle-setup`](actions/gradle-setup), which
checks out the repo and sets up the JDK from `toolchain/versions.env`, Gradle
and the CI `gradle.properties`. The Gradle commands are the shared tasks from
[gradle-plugins](https://github.com/embarrasdf/gradle-plugins#ci-tasks), such
as `embarrasdfTest`.

A repo with several apps keeps each in its own folder, such as `apps/foo`, with
`androidApp`, `iosApp`, `webApp` and `desktopApp` modules inside, and calls
`build-apps.yml` and `firebase-distribute.yml` once per app with its `app-dir`.

Repos extend the shared Renovate config in
[`renovate/default.json5`](renovate/default.json5).

## Build images

Two kinds of Docker image, both in GitHub Container Registry (GHCR):

| Image | Contents | Used by | Rebuilt |
| --- | --- | --- | --- |
| `ghcr.io/embarrasdf/kmp-toolchain` (public) | JDK, Android SDK, git-lfs | Everything below | When `toolchain/` changes on `main`, monthly, or by hand |
| `ghcr.io/embarrasdf/<name>-workspace` | The toolchain, plus the dependencies, Kotlin/Native, Kotlin npm tooling and Gradle build cache from building a set of repos side by side | Cloud sessions | By the private repo that lists the repos (embarrasdf/workspace) |

Workspace images are built on top of the toolchain image, so a session gets the
same JDK and SDK its caches were made with.

`kmp-toolchain` is public: it holds only open-source tools and Google's Android
SDK, so any repo, under any owner, can build on it and cloud sessions can pull
it without a token. GitHub has no API for package visibility, so after the first
build, open the package's settings and choose **Change visibility → Public**.
Workspace images stay private, since they hold compiled private code.

### Changing toolchain versions

Edit [`toolchain/versions.env`](toolchain/versions.env) and merge to `main`.
Cloud sessions and workspace images get their versions from there.
Renovate keeps the JDK and git-lfs lines current.

### Workspace images

A workspace image is built from a list of repos kept in a private repo (for
embarrasdf, `embarrasdf/workspace`), so private repo names stay private. That
repo calls the reusable [`workspace-image.yml`](.github/workflows/workspace-image.yml)
with its list file, the image name, and credentials that can clone the repos;
the header of that workflow shows the call. It clones the repos side by side
with [`actions/clone-repos`](actions/clone-repos) and builds with
[`actions/workspace-image`](actions/workspace-image).

Each build starts from the previous image's caches, so only what changed
downloads or compiles, and drops the caches of Gradle versions no repo's
wrapper uses any more. Dependencies no repo uses linger, though; when the
image has grown, run a build with `fresh: true`, which starts from empty
caches and compiles every repo from scratch. The caller passes it through,
for example from a `workflow_dispatch` input.

Cloud sessions also record how setup went: see
`/var/log/cloud-setup.status` and `/var/log/cloud-setup.log` (described in the
header of `cloud/setup.sh`).

The repo is public, so any repo can use its workflows and actions.

## Cloud sessions (Claude Code on the web)

Sessions can't boot from a custom image, so [`cloud/setup.sh`](cloud/setup.sh)
pulls workspace images and copies their contents onto the session VM; the
environment then snapshots the result for later sessions. A cloud environment's
own setup script sets `WORKSPACES` and runs it, so the same installer serves any
workspace. The header of `cloud/setup.sh` covers the registry token.

Workspace images can also carry Claude Code plugin marketplaces, such as
`embarrasdf/harness`, through the `claude-marketplaces` input of
`workspace-image.yml`, in a layer only workspace images get. `cloud/setup.sh`
enables all their plugins in Claude Code's user settings, so they apply in
every session, including one with several repos, where no repo's own
`.claude/` is read. A marketplace change reaches sessions when the workspace
image is rebuilt. Claude Code specifics stay in `cloud/setup.sh`, out of the
toolchain.

## Files

```
toolchain/
  versions.env              every toolchain version
  install-toolchain.sh      installs them (runs in the image build)
  Dockerfile                kmp-toolchain
  session/                  copied into cloud sessions by cloud/setup.sh
    apply.sh                  installs the toolchain and caches on a session VM
    central-mirror.init.gradle.kts   sends Maven Central traffic to Google's mirror
actions/gradle-setup/       checkout, JDK, Gradle and CI gradle.properties for every job
actions/app-info/           names and Gradle paths for an app folder
actions/release-notes/      tester-facing release notes
actions/format/             fixes and checks formatting
actions/screenshot-tests/   verifies Paparazzi screenshots and commits new ones
actions/commit/             commits from CI jobs, rebasing onto concurrent pushes
actions/workspace-image/    builds and pushes a workspace image
  Dockerfile, warm.sh
actions/clone-repos/        clones a workspace list side by side
.github/workflows/
  ci.yml, publish.yml, build-apps.yml, deploy-pages.yml, firebase-distribute.yml,
  firebase-test-lab.yml, format.yml
                            reusable: CI for the repos
  build-toolchain.yml       builds kmp-toolchain
  workspace-image.yml       reusable: workspace repos call this to build their image
cloud/setup.sh              installs workspace images on a cloud session VM
renovate/default.json5      shared Renovate config
```
