# github-rescue-backup

A reusable **skill** for rescuing GitHub projects into your own account and
keeping them safe from an upstream author who might delete and run.

Wraps the whole workflow the hard way — including the traps that make naive
backups fail.

## What it does

- **Fork** upstream repos → your account gets a server-side copy of code + tags.
- **Archive releases** → download every Release asset (forks don't carry them).
- **Snapshot source** → file-level copy into a private backup repo (survives a
  whole fork-network takedown).
- **Daily cloud sync** → GitHub Actions keeps everything fresh, PC off.
- **Privatize forks** → the copy→delete→rename dance GitHub forces on you.

## Install / use as a skill

Drop this folder where your agent loads skills, e.g.:

```bash
git clone https://github.com/Brind235808/github-rescue-backup.git
# then point your agent's skill/plugin directory at it
```

The entry point is [`SKILL.md`](SKILL.md). Its `description` frontmatter lists
the trigger phrases, so the agent activates it automatically when you say
"帮我备份这个仓库 / 我怕作者删库跑路 / 把这些 fork 转私有".

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/fork-upstream.sh` | Fork one or more upstream repos |
| `scripts/backup-releases.sh` | Download all Release assets |
| `scripts/snapshot-source.sh` | Clone source into a private backup repo |
| `scripts/convert-fork-private.sh` | Copy → delete → rename a public fork to private |

All scripts use the `gh` CLI and `git`. Authenticate first:

```bash
gh auth login
gh auth refresh -h github.com -s delete_repo   # only for the privatize step
```

## The rules that save you

Read [`references/pitfalls.md`](references/pitfalls.md). The big ones:

1. **Never trust a tarball.** `export-ignore` can strip every file. Use `git clone`.
2. **A fork isn't a backup.** No releases, no future commits.
3. **Public forks can't go private directly.** Copy → delete → rename.
4. **`github.com` git can die while `api.github.com` lives** — move push work onto an Actions runner.

## License

MIT — see [LICENSE](LICENSE). Use it to archive your own copies responsibly:
respect upstream licenses, and keep your mirrors **private** unless the license
permits redistribution.
