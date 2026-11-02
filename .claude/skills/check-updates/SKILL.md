---
name: check-updates
description: Check which blakeports ports have newer upstream releases, and whether anyone else has PRs against them in macports-ports. Use when asked to "check for port updates", "do any ports need updating", "what's outdated", "any new releases", or before planning version bumps. Runs scripts/check-updates.sh (default: ports upstream lists @trodemaster as maintainer of; --all: every port in the repo).
---

# Checking blakeports for port updates

`scripts/check-updates.sh` does the work. Don't re-implement it with ad-hoc
curl or `port livecheck` loops; fix the script if it gets something wrong.

## Run it

```bash
cd ~/Developer/blakeports && scripts/check-updates.sh          # ports we maintain upstream
cd ~/Developer/blakeports && scripts/check-updates.sh --all    # every port in the repo
```

Pipe through `sed 's/\x1b\[[0-9;]*m//g'` to strip colours. A full `--all` run
takes a minute or two (timeout 600000).

**Default** checks the ports ports.macports.org lists for maintainer
`trodemaster`. **`--all`** also checks blakeports-only ports (qemu, lima,
vault, python314, ...), labelled `(blakeports only)`. Use `--all` when the user
says "all", "everything", or asks about a specific blakeports-only port.

How each port is checked, in order:
1. `livecheck.type none`: skipped (forks and pinned snapshots)
2. The port's own `livecheck.*` lines: `port livecheck`
3. `github.setup` with a real version: latest GitHub release/tag via `gh api`
4. `fetch.type svn` on SourceForge: the project's RSS feed
5. Commit-pinned (`github.setup`/`go.setup` hash) or `fetch.type git` ports:
   `git ls-remote`
6. Anything else: `port livecheck`

## Network hosts (sandbox)

Project settings (`.claude/settings.json`) allow the livecheck hosts both
modes need: `sourceforge.net`, `developers.yubico.com`, `gnupg.org`,
`ftp.gnu.org`, `ftp.openbsd.org`, `www.python.org` and `download.qemu.org`.
github.com, api.github.com and ports.macports.org are allowed globally.

If a `<sandbox_violations>` block names another host, re-run with that host
added rather than reporting the port as uncheckable.

Git-based ports (netatalk_client, lima-devl, vd_agent) are checked with the
script's own `git ls-remote`, not `port livecheck`. Inside the sandbox, git
needs `http.proxyAuthMethod=basic`, which the sandbox passes in
`GIT_CONFIG_PARAMETERS`. MacPorts strips that variable (and runs git from
`/opt/local/var/macports` with its own HOME), so `port livecheck` on these
ports fails with "Proxy CONNECT aborted". That's not a network block, so don't
add hosts or escape the sandbox for it. "New commits" for a snapshot port
means upstream HEAD has moved, not that a release is out.

## Report

Give a short table, not the raw output:
- **Needs update**: port, current → latest, upstream link
- **Up to date**: one compact list
- **Couldn't check / skipped**: with the reason
- **PRs by others**: `MERGED` means upstream changed the port. Diff the
  blakeports Portfile against `~/Developer/macports-ports/<category>/<port>/Portfile`
  and say whether blakeports needs a sync.

Before recommending a bump, check CLAUDE.md **Open Work**. Some ports
(libgcrypt, python314, icu, libarchive, libevent) are in the middle of
upstream PR work, and their next version is tied to that.

## After the report

Offer, don't start, the bump: version → checksums (keep the old ones until
`sudo port checksum` reports the new values) → `portindex` →
`port lint --nitpick` → CI build (`gh workflow run "Build <Portname>"`). Never
bump `revision` in blakeports; uninstall, `clean --all`, and reinstall
instead.
