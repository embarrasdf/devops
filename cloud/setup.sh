#!/usr/bin/env bash
# Claude Code on the web environment setup script.
# Paste this into the environment's settings (Setup script). It runs as root
# before the repositories are cloned, and the result is snapshotted for later
# sessions. It holds no versions or install steps: those live in
# embarrasdf/devops (toolchain/versions.env, toolchain/session/apply.sh) and
# arrive inside the images.
#
# Registry access needs a classic GitHub token with only the read:packages
# scope, given to the environment one of two ways:
# - as an API credential for ghcr.io (Pro and Max plans), which the session
#   proxy adds to requests so the token never enters the session, or
# - as the environment variable GHCR_TOKEN.
#
# The snapshot is rebuilt when this script changes or after about 7 days.
# To pick up newer images sooner, change the date below.
# Snapshot refreshed: 2026-10-07

set -uo pipefail

# The workspace images to install, usually one. Each holds the toolchain plus
# the caches from building every repo in devops/workspace/<name>.repos.
WORKSPACES="ghcr.io/embarrasdf/embarrasdf-workspace:latest"
# Used only if no workspace image can be pulled.
TOOLCHAIN="ghcr.io/embarrasdf/kmp-toolchain:latest"

log() { echo "==> $*"; }

# Docker is installed but its daemon isn't running yet.
dockerd >/var/log/dockerd.log 2>&1 &
for _ in $(seq 30); do docker info >/dev/null 2>&1 && break; sleep 1; done

if [ -n "${GHCR_TOKEN:-}" ]; then
  echo "$GHCR_TOKEN" | docker login ghcr.io -u token --password-stdin
fi

for image in $WORKSPACES; do docker pull -q "$image" & done
wait

pulled=""
for image in $WORKSPACES; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    pulled="$pulled $image"
  else
    log "warning: couldn't pull $image; continuing without it"
  fi
done

# Workspace images are built on the toolchain image, so the first one also
# supplies the toolchain.
toolchain="${pulled# }"
toolchain="${toolchain%% *}"
if [ -z "$toolchain" ]; then
  log "warning: no workspace image; installing the toolchain without caches"
  docker pull -q "$TOOLCHAIN" || { log "error: couldn't pull $TOOLCHAIN"; exit 1; }
  toolchain="$TOOLCHAIN"
fi

cid="$(docker create "$toolchain")"
rm -rf /tmp/toolchain-session
docker cp "$cid:/opt/toolchain/session" /tmp/toolchain-session
docker rm "$cid" >/dev/null

# shellcheck disable=SC2086
bash /tmp/toolchain-session/apply.sh "$toolchain" $pulled
status=$?

# Free the disk: the snapshot only needs the copied files.
docker system prune -af >/dev/null 2>&1 || true
exit $status
