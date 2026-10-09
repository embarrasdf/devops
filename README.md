# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

## Build images

Three kinds of Docker image, all in GitHub Container Registry (GHCR):

| Image | Contents | Used by | Rebuilt |
| --- | --- | --- | --- |
| `ghcr.io/embarrasdf/kmp-toolchain` | JDK, Android SDK, git-lfs | Everything below | When `toolchain/` changes on `main`, monthly, or by hand |
| `ghcr.io/embarrasdf/<repo>-cache` | The toolchain, plus one repo's dependencies, Kotlin/Native, Kotlin npm tooling and Gradle build cache | That repo's CI | When that repo's own workflow says so |
| `ghcr.io/embarrasdf/<name>-workspace` | The toolchain, plus the same caches for a set of repos built side by side | Cloud sessions | By the private repo that lists the repos (embarrasdf/workspace) |

Cache and workspace images are built on top of the toolchain image, so a build
that uses one gets the same JDK and SDK its caches were made with. Both kinds
come from the same Dockerfile; a `<repo>-cache` image is a workspace of one.

### Changing toolchain versions

Edit [`toolchain/versions.env`](toolchain/versions.env) and merge to `main`.
Cloud sessions, cache images and CI all get their versions from there.
Renovate keeps the JDK and git-lfs lines current.

### Workspace images

A workspace image is built from a list of repos kept in a private repo (for
embarrasdf, `embarrasdf/workspace`), so private repo names stay private. That
repo calls the reusable [`workspace-image.yml`](.github/workflows/workspace-image.yml)
with its list file, the image name, and credentials that can clone the repos;
the header of that workflow shows the call. It clones the repos side by side
with [`actions/clone-repos`](actions/clone-repos) and builds with
[`actions/cache-image`](actions/cache-image).

### Giving a repo its own CI cache image

1. Add `.github/workflows/cache-image.yml` to the repo (copy uievent's). Its
   `on:` block decides when the image rebuilds, and `warm-tasks` lists the
   Gradle tasks whose dependencies and outputs get cached.
2. In the `kmp-toolchain` package settings, under **Manage Actions access**,
   give the repo read access.
3. Run the workflow once by hand.

The image builds the repo on its own, without gradle-plugins beside it, the
same way the repo's CI does, so the cached outputs match CI's builds.

The repo is public, so any repo can use its workflows and actions.

## Cloud sessions (Claude Code on the web)

Sessions can't boot from a custom image, so [`cloud/setup.sh`](cloud/setup.sh)
pulls workspace images and copies their contents onto the session VM; the
environment then snapshots the result for later sessions. A cloud environment's
own setup script sets `WORKSPACES` and runs it, so the same installer serves any
workspace. The header of `cloud/setup.sh` covers the registry token.

## Files

```
toolchain/
  versions.env              every toolchain version
  install-toolchain.sh      installs them (runs in the image build)
  Dockerfile                kmp-toolchain
  session/                  copied into cloud sessions by cloud/setup.sh
    apply.sh                  installs the toolchain and caches on a session VM
    central-mirror.init.gradle.kts   sends Maven Central traffic to Google's mirror
actions/cache-image/        builds and pushes a cache or workspace image
  Dockerfile, warm.sh         shared by both kinds
actions/clone-repos/        clones a workspace list side by side
.github/workflows/
  build-toolchain.yml       builds kmp-toolchain
  cache-image.yml           reusable: repos call this to build their CI cache image
  workspace-image.yml       reusable: workspace repos call this to build their image
cloud/setup.sh              installs workspace images on a cloud session VM
```
