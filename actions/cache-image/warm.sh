#!/usr/bin/env bash
# Runs inside the cache image build (see Dockerfile): builds the repo to fill
# the Gradle caches, then splits $GRADLE_USER_HOME into /out/deps and /out/build.
#
#   warm.sh <gradle task> [<gradle task> ...]

set -euo pipefail

# The previous image's copy may be older than this toolchain's.
mkdir -p "$GRADLE_USER_HOME/init.d"
cp /opt/toolchain/session/central-mirror.init.gradle.kts "$GRADLE_USER_HOME/init.d/"

cd /src/repo
./gradlew "$@" --no-daemon --build-cache --stacktrace

cd "$GRADLE_USER_HOME"
# Per-machine state that shouldn't be shipped.
rm -rf daemon native .tmp gradle.properties
find . -name '*.lock' -delete

# The build cache and Gradle's bookkeeping (journal-1) change on every build.
mkdir -p /out/deps /out/build
for dir in build-cache-1 journal-1; do
  if [ -d "caches/$dir" ]; then mv "caches/$dir" /out/build/; fi
done
find . -mindepth 1 -maxdepth 1 -exec mv {} /out/deps/ \;
