# lima-devl — Upstream PR & Port Tracking

Status of feature patches carried by this port and their upstream submission.
Patch revs: see `b1_rev` / `b2_rev` / `m1_rev` in the Portfile (B4 is parked, no `b4_rev`).

## Feature status

| Patch | Feature | Upstream status |
|-------|---------|-----------------|
| B1 (`patch-05`) | `suppressFirstLoginSetup` | **PR #5336 open** (Issue #5186) — addressing review feedback |
| B2 (`patch-06`) | TCC pre-seeding (`guestPatch.tccPermissions`) | ready for submission (depends on B1) |
| B4 (`patch-10`) | `osOpts.darwin.clipboard` (VZ SPICE agent port, host side only) | **parked — likely unfixable from a CLI binary** (2026-07-11); depends on B1 |
| M1 (`patch-09`) | macOS 27 fakecloudinit workarounds | **NOT for upstream** — macOS 27-beta only |

`patch-01-g1-thread-pin.diff` merged upstream in PR #5036 and removed from port.
`patch-02-g4-window-title.diff` merged upstream in PR #5084 and removed from port.
`patch-04-g3-screenshot.diff` merged upstream in PR #5098 (2026-06-28) and removed from port.
`patch-08-b3-dfu-beta27.diff` (DFU install workaround) removed 2026-07-25 — host reached
macOS 26.6, confirmed via a real throwaway-instance test that the standard `VZMacOSInstaller`
path no longer hits `VZErrorDomain Code=10007`; `b3_rev` and the `upstream-pr/b3-dfu-beta27`
branch (local + `trodemaster`) were also deleted. See
`lima_mac/docs/dfu-install.md` § "2026-07-25 Removal Confirmed".
`patch-07-o1-pid-timeout.diff` (hostagent PID-wait timeout tweak, `pkg/instance/start.go`)
abandoned 2026-07-30 — never actually submitted upstream; confirmed `origin/master` still
has the original 5s `waitHostAgentStart` deadline and no PR/commit history from Blake matches
it. Was disabled in the Portfile the whole time. `upstream-pr/o1-pid-timeout` branch
(local + `trodemaster`) deleted.

## Patch ordering (applied last = macOS 27 block)

```
patch-Makefile.diff
patch-usrlocalgo.diff
patch-05-b1-fakecloudinit.diff       ← upstream candidate
patch-06-b2-tcc.diff                 ← upstream candidate (depends on B1)
patch-09-m1-fakecloudinit-macos27.diff  ← macOS 27-beta workaround, NOT upstream
```

`patch-10-b4-macos-clipboard.diff` still exists in `files/` and the `upstream-pr/b4-macos-clipboard`
git branch is kept, but the patch is **not** in the Portfile's `patchfiles` list (commented out,
2026-07-11) — see the B4 entry below for why it's parked. `patch-04-g3-screenshot.diff` is gone
entirely (merged upstream, removed from `files/` and `patchfiles`).

## Branch topology (as of 2026-07-30, master = e2f8093e)

| Branch | Based on | Commits above base | Role |
|--------|----------|--------------------|------|
| `upstream-pr/b1-fakecloudinit-clean` | origin/master (squashed single commit) | 1 | the actual open PR #5336 branch — never rebased/force-pushed by tooling, GitHub reports MERGEABLE |
| `macports/b2-on-b1` | origin/master + B1 content cherry-picked from b1-clean tip | 4 (1 B1 + 3 B2) | rebuilt 2026-08-02 directly on origin/master — the previous version had silently drifted onto origin/master too, but with a stale pre-review-fix copy of B1 baked in as one of its own commits (see 2026-08-02 note) |
| `upstream-pr/b4-macos-clipboard` | b1-clean tip | 1 | parked (clipboard non-functional from CLI binary); rebased onto b1-clean 2026-07-30 so it no longer depends on the deleted multi-commit B1 branch |
| `macports/m1-fakecloudinit-macos27` | origin/master + B1 content cherry-picked from b1-clean tip | 8 (1 B1 + 7 M1) | macOS 27 workarounds; rebuilt 2026-08-02, same reason as B2 above |
| `feat/vz-mac-guest-provisioning` | origin/master | 1 | VZMacGuestProvisioningOptions first-boot provisioning (macOS 27+ native account setup); re-extracted 2026-07-30 with the DFU-workaround dependency it used to sit on top of removed — `createDiskMacOSGuest` now calls `maybeRunGuestProvisioning` straight after the standard installer path, no DFU code involved |

