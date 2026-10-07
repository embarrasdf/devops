#!/usr/bin/env bash
# Sets up a Claude Code on the web session VM from our images.
# cloud/setup.sh copies this folder out of the kmp-toolchain image and runs it
# as root, after pulling the images:
#
#   apply.sh <toolchain-image> [<cache-image> ...]
#
# It copies the toolchain out of the first image, merges each cache image's
# Gradle and Kotlin/Native caches into ~/.gradle and ~/.konan, then writes the
# session config. A cache image that's missing is skipped with a warning; the
# session then downloads those dependencies on first build.

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

mkdir -p ~/.gradle ~/.konan
copy_out "$toolchain_image" /opt/gradle-home/. ~/.gradle/
for image in "$@"; do
  log "Caches from ${image}"
  if ! { copy_out "$image" /opt/gradle-home/. ~/.gradle/ && copy_out "$image" /opt/konan/. ~/.konan/; }; then
    log "warning: couldn't copy caches from ${image}; skipping it"
  fi
done

# Trust the session proxy's CA in this JDK too, in case a JVM tool runs without
# the session's JAVA_TOOL_OPTIONS truststore.
if [ -f /root/.ccr/agent-proxy-ca.crt ]; then
  /opt/jdk/bin/keytool -importcert -noprompt -alias ccr-agent-proxy \
    -file /root/.ccr/agent-proxy-ca.crt \
    -keystore /opt/jdk/lib/security/cacerts -storepass changeit >/dev/null 2>&1 || true
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

# Environment for every session shell.
cat > /etc/profile.d/android-build.sh <<'EOF'
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_HOME=/opt/jdk
export PATH="/opt/jdk/bin:/opt/android-sdk/platform-tools:$PATH"
EOF
chmod +x /etc/profile.d/android-build.sh
grep -q 'android-build.sh' /root/.bashrc 2>/dev/null \
  || echo '[ -f /etc/profile.d/android-build.sh ] && . /etc/profile.d/android-build.sh' >> /root/.bashrc

log "Session ready"
