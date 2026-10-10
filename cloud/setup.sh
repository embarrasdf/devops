#!/usr/bin/env bash
# Installs workspace images on a Claude Code on the web session VM. A cloud
# environment's setup script sets WORKSPACES and runs this; see
# cloud-setup.sh in embarrasdf/workspace. It runs as root before the
# repositories are cloned, and the result is snapshotted for later sessions.
#
#   WORKSPACES="ghcr.io/embarrasdf/embarrasdf-workspace:latest" bash setup.sh
#
# WORKSPACES lists one or more images built by the cache-image action, usually
# one. Each holds the toolchain plus the caches from building a set of repos.
# Versions and install steps aren't here: they live in toolchain/ and arrive
# inside the images.
#
# Registry access needs a classic GitHub token with only the read:packages
# scope, exported as GHCR_TOKEN by the environment's setup script itself.
# Neither the environment's variables nor its network secrets reach the setup
# script: variables are given to the session only, and the session proxy that
# adds network secrets starts after setup. The login is removed on exit, so
# the token isn't kept in the snapshot.

set -uo pipefail

WORKSPACES="${WORKSPACES:?set WORKSPACES to the workspace images to install}"
GHCR_TOKEN="${GHCR_TOKEN:?export GHCR_TOKEN in the setup script; see the header of this script}"
# Used only if no workspace image can be pulled, such as before its first
# build.
TOOLCHAIN="${TOOLCHAIN:-ghcr.io/embarrasdf/kmp-toolchain:latest}"

log() { echo "==> $*"; }

# Docker is installed but its daemon isn't running yet.
dockerd >/var/log/dockerd.log 2>&1 &
for _ in $(seq 30); do docker info >/dev/null 2>&1 && break; sleep 1; done

if ! echo "$GHCR_TOKEN" | docker login ghcr.io -u token --password-stdin; then
  log "error: docker login to ghcr.io failed; check GHCR_TOKEN"
  exit 1
fi
trap 'docker logout ghcr.io >/dev/null 2>&1 || true' EXIT

# Wait on the pulls only: a bare `wait` also waits on dockerd, which never
# exits, so the script would hang until the environment kills it.
pids=()
for image in $WORKSPACES; do docker pull -q "$image" & pids+=("$!"); done
wait "${pids[@]}"

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

# Claude Code plugin marketplaces that workspace images carry, such as
# embarrasdf/harness (see workspace-image.yml's claude-marketplaces).
rm -rf /opt/claude-marketplaces
mkdir -p /opt/claude-marketplaces
for image in $pulled; do
  cid="$(docker create "$image")"
  docker cp "$cid:/opt/claude-marketplaces/." /opt/claude-marketplaces/ 2>/dev/null || true
  docker rm "$cid" >/dev/null
done

# Claude Code's user settings, which apply in every session whatever folder it
# starts in. A session with several repos starts in the folder they're cloned
# into, where no repo's own .claude/ is read.
# - Its shell snapshot keeps only PATH from the shell profile, so pass the
#   toolchain's other variables here.
# - Register each marketplace and enable all its plugins. Claude Code loads
#   plugins from a directory marketplace in place, so nothing is installed now,
#   when the claude CLI may not be there yet.
python3 - /root/.claude/settings.json /opt/claude-marketplaces <<'EOF' || status=1
import json, os, sys
path, marketplaces = sys.argv[1:]
settings = json.load(open(path)) if os.path.exists(path) else {}
env = settings.setdefault("env", {})
env.update(ANDROID_HOME="/opt/android-sdk", ANDROID_SDK_ROOT="/opt/android-sdk", JAVA_HOME="/opt/jdk")
if os.access("/opt/pw-browsers/chromium", os.X_OK):
    env["CHROME_BIN"] = "/opt/pw-browsers/chromium"
for repo in sorted(os.listdir(marketplaces)):
    root = os.path.join(marketplaces, repo)
    manifest = os.path.join(root, ".claude-plugin", "marketplace.json")
    if not os.path.isfile(manifest):
        print(f"==> warning: {root} has no .claude-plugin/marketplace.json; skipping it")
        continue
    marketplace = json.load(open(manifest))
    name = marketplace["name"]
    settings.setdefault("extraKnownMarketplaces", {})[name] = {
        "source": {"source": "directory", "path": root}
    }
    for plugin in marketplace.get("plugins", []):
        settings.setdefault("enabledPlugins", {})[f"{plugin['name']}@{name}"] = True
    print(f"==> Claude Code marketplace {name} from {repo}")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
EOF

# Free the disk: the snapshot only needs the copied files.
docker system prune -af >/dev/null 2>&1 || true
exit $status
