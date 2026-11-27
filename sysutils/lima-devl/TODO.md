# lima-devl — Upstream PR & Port Tracking

Status of feature patches carried by this port and their upstream submission.
Patch revs: see `w1_rev` / `b2_rev` / `p1_rev` in the Portfile (B4 is parked, no `b4_rev`).

## Feature status

| Patch | Feature | Upstream status |
|-------|---------|-----------------|
| V1 (`patch-04`) | ~~Guest macOS version detection~~ — **merged upstream as PR #5528 (2026-09-23)**, patch removed from port 2026-10-04 | done |
| B2 (`patch-06`) | TCC pre-seeding (`osOpts.Darwin.tccPermissions`, moved from `vmOpts.vz.guestPatch` in r14; sshd csreq fixed in r15, Terminal preset dropped and squashed in r16, presets only in r17, docs subsection in r18); branch `upstream-pr/b2-tcc` | ready for submission (B1 dependency now merged) |
| B4 (`patch-10`) | `osOpts.darwin.clipboard` (VZ SPICE agent port, host side only) | **parked — likely unfixable from a CLI binary** (2026-07-11) |
| M1 (`patch-09`) | ~~macOS 27 fakecloudinit workarounds~~ — **removed from port 2026-10-05** (beta-era; branch `macports/m1-fakecloudinit-macos27` kept in case any SA plist keys are still needed on 27 GA) | dropped |
| A1 (`patch-08`) | `osOpts.Darwin.autoLogin` (opt-in bool): fakecloudinit writes `/etc/kcpassword` + loginwindow `autoLoginUser` for the user it creates (classic and P1 paths), from the second boot; signalled by an empty `auto-login` cidata file. Not in upstream (no auto-login code, no issue); independent of vz v4, so it can go upstream before P1. Branch `feat/darwin-auto-login` (one commit on master) | **r2 2026-11-17**: E2E on a stock config (no lima_mac) auto-logs in from the 2nd boot; a password change breaks it (confirmed), docs say so |
| P1 (`patch-12`) | macOS 27 native guest provisioning, **automatic since r10** (no config): when host and guest are both 27+, Setup Assistant creates the user from `VZMacGuestProvisioningOptions` with a host-generated random password; the guest agent moves the home to `user.home` and sets the user up as for `sysadminctl`. Upstream issue #5516 (refactoring). PR branch `upstream-pr/p1-guest-provisioning` = port branch `macports/p1-port` (Z1 -> B2 -> A1 -> P1; P1 needs B2 for the guest agent's Full Disk Access; patch-12 = its P1 commit); r9 and earlier on `macports/p1-on-z1` | **r11 2026-11-17**: E2E on a stock config (host home mounted, no TCC presets) passes. **r14 2026-11-26**: password kept in `vz-guest-password` so an interrupted first boot can be finished (not guest-tested yet). Still needs a tagged vz v4 (Z1); flow in [P1-FLOW.md](P1-FLOW.md) (r14) |
| Z1 (`patch-11`) | Move to `github.com/Code-Hex/vz/v4` main (`64cc34b`, pseudo-version; r2 2026-11-17 on `fd6cf105`), which has the macOS 27 guest provisioning API (`NewMacGuestProvisioningOptions` / `WithGuestProvisioningOptions`); adapts to v4's channel-taking `StateChangedNotify`. Branch `macports/vz4-upstream` | local only — drop once lima moves to a tagged vz v4 |
| W1 (`patch-03`) | Windows WIM/ESD edition detection (`installationType`); its `Copy-Provision` switch fix was dropped 2026-11-07 (upstream `7cc8a755`) | carried in port; not yet submitted upstream |

