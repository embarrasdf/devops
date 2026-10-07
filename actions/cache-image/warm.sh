#!/usr/bin/env bash
# Runs inside the cache image build (see Dockerfile): builds the repo to fill
# the Gradle caches, then splits $GRADLE_USER_HOME into /out/deps and /out/build.
#
#   warm.sh <gradle task> [<gradle task> ...]

set -euo pipefail

# The previous image's copy may be older than this toolchain's.
mkdir -p "$GRADLE_USER_HOME/init.d"
cp -p /opt/toolchain/session/central-mirror.init.gradle.kts "$GRADLE_USER_HOME/init.d/"

cd /src/repo
./gradlew "$@" --no-daemon --build-cache --stacktrace

cd "$GRADLE_USER_HOME"
# Per-machine state, build reports and file-hash bookkeeping that Gradle and
# Kotlin rewrite on every build. Gradle recreates what it needs.
rm -rf daemon native .tmp gradle.properties kotlin-profile \
  caches/[0-9]*/fileHashes caches/[0-9]*/file-changes
find . -name '*.lock' -delete

# The build cache and Gradle's access journal (journal-1) change on every build.
mkdir -p /out/deps /out/build
for dir in build-cache-1 journal-1; do
  if [ -d "caches/$dir" ]; then mv "caches/$dir" /out/build/; fi
done
find . -mindepth 1 -maxdepth 1 -exec mv {} /out/deps/ \;

# Directory timestamps change whenever an entry is added or removed. Pin them so
# the dependencies layer is byte-for-byte identical, and is reused rather than
# downloaded again, when no dependency changed. The toolchain's own timestamp
# keeps them recent enough that Gradle's cache cleanup leaves them alone.
find /out/deps -type d -exec touch -r /opt/toolchain/versions.env {} +
