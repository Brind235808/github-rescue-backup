# Daily cloud sync (GitHub Actions)

Run the syncing **on GitHub's servers** so your PC can be off — and, crucially,
so it works even when `github.com` git is blocked or flaky on your own machine
(runners always have clean access).

There are two shapes, depending on whether the repo is a **fork** or a **mirror**.

## A. Sync your forks — `merge-upstream` API

The cheapest approach: no checkout at all, just tell GitHub to fast-forward your
fork from upstream. Works for every active fork.

```yaml
# .github/workflows/fork-sync.yml  (put this in a private "control" repo)
name: Sync forks
on:
  schedule: [{ cron: '0 2 * * *' }]   # daily 02:00 UTC
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: |
          forks=(
            "you/ForkA:upstreamOwner/RepoA:main"
            "you/ForkB:upstreamOwner/RepoB:master"
          )
          for entry in "${forks[@]}"; do
            IFS=: read -r me up branch <<< "$entry"
            echo "==> $me"
            gh api -X POST "repos/$me/merge-upstream" \
              -f branch="$branch" >/dev/null 2>&1 \
              && echo "    synced" || echo "    no update / conflict"
          done
```

## B. Mirror a non-fork upstream — append-only clone + push

For repos that are plain mirrors (not forks), a runner clones the upstream (full
history, ignores `export-ignore`) and updates your private repo. It must be
**append-only**: never prune, and freeze the old head before any history
rewrite — otherwise an upstream deletion or force-push would wipe your "backup"
itself (see #11 in `pitfalls.md`).

```yaml
# .github/workflows/mirror-sync.yml  (in your private "control" repo)
name: Mirror upstreams (append-only)
on:
  schedule: [{ cron: '0 2 * * *' }]
  workflow_dispatch:
concurrency: { group: mirror-sync, cancel-in-progress: false }
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: |
          OWNER=you
          TODAY=$(date -u +%Y%m%d)
          # mine:upstream_full_name:upstream_id   ← id is immutable, pins the upstream
          map=("Repo1:OwnerA/Repo1:123456" "Repo2:OwnerB/Repo2:789012")
          fail=0
          for entry in "${map[@]}"; do
            IFS=: read -r mine up pinned <<< "$entry"
            cur=$(gh api "repositories/$pinned" --jq .full_name 2>/dev/null || true)
            if [ -z "$cur" ]; then echo "MISSING $up — keeping backup untouched"; fail=1; continue; fi
            [ "$cur" != "$up" ] && echo "NOTE renamed: $up -> $cur"
            rm -rf "/tmp/$mine.git"
            git clone --quiet --mirror "https://x-access-token:${GH_TOKEN}@github.com/${cur}.git" "/tmp/$mine.git" \
              || { echo "CLONE FAIL $cur"; fail=1; continue; }
            MIRROR="https://x-access-token:${GH_TOKEN}@github.com/${OWNER}/${mine}.git"
            git -C "/tmp/$mine.git" remote add mine "$MIRROR"
            git -C "/tmp/$mine.git" fetch --quiet mine '+refs/heads/*:refs/remotes/mine/*' || true
            while read -r b; do
              [ -z "$b" ] && continue
              U=$(git -C "/tmp/$mine.git" rev-parse "refs/heads/$b")
              O=$(git -C "/tmp/$mine.git" rev-parse -q --verify "refs/remotes/mine/$b" 2>/dev/null || true)
              if [ -n "$O" ] && [ "$U" != "$O" ] && ! git -C "/tmp/$mine.git" merge-base --is-ancestor "$O" "$U"; then
                git -C "/tmp/$mine.git" push --quiet "$MIRROR" \
                  "refs/remotes/mine/$b:refs/tags/archive-$b-$TODAY-${O:0:8}" || true
              fi
              git -C "/tmp/$mine.git" push --quiet --force "$MIRROR" "refs/heads/$b:refs/heads/$b" || fail=1
            done < <(git -C "/tmp/$mine.git" for-each-ref --format='%(refname:short)' refs/heads)
            git -C "/tmp/$mine.git" push --quiet "$MIRROR" "refs/tags/*:refs/tags/*" || true   # add-only
            rm -rf "/tmp/$mine.git"
          done
          exit $fail
```

> Prefer `git clone` over a tarball everywhere: tarballs honour
> `export-ignore`, which can hand you an empty snapshot. See `pitfalls.md`.

## C. One-shot privatize on the runner

If your own `github.com` access is blocked, do the fork→private copy **inside an
Action** instead of locally. Here `--prune` is safe because the target `-tmp` is a
brand-new repo (nothing to lose) — unlike Job 5's ongoing backups:

```yaml
name: Privatize forks
on: { workflow_dispatch: {} }
jobs:
  copy:
    runs-on: ubuntu-latest
    steps:
      - env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: |
          forks=(ForkA ForkB ForkC)
          for f in "${forks[@]}"; do
            git clone --quiet --mirror \
              "https://x-access-token:${GH_TOKEN}@github.com/you/${f}.git" "/tmp/$f.git"
            # push heads+tags only: a full `--mirror` push also tries refs/pull/* and
            # GitHub rejects it with "deny updating a hidden ref" (grown-up forks have PR refs)
            git -C "/tmp/$f.git" push --quiet --prune --force \
              "https://x-access-token:${GH_TOKEN}@github.com/you/${f}-tmp.git" \
              "refs/heads/*:refs/heads/*" "refs/tags/*:refs/tags/*"
          done
```

## D. Archive Releases (add-only: assets **and** the notes text)

Release assets are standalone binaries — not in git, so no mirror captures them.
Capture them **once a day, add-only** (never delete or overwrite an existing
file). Archive the release **notes** too: the changelog lives only in the
release object, not in the tag, so a `git clone` misses it entirely.

```yaml
# .github/workflows/release-sync.yml
name: Backup releases (add-only)
on:
  schedule: [{ cron: '30 2 * * *' }]
  workflow_dispatch:
permissions: { contents: write }
jobs:
  releases:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: |
          # upstream_id|upstream_full_name|dest_dir
          map=("123456|OwnerA/Repo1|Repo1")
          changed=0
          fail=0
          for entry in "${map[@]}"; do
            IFS='|' read -r id up dest <<< "$entry"
            cur=$(gh api "repositories/$id" --jq .full_name 2>/dev/null || true)
            if [ -z "$cur" ]; then echo "MISSING $up — keep backup untouched"; continue; fi
            gh api "repos/$cur/releases?per_page=100" --paginate > /tmp/rel.json 2>/dev/null || : > /tmp/rel.json
            tags=$(jq -r '.[].tag_name' /tmp/rel.json 2>/dev/null | tr -d '\r' || true)
            if [ -z "$tags" ]; then echo "no releases: $cur"; continue; fi
            for t in $tags; do
              n=$(jq --arg t "$t" '[.[] | select(.tag_name == $t)][0].assets | length' /tmp/rel.json 2>/dev/null || echo 0)
              dir="references/releases/$dest/$t"
              mkdir -p "$dir"
              before=$(find "$dir" -maxdepth 1 -type f | wc -l)
              ok=1
              if [ "$n" -gt 0 ]; then
                gh release download "$t" -R "$cur" -D "$dir" --skip-existing >/dev/null 2>&1 || ok=0
              fi
              after=$(find "$dir" -maxdepth 1 -type f | wc -l)
              if [ "$after" -gt "$before" ]; then echo "  + $dest/$t"; changed=1; fi
              # assets exist but the download failed -> something is really missing, don't hide it
              if [ "$ok" = "0" ]; then echo "  FAIL download: $cur $t (upstream has $n assets)"; fail=1; fi
              # archive the notes text (add-only: an existing file is never rewritten)
              nf="$dir/RELEASE_NOTES.md"
              if [ ! -f "$nf" ]; then
                if jq -r --arg t "$t" '
                      .[] | select(.tag_name == $t) |
                      "# " + (.name // .tag_name) + "\n\n" +
                      "* tag: `" + .tag_name + "`\n" +
                      "* published: " + (.published_at // "unknown") + "\n" +
                      "* prerelease: " + (.prerelease | tostring) + "\n" +
                      "* url: " + (.html_url // "") + "\n\n" +
                      "## Notes\n\n" + (.body // "_(no release notes)_") + "\n\n" +
                      "## Assets\n\n" +
                      ( if ((.assets | length) == 0) then "_upstream uploaded no assets_"
                        else ( [ .assets[] | "- `" + .name + "` — " + (.size | tostring) + " bytes" ] | join("\n") ) end ) + "\n"
                    ' /tmp/rel.json > "$nf" 2>/dev/null; then
                  changed=1
                  echo "  + $dest/$t/RELEASE_NOTES.md"
                else
                  rm -f "$nf"
                fi
              fi
            done
          done
          if [ "$changed" = "1" ]; then
            git config user.name  "sync-bot"
            git config user.email "sync-bot@users.noreply.github.com"
            git add references/releases
            git commit -m "release backup: $(date -u +%F)" || true
            git push || { echo "PUSH FAIL"; fail=1; }
          fi
          exit $fail
```

## Alert on failure

A sync that silently stops is worse than one that never ran. Add a final step so
GitHub opens an issue for you:

```yaml
      - if: failure()
        env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: gh issue create -R you/control-repo --title "sync failure" \
              --body "see ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
```

## Token

Create a fine-grained or classic PAT with `repo` + `workflow` (and
`delete_repo` if a job deletes anything), store it as the `SYNC_TOKEN` secret in
the control repo. Scheduled workflows are auto-disabled after ~60 days of repo
inactivity — GitHub emails you; re-enable from the Actions tab.