`patch-01-g1-thread-pin.diff` merged upstream in PR #5036 and removed from port.
`patch-02-g4-window-title.diff` merged upstream in PR #5084 and removed from port.
`patch-04-g3-screenshot.diff` merged upstream in PR #5098 (2026-06-28) and removed from port.
`patch-05-b1-fakecloudinit.diff` (`suppressFirstLoginSetup`, Issue #5186) merged upstream in
PR #5336 (2026-09-10, merge commit `19e75908`) and removed from port; `b1_rev` dropped and the
`upstream-pr/b1-fakecloudinit-clean` branch deleted locally (still present on `trodemaster` —
delete from the fork). B2/M1 no longer stack on a local B1 branch; their own commits now rebase
straight onto `origin/master`.
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
patch-03-w1-windows-edition-detection.diff  ← carried in port
patch-04-v1-guest-os-version.diff    ← "PR 1" precursor, log-only
patch-06-b2-tcc.diff                 ← upstream candidate (B1 dependency merged)
patch-11-z1-vz-v4-upstream.diff      ← Code-Hex/vz v4 main, local only
patch-12-p1-guest-provisioning.diff  ← macOS 27 guest provisioning on Z1, local only
```

`patch-04-v1-guest-os-version.diff` — the full "PR 1". Branch
`feat/vz-guest-os-version-log` off `origin/master` (`19e75908`), 2 signed-off
commits:
1. `feat(vz): log the guest macOS version from the restore image` — one
   `logrus.Infof` in `newMacPlatformConfiguration` right where the driver already
   loads the restore image for the hardware model.
2. `feat(vz): expose the guest macOS version to cidata as LIMA_CIDATA_GUEST_OS_*`
   — persist `OperatingSystemVersion().String()` / `BuildVersion()` to two
   plain-text sentinels (`vz-guest-os-version`, `vz-guest-os-build-version`,
   `0o444`, written once alongside `vz-hwmodel` at create time); `templateArgs`
   reads them back for macOS guests via a new `readOptionalInstanceFile` helper;
   `TemplateArgs.GuestOSVersion` / `GuestOSBuildVersion`; `lima.env` template
   emits `LIMA_CIDATA_GUEST_OS_VERSION` / `LIMA_CIDATA_GUEST_OS_BUILD_VERSION`
   (always present, empty for non-macOS / qemu / pre-existing instances). Test
   `TestTemplateGuestOSVersion`. Docs in `website/.../dev/internals.md`.

Conventions matched deliberately (per Blake, "don't swim upstream"): sentinel
files mirror `vz-hwmodel` (macOS-only, one datum per file) and the `LimaVersion`
plain-text precedent; no new YAML/config knob; nothing consumes the value yet;
values are the restore image's (guest version at first boot, not tracked across
OS updates); env vars always emitted like the other optional `LIMA_CIDATA_*`.

`v1_rev` 1→2 when the patch grew from log-only to the full stack. Not yet
pushed to `trodemaster`, no PR — the issue draft goes up first per the skill's
issue workflow (`~/orac/Computer/blakeports/lima guest os version issue draft.md`).
Research: `lima_mac/docs/ipsw-build-manifest.md`.

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

**2026-11-07 sync to master `2f466781` (v2.3.0 released 2026-11-06):** 146 upstream
commits since `27bf0188`. W1's last commit (`Copy-Provision -Extension` `[bool]` →
`[switch]`) dropped on rebase: upstream fixed it independently in `7cc8a755`, which also
renames the `$dst` loop variable. W1 now 3 commits. B2 rebased clean (hunk offsets only).
P1 conflicted on `go.mod`/`go.sum` (upstream bumped vz v3.7.1 → v3.8.0 and hcsshim/go-winio)
and on `vz_driver_darwin_test.go` (upstream added hostLoopback tests next to P1's
`TestGuestProvisioningSkipReason`; kept both). go.mod resolved as upstream's with the
`vz/v3` → `vz/v4` swap and the `trodemaster/vz` replace re-applied, then `go mod tidy`.
`go vet ./...` clean on P1. `w1_rev` 6→7, `b2_rev` 12→13, `revision` reset to 0.
Then parked P1 (removed `patch-10`, dropped `p1_rev`; Blake will rebuild it on upstream vz)
and added Z1 (`patch-11`, `z1_rev 1`): upstream `Code-Hex/vz` main now has its own guest
provisioning API but no tagged v4 release, and lima master is still on v3.8.0, so Z1 pins
`v4.0.0-20261107060947-64cc34bcd7d0` (`// gomodjail:unconfined` kept) and bumps purego
0.11.3 / x/mod 0.42.0 with it. v4's `StateChangedNotify(chan)` returns a stop func, so
`startVM` registers a buffered channel before `Start`. Stack (Makefile, usrlocalgo, 03, 06,
11) applies clean on `2f466781`; `go vet ./...` clean for arm64 and amd64.
`build-lima-devl.yml` now reads the golangci-lint version from the source's
`hack/tools/go.mod` instead of a hand-bumped pin: v2.13.2 failed on the macOS_27 runner
("export data version 5 is greater than maximum supported version 4", newer go-1.27).
Tested on CI macOS_27 first.

**2026-11-26 B2 r14: config moved to `osOpts.Darwin.tccPermissions`** (was
`vmOpts.vz.guestPatch.tccPermissions`), ahead of the upstream PR: AkihiroSuda's rule from
#5186 is that guest-OS settings go under `osOpts.<os>`, not `vmOpts.<driver>`.
`TCCPermissions` is a field of `DarwinOpts` next to `AutoLogin`; `VZGuestPatch` is gone. The
vz driver reads `osOpts.Darwin` in `Configure` (macOS guests only, conversion errors fail
`Configure`) into `l.tccPermissions`. The docs examples moved too. The upstream PR branch is
now `upstream-pr/b2-tcc` (origin/master + B2's 3 commits; replaces `macports/b2-on-b1`).
`macports/p1-port` was rebuilt as Z1 → B2 → A1 → P1 (old one: `backup/p1-port-20261126`);
the only differences are the move and P1's `macos.Patch(ctx, disk, l.tccPermissions, opts)`.
A1's patch changed only in context lines (`a1_rev` stays 2); `b2_rev` 13→14, `p1_rev` 11→12.
Build, vet and the vz, limayaml, cidata and fakecloudinit tests pass on the fully patched
tree, except W1's ISO fixture test (binary fixtures can't travel in a `.diff`, as before).
lima_mac's macos-14/15/26/27 yamls moved their `tccPermissions` into `osOpts.Darwin` at the
same time; existing VMs are unaffected (TCC rows are only written when a disk is patched).
CI run 45917460516 green on 15/26/27 (incl. golangci-lint). E2E: `make rebuild-27` with a
limactl built from the port's patches (27.2.1 guest): the system TCC.db (read from the stopped
disk on the host) has the sshd FDA, Terminal Accessibility/PostEvent and guest-agent FDA rows,
auth_value 2, written at disk-patch time; the Terminal rows come only from the yaml, so the
new key works. P1 home move, SecureToken and A1 auto-login also OK. As already known, macOS
ignores some pre-written rows: SSH has no FDA and Terminal no Accessibility despite the rows
(sshd FDA has no effect on macos-26 either); only the guest-agent FDA row takes effect.
`upstream-pr/b2-tcc` also has a `TestConfigureTCCPermissions` commit (not in the port).

