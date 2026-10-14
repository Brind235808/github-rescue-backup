#!/usr/bin/env bash
# Download EVERY Release asset of a repo.
#
# Why this matters: a fork and a `git clone` do NOT carry Release assets — they
# are standalone binaries uploaded separately. If the author deletes the repo,
# the releases disappear too. This script fetches them explicitly.
#
# Usage:
#   ./backup-releases.sh OWNER/REPO [OUTDIR]
#
# Output layout:
#   OUTDIR/REPO/<tag>/<asset files>
#
# Add-only: re-running never deletes or overwrites an existing backup file
# (--skip-existing), so this is safe to run on a schedule.
#
# Reads go through api.github.com, which is often reachable even when
# github.com (git) is blocked or flaky.
set -euo pipefail

slug="${1:?usage: backup-releases.sh OWNER/REPO [OUTDIR]}"
out="${2:-./_releases}"
name="${slug##*/}"
dest="$out/$name"

mkdir -p "$dest"

tags="$(gh api "repos/$slug/releases" --paginate --jq '.[].tag_name' || true)"
if [ -z "$tags" ]; then
  echo "==> $slug has no releases"
  exit 0
fi

while IFS= read -r tag; do
  [ -z "$tag" ] && continue
  echo "==> $slug @ $tag"
  mkdir -p "$dest/$tag"
  # gh release download talks to api.github.com and grabs all assets for a tag
  gh release download "$tag" -R "$slug" -D "$dest/$tag" --skip-existing 2>/dev/null \
    || echo "    (no downloadable assets for $tag)"
done <<< "$tags"

echo "saved releases under: $dest"
