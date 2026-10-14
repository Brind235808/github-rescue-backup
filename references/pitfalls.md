# Pitfalls & gotchas

Everything here is something that actually bit us. Read it before trusting a
"backup".

## 1. Tarballs lie — `export-ignore` empties them

GitHub's codeload tarball (`/tarball/<ref>`) honours `.gitattributes`. An
author can write:

```
/* export-ignore
/README-GITHUB.txt -export-ignore
```

Every file except `README-GITHUB.txt` is stripped — **the tarball is effectively
empty**. So `curl .../tarball/main | tar xz` looks successful but backs up
nothing.

**Rule: always `git clone`.** `clone` ignores `export-ignore` and fetches the
real tree. (`git archive`/tarball is the only thing affected.)

## 2. A fork is NOT a full backup

`gh repo fork` copies code, branches and tags — but:

- **Release assets are not carried.** They are standalone uploads, absent from
  git history. Download them yourself (`backup-releases.sh`).
- **It is a point-in-time copy.** New upstream commits don't arrive unless you
  sync (`merge-upstream`) or re-clone.

## 3. One fork per fork-network per account

For `upstreamOwner/Repo`, GitHub lets your account hold exactly **one** fork in
that network. Forking the official repo AND a community fork of the same project
collides — the second fails. Choose, or mirror instead of fork.

## 4. Public forks cannot be made private (directly)

```
PATCH /repos/{owner}/{repo} {"private": true}
-> 422 Validation Failed: "Public forks can't be made private"
```

You must copy → delete → rename (see `convert-fork-private.sh`). Deleting needs
the `delete_repo` OAuth scope:

```bash
gh auth refresh -h github.com -s delete_repo
```

## 5. Secondary rate limits (HTTP 403)

Creating repos / files too fast triggers:

```
You have exceeded a secondary rate limit and have been temporarily blocked
from content creation. (HTTP 403)
```

Back off and retry later — do **not** hammer, or the block lengthens. Space out
`gh repo create` / `gh repo fork` calls (sleep 10-15s).

## 6. `github.com` git down, `api.github.com` up

These are different hosts. In some networks `github.com:443` (git) is reset while
`api.github.com:443` (REST) works. Symptoms:

```
fatal: unable to access 'https://github.com/...': Recv failure: Connection was reset
```

...while `gh api rate_limit` returns fine.

**Workaround:** do REST work (`gh api`) directly, and push everything that needs
git through a **GitHub Actions runner** (see `cloud-sync.md`), which always has
clean `github.com` access.

## 7. Git cannot be pushed from a shallow clone

`git clone --depth 1` then `git push` fails (`shallow update not allowed`).
Either fully unshallow (`git fetch --unshallow`) or rebuild from the working tree.
For pure archival, `git clone --mirror` is the robust choice.

## 8. Windows / PowerShell 5 quirks (when scripting this on Windows)

- No `&&` / `||`; chain with `;` and test `$LASTEXITCODE`.
- No `??` null-coalescing operator.
- **Don't put spaces, `>` or `+` inside `gh ... --jq '...'`** — PowerShell
  re-splits the argument. Use raw JSON + `ConvertFrom-Json`, or keep the jq
  expression space-free.
- Run scripts with `powershell -File` or call with the `&` operator for paths
  containing spaces.

## 9. Version history can be lost by "sync" designs

A sync that downloads a tarball and makes a single fresh commit every day
**rewrites history** (force push). If you care about tags/branches, use a
`--mirror` clone+push, not a tarball squash.
