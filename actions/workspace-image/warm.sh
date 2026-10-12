#!/usr/bin/env bash
# Runs inside the workspace image build (see Dockerfile): builds every repo in the
# list to fill the shared Gradle, Kotlin/Native and Kotlin npm caches, then
# splits $GRADLE_USER_HOME into /out/deps and /out/build.
#
#   warm.sh <list file>
#
# Each line of the list is "<folder under /src> <gradle task> [<gradle task> ...]".
# A repo whose build fails is reported and skipped, so one broken repo doesn't
# hold back everyone else's caches; the image fails only if every repo fails.

set -uo pipefail

# The previous image's copy may be older than this toolchain's.
mkdir -p "$GRADLE_USER_HOME/init.d"
cp -p /opt/toolchain/session/central-mirror.init.gradle.kts "$GRADLE_USER_HOME/init.d/"

built=()
failed=()
# Gradle versions the repos' wrappers use, to drop caches no repo needs.
versions=()
while read -r dir tasks; do
  case "$dir" in ''|'#'*) continue ;; esac
  echo "==> Warming ${dir}: ${tasks}"
  version="$(sed -n 's|^distributionUrl=.*/gradle-\(.*\)-[a-z]*\.zip$|\1|p' \
    "/src/$dir/gradle/wrapper/gradle-wrapper.properties" 2>/dev/null)"
  if [ -n "$version" ]; then versions+=("$version"); fi
  # Kotlin compiles in Gradle's own JVM rather than a daemon that would otherwise
  # double the memory a build needs.
  # shellcheck disable=SC2086 # tasks are separate arguments
  if (cd "/src/$dir" && ./gradlew $tasks --no-daemon --build-cache --stacktrace \
      -Pkotlin.compiler.execution.strategy=in-process < /dev/null); then
    built+=("$dir")
  else
    failed+=("$dir")
  fi
  # The caches are in the Gradle home; the checkout and its build outputs aren't
  # part of the image, and keeping them can fill the disk.
  rm -rf "/src/${dir:?}"
done < "$1"

echo "==> Built: ${built[*]:-none}"
if [ ${#failed[@]} -gt 0 ]; then
  echo "==> FAILED, caches for these repos are incomplete: ${failed[*]}"
fi
if [ ${#built[@]} -eq 0 ]; then
  exit 1
fi

set -e
cd "$GRADLE_USER_HOME"
# Per-machine state, build reports and file-hash bookkeeping that Gradle and
# Kotlin rewrite on every build. Gradle recreates what it needs.
rm -rf daemon native .tmp gradle.properties kotlin-profile \
  caches/[0-9]*/fileHashes caches/[0-9]*/file-changes
find . -name '*.lock' -delete

# Gradle unpacks the JDKs it provisions next to the archives it downloaded
# them as, and only uses the unpacked copy.
rm -f jdks/*.tar.gz jdks/*.zip

# Each Gradle version has its own caches/<version> and wrapper distribution,
# which this image would otherwise carry forward from the previous one long
# after every repo has moved on, since the timestamps pinned below keep Gradle's
# own cleanup from ever seeing them as unused. The shared caches, such as
# modules-2 and build-cache-1, aren't per version and stay.
if [ ${#versions[@]} -gt 0 ]; then
  echo "==> Keeping Gradle caches for: $(printf '%s\n' "${versions[@]}" | sort -u | tr '\n' ' ')"
  for path in caches/[0-9]*.*/ wrapper/dists/gradle-*/; do
    [ -d "$path" ] || continue
    version="$(basename "$path")"
    version="${version#gradle-}"
    version="${version%-bin}"
    version="${version%-all}"
    if ! printf '%s\n' "${versions[@]}" | grep -qxF "$version"; then
      echo "==> Removing ${path} (Gradle ${version}, no repo uses it)"
      rm -rf "$path"
    fi
  done
fi

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
