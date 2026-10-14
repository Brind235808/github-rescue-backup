#!/usr/bin/env bash
# Convert a PUBLIC fork you own into a PRIVATE repo holding the same content.
#
# GitHub hard-refuses to flip a public fork to private:
#   422 Validation Failed: "Public forks can't be made private"
# So the only working path is COPY -> DELETE -> RENAME:
#   1. create a new private repo NAME-tmp
#   2. mirror-copy the fork's content into it
#   3. delete the public fork
#   4. rename NAME-tmp -> NAME
#
# Requires the delete_repo scope:
#   gh auth refresh -h github.com -s delete_repo
#
# Usage:
#   ./convert-fork-private.sh YOU/REPO
#
# If `github.com` git is blocked but `api.github.com` works, run steps 1-2 as a
# GitHub Actions job instead (see references/cloud-sync.md) — the runner has
# reliable access to github.com.
set -euo pipefail

slug="${1:?usage: convert-fork-private.sh OWNER/REPO}"
owner="${slug%%/*}"
name="${slug##*/}"
tmp="${name}-tmp"

echo "==> [1/4] create private $owner/$tmp"
if gh api "repos/$owner/$tmp" >/dev/null 2>&1; then
  echo "    already exists"
else
  gh api -X POST user/repos -f name="$tmp" -F private=true >/dev/null
  sleep 5
fi

echo "==> [2/4] mirror-copy content $slug -> $owner/$tmp"
d="$(mktemp -d)"
trap 'rm -rf "$d"' EXIT
git clone --mirror "https://github.com/$slug.git" "$d/r.git"
# heads+tags only — a full `--mirror` push also tries refs/pull/* and GitHub
# rejects it with "deny updating a hidden ref" (any repo with PRs hits this)
git -C "$d/r.git" push --prune --force "https://github.com/$owner/$tmp.git" \
  "refs/heads/*:refs/heads/*" "refs/tags/*:refs/tags/*"

echo "==> [3/4] delete public fork $slug"
gh api -X DELETE "repos/$slug"

echo "==> [4/4] rename $tmp -> $name"
gh api -X PATCH "repos/$owner/$tmp" -f name="$name" >/dev/null

echo "done: $owner/$name is now private"
