#!/usr/bin/env bash
# Snapshot a repo's SOURCE FILES into a path inside a private backup repo.
#
# Why: a fork is only a pointer into GitHub's fork-network. If GitHub removes
# the whole network (DMCA / abuse), the fork goes too. A file-level snapshot in
# an unrelated private repo is the last line of defence.
#
# CRITICAL: this uses `git clone`, NEVER a tarball. GitHub's tarball honours
# `.gitattributes` `export-ignore`; some authors write `/* export-ignore`, which
# strips EVERY file from the tarball (leaving only README-GITHUB.txt). `git
# clone` ignores `export-ignore` and always fetches the real tree.
#
# Usage:
#   ./snapshot-source.sh OWNER/REPO YOU/BACKUP-REPO PATH_INSIDE_BACKUP
set -euo pipefail

src="${1:?usage: snapshot-source.sh OWNER/REPO YOU/BACKUP-REPO PATH_INSIDE_BACKUP}"
backup="${2:?missing backup repo slug}"
dest="${3:?missing destination path}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> clone $src (full tree, ignores export-ignore)"
git clone --depth 1 "https://github.com/$src.git" "$tmp/src"

echo "==> clone backup repo $backup"
gh repo clone "$backup" "$tmp/backup"

mkdir -p "$tmp/backup/$dest"

echo "==> snapshot into $dest"
rm -rf "$tmp/backup/$dest"
mkdir -p "$tmp/backup/$dest"
cp -r "$tmp/src/." "$tmp/backup/$dest/"
rm -rf "$tmp/backup/$dest/.git"

cd "$tmp/backup"
git add "$dest"
if git commit -m "snapshot: $src @ $(date -u +%Y-%m-%dT%H:%MZ)"; then
  git push
  echo "    pushed"
else
  echo "    no changes"
fi
