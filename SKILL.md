---
name: github-rescue-backup
description: >-
  Rescue, mirror, and privatize GitHub repositories so upstream authors can no
  longer delete them out from under you. Use when the user wants to 备份/克隆/
  fork/镜像 a GitHub project to their own account, 保留源码或 Release 附件,
  设置每天云端自动同步, or 把公开 fork 转成私有仓库. Covers upstream forking,
  release-asset archiving, full source snapshots, GitHub Actions daily sync,
  and the fork→private conversion that GitHub refuses to do directly.
---

# GitHub Rescue Backup

Preserve other people's GitHub projects inside your own account, then keep them
in sync automatically — so an upstream `rm -rf` (or account deletion) cannot
take your copy with it.

## When to use

Trigger this skill when the user says things like:

- "帮我把这个 GitHub 项目备份到我仓库 / 我怕作者删库跑路"
- "把 xxx 这个项目 fork / 克隆 / 镜像 过来"
- "这几个 Release 也备份一下 / 原仓库 Release 没了"
- "搞个每天云端自动同步"
- "把我这些公开 fork 转成私有仓库"

## The four jobs

| Job | What it does | Reference |
|-----|--------------|-----------|
| **1. Fork upstream** | Server-side copy of code + all branches/tags | `scripts/fork-upstream.sh` |
| **2. Archive releases** | Fork does NOT carry Release assets — download them | `scripts/backup-releases.sh` |
| **3. Snapshot source** | File-level snapshot into a private backup repo | `scripts/snapshot-source.sh` |
| **4. Privatize forks** | Public forks can't go private — copy → delete → rename | `scripts/convert-fork-private.sh` |

Plus **5. Daily cloud sync** via GitHub Actions — see
`references/cloud-sync.md`.

## Job 1 — Fork upstream (quick win, but incomplete)

```bash
gh repo fork OWNER/REPO --clone=false        # server-side; code + tags land under your account
```

Result: your `you/REPO` survives upstream deletion. **But a fork is a
point-in-time copy** — upstream later commits don't arrive unless you sync, and
**Release assets are never carried over**.

Rate limit note: GitHub allows only one fork per network per account, and rapid
forking trips a secondary rate limit (403). Space them out.

## Job 2 — Archive releases (the part everyone forgets)

Release assets are standalone binaries, not part of git history, so forks and
`git clone` miss them. Download every asset explicitly:

```bash
./scripts/backup-releases.sh you/REPO Owner/REPO ./_backup
```

Stores each release under `_backup/releases/<repo>/<tag>/` with the original
asset names, plus a `manifest.json` (tag, asset, size, sha256).

## Job 3 — Snapshot source (belt-and-braces)

A fork can still vanish if GitHub removes the whole network (DMCA/abuse). Keep a
file-level snapshot in a single private repo:

```bash
./scripts/snapshot-source.sh Owner/REPO you/backup-repo references/repos/REPO
```

> **Critical pitfall — never use a tarball to snapshot.** GitHub's codeload
> tarball honours `.gitattributes` `export-ignore`, which some authors use to
> strip *everything* (`/* export-ignore`). A tarball then contains only
> `README-GITHUB.txt`. **Always `git clone`** (clone ignores `export-ignore`).
> See `references/pitfalls.md`.

## Job 4 — Convert public forks to private

GitHub hard-refuses `PATCH ... private=true` on a public fork:

```
422 Validation Failed: "Public forks can't be made private"
```

The only working sequence is:

1. Create a **new private repo** (`REPO-tmp`).
2. Copy content into it (mirror clone + push, or a cloud Actions job).
3. **Delete the public fork.**
4. **Rename** `REPO-tmp` → `REPO`.

```bash
./scripts/convert-fork-private.sh you/REPO
```

Requires the `delete_repo` scope:

```bash
gh auth refresh -h github.com -s delete_repo
```

## Job 5 — Daily cloud sync

Put a scheduled GitHub Actions workflow in a private "control" repo so GitHub's
runners do the syncing — your PC can be off, and (bonus) it bypasses a blocked /
flaky `github.com` on your own machine. Templates and the full rationale live in
`references/cloud-sync.md`.

## Hard-won rules (read before acting)

1. **Tarball ≠ backup.** `export-ignore` silently empties snapshots. Clone.
2. **Fork ≠ complete backup.** No releases, no future commits.
3. **One fork per network per account.** Official + community forks collide.
4. **Public forks can't be privatized directly.** Copy → delete → rename.
5. **Releases must be downloaded separately.** They are not in git.
6. **Secondary rate limits (403) bite on repo/file creation.** Back off, retry
   later; don't hammer.
7. **`github.com` git can be blocked while `api.github.com` works.** When git
   is dead but `gh api` works, do the work on a **GitHub Actions runner**.
8. **Respect upstream licenses.** A private mirror for personal archival is
   normal; republishing someone's code publicly is not. Keep mirrors private
   unless the license allows otherwise.
