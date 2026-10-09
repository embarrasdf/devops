# devops

Shared build infrastructure for the embarrasdf Kotlin Multiplatform repos.

## Build images

Two kinds of Docker image, both in GitHub Container Registry (GHCR):

| Image | Contents | Rebuilt |
| --- | --- | --- |
| `ghcr.io/embarrasdf/kmp-toolchain` | JDK, Android SDK, git-lfs | When `toolchain/` changes on `main`, monthly, or by hand |
| `ghcr.io/<owner>/<repo>-cache` | The toolchain, plus one repo's downloaded dependencies, Kotlin/Native and Gradle build cache | When that repo's own workflow says so |

Each cache image is built on top of the toolchain image, so a build that uses it
gets the same JDK and SDK the cache was made with.

### Changing toolchain versions

Edit [`toolchain/versions.env`](toolchain/versions.env) and merge to `main`.
Cloud sessions, cache images and CI all get their versions from there.
Renovate keeps the JDK and git-lfs lines current.

### Adding a repo

1. Add `.github/workflows/cache-image.yml` to the repo (copy uievent's). Its
   `on:` block decides when the image rebuilds, and `warm-tasks` lists the
   Gradle tasks whose dependencies and outputs get cached.
2. In the `kmp-toolchain` package settings, under **Manage Actions access**,
   give the repo read access.
3. Run the workflow once by hand, then add the image to `CACHES` in
   [`cloud/setup.sh`](cloud/setup.sh).

While this repo is private, only private repos owned by `embarrasdf` can use its
workflows (Settings → Actions → General → Access must allow the organization).

## Files

```
toolchain/
  versions.env              every toolchain version
  install-toolchain.sh      installs them (runs in the image build)
  Dockerfile                kmp-toolchain
  session/                  copied into cloud sessions by cloud/setup.sh
    apply.sh                  installs the toolchain and caches on a session VM
    central-mirror.init.gradle.kts   sends Maven Central traffic to Google's mirror
actions/cache-image/        builds and pushes <repo>-cache
.github/workflows/
  build-toolchain.yml       builds kmp-toolchain
  cache-image.yml           reusable: repos call this to build their cache image
cloud/setup.sh              the Claude Code on the web environment setup script
```

## Cloud sessions (Claude Code on the web)

Sessions can't boot from a custom image, so [`cloud/setup.sh`](cloud/setup.sh)
pulls the images and copies their contents onto the session VM. The environment
then snapshots the result for later sessions.

To set up an environment:

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
