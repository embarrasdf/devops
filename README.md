# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

## Build images

Three kinds of Docker image, all in GitHub Container Registry (GHCR):

| Image | Contents | Used by | Rebuilt |
| --- | --- | --- | --- |
| `ghcr.io/embarrasdf/kmp-toolchain` | JDK, Android SDK, git-lfs | Everything below | When `toolchain/` changes on `main`, monthly, or by hand |
| `ghcr.io/embarrasdf/<repo>-cache` | The toolchain, plus one repo's dependencies, Kotlin/Native, Kotlin npm tooling and Gradle build cache | That repo's CI | When that repo's own workflow says so |
| `ghcr.io/embarrasdf/embarrasdf-workspace` | The toolchain, plus the same caches for every repo in [`workspace/embarrasdf.repos`](workspace/embarrasdf.repos) | Cloud sessions | Nightly, when the list changes, or by hand |

Cache and workspace images are built on top of the toolchain image, so a build
that uses one gets the same JDK and SDK its caches were made with. Both kinds
come from the same Dockerfile; a `<repo>-cache` image is a workspace of one.

### Changing toolchain versions

Edit [`toolchain/versions.env`](toolchain/versions.env) and merge to `main`.
Cloud sessions, cache images and CI all get their versions from there.
Renovate keeps the JDK and git-lfs lines current.

### Adding or removing a repo in the workspace image

Edit [`workspace/embarrasdf.repos`](workspace/embarrasdf.repos): one line per
repo, with the Gradle tasks that fill its caches. Merge to `main`, and the
image rebuilds. A new repo also has to be one the workspace GitHub App can read
(see below); with the app installed on all repositories, it already is.

### Giving a repo its own CI cache image

1. Add `.github/workflows/cache-image.yml` to the repo (copy uievent's). Its
   `on:` block decides when the image rebuilds, and `warm-tasks` lists the
   Gradle tasks whose dependencies and outputs get cached.
2. In the `kmp-toolchain` package settings, under **Manage Actions access**,
   give the repo read access.
3. Run the workflow once by hand.

The image builds the repo on its own, without gradle-plugins beside it, the
same way the repo's CI does, so the cached outputs match CI's builds.

While this repo is private, only private repos owned by `embarrasdf` can use its
workflows (Settings → Actions → General → Access must allow the organization).

## One-time setup

### Workspace GitHub App

The workspace workflow needs to clone private repos, which this repo's own
Actions token can't read. A GitHub App owned by the organization provides a
short-lived token instead:

1. Organization settings → Developer settings → GitHub Apps → **New GitHub App**.
   Name it (for example `embarrasdf-workspace`), turn off **Webhook**, and under
   **Repository permissions** set **Contents** to **Read-only**. Nothing else.
2. Create it, then **Generate a private key** (a `.pem` file downloads).
3. **Install App** on `embarrasdf`, for all repositories or the ones in the list.
4. In this repo's Settings → Secrets and variables → Actions, add the variable
   `WORKSPACE_APP_ID` (the app's ID, on its settings page) and the secret
   `WORKSPACE_APP_PRIVATE_KEY` (the contents of the `.pem` file).

### Cloud environment

Sessions can't boot from a custom image, so [`cloud/setup.sh`](cloud/setup.sh)
pulls the workspace image and copies its contents onto the session VM. The
environment then snapshots the result for later sessions.

1. Create a classic GitHub token with only the `read:packages` scope, and give
   it an expiry. ghcr.io doesn't document support for fine-grained tokens.
2. Give the environment the token, either way:
   - **API credential** (Pro and Max plans): the session proxy adds it to
     requests for `ghcr.io`, so the token never enters the session. Use
     Credential type Bearer, header `Authorization`, and the base64 of the
     token as the value. This hasn't been tested with `docker pull` yet; if
     pulls fail with 401, use the variable instead.
   - **Environment variable** `GHCR_TOKEN=<token>`. Claude and anyone using the
     environment can read it.
3. Paste `cloud/setup.sh` as the setup script.

The snapshot is rebuilt when the setup script changes or after about 7 days.
To pick up newer images sooner, change the date line in the script.

`WORKSPACES` in the script can list more than one workspace image, but their
Gradle dependency indexes overwrite each other when merged, so the second
workspace's dependencies get re-checked over the network. One workspace per
cloud environment avoids that.

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
workspace/
  embarrasdf.repos          the repos in embarrasdf-workspace
  clone.sh                  clones a workspace's repos side by side
.github/workflows/
  build-toolchain.yml       builds kmp-toolchain
  build-workspace-image.yml builds the workspace images
  cache-image.yml           reusable: repos call this to build their CI cache image
cloud/setup.sh              the Claude Code on the web environment setup script
```
