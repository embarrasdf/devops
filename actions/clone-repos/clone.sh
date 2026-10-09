#!/usr/bin/env bash
# Clones every repo in a workspace list side by side, the way a cloud session
# lays them out, and writes the build list the cache-image action reads.
# Used by action.yml in this folder.
#
#   TOKEN=<token that can read the repos> clone.sh <list file> <destination>
#
# Each line of the list is "<owner>/<repo> <gradle task> [<gradle task> ...]".

set -euo pipefail

list="$1"
dest="$2"
mkdir -p "$dest"
: > "$dest/workspace.repos"

# Golden images and other LFS files aren't needed to build.
export GIT_LFS_SKIP_SMUDGE=1

while read -r repo tasks; do
  case "$repo" in ''|'#'*) continue ;; esac
  name="${repo#*/}"
  echo "==> Cloning $repo"
  # Full history and tags: the release plugin derives versions from tags.
  git clone --quiet --filter=blob:none \
    "https://x-access-token:${TOKEN}@github.com/${repo}.git" "$dest/$name"
  # Keep the token out of the image.
  git -C "$dest/$name" remote set-url origin "https://github.com/${repo}.git"
  echo "$name $tasks" >> "$dest/workspace.repos"
done < "$list"