**2026-08-02 review-feedback sync:** PR #5336 got reviewer pushback on
`suppressFirstLoginSetup: {}` ("why not `true`?") plus a request to keep the custom-plist
override as a separate option rather than a nested field. Amended the PR's single commit
(force-pushed, `c6b2a4a1` → `e40a3a34`): `DarwinOpts.SuppressFirstLoginSetup` is now `*bool`,
and a new `DarwinOpts.SuppressFirstLoginSetupPlist *string` carries the custom plist; the
`SuppressFirstLoginSetup` struct type is gone. Docs updated to `suppressFirstLoginSetup: true`
+ a sibling `suppressFirstLoginSetupPlist: |` key.

Regenerating patch-05 surfaced that `macports/b2-on-b1` and `macports/m1-fakecloudinit-macos27`
were not actually stacked on the b1-clean branch tip as the topology table claimed — both had
silently ended up based on `origin/master` with a leftover duplicate B1 commit
(`2744b5f6`/pre-fix content) baked into their own history, left over from however they were
rebased during the 2026-07-30 sync. Diffing against the literal b1-clean tip would have pulled
in ~50 unrelated master commits (dependabot/CI bumps, `cmd/limactl/shell.go`, `go.mod`, etc.) —
same base-drift contamination pattern as before, just latent until this regen exposed it.
Fixed by rebuilding both from scratch: rebased the amended B1 commit onto `origin/master`
(disposable branch), then cherry-picked B2's 3 own commits and M1's 7 own commits (identified
by walking `origin/master..<old-branch-tip>` and finding the fake-B1 commit boundary) onto that
clean base. Both cherry-picked with zero conflicts. Regenerated patch-05 (105 lines changed)
and patch-06 (10 lines changed, line-offset only); patch-09 (M1) came out byte-identical since
M1 doesn't touch `suppressFirstLoginSetup`. All three dry-run clean in sequence against a fresh
`origin/master` archive; gofmt clean. Bumped `b1_rev`→8, `b2_rev`→8 (`m1_rev` unchanged). Both
branches force-pushed to `trodemaster` (`gh pr list` confirmed neither has an open PR first).

**2026-07-30 cleanup:** old multi-commit `upstream-pr/b1-fakecloudinit` branch deleted (fully
superseded by `b1-fakecloudinit-clean`, which also carries the cloud-config doc fix the old
branch lacked); `patch-07-o1-pid-timeout.diff`/O1 abandoned (never upstreamed, disabled in
Portfile) and its branch deleted; several merged-PR duplicate branches deleted
(`fix/darwin-lock-main-thread`, `upstream-pr/5036-darwin-lock-main-thread`,
`feat/vz-window-title`, `upstream-pr/g4-window-title` — all fully superseded by their already-merged
content in `origin/master`); `feature-review` (scratch branch) deleted; `feat/macos-vz-gui-appbundle`
deleted (rejected upstream, no salvage). `fork-docs` left untouched, still needs a look.

`upstream-pr/b3-dfu-beta27` (was: origin/master, 13 commits) deleted 2026-07-25 — see Feature
status table above.

**2026-07-23 sync:** fetched upstream (`35de194b` → `b48d0187`, 118 new commits) and rebased
every branch. All six (B1, B2, M1, B3, O1, B4) rebased with zero conflicts — no
duplicate-content skips needed this round. Regenerated patch-05/06/07/08/10 (small
context-line deltas from the rebase); patch-09 (M1) came out byte-identical, since
`fakecloudinit_darwin.go` wasn't touched by any of the 118 new upstream commits. Found and
fixed a stale patch-generation command for B4 in this doc (line 70 below still said
`origin/master..upstream-pr/b4-macos-clipboard`, but B4 is stacked on B1 like B2/M1 — using
the wrong base bloated the regenerated patch to 21K by re-including B1's own content before
the fix). All 6 active + 2 disabled patches dry-run clean, in sequence, against a fresh
archive of the new master. Bumped `b1_rev`→3, `b2_rev`→3, `b3_rev`→2 (m1_rev unchanged,
patch content identical).

**2026-07-11 restructure (meeting #5186 review asks):** rebased everything onto master
`47f138a2`; added conventions-alignment commit to B1 (single `limayaml.Convert` for
`osOpts.darwin` before the `TemplateArgs` literal matching the WindowsOpts pattern, all
`%q` → `%#q`, `OsOpts` added to the VZ driver's `knownYamlProperties` so `osOpts.darwin`
configs no longer log "vmType vz: ignoring [OsOpts]", template tidy); moved the
OpenDirectory/dscl commit from B1 into M1's base (its real justification is the macOS 27
pre-existing-user path; keeps the upstream PR single-feature). B1's diff now contains
zero macOS 27 / TCC / dscl content.

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

