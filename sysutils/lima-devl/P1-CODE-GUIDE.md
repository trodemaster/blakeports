# Code guide: the macOS guest stack (A1, users-before-mounts, B2, P1)

A reading guide for reviewing the lima changes yourself before any PR. It follows the
order the PRs would go upstream, and inside each one the order the code runs. The
design history and test results are in [P1-FLOW.md](P1-FLOW.md) and [TODO.md](TODO.md);
this file only says where to look and what to check.

Paths are relative to `~/Developer/lima-devl`. Line numbers are for the stack branch
`macports/p1-port` as of 2026-11-27 (B2 r20, A1 r3, P1 r16); the standalone branches
have the same code a few lines off.

## Setup

```bash
cd ~/Developer/lima-devl
git checkout macports/p1-port
git log --oneline origin/master..HEAD     # Z1, B2, A1, then P1's three commits
git show --stat <sha>                     # one commit at a time
```

| Order | Commit | Standalone branch (on `origin/master`) | Size |
|---|---|---|---|
| 1 | A1 `19268c2c` `feat(darwin): add osOpts.Darwin.autoLogin` | `upstream-pr/a1-auto-login` `5641ee67` | 6 files, +111 |
| 2 | `ca55afba` `fix(fakecloudinit): create macOS guest users before mounting` | `upstream-pr/users-before-mounts` `f502bcbe` | 1 file, +7 −5 |
| 3 | B2 `aeead930` `vz: write TCC entries into macOS guests before the first boot` | `upstream-pr/b2-tcc` `968911e9` | 7 files, +423 −23 |
| — | Z1 `ac0824b6` vz v4 (local only; waits for a vz v4 tag) | `macports/vz4-upstream` | go.mod and imports |
| 4 | P1 `fa39fc07` refactor, then `e4209709` the feature | `upstream-pr/p1-guest-provisioning` (the stack) | refactor +15 −6; feature 13 files, +477 −17 |

A1, the fix and B2 each apply to master alone. P1 needs B2 and Z1.

## Where the code runs

Every piece runs at one of these points. Knowing which one answers most "why is this
here" questions.

