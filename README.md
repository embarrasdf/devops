# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

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
actions/workspace-image/    builds and pushes a workspace image
  Dockerfile, warm.sh
actions/clone-repos/        clones a workspace list side by side
.github/workflows/
  build-toolchain.yml       builds kmp-toolchain
  workspace-image.yml       reusable: workspace repos call this to build their image
cloud/setup.sh              installs workspace images on a cloud session VM
```
