#!/usr/bin/env bash
# Installs the JDK, Android SDK and git-lfs listed in versions.env.
# Runs while building the kmp-toolchain image (see Dockerfile).
#
# Layout it produces, which cloud/setup.sh and session/apply.sh rely on:
#   /opt/jdk                  JDK (JAVA_HOME)
#   /opt/android-sdk          Android SDK (ANDROID_HOME)
#   /usr/local/bin/git-lfs
#
# The Android SDK is installed with the SDK's own installer, which writes the
# package.xml each package needs. Without it AGP can't see a platform with a
# minor version, such as android-37.0, and downloads it again in every build.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR
. "$here/versions.env"

JDK_DIR=/opt/jdk
ANDROID_HOME=/opt/android-sdk

log() { echo "==> $*"; }

log "JDK ${JDK_RELEASE}"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/jdk.tar.gz" \
  "https://api.adoptium.net/v3/binary/version/${JDK_RELEASE//+/%2B}/linux/x64/jdk/hotspot/normal/eclipse"
mkdir -p "$JDK_DIR"
tar -xzf "$tmp/jdk.tar.gz" -C "$JDK_DIR" --strip-components=1
rm -rf "$tmp"

log "Android SDK command-line tools ${ANDROID_CMDLINE_TOOLS_BUILD}"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/cmdline-tools.zip" \
  "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_BUILD}_latest.zip"
unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
mkdir -p "$ANDROID_HOME/cmdline-tools"
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
rm -rf "$tmp"

# The Android CLI, with metrics collection off. It accepts the SDK license
# itself, and like any JVM tool takes the proxy from the JVM's settings, not
# HTTPS_PROXY.
android=("$ANDROID_HOME/cmdline-tools/latest/bin/android" --no-metrics --sdk="$ANDROID_HOME")
export JAVA_HOME="$JDK_DIR"
# One package per line; read returns 1 at the end of its input.
read -r -d '' -a packages <<< "$ANDROID_SDK_PACKAGES" || true
log "Android SDK ${packages[*]}"
"${android[@]}" sdk install "${packages[@]}" > /dev/null
# The CLI unpacks a copy of itself (~250 MB) into ~/.android on first run, and
# downloads one again if it's missing.
rm -rf "$ANDROID_HOME/.temp" "$HOME/.android/cli" "$HOME/.android/bin"

log "git-lfs ${GIT_LFS_VERSION}"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/git-lfs.tar.gz" \
  "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-amd64-v${GIT_LFS_VERSION}.tar.gz"
tar -xzf "$tmp/git-lfs.tar.gz" -C "$tmp"
install -m0755 "$(find "$tmp" -type f -name git-lfs | head -1)" /usr/local/bin/git-lfs
rm -rf "$tmp"

log "Toolchain installed"