| When | Process | Files |
|---|---|---|
| `limactl create` / first `start`, before anything boots | `limactl` | `pkg/driver/vz/vz_driver_darwin.go` (`Validate`, `CreateDisk`, `createDiskMacOSGuest`), `pkg/guestpatch/macos/` (writes into the guest's disk image) |
| Every start, before boot | hostagent | `pkg/cidata/cidata.go` (builds the cidata ISO), `pkg/driver/vz/vm_darwin.go` (`startVM`) |
| Every guest boot | guest, root, LaunchDaemon → `lima-guestagent fake-cloud-init` | `pkg/guestagent/fakecloudinit/fakecloudinit_darwin.go` |

The host passes nothing to the guest except the cidata volume. Each feature's on/off
signal is a file on it (`auto-login`, `guest-provisioning-password`), never a
`user-data` key: Akihiro asked for that in the B1 review (#5336).

---

## 1. A1: `osOpts.Darwin.autoLogin`

Turns on automatic login for the Lima user, from the second boot.

Read in this order:

1. `pkg/limatype/lima_yaml.go:379`: the option, a plain `*bool` under `osOpts.Darwin`,
   next to B1's `suppressFirstLoginSetup` (same pattern: no defaults code, unset = off).
2. `pkg/cidata/cidata.go:188`: `templateArgs` turns it into `TemplateArgs.AutoLogin`.
3. `pkg/cidata/cidata.go:479`: `GenerateISO9660` adds an empty `auto-login` file.
4. `pkg/guestagent/fakecloudinit/fakecloudinit_darwin.go:656` `maybeEnableAutoLogin`:
   called at the end of `createUser` (`:438`), only when the user is created, so only
   on the first boot.
5. `:669` `kcpasswordKey`, `:674` `encodeKCPassword`: the XOR obfuscation loginwindow
   expects in `/etc/kcpassword`.
6. `:687` `enableAutoLogin`: writes `/etc/kcpassword` (0600) and
   `defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser`.
7. Docs: `website/content/en/docs/usage/guests/macos.md`, `### Automatic login`.
8. Test: `pkg/guestagent/fakecloudinit/fakecloudinit_darwin_test.go:13`
   `TestEncodeKCPassword`.

Check:

- The comment on `kcpasswordKey` says the format is undocumented. Reviewers ask about
  bare literals; this one is explained.
- Failure is a warning, not an error: SSH still works without auto-login.
- Why not `sysadminctl -autologin set`: it needs the Security Agent, which a
  LaunchDaemon at boot doesn't have, and fails silently. The commit message says so.
- What a reviewer may ask: why not take effect on the first boot (loginwindow reads the
  setting when it starts, before the agent runs); FileVault (auto-login is unavailable
  with it; the docs say so).

## 2. Create users before mounts (fix)

A one-hunk change in `processUserData`,
`pkg/guestagent/fakecloudinit/fakecloudinit_darwin.go:87`.

1. `:116`: users are now created before the mount loop.
2. Why it is a fix on its own: `mountVirtiofs` (`:168`) makes a mount as a symlink
   (`os.Symlink` at `:188`) and doesn't create parent directories. On the first boot
   the home doesn't exist before `createUser`, so a mount point inside it
   (`mountPoint: /Users/<user>.guest/work`) failed.

Check:

- Nothing in the mount loop needs a user to not exist yet.
- This is from reading the code; it hasn't been reproduced on a guest. Worth one test
  before the PR: a stock macOS 26 instance with a `mountPoint` under `user.home`, on
  the old and new code.

## 3. B2: `osOpts.Darwin.tccPermissions`

Writes rows into the guest's system TCC database while the disk image is patched,
before the first boot. Presets only.

Read in this order:

1. `pkg/limatype/lima_yaml.go:376` and `:384`: `TCCPermissions []TCCPermission`, where
   `TCCPermission` has only `preset`.
2. `pkg/driver/vz/vz_driver_darwin.go:264` `Validate` and `:292` `darwinTCCPermissions`:
   parses `osOpts.Darwin` and rejects an unknown preset at start, before the install.
   It is deliberately not in `Configure`, which delete also runs (the r19 lesson: an
   instance made with a preset a later Lima dropped must still be deletable).
3. `:429` `CreateDisk` → `:448` `macos.Patch(ctx, disk, tccPerms, opts)`. Runs once,
   guarded by the `disk.patched` marker.
4. `pkg/guestpatch/macos/macos_darwin.go:70` `Patch`: two passes over the disk image.
   - `:160` `writeGuestFiles`: mounts the Data volume `noowners`, writes the
     LaunchDaemon, init script and markers (upstream code), then `patchTCC` (`:217`).
   - `:120` `patchFixOwnership`: chowns what was written to root:wheel by editing APFS
     inodes on the raw device (upstream's trick, no sudo). B2 adds the TCC paths to
     the list.
5. `pkg/guestpatch/macos/tcc_darwin.go`:
   - `:50` `tccPresets`: two entries, `sshd-full-disk-access` (with the csreq at
     `:36`) and `lima-guestagent-full-disk-access` (no csreq: the agent is ad-hoc
     signed and changes every build; tccd records its cdhash on first use).
   - `:23` `tccEntry`: service, client and csreq. The other columns are the same for
     every preset and are literals in `insertTCCEntry` (`:166`), explained in the
     `tccEntry` comment.
   - `:75` `patchTCC`: creates the directory (`mkdirAllTracked`, `:186`, records what
     it made so ownership can be fixed), creates the schema, inserts rows.
   - `:211` `runSQLite`: shells out to the host's `/usr/bin/sqlite3`.
6. Docs: `macos.md` `### Pre-populating TCC permissions`.
7. Tests: `pkg/guestpatch/macos/tcc_darwin_test.go:44` `TestPresetCSReqs` (decodes the
   csreq blob), `pkg/driver/vz/vz_driver_darwin_test.go:93` `TestDarwinTCCPermissions`.

Check:

- The schema is macOS 15's, `admin.version` 30. Tested on 14 to 27 guests.
- What a reviewer may ask:
  - why a list of `{preset: …}` objects instead of a list of strings (open question
    below);
  - why `sqlite3` from the host instead of a Go library (no new dependency; it ships
    with macOS);
  - why a preset for Lima's own guest agent (P1 needs it; it's also useful alone);
  - that tccd keeps but doesn't honor every pre-written row (the docs' last paragraph).

## 4. P1: guest provisioning for macOS 27+ guests

Two commits. Read the refactor first: it makes the feature diff smaller.

### 4a. Refactor `fa39fc07`

`installUserFiles` (`fakecloudinit_darwin.go:625`) is split out of `createUser`:
`~/password`, `~/.ssh/authorized_keys`, sudoers. No change in behavior. Compare with
`git show fa39fc07`: the body moves as is, and `err =` becomes `err :=`.

### 4b. The feature `e4209709`

Automatic, no config: used when the host and the guest are both macOS 27 or later.
Follow one instance from create to second boot.

**Host, at create** (`limactl`):

1. `pkg/driver/vz/vz_driver_darwin.go:468` `createDiskMacOSGuest`: after the install
   it calls `:518` `prepareGuestProvisioning` (`:529`).
2. `:565` `guestProvisioningSkipReason`: host major from `osutil.ProductVersion`, guest
   version from `vz-guest-os-version` (PR #5528). Guests before 27 ignore the options
   silently, so the version has to be checked up front. Test:
   `vz_driver_darwin_test.go:130`.
3. If it applies: a 16-character password goes to `vz-guest-password` (0600, kept)
   and an empty marker `vz-guest-provisioning` (0644, removed after the first start).
   Names in `pkg/limatype/filenames/filenames.go:77`, documented in
   `website/content/en/docs/dev/internals.md`.
4. `CreateDisk` (`:448`): `PatchOptions{GuestProvisioning}` is true while the marker
   exists. In `pkg/guestpatch/macos/macos_darwin.go`:
   - `:42` `PatchOptions`, `:60` `setupAssistantMarkers`: with provisioning,
     `.AppleSetupDone` and `.skipbuddy` are not written, so Setup Assistant runs and
     reads the options;
   - `:54`: B2's `lima-guestagent-full-disk-access` is added. Without it macOS refuses
     both the home rename and the `dscl` change in the guest (EPERM).

**Host, every start** (hostagent):

5. `pkg/cidata/cidata.go:145`: reads `vz-guest-password`; `:488` puts it on cidata as
   `guest-provisioning-password`, every boot.
6. `pkg/driver/vz/vm_darwin.go:132`: `guestProvisioningStartOptions`
   (`vm_darwin_arm64.go:193`) returns options only while the marker exists. Full name =
   `user.comment` or `user.name`; automatic and remote login off (the comments say
   why). `:146` `machine.Start(startOpts...)` (vz v4 API, hence Z1); `:154` removes the
   marker.

**Guest, first boot** (`fakecloudinit_darwin.go`):

7. `:341` `createUser` → `:350`: `guest-provisioning-password` on cidata means "adopt,
   don't create". `:355`: skip once `user.home/.ssh/authorized_keys` exists (not "home
   exists": Setup Assistant creates the home itself).
8. `:447` `adoptProvisionedUser`:
   - waits for the directory record (`lookupDSUser` `:585`, `parseDSCLRead` `:601`,
     tested at `fakecloudinit_darwin_test.go:30`), then for `/var/db/.AppleSetupDone`.
     The second wait happens even when the home doesn't move (new in r16);
   - moves the home if `user.home` differs from `/Users/<user>`;
   - `suppressFirstLoginScreens` if B1 is on, `chmod 700`, `installUserFiles`, then
     A1's `maybeEnableAutoLogin`.
9. `:510` `moveProvisionedHome`: `launchctl bootout user/<uid>` (Setup Assistant
   leaves a background session holding the home), wait until `pgrep -U` finds nothing,
   refuse a non-directory source or an existing target, `rename`, `dscl -create
   NFSHomeDirectory` (renamed back on failure), flush the cache, read the record
   again.
10. If the move fails, the caller symlinks `user.home` to Apple's home and logs a
    warning, so boot scripts still work.
11. Then the mounts (after users, from commit 2) and the boot scripts.

**Guest, later boots:** `authorized_keys` exists, so `createUser` returns at `:355`.
A boot cut off after Setup Assistant made the account but before `authorized_keys`
redoes step 8 on the next boot.

Check:

- `waitFor` (`:566`) timeouts: 10 min for the account, 10 min for Setup Assistant,
  1 min for the processes.
- The amd64 stub, `vm_darwin_amd64.go`: returns no options (Intel hosts can't run
  macOS guests).
- What a reviewer may ask: the FDA grant to Lima's agent; the plaintext password in
  the instance dir and on cidata (same as the classic path's `~/password`); the marker
  removed when `Start` returns, not when the boot finishes (macOS guests run no agent
  daemon, so the host can't know); moving the home at all (the separate home-move
  issue draft explains it).

---

## Upstream fit

| Rule (from earlier reviews) | Status |
|---|---|
| Guest OS options under `osOpts.<os>` | all three options are in `osOpts.Darwin` |
| Plain booleans, not `{}` flags | `autoLogin: true`; P1 has no option |
| Out-of-band cidata files, not `user-data` keys | `auto-login`, `guest-provisioning-password` |
| Explain non-obvious literals | kcpassword key, csreq blob, TCC column values |
| DCO `Signed-off-by` on every commit | all five commits (Z1 is local only and has none) |
| Tests for logic that can run on the host | `TestEncodeKCPassword`, `TestParseDSCLRead`, `TestGuestProvisioningSkipReason`, `TestDarwinTCCPermissions`, `TestPresetCSReqs` |
| One change per PR | A1, the fix and B2 apply alone to master; P1 is refactor + feature |

Commit subjects: upstream mostly uses `area: change` (about 9 in 10 commits since
October, leaving out dependabot's `build(deps):`); `feat(vz):` is accepted too (our PR #5528 merged as one). The stack mixes
both (B2 is `vz:`). Pick one before the first PR.

## Open questions for you

1. B2's YAML shape: `tccPermissions: [{preset: sshd-full-disk-access}]` or a plain
   list, `tccPermissions: [sshd-full-disk-access]`. The object leaves room for more
   fields, but there are none since custom entries were dropped, and Akihiro has
   pushed back on unneeded structure before.
2. Whether to reproduce the mount-inside-home failure on a guest before proposing the
   fix.
3. Commit subject style (above).
