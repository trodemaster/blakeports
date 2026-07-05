# lima-devl — Upstream PR & Port Tracking

Status of feature patches carried by this port and their upstream submission.
Patch revs: see `g3_rev` / `b1_rev` / `b2_rev` / `b3_rev` / `m1_rev` in the Portfile.

## Feature status

| Patch | Feature | Upstream status |
|-------|---------|-----------------|
| B1 (`patch-05`) | `suppressFirstLoginSetup` | **Issue #5186 open** — awaiting maintainer feedback before PR |
| B2 (`patch-06`) | TCC pre-seeding (`guestPatch.tccPermissions`) | ready for submission (depends on B1) |
| M1 (`patch-09`) | macOS 27 fakecloudinit workarounds | **NOT for upstream** — macOS 27-beta only |
| B3 (`patch-08`) | DFU install workaround for macOS 27 beta | **NOT for upstream** — macOS 27-beta only |
| O1 (`patch-07`) | PID timeout | disabled in Portfile |

`patch-01-g1-thread-pin.diff` merged upstream in PR #5036 and removed from port.
`patch-02-g4-window-title.diff` merged upstream in PR #5084 and removed from port.
`patch-04-g3-screenshot.diff` merged upstream in PR #5098 (2026-06-28) and removed from port.

## Patch ordering (applied last = macOS 27 block)

```
patch-Makefile.diff
patch-usrlocalgo.diff
patch-04-g3-screenshot.diff          ← upstream candidate
patch-05-b1-fakecloudinit.diff       ← upstream candidate
patch-06-b2-tcc.diff                 ← upstream candidate (depends on B1)
patch-09-m1-fakecloudinit-macos27.diff  ← macOS 27-beta workaround, NOT upstream
patch-08-b3-dfu-beta27.diff             ← macOS 27-beta workaround, NOT upstream
```

## Branch topology (as of 2026-06-27)

| Branch | Based on | Commits above base | Role |
|--------|----------|--------------------|------|
| `upstream-pr/g3-screenshot-clean` | origin/master | 1 | upstream PR branch |
| `upstream-pr/b1-fakecloudinit` | origin/master | 7 | upstream PR branch (clean) |
| `upstream-pr/b2-tcc` = `macports/b2-on-b1` | b1-tip | 3 | stacked on B1 for patching; use b1-tip as B2 patch base |
| `macports/m1-fakecloudinit-macos27` | b1-tip | 5 | macOS 27 workarounds stacked on B1 |
| `upstream-pr/b3-dfu-beta27` | origin/master | 6 | macOS 27 DFU workaround |

Patch generation commands:
- patch-04: `git diff --no-prefix origin/master..upstream-pr/g3-screenshot-clean`
- patch-05: `git diff --no-prefix origin/master..upstream-pr/b1-fakecloudinit`
- patch-06: `git diff --no-prefix upstream-pr/b1-fakecloudinit..upstream-pr/b2-tcc`
- patch-09: `git diff --no-prefix upstream-pr/b1-fakecloudinit..macports/m1-fakecloudinit-macos27`
- patch-08: `git diff --no-prefix origin/master..upstream-pr/b3-dfu-beta27`

## TODO

### Upstream PRs
- [x] G3 / PR #5098: merged 2026-06-28.
- [ ] B1: issue #5186 open (2026-07-04). Once there's some acceptance of the feature concept,
      create upstream PR branch from `upstream-pr/b1-fakecloudinit`, sign off (DCO), reference
      the issue in the PR body. PR description must state tested guest versions: macOS 15, macOS 26.
- [ ] B2: submit after B1 merges.
      PR description must cover: TCC schema v30 + tccd forward-migration rationale,
      presets shipped (sshd-full-disk-access, lima-guestagent-full-disk-access, terminal-accessibility),
      per-user TCC deferred (tccd revokes per-user grants on first login — by design),
      tested on macOS 15 + 26.

### macOS 27 workarounds (M1 + B3)
- [ ] Revisit M1 (fakecloudinit) and B3 (DFU) when macOS 27 is released:
      - M1 may be partially upstreamable if ISRootMigrator behavior is documented
      - B3 may be upstreamable or resolved by Apple fixing VZMacOSInstaller
- [ ] Test TCC patching against a macOS 27-beta guest (template exists in lima_mac, untested).
- Related flakiness observed 2026-07-05 (not in the M1 patch itself — in `lima_mac`'s
  `configure.sh`, which runs after Lima's own fakecloudinit as a provisioning script):
  on a macOS 27 beta guest, Setup Assistant hung at the first-boot progress screen
  (`Setup Assistant -MiniBuddyYes`, near-zero CPU) and a `defaults write NSGlobalDomain`
  call in `configure_screensaver` blocked indefinitely on the same cfprefsd round-trip,
  stalling Lima's "boot scripts must have finished" gate for the whole build. Not seen on
  macOS 26 or 15. Fixed defensively in `lima_mac` (commit `bcd1434`) by wrapping
  `configure_setup_assistant`/`configure_screensaver` with a 60s timeout — see
  `lima_mac/CLAUDE.md`'s caveats list. Same failure class (cfprefsd/Setup Assistant
  flakiness on macOS 27 beta) as what M1's guest-side Setup Assistant plist writes in
  `fakecloudinit_darwin.go` work around; worth keeping in mind if `ISRootMigrator`
  behavior is investigated for the M1 upstreamability question above.

### Verification
- [ ] Rebuild a VM using the new patch set to confirm behavior: B1+B2+M1 patching.

### CI maintenance
- [ ] Verify golangci/golangci-lint-action works under Node 24 (GitHub forced it 2026-06-16).

### Deferred / not planned
- Per-user TCC database pre-seeding: removed from B2 — proven non-functional
  (tccd validates and removes unrecognized per-user grants on first login).
  Revisit only if tccd behavior changes in a future macOS.
- AppleEvents presets (`terminal-apple-events`, `sshd-apple-events-finder`):
  removed from B2 — system DB entries for AppleEvents require special handling
  and the use cases are covered by custom entries in lima.yaml.

## Workflow reminders
- Regenerate patches from git commit ranges, never hand-edit
  (see lima-mac skill → "MacPorts Patch Fix Workflow").
- Bump the matching `*_rev` in the Portfile on every patch regeneration.
- `gofmt -w` all changed files before regenerating any patch.
- Never modify upstream CI config (.golangci.yml etc.) in a PR.
