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

## B. Mirror a non-fork upstream — clone + push on the runner

For repos that are plain mirrors (not forks), a runner can clone the upstream
(full history, ignores `export-ignore`) and force-push into your private repo.

```yaml
# .github/workflows/mirror-sync.yml
name: Mirror upstreams
on:
  schedule: [{ cron: '0 2 * * *' }]
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - env: { GH_TOKEN: '${{ secrets.SYNC_TOKEN }}' }
        run: |
          repos=("OwnerA/Repo1:you/Repo1:main" "OwnerB/Repo2:you/Repo2:master")
          for entry in "${repos[@]}"; do
            IFS=: read -r src dst branch <<< "$entry"
            echo "==> $src -> $dst ($branch)"
            rm -rf /tmp/ws
            git clone --quiet "https://x-access-token:${GH_TOKEN}@github.com/${src}.git" /tmp/ws
            cd /tmp/ws && git checkout "$branch"
            git push "https://x-access-token:${GH_TOKEN}@github.com/${dst}.git" "HEAD:${branch}" --force
            cd - >/dev/null
          done
```

> Prefer `git clone` over a tarball everywhere: tarballs honour
> `export-ignore`, which can hand you an empty snapshot. See `pitfalls.md`.

## C. One-shot privatize on the runner

If your own `github.com` access is blocked, do the fork→private copy **inside an
Action** instead of locally:

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

## Token

Create a fine-grained or classic PAT with `repo` + `workflow` (and
`delete_repo` if a job deletes anything), store it as the `SYNC_TOKEN` secret in
the control repo. Scheduled workflows are auto-disabled after ~60 days of repo
inactivity — GitHub emails you; re-enable from the Actions tab.
