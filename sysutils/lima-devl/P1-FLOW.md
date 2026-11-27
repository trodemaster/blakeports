# P1 flow: macOS 27 guest provisioning with a moved home

How Lima creates the user of a macOS 27+ guest with Apple's guest provisioning, as of
P1 r14 (2026-11-26). P1 is automatic and has no config. The branch is lima
`macports/p1-port`, which is also the upstream PR branch `upstream-pr/p1-guest-provisioning`:

| Commit | Patch | What |
|---|---|---|
| `ac0824b6` | Z1, patch-11 | move to Code-Hex/vz v4 main (untagged) |
| `b6294479` | B2, patch-06 | TCC presets (`osOpts.Darwin.tccPermissions`) |
| `00558c36` | A1, patch-08 | `osOpts.Darwin.autoLogin` |
| `9332409e` | P1, patch-12 | guest provisioning |

The test history is in [TODO.md](TODO.md) (the P1 notes from 2026-11-07, -13 and -17).
The Apple-side mechanism is reverse engineered in
`~/Developer/lima_mac/docs/macos27-guest-provisioning.md`.

## The problem in one paragraph

On macOS 27, `VZMacGuestProvisioningOptions` (username, full name, password, auto-login,
Remote Login) is handed to the guest on its first boot. The faceless Setup Assistant
creates the account from it and writes `.AppleSetupDone`. The account is no better than
a `sysadminctl` one: on 2026-11-26 the 26 runner's `sysadminctl` account and the 27
runner's Setup Assistant account both had SecureToken ENABLED. Issue #5516 asks Lima to use this for 27+ guests instead of skipping
Setup Assistant and running `sysadminctl`. But Apple always puts the home at
`/Users/<username>`, and the API has no home option. Lima's macOS default home is
`/Users/<user>.guest`, because `/Users/<user>` is where the host's home is mounted
(upstream's macOS templates include `_default/mounts`). So P1 keeps the account name
`<user>` and **moves the home** to `user.home` on the first boot, before anyone logs in
and before the mounts are set up.

## Where each step runs

| Step | Process | Code |
|---|---|---|
| Install, version check, password | `limactl` (create/first start) | `pkg/driver/vz/vz_driver_darwin.go` `createDiskMacOSGuest`, `prepareGuestProvisioning`, `guestProvisioningSkipReason` |
| Disk patch: run Setup Assistant, grant FDA | `limactl` | `pkg/guestpatch/macos/macos_darwin.go` `Patch` with `PatchOptions{GuestProvisioning}`; B2's `patchTCC` |
| cidata file | hostagent | `pkg/cidata/cidata.go` `templateArgs`, `GenerateISO9660` |
| Start options | hostagent | `pkg/driver/vz/vm_darwin_arm64.go` `guestProvisioningStartOptions`; `vm_darwin.go` `startVM` |
| Account creation | guest, Setup Assistant (Apple) | — |
| Adopt, move, auto-login | guest, LaunchDaemon `io.lima-vm.lima-macos-init` → `lima-guestagent fake-cloud-init` (root) | `pkg/guestagent/fakecloudinit/fakecloudinit_darwin.go` `Run`, `createUser`, `adoptProvisionedUser`, `moveProvisionedHome`, `maybeEnableAutoLogin` (A1) |

The fakecloudinit log goes to the guest's `/dev/tty.virtio`, which is the host's
`~/.lima/<instance>/serialv.log`. Read it there; reading `/dev/tty.virtio` inside the
guest hangs. The serial log is rewritten on every boot, so read it before restarting.

## Host side: create and first start

1. **Install** (`createDiskMacOSGuest`). macOS is installed from the IPSW, and the
   restore image's version is written to `vz-guest-os-version` (merged upstream as
   PR #5528).
2. **Gate** (`prepareGuestProvisioning`). It checks the host with
   `osutil.ProductVersion` and the guest with `store.ReadGuestOSVersion`.
   `guestProvisioningSkipReason` returns a reason when:
   - the guest version is unknown or can't be parsed;
   - the guest is older than 27 (older guests ignore the options without an error, so
     this has to be checked up front);
   - the host is older than 27 while the guest is 27+.

   Only the last case logs a warning; the others log at debug, so older guests are
   quiet. With a reason, the instance takes the classic `sysadminctl` path. Otherwise it
   generates a random 16-character password (same generator as the classic path and
   Windows) to `vz-guest-password` (`0600`) and writes the empty marker
   `vz-guest-provisioning`, both in the instance directory. The marker means "the next
   start passes the provisioning options"; the password file means "Setup Assistant
   creates this instance's user" and is kept for the life of the instance.
3. **Patch the disk** (`CreateDisk` → `macos.Patch`). With
   `PatchOptions{GuestProvisioning: true}` it installs the `lima-macos-init`
   LaunchDaemon as usual, but:
   - it does **not** write `.AppleSetupDone` and `Library/User Template/.skipbuddy`,
     because Setup Assistant is what reads the provisioning options;
   - it adds B2's `lima-guestagent-full-disk-access` TCC entry. Without Full Disk Access,
     macOS refuses both the rename of the home and `dscl -create … NFSHomeDirectory`
     (`ODErrorRecordPermissionError`, even with `-u`/`-P`).
4. **Build cidata** (hostagent, before every start). While `vz-guest-password` exists
   (always, for these instances), `GenerateISO9660` adds `guest-provisioning-password`,
   containing the password. Its presence tells fakecloudinit that Setup Assistant
   creates the user, so it adopts the account instead of running `sysadminctl`. It
   is a separate file so `user-data` stays strictly cloud-config. If
   `osOpts.Darwin.autoLogin` is set, A1's empty `auto-login` file is there too.
5. **Start the VM** (`startVM`). `guestProvisioningStartOptions` builds
   `vz.NewMacGuestProvisioningOptions(fullName, user.name, password,
   WithGuestAutomaticLogin(false), WithGuestRemoteLogin(false))`. `fullName` is
   `user.comment`, or `user.name` when that is empty, since Setup Assistant needs one.
   - Auto-login is off because a logged-in session would hold the old home open.
   - Remote Login is off because fakecloudinit's `enableSSHD` always turns sshd on.

   The options are passed as `machine.Start(vz.WithGuestProvisioningOptions(opts))`.
   Once `Start` returns, the marker is deleted, because macOS only evaluates the options
   on the first boot after installation. The password file stays.

## Guest side: first boot

Two things start in parallel on the first boot: Setup Assistant at the login window, and
Lima's LaunchDaemon.

**Setup Assistant (Apple, faceless).** It reads the provisioning options. It creates the
admin account `<user.name>` (uid 501, full name from the options) and its home
`/Users/<user.name>`, with a SecureToken (as `sysadminctl` gives the first account too). It
writes `/var/db/.AppleSetupDone`, then stops at the login window. It leaves a background
launchd session `user/501` running (`cfprefsd`, `secd`, `lsd`, `trustd`, `distnoted`,
`pkd`, ...), whose processes hold the home open.

**fakecloudinit** (`Run`): `enableSSHD`, meta-data, then user-data in this order:
timezone, **users, then mounts**, write_files, resolv.conf, then boot scripts. Users come
before mounts because the default host-home mount is a symlink at `/Users/<user>`. If it
came first, it would take that path a few seconds before Setup Assistant made the home
there. That happened in the r11 test, and the move then renamed the symlink.

For the Lima user, `createUser` sees `guest-provisioning-password` on cidata. If
`user.home/.ssh/authorized_keys` exists, the account was set up on an earlier boot and it
is skipped. (Not "the home exists": Setup Assistant creates the home itself, so with
`user.home` = `/Users/<user>` that would skip before Lima's files are in.) Otherwise it
calls `adoptProvisionedUser`:

1. **Wait for the account**: `lookupDSUser` (`dscl . -read /Users/<name> UniqueID
   NFSHomeDirectory`, parsed by the tested `parseDSCLRead`, `UniqueID` required) every
   2 s, for up to 10 min. A UID different from `user.uid` is logged as a warning.
2. **Move the home** (`moveProvisionedHome`), when the cleaned home path differs from
   `user.home`:
   1. Wait for `/var/db/.AppleSetupDone` (up to 10 min), so Setup Assistant has finished.
   2. `launchctl bootout user/<uid>` ends Setup Assistant's background session. A failure
      is logged and the next check decides.
   3. Wait until `pgrep -U <uid>` finds nothing (exit 1), for up to 1 min.
   4. Refuse if Apple's home is not a real directory (`Lstat`), or if `user.home`
      already exists.
   5. `rename(/Users/<name>, user.home)`. It is the same APFS volume, so the move is
      atomic and keeps ownership, ACLs and xattrs. This needs Full Disk Access (step 3
      on the host).
   6. `dscl . -create /Users/<name> NFSHomeDirectory <user.home>`. This also needs Full
      Disk Access. If it fails, the directory is renamed back.
   7. `dscacheutil -flushcache`, then read the record again and require the new path.
3. **If the move fails**, it logs a warning, keeps Apple's home and symlinks `user.home`
   to it, so boot scripts that use `user.home` still work. With the default host-home
   mount, Apple's home is then hidden under the mount. With the FDA grant this hasn't
   happened.
4. Create the home if it's missing, run `suppressFirstLoginScreens` if
   `suppressFirstLoginSetup` is set, and `chmod 700` the home (as `sysadminctl` does).
5. `installUserFiles`: `~/password` (mode 0400), `~/.ssh/authorized_keys`, and sudoers.
6. **Auto-login** (A1's `maybeEnableAutoLogin`), if `auto-login` is on cidata. It writes
   `/etc/kcpassword` (the password XORed with the fixed loginwindow key and padded to a
   multiple of 12 bytes, mode 0600), then sets
   `/Library/Preferences/com.apple.loginwindow autoLoginUser`. loginwindow only reads
   these at boot, so auto-login starts from the **second** boot. The classic path calls
   the same function after `sysadminctl`.
7. Mounts, then `runBootScripts`; Lima's readiness checks over SSH pass. The first boot
   ends READY at the login window, with nobody logged in.

Seen on far-star 2026-11-17 (macOS 27.2 host, 27.2.1 guest, stock config with the host
home mounted): the home moved 7 s after the agent started, and the instance was READY
about 3 minutes after `limactl start`, including the install.

## Guest side: later boots

- There is no marker, so there are no provisioning options.
  `guest-provisioning-password` is still on cidata.
- `createUser` finds `user.home/.ssh/authorized_keys` and skips the user.
- If the first boot was cut off after Setup Assistant created the account but before
  `authorized_keys` was written, the account isn't skipped: the next boot finds it right
  away and finishes the move and setup.
- loginwindow reads `autoLoginUser` and `kcpassword` and logs the user in.
- Provision scripts that need a GUI user session (for example `defaults write` in the
  user's domain) only work from this boot. On the first boot they fail with
  `Could not write domain`; lima_mac's user script hits this harmlessly.

## Flow diagram

```mermaid
sequenceDiagram
    participant L as limactl / hostagent
    participant VZ as Virtualization.framework
    participant SA as Setup Assistant (guest)
    participant FC as fakecloudinit (guest, root)
    participant LW as loginwindow (guest)

    L->>L: install IPSW, write vz-guest-os-version
    L->>L: host and guest >= 27? write vz-guest-password, empty vz-guest-provisioning
    L->>L: macos.Patch(GuestProvisioning): no skip markers, add guest agent FDA
    L->>L: cidata: guest-provisioning-password (+ auto-login if osOpts.Darwin.autoLogin)
    L->>VZ: Start(WithGuestProvisioningOptions(fullName, name, pw, auto/remote login off))
    L->>L: remove vz-guest-provisioning
    VZ->>SA: first boot reads provisioning options
    SA->>SA: create user, /Users/name, SecureToken, .AppleSetupDone
    SA-->>LW: login window; background user/uid session left running
    FC->>FC: enable sshd; wait for dscl record
    FC->>FC: wait for .AppleSetupDone
    FC->>FC: launchctl bootout user/uid, wait until pgrep -U uid is empty
    FC->>FC: rename /Users/name to user.home, dscl NFSHomeDirectory, verify
    FC->>FC: chmod 700, ~/password, authorized_keys, sudoers
    FC->>FC: /etc/kcpassword + autoLoginUser (A1)
    FC->>FC: mounts (host home symlink at /Users/name), boot scripts, READY
    Note over L,LW: second boot
    L->>VZ: Start() with no provisioning options
    FC->>FC: user.home exists, skip user
    LW->>LW: auto-login with kcpassword
```

## Why it is built this way (things that didn't work)

| Tried | Result | Now |
|---|---|---|
| Lima writes `.AppleSetupDone`/`.skipbuddy` (as for older guests) | Setup Assistant never runs, so the options are ignored | Not written when provisioning (r4; since r10 by `PatchOptions`, not a second mount) |
| Name the account `<user>.guest` (r5/r6) | Works; Apple puts the home at `/Users/<name>` for any name. But it changes Lima's default username | Reverted in r8 |
| `osOpts.Darwin.guestProvisioning` config (r1–r9) | #5516 is a refactoring issue; `enablesRemoteLogin` was a no-op, and the password knob differed from every other guest | Automatic, no config (r10) |
| Apple's auto-login with a moved home | The user is logged in with the old home open | Apple's off; A1 turns Lima's on after the move |
| Wait for no processes as the uid (r8) | Setup Assistant's background `user/501` session never exits | `launchctl bootout user/<uid>` first (r9) |
| Move the home without Full Disk Access (r9/r10 on a stock config) | `rename` EPERM and `dscl` `ODErrorRecordPermissionError`; r9 only passed because lima_mac's yaml sets B2's FDA preset | P1 adds that preset itself (r11) |
| Mounts before users (upstream order) | The host-home symlink took `/Users/<user>` before Setup Assistant; the move renamed the symlink | Users first; the move refuses a non-directory (r11) |
| `killall loginwindow` after writing kcpassword | Login window comes back, no auto-login on 27.2 | Auto-login from the second boot |
| `sysadminctl -autologin set` from the agent or SSH | Needs the Security Agent; fails without reporting an error | A1 writes kcpassword itself |
| Root `launchctl bootout gui/501` | Hung | Not used |

## Verification checklist (fresh macOS 27 instance)

Test on a **stock** config as well as lima_mac's: `mounts: [{location: "~"}]`, no
`tccPermissions`, no provision scripts. lima_mac's yaml hid both r11 bugs. After the
second boot, run in the guest:

```bash
id; echo $HOME                                    # uid 501 <user>, /Users/<user>.guest
dscl . -read /Users/$USER NFSHomeDirectory RealName
ls -ld /Users/$USER                               # symlink to /Volumes/My Shared Files/... (host home)
stat -f %Su /dev/console                          # <user>, if autoLogin is set
sysadminctl -secureTokenStatus $USER 2>&1         # ENABLED
ls -l ~/password ~/.ssh/authorized_keys
```

On the host, `~/.lima/<instance>/serialv.log` from the first boot should show
`Moving home of user ...`, `Adopted user ...` and, with `autoLogin`,
`Enabled automatic login ... from the next boot`, with no `Keeping home` warning.

To see the guest's screen: `limactl screenshot <instance> -o shot.png`. It returns "no
data" when the limactl app is hidden (Cmd-H). Unhide it first:

```bash
osascript -e 'tell application "System Events" to set visible of (first process whose unix id is '"$(cat ~/.lima/<instance>/ha.pid)"') to true'
```

## Open points for upstream (#5516)

- **P1 depends on B2 upstream.** The FDA grant uses B2's TCC writer and preset, so B2 has
  to be submitted and merged first. The PR order is Z1 → B2 → A1 → P1.
- **Lima grants its guest agent Full Disk Access on 27+ guests.** The agent already runs
  as root, but expect a reviewer to ask about it. The docs say so.
- **Users are now created before mounts on every macOS guest.** Nothing depends on the
  old order, and a mount point inside the guest home needs the home to exist first.
- **An interrupted first boot (r14).** macOS guests run no guest agent daemon, so the host
  can't tell when the first boot finished, and the marker is removed once `Start` returns.
  The password stays on cidata, so if the first boot dies after Setup Assistant created
  the account, the next boot adopts it and moves the home. If it dies before Setup
  Assistant ran, the next start has no provisioning options and there is no
  `.AppleSetupDone`, so Setup Assistant would run interactively; the docs say to recreate
  the instance. Neither case is tested on a guest yet.
- **The password is stored in plain text** in the instance directory (`0600`) and on
  cidata on every boot, as for the classic path's `~/password`.
- **Changing the password breaks auto-login** (confirmed 2026-11-17): kcpassword keeps
  the old one. The A1 docs say so.
- **The `kcpassword` encoding is reverse engineered.** The 11-byte key and 12-byte padding
  are what macOS has used for years. They are confirmed on 27.2 and match lima_mac's
  encoder.
- Still blocked on a tagged Code-Hex/vz v4 release and lima moving to it (Z1).
