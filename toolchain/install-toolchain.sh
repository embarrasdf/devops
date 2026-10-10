#!/usr/bin/env bash
# Installs the JDK, Android SDK, git-lfs and headless Chrome listed in versions.env.
# Runs while building the kmp-toolchain image (see Dockerfile).
#
# Layout it produces, which cloud/setup.sh and session/apply.sh rely on:
#   /opt/jdk                  JDK (JAVA_HOME)
#   /opt/android-sdk          Android SDK (ANDROID_HOME)
#   /usr/local/bin/git-lfs
#   /opt/chrome               chrome-headless-shell (CHROME_BIN), for CI only
#
# The Android SDK comes from the archive zips directly rather than through
# sdkmanager: sdkmanager is a JVM tool that doesn't pick up the cloud
# environment's proxy, and fetching the zips keeps every download a plain curl.

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

while read -r dest archive; do
  [ -n "$dest" ] || continue
  log "Android SDK ${dest} (${archive})"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/pkg.zip" "https://dl.google.com/android/repository/${archive}"
  unzip -q "$tmp/pkg.zip" -d "$tmp/x"
  # Each zip holds a single top-level directory, named inconsistently
  # (build-tools zips use "android-16", for example). Move it into place.
  top="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -1)"
  mkdir -p "$(dirname "$ANDROID_HOME/$dest")"
  rm -rf "${ANDROID_HOME:?}/$dest"
  mv "$top" "$ANDROID_HOME/$dest"
  rm -rf "$tmp"
done <<< "$ANDROID_SDK_PACKAGES"

# Accept the SDK license (Google's published hashes) so AGP doesn't try to.
mkdir -p "$ANDROID_HOME/licenses"
printf '\n8933bad161af4178b1185d1a37fbf41ea5269c55\nd56f5187479451eabf01fb78af6dfcb131a6481e\n24333f8a63b6825ea9c5514f83c2829b004d1fee\n' \
  > "$ANDROID_HOME/licenses/android-sdk-license"

log "git-lfs ${GIT_LFS_VERSION}"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/git-lfs.tar.gz" \
  "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-amd64-v${GIT_LFS_VERSION}.tar.gz"
tar -xzf "$tmp/git-lfs.tar.gz" -C "$tmp"
install -m0755 "$(find "$tmp" -type f -name git-lfs | head -1)" /usr/local/bin/git-lfs
rm -rf "$tmp"

log "chrome-headless-shell ${CHROME_VERSION}"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/chrome.zip" \
  "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-headless-shell-linux64.zip"
unzip -q "$tmp/chrome.zip" -d "$tmp"
rm -rf /opt/chrome
mv "$tmp/chrome-headless-shell-linux64" /opt/chrome
rm -rf "$tmp"
/opt/chrome/chrome-headless-shell --version

log "Toolchain installed"
