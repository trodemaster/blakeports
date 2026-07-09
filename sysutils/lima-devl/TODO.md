# lima-devl — Upstream PR & Port Tracking

Status of feature patches carried by this port and their upstream submission.
Patch revs: see `g3_rev` / `b1_rev` / `b2_rev` / `b3_rev` / `b4_rev` / `m1_rev` in the Portfile.

## Feature status

| Patch | Feature | Upstream status |
|-------|---------|-----------------|
| B1 (`patch-05`) | `suppressFirstLoginSetup` | **Issue #5186 open** — feedback received 2026-07-06, PR welcomed; schema move to `osOpts.darwin` done, PR not yet opened |
| B2 (`patch-06`) | TCC pre-seeding (`guestPatch.tccPermissions`) | ready for submission (depends on B1) |
| B4 (`patch-10`) | `osOpts.darwin.clipboard` (VZ SPICE agent port, host side only) | **not yet an issue** — validating locally first; depends on B1 |
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
patch-10-b4-macos-clipboard.diff     ← validating locally (depends on B1)
patch-09-m1-fakecloudinit-macos27.diff  ← macOS 27-beta workaround, NOT upstream
patch-08-b3-dfu-beta27.diff             ← macOS 27-beta workaround, NOT upstream
```

## Branch topology (as of 2026-07-08)

| Branch | Based on | Commits above base | Role |
|--------|----------|--------------------|------|
| `upstream-pr/g3-screenshot-clean` | origin/master | 1 | upstream PR branch |
| `upstream-pr/b1-fakecloudinit` | go.setup commit (13b850b0) | 9 | upstream PR branch (clean); tip = schema move to `osOpts.darwin` |
| `upstream-pr/b2-tcc` = `macports/b2-on-b1` | b1-tip | 3 | stacked on B1 for patching; use b1-tip as B2 patch base |
| `upstream-pr/b4-macos-clipboard` | b1-tip | 1 | stacked on B1 for patching (needs `DarwinOpts`); host-side clipboard only |
| `macports/m1-fakecloudinit-macos27` | b1-tip | 5 | macOS 27 workarounds stacked on B1 |
| `upstream-pr/b3-dfu-beta27` | origin/master | 6 | macOS 27 DFU workaround |

**2026-07-08 fix:** `patch-05`/`patch-06` had gone stale — they still put `suppressFirstLoginSetup`
under `VZOpts` (the pre-#5186-feedback location) even though the `upstream-pr/b1-fakecloudinit`
git branch had already moved it to `DarwinOpts`/`osOpts.darwin` (commit `477f30c5`, 2026-07-06).
The port was silently shipping the schema the maintainer asked us to move away from. Found while
generating patch-10 (B4 depends on the current `DarwinOpts` shape, so it conflicted against the
stale patch-06). Fixed by regenerating patch-05 from the go.setup commit to the current B1 tip,
then rebasing `macports/b2-on-b1` onto that tip (2 duplicate-content commits skipped, 1 genuine
conflict in `lima_yaml.go` resolved by keeping `VZOpts.GuestPatch` and dropping the stale
`SuppressFirstLoginSetup`/`VZOpts` duplication) and regenerating patch-06. Bumped `b1_rev`→2,
`b2_rev`→2. Full 5-patch chain (05, 06, 10, 09, 08) dry-run verified clean in sequence.

Patch generation commands:
- patch-04: `git diff --no-prefix origin/master..upstream-pr/g3-screenshot-clean`
- patch-05: `git diff --no-prefix 13b850b0a62d7b3de68450771e64346fa1ecb9d6..upstream-pr/b1-fakecloudinit`
- patch-06: `git diff --no-prefix upstream-pr/b1-fakecloudinit..macports/b2-on-b1`
- patch-10: `git diff --no-prefix upstream-pr/b1-fakecloudinit..upstream-pr/b4-macos-clipboard`
- patch-09: `git diff --no-prefix upstream-pr/b1-fakecloudinit..macports/m1-fakecloudinit-macos27`
- patch-08: `git diff --no-prefix origin/master..upstream-pr/b3-dfu-beta27`

Note: patch-05's base is pinned to the `go.setup` commit (not `origin/master`), since B1 hasn't
been rebased onto current upstream master yet and the two have diverged. Regenerate against
whatever `go.setup` points to, not against a live `origin/master` that may have moved further.

## TODO

### Upstream PRs
- [x] G3 / PR #5098: merged 2026-06-28.
- [ ] B1: issue #5186 open (2026-07-04). Maintainer (AkihiroSuda) feedback 2026-07-06:
      feature concept accepted for macOS 15/26 ("feel free to submit a PR"); can't
      test/review the macOS 27 native-provisioning path until macOS 27 GA (out of scope
      for this feature). One required change before submitting: move the config from
      `vmOpts.vz.suppressFirstLoginSetup` to `osOpts.darwin.suppressFirstLoginSetup`,
      mirroring the existing `WindowsOpts`/`osOpts` pattern (`lima_yaml.go` L350-354).
      Done: new `DarwinOpts` type added, `VZOpts.SuppressFirstLoginSetup` removed, all
      call sites (`pkg/cidata/cidata.go`, docs) repointed. Commit `477f30c5`, pushed to
      `trodemaster/upstream-pr/b1-fakecloudinit`. Verified via `go build ./...`,
      `go vet ./...`, `go test ./pkg/limatype/... ./pkg/limayaml/... ./pkg/cidata/...`,
      and `golangci-lint run` (0 issues) — all clean, no local VM rebuild needed.
      Next: open the upstream PR (sign off DCO, reference #5186 in the PR body, state
      tested guest versions: macOS 15, macOS 26) — this is what actually triggers CI
      (`test.yml` only runs on push to master/release or on `pull_request`, not on a
      plain fork branch push). Holding off on opening the PR for now per 2026-07-06
      decision.
- [ ] B2: submit after B1 merges.
      PR description must cover: TCC schema v30 + tccd forward-migration rationale,
      presets shipped (sshd-full-disk-access, lima-guestagent-full-disk-access, terminal-accessibility),
      per-user TCC deferred (tccd revokes per-user grants on first login — by design),
      tested on macOS 15 + 26.
- [ ] B4 (`osOpts.darwin.clipboard`, host-side only): no GitHub issue yet — deliberately
      validating locally first before writing anything public, per 2026-07-08 decision.
      Adds `DarwinOpts.Clipboard *bool`; when set, `pkg/driver/vz/clipboard_darwin.go`
      attaches a `VZSpiceAgentPortAttachment` console port (`vz.NewSpiceAgentPortAttachment`
      + `SetSharesClipboard(true)`), mirroring the mechanism in the stalled/contentious
      upstream PR #4480 ("feat: VZ configurable display, audio, and clipboard support") but
      scoped to *just* clipboard — no display/audio bundled in.
      This only wires up the host side. The guest needs a SPICE vdagent-compatible agent
      listening on the named port; Lima does not ship one. UTM's own guest tools
      (github.com/utmapp/vd_agent — GPL-3.0, a `spice-vdagentd` LaunchDaemon + per-user
      `spice-vdagent` LaunchAgent) are the known-working reference implementation — UTM's
      docs confirm clipboard sharing on the Apple Virtualization backend requires macOS 15+
      on *both* host and guest, and works via that same `VZSpiceAgentPortAttachment`
      mechanism today (docs.getutm.app/guest-support/macos6).
      Local verification done: `go build`/`go vet`/`go test`/`golangci-lint` all clean on
      `upstream-pr/b4-macos-clipboard` (stacked on B1's tip, needs `DarwinOpts`).
      CI: NOT lima-vm/lima's own Actions (a fork-internal PR was tried and reverted — wrong
      approach, see workflow note below). Testing goes through blakeports' own
      `build-lima-devl.yml` GitHub Actions workflow instead, which does a real
      `sudo port -kv install lima-devl` on self-hosted macOS runners (15/26/27-beta) plus
      `port lint` and `golangci-lint` — this is the CI blakeports actually uses for this port.
      Next: push this patch, let build-lima-devl.yml validate the MacPorts build, then Blake
      manually installs the UTM vd_agent guest tools in a real macOS 15+/26 guest and tests
      whether clipboard sharing actually works end-to-end. Only after that succeeds does it
      make sense to draft the Obsidian issue and open a real upstream PR (issue-first, per
      the lima-devl skill's substantial-feature workflow) — no point proposing this publicly
      before confirming it functions.

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