Patch generation commands (as of 2026-08-02, go.setup == origin/master == e2f8093e):
- patch-05: `git diff --no-prefix origin/master..upstream-pr/b1-fakecloudinit-clean` — safe
  as-is only while `upstream-pr/b1-fakecloudinit-clean`'s base (`bc7ba1ec`) matches
  `origin/master`; once they diverge, rebuild on a disposable branch instead (see below).
- patch-06 / patch-09 / patch-10: do **not** diff directly against
  `upstream-pr/b1-fakecloudinit-clean` or trust `macports/b2-on-b1` /
  `macports/m1-fakecloudinit-macos27` to still be literally stacked on its tip — twice now
  (2026-07-08, 2026-08-02) those branches had silently drifted onto `origin/master` with a
  stale duplicate B1 commit baked in, and a naive diff against the real PR branch pulled in
  dozens of unrelated master commits. Regenerate with the disposable-branch method instead:
  1. `git branch -f _tmp-b1-basis upstream-pr/b1-fakecloudinit-clean && git rebase --onto origin/master <old-base-sha> _tmp-b1-basis`
  2. For each of B2/M1/B4: `git branch -f _tmp-X-basis _tmp-b1-basis`, then
     `git cherry-pick <that branch's own unique commit SHAs>` (find them via
     `git log --oneline origin/master..<branch-tip>`, taking everything above the fake-B1
     commit if one is present)
  3. `git diff --no-prefix _tmp-b1-basis.._tmp-X-basis > patch-NN-....diff`
  4. Promote: `git branch -f macports/X-on-b1 _tmp-X-basis`, delete temp refs, force-push
  5. `git diff --stat` each result before trusting it — file list should match the feature's
     own scope, nothing from `.github/`, `go.mod`/`go.sum`, or unrelated packages.

