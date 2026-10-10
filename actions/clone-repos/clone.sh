#!/usr/bin/env bash
# Clones every repo in a workspace list side by side, the way a cloud session
# lays them out, and writes the build list the workspace-image action reads.
# Used by action.yml in this folder.
#
#   clone.sh <destination> <list file> [<list file> ...]
#
# Each line of a list is "<owner>/<repo> <gradle task> [<gradle task> ...]". A
# repo in more than one list is cloned once, with the tasks from its first line.
#
# Credentials, from the environment, for repos that aren't public:
#   APP_ID and APP_PRIVATE_KEY  a GitHub App installed on the owners of the
#                               private repos; a read-only token is made per owner
#   TOKEN                       or one token that can read every repo

set -euo pipefail

dest="$1"
shift
mkdir -p "$dest"
: > "$dest/workspace.repos"

APP_ID="${APP_ID:-}"
APP_PRIVATE_KEY="${APP_PRIVATE_KEY:-}"
TOKEN="${TOKEN:-}"

if [ -n "$APP_ID" ] && [ -z "$APP_PRIVATE_KEY" ]; then
  echo "::error::Got an app ID but no app private key." >&2
  exit 1
fi
if [ -z "$APP_ID" ] && [ -n "$APP_PRIVATE_KEY" ]; then
  echo "::error::Got an app private key but no app ID. If the ID comes from vars.<NAME>, check that <NAME> is a variable, not a secret, under the calling repo's Settings → Secrets and variables → Actions → Variables." >&2
  exit 1
fi

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Prints a read-only token for the app's installation on an owner.
app_token() {
  local owner="$1" now header payload signature jwt installation token
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$APP_ID" | b64url)"
  signature="$(printf '%s.%s' "$header" "$payload" \
    | openssl dgst -sha256 -sign <(printf '%s\n' "$APP_PRIVATE_KEY") | b64url)"
  jwt="$header.$payload.$signature"

  installation="$(curl -fsS -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/users/$owner/installation" | jq -r .id)" || {
    echo "::warning::The GitHub App isn't installed on $owner, or its ID or key is wrong; cloning $owner's repos without credentials, which works only for public ones." >&2
    return 0
  }
  token="$(curl -fsS -X POST -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    -d '{"permissions":{"contents":"read"}}' \
    "https://api.github.com/app/installations/$installation/access_tokens" | jq -r .token)"
  # To the job log through fd 3, since stdout here is captured.
  echo "::add-mask::$token" >&3
  printf '%s' "$token"
}

declare -A owner_tokens
exec 3>&1

# Golden images and other LFS files aren't needed to build.
export GIT_LFS_SKIP_SMUDGE=1

while read -r repo tasks; do
  case "$repo" in ''|'#'*) continue ;; esac
  owner="${repo%%/*}"
  name="${repo#*/}"
  [ -d "$dest/$name" ] && continue

  token="$TOKEN"
  if [ -n "$APP_ID" ]; then
    if [ -z "${owner_tokens[$owner]+set}" ]; then
      owner_tokens[$owner]="$(app_token "$owner")"
    fi
    token="${owner_tokens[$owner]}"
  fi

  url="https://github.com/${repo}.git"
  clone_url="$url"
  [ -n "$token" ] && clone_url="https://x-access-token:${token}@github.com/${repo}.git"
  echo "==> Cloning $repo"
  # Full history and tags: the release plugin derives versions from tags.
  if ! git clone --quiet --filter=blob:none \
      "$clone_url" "$dest/$name"; then
    if [ -z "$token" ]; then
      echo "::error::Couldn't clone $repo without credentials. A private repo needs the GitHub App installed on $owner, or a token." >&2
    else
      echo "::error::Couldn't clone $repo. Check that the app's installation on $owner (or the token) covers it." >&2
    fi
    exit 1
  fi
  # Keep the token out of the image.
  git -C "$dest/$name" remote set-url origin "$url"
  echo "$name $tasks" >> "$dest/workspace.repos"
done < <(cat "$@")
