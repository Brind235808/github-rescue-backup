#!/usr/bin/env bash
# Fork upstream repositories into your own account (server-side copy of code + tags).
#
# Usage:
#   ./fork-upstream.sh OWNER/REPO [OWNER/REPO ...]
#
# Notes:
#   - GitHub allows only ONE fork per fork-network per account. A second attempt
#     on the same upstream fails ("already have a fork").
#   - Forking too fast trips a secondary rate limit (HTTP 403). We sleep between
#     calls on purpose.
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: fork-upstream.sh OWNER/REPO [...]"; exit 1; }

for slug in "$@"; do
  echo "==> forking $slug"
  if gh repo fork "$slug" --clone=false; then
    echo "    ok"
  else
    echo "    ! failed (already forked, name taken, or rate limited)"
  fi
  sleep 10   # keep clear of the secondary rate limit
done
