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
#   OUTDIR/REPO/<tag>/RELEASE_NOTES.md
#
# Add-only: re-running never deletes or overwrites an existing backup file
# (--skip-existing for assets; the notes file is written only if absent), so
# this is safe to run on a schedule.
#
# Why the notes file: a release's changelog text lives ONLY in the release
# object, never in the tag, so `git clone` misses it. We archive it too.
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
  # archive the notes text too (add-only: an existing file is never rewritten)
  # gh api --jq avoids pulling in an external jq dependency
  nf="$dest/$tag/RELEASE_NOTES.md"
  if [ ! -f "$nf" ]; then
    if gh api "repos/$slug/releases/tags/$tag" --jq '
          "# " + (.name // .tag_name) + "\n\n" +
          "* tag: `" + .tag_name + "`\n" +
          "* published: " + (.published_at // "unknown") + "\n" +
          "* prerelease: " + (.prerelease | tostring) + "\n" +
          "* url: " + (.html_url // "") + "\n\n" +
          "## Notes\n\n" + (.body // "_(no release notes)_") + "\n\n" +
          "## Assets\n\n" +
          ( if ((.assets | length) == 0) then "_upstream uploaded no assets_"
            else ( [ .assets[] | "- `" + .name + "` — " + (.size | tostring) + " bytes" ] | join("\n") ) end ) + "\n"
        ' > "$nf" 2>/dev/null; then
      echo "    + notes archived"
    else
      rm -f "$nf"
    fi
  fi
done <<< "$tags"

echo "saved releases under: $dest"
