#!/usr/bin/env bash
# Sets up a Claude Code on the web session VM from our images.
# cloud/setup.sh copies this folder out of a pulled image and runs it as root:
#
#   apply.sh <toolchain-image> [<cache-image> ...]
#
# It copies the toolchain out of the first image, merges each cache image's
# Gradle, Kotlin/Native and Kotlin npm caches into ~/.gradle, ~/.konan and
# ~/.kotlin, then writes the session config. A cache image that's missing is
# skipped with a warning; the session then downloads those dependencies on
# first build.

set -euo pipefail

toolchain_image="$1"; shift

log() { echo "==> $*"; }

# Copies a path out of an image without running it.
copy_out() { # <image> <path in image> <destination>
  local cid
  cid="$(docker create "$1")"
  docker cp "$cid:$2" "$3"
  docker rm "$cid" >/dev/null
}

log "Toolchain from ${toolchain_image}"
rm -rf /opt/jdk /opt/android-sdk
copy_out "$toolchain_image" /opt/jdk /opt/
copy_out "$toolchain_image" /opt/android-sdk /opt/
copy_out "$toolchain_image" /usr/local/bin/git-lfs /usr/local/bin/

mkdir -p ~/.gradle ~/.konan ~/.kotlin/kotlin-npm-tooling
copy_out "$toolchain_image" /opt/gradle-home/. ~/.gradle/
for image in "$@"; do
  log "Caches from ${image}"
  if ! { copy_out "$image" /opt/gradle-home/. ~/.gradle/ \
      && copy_out "$image" /opt/konan/. ~/.konan/ \
      && copy_out "$image" /root/.kotlin/kotlin-npm-tooling/. ~/.kotlin/kotlin-npm-tooling/; }; then
    log "warning: couldn't copy caches from ${image}; skipping it"
  fi
done

# Trust the session proxy's CA in this JDK too, in case a JVM tool runs without
# the session's JAVA_TOOL_OPTIONS truststore. The CA doesn't exist yet while
# setup runs: each session adds it to the system Java truststore when it
# starts, so point the JDK at that store instead of importing the CA here.
if [ -f /etc/ssl/certs/java/cacerts ]; then
  ln -sf /etc/ssl/certs/java/cacerts /opt/jdk/lib/security/cacerts
fi

# Fetch Paparazzi golden images from LFS on every clone.
git lfs install --system --skip-repo || true

# Gradle settings for every session.
gp=~/.gradle/gradle.properties
touch "$gp"
sed -i '/^org.gradle.java.installations.paths=/d; /^warningsAsErrors=/d' "$gp"
cat >> "$gp" <<'EOF'
org.gradle.java.installations.paths=/opt/jdk
warningsAsErrors=false
EOF

# Environment for every session shell. The zz- prefix sorts it after the
# image's java.sh, which would otherwise set JAVA_HOME to its own JDK.
rm -f /etc/profile.d/android-build.sh
cat > /etc/profile.d/zz-android-build.sh <<'EOF'
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_HOME=/opt/jdk
export PATH="/opt/jdk/bin:/opt/android-sdk/platform-tools:$PATH"
# Kotlin/Wasm browser tests run in the Chromium that ships with the session image.
if [ -x /opt/pw-browsers/chromium ]; then export CHROME_BIN=/opt/pw-browsers/chromium; fi
EOF
chmod +x /etc/profile.d/zz-android-build.sh
# Source it from the top of .bashrc: below the early return for non-interactive
# shells it never runs there. Drops the line for the old android-build.sh too.
{
  echo '[ -f /etc/profile.d/zz-android-build.sh ] && . /etc/profile.d/zz-android-build.sh'
  grep -vF 'android-build.sh' /root/.bashrc 2>/dev/null || true
} > /root/.bashrc.new
mv /root/.bashrc.new /root/.bashrc

log "Session ready"