Note: if `go.setup` and `origin/master` ever diverge again (master moves before the next
sync), regenerate patch-05 against whatever `go.setup` points to, not a live
`origin/master` that may have moved further.

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
      call sites (`pkg/cidata/cidata.go`, docs) repointed (commit `477f30c5`).
      **2026-07-11 review-readiness pass** (revisiting #5186 asks — stick to existing
      constructs, single-feature PR): rebased onto master `47f138a2` and added a
      conventions commit (`e0620438`) — single `limayaml.Convert` for `osOpts.darwin`
      before the `TemplateArgs` literal (matches the WindowsOpts pattern at
      `pkg/driver/qemu/qemu.go` / `pkg/instance/start.go`, error propagated, gated on
      `OS == darwin`), all `%q` → `%#q` per house style, `OsOpts` added to the VZ
      driver's `knownYamlProperties` (fixes spurious "vmType vz: ignoring [OsOpts]"
      warning), user-data template tidy. Moved the OpenDirectory/dscl user-existence
      commit out of B1 into M1 (its justification is macOS 27 pre-existing users — out
      of scope per maintainer). B1 diff is now 376 lines, zero macOS 27/TCC content.
      **PR #5336 opened**, referencing #5186. Review feedback received: a `user-data`
      cloud-config-conformance nit on `pkg/cidata/cidata.TEMPLATE.d/user-data` (already
      addressed pre-2026-08-02 by switching to the file-marker approach, see PR comment
      thread), a question on the `13` magic number in `fakecloudinit_darwin.go` (answered:
      undocumented MiniBuddy state-tracking value, not changeable), and — the substantive
      one — `suppressFirstLoginSetup: {}` questioned ("why not `true`?"), with a follow-up
      asking
      for the custom-plist override to be its own option rather than nested under the
      struct. **2026-08-02: addressed** — amended the PR commit (`c6b2a4a1` → `e40a3a34`):
      `SuppressFirstLoginSetup` is now `*bool`, custom plist moved to a new
      `SuppressFirstLoginSetupPlist *string`; the old `SuppressFirstLoginSetup` struct type
      removed. Port patches (patch-05/06) regenerated and synced, see the 2026-08-02 note
      above.
      Next: watch for further review on #5336.
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
      **2026-07-11: end-to-end test done, clipboard sharing does not work — parked.**
      Tested on a real macos-26 guest with utmapp/vd_agent 0.22.1 installed. Two real bugs
      found and fixed locally (not yet upstreamed as separate patches, since the underlying
      feature doesn't work anyway):
        1. `osOpts.darwin.clipboard: true` must actually be set in the guest yaml — obvious
           in hindsight, but easy to silently no-op since the field is a no-op when unset.
        2. utmapp/vd_agent's own `com.redhat.spice.vdagentd.plist` hardcodes
           `-s /dev/tty.com.redhat.spice.0` (a Linux/QEMU-SPICE convention path), but Apple's
           VZ framework actually names the guest device `/dev/tty.virtio`. vdagentd crash-loops
           against the wrong path until this is patched — this bug lives in vd_agent's macOS
           packaging, not in lima-devl; worth an upstream issue against utmapp/vd_agent
           separately, but out of scope here. (Resets on every vd_agent package reinstall.)
      With both fixed — vdagentd running clean with no errors, guest agent connected to the
      socket, confirmed via manual GUI copy/paste in the actual VM window (not just SSH
      pbcopy/pbpaste) — clipboard content still does not sync in either direction.
      Verbose debug logging (`spice-vdagentd -d -d`, `spice-vdagent -d`, both `-x` foreground)
      proved the actual virtio-serial channel carries **zero bytes** in either direction: the
      guest's own startup clipboard-grab message never gets any host-side response, and a host
      `pbcopy` produces no guest-side log activity at all. No error, no exception, no TCC
      prompt/denial anywhere on the host (checked via `log show` across the full test window).
      Reviewed `clipboard_darwin.go` line-by-line against Apple's own header-comment
      requirements in the Code-Hex/vz source (`virtualization_13.m`) — it correctly satisfies
      both documented constraints (`attachment` set to `VZSpiceAgentPortAttachment`,
      `isConsole` left at the required `false`). Diffed against UTM's actual open-source
      reference implementation (`Configuration/UTMAppleConfigurationVirtualization.swift`,
      github.com/utmapp/UTM) — structurally identical, same object graph, same call order.
      Checked UTM's entitlements (`Platform/macOS/macOS.entitlements` and the
      Developer-ID `macOS-unsigned.entitlements` variant) for anything Lima's `limactl`
      lacks: `com.apple.vm.device-access` and `com.apple.vm.networking` are present in the
      MAS build but confirmed via Apple's own docs to be USB-passthrough-specific
      (`IOUSBHostDevice`) and irrelevant to `VZSpiceAgentPortAttachment`; UTM's
      Developer-ID/unsigned variant doesn't carry either and isn't gated differently for
      clipboard, so entitlements are ruled out as the cause.
      The one remaining structural difference: UTM is a real, bundled `.app`
      (`com.apple.security.app-sandbox`, `CFBundleIdentifier`, launched from
      `UTM.app/Contents/MacOS/UTM`); `limactl`/`hostagent` is a bare CLI binary with no
      bundle structure. Working hypothesis (unconfirmed — would need an app-bundle
      experiment or an Apple DTS answer to verify) is that Apple's Virtualization.framework
      requires actual app-bundle identity before its internal SPICE clipboard-pump logic
      activates, silently no-opping otherwise rather than raising an error — matching every
      symptom observed (clean attach, clean guest connection, zero bytes, no error).
      **Lima's maintainers are strongly against shipping `limactl`/hostagent as an app
      bundle**, so even if this hypothesis is correct there is no fix path available within
      Lima's CLI-only architecture — this is being treated as a design-level blocker, not a
      bug to iterate on. Decision 2026-07-11: park B4, do not open an issue or PR, do not
      pursue further debugging or an Apple Feedback report for now.
      `upstream-pr/b4-macos-clipboard` and `patch-10-b4-macos-clipboard.diff` are left as-is,
      unmerged, in case Apple's framework behavior changes in a future macOS release.

### macOS 27 workarounds (M1)
- [ ] Revisit M1 (fakecloudinit) when macOS 27 is released — may be partially upstreamable
      if ISRootMigrator behavior is documented.
- [x] **B3 (DFU install workaround) removed 2026-07-25.** Host reached stable macOS 26.6
      (25G70). Re-tested against the same beta-4 IPSW (`26A5388g`) with a throwaway instance:
      `VZErrorDomain Code=10007` is gone — the standard `VZMacOSInstaller` path now runs to a
      different, unrelated failure (`Code=10006`, "software update required" — the beta-4
      IPSW itself is stale relative to what a 26.6 host's restore service will accept; a
      newer macOS 27 beta IPSW is needed to get a full end-to-end install, DFU or not).
      Confirms VirtualBuddy's own bug reports (insidegui/VirtualBuddy#706, #555) that this
      needed the *host* on a version-adjacent build, not just a matching Xcode device-support
      package. `patch-08-b3-dfu-beta27.diff`, `b3_rev`, and the `upstream-pr/b3-dfu-beta27`
      branch (local + `trodemaster`) are deleted. Full log:
      `lima_mac/docs/dfu-install.md` § "2026-07-25 Removal Confirmed".
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

### GUI / display ideas (not started)
- [ ] VZ GUI fullscreen mode includes the macOS menu bar — investigate whether the
      Virtualization.framework display surface can be presented without it (or whether
      this is a host-side `NSWindow`/`NSApplication` presentation option in `limactl`'s
      own GUI code rather than something VZ controls). Not yet scoped: no upstream issue,
      no branch.

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