**2026-11-26 B2 r15: sshd preset csreq fixed.** The sshd FDA failure was B2's own bug: the
hard-coded `csreqSSHDKeygen` hex had one extra zero pad byte (61 bytes, length field 60), so
tccd saw `identifier "com.apple.sshd-keygen-wrapper" and never`. Replaced with the blob
`csreq -b` compiles for `... and anchor apple`; new `TestPresetCSReqs` decodes both preset
blobs (fails on the old hex). Commit `0ed25185` on `upstream-pr/b2-tcc`; `macports/p1-port`
rebuilt as Z1 → B2 (now incl. both tests and the fix) → A1 → P1 (old: `backup/p1-port-20261126b`;
the only differences are the two tests and the fix). patch-06 now includes the test commits;
patch-12 changed only in test-file context; patch-08 identical. `b2_rev` 14→15, `p1_rev`
12→13. Write-up: [findings/lima-tcc-sshd-csreq.md](../../findings/lima-tcc-sshd-csreq.md).
E2E 2026-11-26: `make rebuild-27` with a limactl from the port's patches (27.2.1 guest): SSH
sessions now have Full Disk Access (TCC dir, `~/Library/Mail`, system TCC.db readable); no
prompts; runner back online.

**2026-11-26 B2 r16: prepared for the upstream PR.** Dropped the `terminal-accessibility`
preset (rows kept but ignored on 26/27) and its csreq; docs now say presets carry the csreq,
custom entries get the binary's cdhash recorded by tccd on first use, and a "Limits" section
(system DB only; macOS doesn't honor every entry). Squashed `upstream-pr/b2-tcc` into one
commit `179b48f9` "vz: write TCC entries into macOS guests before the first boot" (old:
`backup/b2-tcc-20261126`). `macports/p1-port` rebuilt on it (A1 docs conflict resolved by
keeping both sections); patch-08 and patch-12 changed only in context (`a1_rev`/`p1_rev`
unchanged), `b2_rev` 15→16. lima_mac yamls (14/15/26/27) dropped the preset; a rebuild with
an r16 limactl would otherwise fail on an unknown preset.

**2026-11-26 B2 r17: presets only.** Custom entries (`service`/`client`/`clientType`/`authValue`)
removed: none of it was ever upstream, lima_mac used presets only, and pre-written rows can be
silently ignored. `TCCPermission` has only `preset`; `macos.ValidateTCCPermissions` runs in vz
`Configure`, so an unknown preset fails before the macOS install (new subtest). Docs: one preset
table, no custom section. B2 is now one commit `5f09d6c1` (414 lines; old `backup/b2-tcc-20261126`),
`macports/p1-port` rebuilt (`48b47c14`; old `backup/p1-port-20261126c`); patch-08/12 context only;
`b2_rev` 16→17. lima_mac yamls validate with an r17 limactl.

**2026-11-26 B2 r18 / P1 r14: P1 refinement.** Blake chose: keep
`lima-guestagent-full-disk-access` a public B2 preset; close P1's retry gap by keeping the
password.
- B2 (docs only): the TCC section is now `### Pre-populating TCC permissions` under Advanced
  topics, with a `Lima >= 2.4` requirement table, so A1's `### Automatic login` no longer
  lands under it. `upstream-pr/b2-tcc` = `53a5a1c2` (old `backup/b2-tcc-20261126b`).
- P1: the initial password moved to its own file, `vz-guest-password`, kept for the life of
  the instance and put on cidata every boot. `vz-guest-provisioning` is now an empty marker,
  still removed after the first start (the only one that passes the provisioning options).
  fakecloudinit skips adoption once `~/.ssh/authorized_keys` exists (not "home exists":
  Setup Assistant creates the home itself, so with `user.home` = `/Users/<user>` that would
  skip too early), so a first boot cut off after Setup Assistant made the account is
  finished on the next boot. If it is cut off before Setup Assistant ran, the docs say to
  recreate the instance. Not tested on a guest yet.
- P1 docs: the TCC link pointed at `#built-in-presets`, which r17 removed; now
  `#pre-populating-tcc-permissions`. Commit message: the users-before-mounts reorder
  applies to all macOS guests, and says so.
- A1 and P1 had no `Signed-off-by` (Lima requires DCO); added.
- `macports/p1-port` = `upstream-pr/p1-guest-provisioning` = `9332409e`: Z1 `ac0824b6` →
  B2 `b6294479` → A1 `00558c36` → P1 (old `backup/p1-port-20261126d`). patch-08 context
  only (`a1_rev` stays 2); `b2_rev` 17→18, `p1_rev` 13→14. All patches apply to `9a3022aa`
  without fuzz; build, vet (arm64, amd64 cgo), the vz, cidata, fakecloudinit and guestpatch
  tests, and golangci-lint v2.15.0 (0 issues) pass.
- Checked on the runners: the 26 guest's `sysadminctl` account and the 27 guest's
  Setup Assistant account both have SecureToken ENABLED, so SecureToken is not a reason
  for P1 (P1-FLOW.md said it was).
- **macos-26 rebuilt** with an r18/r14 limactl (`2.3.0-dev.20261126c`, built from
  `9a3022aa` + the port patches; CI run 45952421945 green on 15/26/27), 22:33–22:55:
  26.7.3 guest, no `vz-guest-provisioning`/`vz-guest-password`, `.AppleSetupDone` and
  `.skipbuddy` written by Lima, `sysadminctl` account `blake` with home
  `/Users/blake.guest`, auto-login, runner `macOS_26` online. The `sysadminctl` path is
  unchanged with the users-before-mounts order.
- **Upstream boot race (not ours), seen in that rebuild:** after the guest rebooted itself
  (lima_mac `autologin-reboot.sh`), `lima-macos-init.sh` found `/Volumes/cidata` but
  `exec /Volumes/cidata/lima-guestagent` failed with "No such file or directory": the
  mount point was there before the ISO contents. The LaunchDaemon is `RunAtLoad` only,
  with no retry, so fake-cloud-init didn't run on that boot: no mounts, `wait-mount` timed
  out and `build-26` failed. A host `limactl stop`/`start` (`make patch-26`) recovered it.
  The script is upstream code in `guestpatch/macos` (only checks `-e /Volumes/cidata`);
  waiting for the agent binary, or `KeepAlive` on failure, would fix it. Not reported.

**2026-11-26 B2 r19 / P1 r15: preset check moved out of `Configure`.** `make rebuild-27` with
the r18 limactl failed in `clean-27`: `limactl remove macos-27` → `failed to create driver
instance: osOpts.Darwin.tccPermissions: unknown TCC preset "terminal-accessibility"`. The
instance was created at r15, when that preset existed, and r17 checked presets in vz
`Configure`, which deletion also runs (upstream's own comment in `Validate` says so). So an
instance with a preset a later Lima drops couldn't be deleted. Now `darwinTCCPermissions(cfg)`
parses and checks the presets; the driver's `Validate` (start, before the install) and
`CreateDisk` call it; `Configure` doesn't, and the `tccPermissions` driver field is gone.
`TestDarwinTCCPermissions` replaces `TestConfigureTCCPermissions` and checks that `Configure`
succeeds with an unknown preset. B2 `6ec347e9` (old `backup/b2-tcc-20261126c`); stack Z1 →
B2 `d88cdbb4` → A1 `1ba0a9cc` → P1 `eff6292f` (old `backup/p1-port-20261126e`; P1 conflicted
only at the `macos.Patch` call). patch-08 unchanged; `b2_rev` 18→19, `p1_rev` 14→15. Build,
tests (B2 alone and the stack), amd64 vet and golangci-lint pass. The failed `clean-27` had
already deregistered `macOS_27` and stopped the VM.

**2026-11-26 sync to master `9a3022aa` (v2.3.0-rc.0+):** 65 upstream commits since
`fd6cf105`, mostly fixes and dependabot. Nothing touches the plans: A1 still not merged,
no tagged vz v4 (v3.8.0 still latest), #5516 unchanged, #5790 (USB) still open. Upstream
vz changes are `vsock_forwarder.go` (close vsock when ssh client goes away, Accept-spin
fix) and launchd ExitTimeOut. W1, B2, Z1, A1 and P1 rebased clean; all patches differ
only in `index` hashes, so no rev bumps. Full stack dry-runs in Portfile order.
The tarball shrank 8.1 MB to 2.45 MB (upstream dropped `demo.gif`).

**2026-11-17 sync to master `fd6cf105` (v2.3.0-43):** 21 non-merge upstream commits
since `2f466781`. W1, B2, Z1 and P1 rebased clean with no conflicts. W1, B2 and P1
regenerated byte-identical. Z1 got smaller: upstream's dependabot took the
`golang.org/x/mod` 0.41.0 → 0.42.0 bump Z1 used to carry, so `patch-11` is now only
the vz v4 swap and purego 0.11.3 (`z1_rev` 1→2). Code-Hex/vz is still untagged (v3.8.0
latest, main still `64cc34b`, Z1's pin). Full stack applies to `fd6cf105` in Portfile
order; `go mod tidy -diff` clean, `limactl` builds, and vet is clean on the vz, cidata,
fakecloudinit, guestpatch and limatype packages. In the patched tree, W1's
`TestCheckWindowsVersionFixtures` fails because a diff patch can't carry the binary
`pkg/udfutil/testdata/*.iso` fixtures; it passes on the W1 branch itself (the port
doesn't run `go test`). Lima PR #5790 (USB passthrough) moves lima to the same vz v4
pseudo-version as Z1; it's needs-design-consensus.

**2026-11-17 P1 r10, review against upstream conventions:** Issue #5516 is a
`kind/refactoring` issue asking to use `VZMacGuestProvisioningOptions` for 27+ guests in
place of part of `guestpatch/macos.Patch`, so Blake chose automatic provisioning with no
config. Removed: `osOpts.Darwin.guestProvisioning` (password, `logsInAutomatically`,
`enablesRemoteLogin`), the `limayaml` home helpers, `RemoveSetupAssistantMarkers` (second
disk mount) and Lima's own auto-login (`/etc/kcpassword`, reverse engineered).
`enablesRemoteLogin` was a no-op (fakecloudinit `enableSSHD` always runs). Now:
`prepareGuestProvisioning` writes a random password (same generator as Windows and the
classic path) to the `0600` `vz-guest-provisioning` marker; `macos.Patch` takes
`PatchOptions{RunSetupAssistant}` and doesn't write the markers; start options use
`user.comment` (falls back to `user.name`, since Setup Assistant needs a full name), auto
and remote login off. Guest: home compared as cleaned paths, `chmod 700` like
`sysadminctl` users, UID-mismatch warning, `dscl` output parsed by a tested
`parseDSCLRead` (missing `UniqueID` used to give uid 0; values with spaces wrap), no
silent "already in directory services" skip, no `%w` of a nil error. Only a host older
than a 27 guest warns; older guests log at debug. Docs: macos.md section rewritten
(Lima >= 2.4), `vz-guest-provisioning` added to dev/internals.md. golangci-lint v2.15.0
0 issues; darwin/amd64 cgo build and vet clean; tests pass. P1 now conflicts with B2 in
`macos.Patch` (both add a parameter), so the port's P1 comes from `macports/p1-port`
(Z1 + B2 + P1); upstream, whichever PR merges second rebases. lima_mac `macos-27`
no longer sets `guestProvisioning` or `PROVISION_PASSWORD`.
Blake: auto-login is needed, so it came back as its own upstreamable feature A1
(`osOpts.Darwin.autoLogin`, patch-08) rather than a P1 knob: P1 keeps Apple's
`logsInAutomatically` off (the home move needs the user logged out) and calls A1's
guest-side step after the move. P1 PR branch is now Z1 -> A1 -> P1; port branch
`macports/p1-port` is Z1 -> B2 -> A1 -> P1. lima_mac `macos-27` sets `autoLogin: true`.

**2026-11-17 P1 r11, found by E2E on a stock config** (throwaway VM, no lima_mac
provisioning, `mounts: ["~"]` as in upstream's `template:macos-27`): (1) without Full
Disk Access macOS refuses both the home rename and `dscl -create NFSHomeDirectory`
(`ODErrorRecordPermissionError`, even with `-u/-P`); r9 only worked because lima_mac
sets B2's `lima-guestagent-full-disk-access`. Blake chose to grant it: `PatchOptions` is
now `GuestProvisioning`, which also adds that preset, so **P1 now builds on B2 upstream
too** (PR order Z1 -> B2 -> A1 -> P1; `upstream-pr/p1-guest-provisioning` ==
`macports/p1-port`). (2) fakecloudinit set up mounts before users, so the host-home
symlink took `/Users/<user>` before Setup Assistant made the home there and the agent
renamed the symlink; users are now created first, and the move refuses a non-directory.
A1 patch-08 is now generated from the port branch (after B2) so it applies without fuzz.

**2026-11-13 P1 r8/r9, move the home instead of renaming the account (working, r9):**
The end-to-end flow (host and guest steps, files, failure handling, what didn't work)
is in [P1-FLOW.md](P1-FLOW.md).
two local commits on `macports/p1-on-z1`, `5f77b1ec` (r8) and `ffb7615c` (r9). Lima keeps its
normal macOS guest defaults (account `<host user>`, home `/Users/<user>.guest`), so the
upstream PR doesn't have to change the default username.
- Reverted r5/r6: no `.guest` username suffix, no `user.home` validation.
- `limayaml.GuestProvisioningMovesHome`: `user.home` != `/Users/<user.name>`. When true, the
  vz driver passes automatic login **off** to Apple, and cidata adds an empty
  `guest-provisioning-autologin` file (only while the provisioning marker exists).
- fakecloudinit `moveProvisionedHome`, after adopting the account: wait for
  `/var/db/.AppleSetupDone`, `launchctl bootout user/<uid>` (r9), wait for no processes as the
  uid (`pgrep -U`), `mv` the home, `dscl . -create /Users/<name> NFSHomeDirectory`,
  `dscacheutil -flushcache`, re-read the record. If it fails, `user.home` is symlinked to
  Apple's home so the boot scripts still work (r9).
- `enableAutoLogin` writes `/etc/kcpassword` and `autoLoginUser`; it takes effect from the
  second boot.
- **r8 guest test** (`make rebuild-27`, 27.2 host and guest):
  - The move was skipped. Setup Assistant leaves a background `user/501` launchd session at
    the login window (distnoted, cfprefsd, trustd, secd, lsd, pkd, containermanagerd, ...),
    so the `pgrep` wait gave up after a minute.
  - The fallback then broke `00-lima.boot.sh`: `cp: /Users/blake.guest/.lima-user-script`.
  - `killall loginwindow` at the login window did **not** log the user in. The `kcpassword`
    encoding is right, though: auto-login worked on the next boot. Root `launchctl bootout
    gui/501` (to test logout) hung, then the job vanished; not used.
- **r9 guest test** (`make rebuild-27`, 21:48):
  - The first boot moved the home 5 s after Setup Assistant created the account, and was
    READY about 20 s later; the first boot stops at the login window.
  - lima_mac's user provision script logs `defaults write ... Could not write domain` on that
    first boot, because there is no user session yet. On the second boot it auto-logs in and
    the script runs clean.
  - Checked in the guest: one account `blake` (uid 501, full name from the host), home
    `/Users/blake.guest`, no `/Users/blake`; GUI login session; SecureToken enabled and
    `fdesetup list` shows blake; the login keychain unlocks with `~/password`; no
    `/Users/blake/` paths in `~/Library/Preferences`; passwordless sudo; desktop with no
    first-login screens.
- `limactl screenshot` works on 27.2 when the VM window's app isn't hidden; it fails with "no
  data" when the limactl app is hidden (Cmd-H). Earlier black frames were not reproduced.

**2026-11-07 P1 rebuilt on Z1 and verified on both far-star runners:**

- **The port.** P1 was ported from the `trodemaster/vz` fork API to upstream vz v4 as one
  commit, `f0387c56` on branch `macports/p1-on-z1`, stacked on `macports/vz4-upstream`.
  - `vz.WithGuestProvisioning(vz.MacGuestProvisioningOptions{...})` became
    `vz.WithGuestProvisioningOptions(vz.NewMacGuestProvisioningOptions(...,
    vz.WithGuestAutomaticLogin, vz.WithGuestRemoteLogin))`.
  - The start options are now built before the `StateChangedNotify` registration.
- **The patch.** `patch-12-p1-guest-provisioning.diff` is the diff
  `macports/vz4-upstream..macports/p1-on-z1`; `p1_rev` is 7.
  - The full stack applies to `2f466781` without fuzz.
  - `go vet` is clean for arm64 and amd64 (amd64 needs `CGO_ENABLED=1`).
  - The provisioning, cidata and limayaml tests pass.
- **CI and merge.** Green on macOS_27 (run 42429288709), then macOS_26 and macOS_15 (run
  42430665815). Merged to main as `09f010b`; the push run 42431370386 was green on all three.
- **macOS_27 runner rebuilt with it** (`make rebuild-27`, 16:30–16:38, macOS 27.2 host and
  27.2 `26B123` guest):
  - Setup Assistant created the only regular account, `blake` (uid 501, admin,
    `/Users/blake`, full name from the host), and fakecloudinit adopted it.
  - The guest has auto-login, Remote Login on, `authorized_keys`, `~/password` and
    passwordless sudo.
  - Setup Assistant wrote `.AppleSetupDone` itself, and the `vz-guest-provisioning`
    marker was removed after the first boot.
  - netatalk CI on the new runner passed (run 42430668244).
- **macOS_26 runner rebuilt** (`make rebuild-26`, 17:41–17:56, 26.6.2 `25G83` guest). This
  checks the skip path for a 27 host with a pre-27 guest:
  - no provisioning marker, and Setup Assistant didn't run;
  - the classic `sysadminctl` account `blake` with home `/Users/blake.guest`.
  - netatalk CI passed (run 42436357149).
  - The two runners now have different home paths by design.
- **Watching the console.** `limactl screenshot` gave only black frames on macOS 27.2; use
  Screen Sharing to far-star instead.

**2026-08-02 review-feedback sync:** PR #5336 got reviewer pushback on
`suppressFirstLoginSetup: {}` ("why not `true`?") plus a request to keep the custom-plist
override as a separate option rather than a nested field. Amended the PR's single commit
(force-pushed, `c6b2a4a1` → `e40a3a34`): `DarwinOpts.SuppressFirstLoginSetup` is now `*bool`,
and a new `DarwinOpts.SuppressFirstLoginSetupPlist *string` carries the custom plist; the
`SuppressFirstLoginSetup` struct type is gone. Docs updated to `suppressFirstLoginSetup: true`
+ a sibling `suppressFirstLoginSetupPlist: |` key.

**2026-09-02 sync to master `659e69a5` (v2.3.0-dev):** PR #5336's last open review thread was
`ADD VERSION HERE` in `website/content/en/docs/usage/guests/macos.md` — filled in as
`macOS >= 13.0` (Blake: feature works on macOS 13–26; table is scoped to the feature's own
`###` heading, page-wide requirement stays in the top table). Rebased
`upstream-pr/b1-fakecloudinit-clean` onto `659e69a5`, amended the single commit with the doc
fix (`e40a3a34` → `c700cfd6`), force-pushed to `trodemaster` (has open PR #5336, approved).
Rebuilt `macports/b2-on-b1` (3 own commits) and `macports/m1-fakecloudinit-macos27` (7 own
commits) via the disposable-branch cherry-pick method onto the new B1 tip — zero conflicts;
`feat/windows-wim-edition-detection` (W1, 4 commits) rebased onto `659e69a5` clean.
Regenerated patch-03/05/06; patch-09 (M1) came out byte-identical. `go.setup` → `659e69a5`,
`version` → `2.3.0-dev.20260902`, new distfile checksums. Bumped `w1_rev`→3, `b1_rev`→9,
`b2_rev`→9 (`m1_rev` unchanged). All six patches (Makefile, usrlocalgo, 03, 05, 06, 09)
apply clean in sequence against a fresh `659e69a5` archive; fully-patched tree builds
(`go build ./...`) and vets clean; `port lint` 0/0. `macports/b2-on-b1`,
`macports/m1-fakecloudinit-macos27`, and `feat/windows-wim-edition-detection` NOT yet
force-pushed to `trodemaster` (none has an open PR).

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
      `sudo port -kv install lima-devl` on self-hosted macOS runners (15/26/27) plus
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
- [ ] Revisit M1 (fakecloudinit) now that macOS 27 is released — may be partially upstreamable
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
- [ ] Test TCC patching against a macOS 27 guest (template exists in lima_mac, untested).
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
- [x] Rebuild VMs with the current patch set (W1, B2, Z1, P1): macOS_27 (native
      provisioning) and macOS_26 (classic path) rebuilt and green 2026-11-07, see the
      2026-11-07 P1 note above.

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
