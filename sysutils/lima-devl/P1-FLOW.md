# P1 flow: macOS 27 guest provisioning with a moved home

How `osOpts.darwin.guestProvisioning` creates the macOS guest user, as of P1 r9
(lima branch `macports/p1-on-z1`, commits `5f77b1ec` and `ffb7615c` on top of
`f0387c56`; port `patch-12-p1-guest-provisioning.diff`, `p1_rev 9`). The test
history and results are in [TODO.md](TODO.md) (2026-11-07 and 2026-11-13 P1 notes).
The Apple-side mechanism is reverse engineered in
`~/Developer/lima_mac/docs/macos27-guest-provisioning.md`.

## The problem in one paragraph

On macOS 27, `VZMacGuestProvisioningOptions` (username, full name, password,
auto-login, Remote Login) is handed to the guest on its first boot, and the faceless
Setup Assistant creates the account from it. That gives a proper account: SecureToken,
FileVault user, login keychain, `.AppleSetupDone`. But Apple always puts the home at
`/Users/<username>`, and the API has no home option. Lima's macOS default home is
`/Users/<user>.guest`, so it can't collide with the host's home directory if that is
mounted into the guest. r5/r6 solved this by naming the account `<user>.guest`; r8/r9
instead keep the account name `<user>` and **move the home** to `user.home` on the first
boot, before anyone logs in.

## Where each step runs

| Step | Process | Code |
|---|---|---|
| Install, version check, marker | `limactl` (create/first start) | `pkg/driver/vz/vz_driver_darwin.go` `CreateDisk`, `createDiskMacOSGuest`, `prepareGuestProvisioning` |
| Undo Lima's Setup Assistant skip | `limactl` | `pkg/guestpatch/macos/provisioning_darwin.go` `RemoveSetupAssistantMarkers` |
| cidata files | hostagent | `pkg/cidata/cidata.go` `templateArgs`, `GenerateISO9660` |
| Start options | hostagent | `pkg/driver/vz/vm_darwin_arm64.go` `guestProvisioningStartOptions`; `vm_darwin.go` `startVM` |
| "Does the home move?" | both sides of the host | `pkg/limayaml/guestprovisioning.go` `GuestProvisioningMovesHome` |
| Account creation | guest, Setup Assistant (Apple) | — |
| Adopt, move, auto-login | guest, LaunchDaemon `io.lima-vm.lima-macos-init` → `lima-guestagent fake-cloud-init` (root) | `pkg/guestagent/fakecloudinit/fakecloudinit_darwin.go` `createUser`, `adoptProvisionedUser`, `moveProvisionedHome`, `enableAutoLogin` |

The fakecloudinit log goes to the guest's `/dev/tty.virtio`, which is the host's
`~/.lima/<instance>/serialv.log`. Read it there; reading `/dev/tty.virtio` inside the
guest hangs.

## Host side: create and first start

1. **Install** (`createDiskMacOSGuest`). macOS is installed from the IPSW, and the
   restore image's version is written to `vz-guest-os-version` (merged upstream as
   PR #5528).
2. **Gate** (`prepareGuestProvisioning`). If `guestProvisioning` is set, it checks the
   host with `osutil.ProductVersion` and the guest with `store.ReadGuestOSVersion`.
   `guestProvisioningSkipReason` returns a reason when:
   - the guest version is unknown or can't be parsed;
   - the guest is older than 27 (older guests ignore the options without an error, so
     this has to be checked up front);
   - the host is older than 27.

   When there's a reason, it logs `Ignoring osOpts.Darwin.guestProvisioning: <reason>`
   and the instance takes the classic `sysadminctl` path. Otherwise it writes an empty
   `vz-guest-provisioning` marker in the instance directory. **Every later step keys off
   this marker.**
3. **Patch the disk** (`CreateDisk`). `macos.Patch` runs as usual. It installs the
   `lima-macos-init` LaunchDaemon and writes `.AppleSetupDone` and
   `Library/User Template/.skipbuddy` to skip Setup Assistant. If the marker exists,
   `RemoveSetupAssistantMarkers` mounts the data volume again and deletes those two
   files: Setup Assistant must run, because it is what reads the provisioning options.
4. **Build cidata** (hostagent, before the VM starts). While the marker exists,
   `GenerateISO9660` adds:
   - `guest-provisioning-password`, containing the password. Its presence tells
     fakecloudinit that Setup Assistant creates the user on this boot. It is a separate
     file so `user-data` stays strictly cloud-config.
   - `guest-provisioning-autologin`, an empty file, only when `logsInAutomatically` is set
     **and** the home moves. It tells the guest to turn auto-login on itself.
5. **Start the VM** (`startVM`). `guestProvisioningStartOptions` builds
   `vz.NewMacGuestProvisioningOptions(user.comment, user.name, password,
   WithGuestAutomaticLogin(autoLogin), WithGuestRemoteLogin(enablesRemoteLogin))`, where
   `autoLogin = logsInAutomatically && !GuestProvisioningMovesHome`. It is passed as
   `machine.Start(vz.WithGuestProvisioningOptions(opts))`. Once `Start` returns, the
   marker is deleted, because macOS only evaluates the options on the first boot after
   installation.

`GuestProvisioningMovesHome` is `user.home != "/Users/" + user.name`. With Lima's
defaults (`user.name` = host user, `user.home` = `/Users/{{.User}}.guest` from
`pkg/osutil/user.go`) it is always
true. Setting `user.home: /Users/<user.name>` turns the move off; then Apple's own
auto-login is used and nothing below about moving applies.

## Guest side: first boot

Two things start in parallel on the first boot: Setup Assistant at the login window, and
Lima's LaunchDaemon.

**Setup Assistant (Apple, faceless).** It reads the provisioning options and creates the
admin account `<user.name>` (uid 501, full name `user.comment`), its home
`/Users/<user.name>`, SecureToken (which makes it a FileVault-enabled user) and login
keychain. It turns on
Remote Login if asked and writes `/var/db/.AppleSetupDone`. Because Lima passed
auto-login **off**, it stops at the login window. It still leaves a background launchd
session `user/501` running (`cfprefsd`, `secd`, `lsd`, `trustd`, `distnoted`, `pkd`,
`containermanagerd`, `mdbulkimport`, ...). Those processes hold the old home open.

**fakecloudinit** (`Run`): `enableSSHD`, then `processMetaData`, `processUserData` and
`runBootScripts`. For the Lima user, `createUser` sees `guest-provisioning-password` on
cidata and calls `adoptProvisionedUser`:

1. **Wait for the account**: poll `dscl . -read /Users/<name> UniqueID NFSHomeDirectory`
   every 2 s, for up to 10 min.
2. **Move the home** (`moveProvisionedHome`), when the home Apple chose differs from
   `user.home`:
   1. Wait for `/var/db/.AppleSetupDone` (up to 10 min), so Setup Assistant has finished
      with the account.
   2. `launchctl bootout user/<uid>` ends Setup Assistant's background user session. A
      failure is logged and the next check decides.
   3. Wait until `pgrep -U <uid>` finds nothing (exit 1), for up to 1 min.
   4. Refuse if `user.home` already exists (`Lstat`, so a symlink counts).
   5. `rename(/Users/<name>, user.home)`. It is the same APFS volume, so the move is
      atomic and keeps ownership, ACLs and xattrs.
   6. `dscl . -create /Users/<name> NFSHomeDirectory <user.home>`. If this fails, the
      directory is renamed back.
   7. `dscacheutil -flushcache`, then read the record again and require the new path.
3. **If the move fails**, it logs a warning, keeps Apple's home and symlinks `user.home`
   to it. That keeps Lima's boot scripts working, since they use `user.home`. Without the
   symlink, r8's fallback broke `00-lima.boot.sh`
   (`cp: /Users/<user>.guest/.lima-user-script: No such file`).
4. `suppressFirstLoginScreens`, if `suppressFirstLoginSetup` is also set.
5. `installUserFiles`: `~/password` (mode 0400), `~/.ssh/authorized_keys`, and sudoers.
6. **Auto-login** (`enableAutoLogin`), if `guest-provisioning-autologin` is on cidata:
   write `/etc/kcpassword` (the password XORed with the fixed loginwindow key and padded
   to a multiple of 12 bytes, mode 0600), then
   `defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser <name>`.
   loginwindow only reads these at boot, so auto-login starts from the **second** boot.
7. `runBootScripts`, then Lima's readiness checks over SSH pass. The first boot ends
   READY at the login window, with nobody logged in.

Seen on far-star 2026-11-13 (macOS 27.2 host and guest, `make rebuild-27`): the home
moved 5 s after the account appeared, and the instance was READY about 20 s later.

## Guest side: later boots

- There is no marker, so no provisioning options and no `guest-provisioning-*` files on
  cidata.
- `createUser` finds `user.home` and skips the user. There is also a `dscl` lookup
  fallback, so it never runs `sysadminctl` for an account Setup Assistant made.
- loginwindow reads `autoLoginUser` and `kcpassword` and logs the user in. The keychain
  unlocks with the same password, and there are no first-login screens.
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
    L->>L: prepareGuestProvisioning: host and guest >= 27? write vz-guest-provisioning
    L->>L: macos.Patch, then RemoveSetupAssistantMarkers
    L->>L: cidata: guest-provisioning-password (+ -autologin if home moves)
    L->>VZ: Start(WithGuestProvisioningOptions(name, fullName, pw, autoLogin=false if home moves))
    L->>L: remove vz-guest-provisioning
    VZ->>SA: first boot reads provisioning options
    SA->>SA: create user, /Users/name, SecureToken, keychain, .AppleSetupDone
    SA-->>LW: login window (no auto-login); background user/uid session left running
    FC->>FC: wait for dscl record
    FC->>FC: wait for .AppleSetupDone
    FC->>FC: launchctl bootout user/uid, wait until pgrep -U uid is empty
    FC->>FC: mv /Users/name to user.home, dscl NFSHomeDirectory, flush cache, verify
    FC->>FC: authorized_keys, ~/password, sudoers
    FC->>FC: /etc/kcpassword + autoLoginUser
    FC->>FC: boot scripts, then READY (first boot stays at the login window)
    Note over L,LW: second boot
    L->>VZ: Start() with no provisioning options
    FC->>FC: user.home exists, skip user
    LW->>LW: auto-login with kcpassword
```

## Configurations

| `user.home` | `logsInAutomatically` | Apple auto-login | Home | Auto-login |
|---|---|---|---|---|
| default `/Users/<user>.guest` | true | off | moved on boot 1 | Lima's kcpassword, from boot 2 |
| default `/Users/<user>.guest` | false | off | moved on boot 1 | none |
| `/Users/<user.name>` | true | on | Apple's, unchanged | Apple's, from boot 1 |
| `/Users/<user.name>` | false | off | Apple's, unchanged | none |
| any, guest or host < 27 | — | — | classic `sysadminctl` user at `user.home` | Lima's usual path |

## Why it is built this way (things that didn't work)

| Tried | Result | Now |
|---|---|---|
| Lima writes `.AppleSetupDone`/`.skipbuddy` (as for older guests) | Setup Assistant never runs, so the options are ignored | Markers removed when provisioning (r4) |
| Name the account `<user>.guest` (r5/r6) | Works; Apple puts the home at `/Users/<name>` for any name. But it changes Lima's default username, which upstream would question | Reverted in r8 |
| Leave Apple's auto-login on and move the home | The user is logged in with the old home open | Apple auto-login off while the home moves |
| Wait for no processes as the uid (r8) | Setup Assistant's background `user/501` session never exits; the wait timed out and the move was skipped | `launchctl bootout user/<uid>` first (r9) |
| Fall back to Apple's home with no link (r8) | `00-lima.boot.sh` fails writing to `user.home` | Symlink `user.home` → Apple's home (r9) |
| `killall loginwindow` after writing kcpassword | Login window comes back, no auto-login on 27.2 (the kcpassword itself was correct) | Auto-login from the second boot |
| Root `launchctl bootout gui/501` | Hung | Not used |

## Verification checklist (fresh macOS 27 instance)

After the second boot, run in the guest:

```bash
id; echo $HOME                                    # uid 501 <user>, /Users/<user>.guest
dscl . -read /Users/$USER NFSHomeDirectory RealName
ls -ld /Users/$USER 2>&1                          # should not exist
stat -f %Su /dev/console                          # <user> (auto-logged in)
sysadminctl -secureTokenStatus $USER 2>&1         # ENABLED
sudo fdesetup list                                # <user>
security unlock-keychain -p "$(cat ~/password)" ~/Library/Keychains/login.keychain-db
grep -rl "/Users/$USER/" ~/Library/Preferences 2>/dev/null   # nothing
sudo -n true && echo sudo-ok
```

On the host, `~/.lima/<instance>/serialv.log` should show `Moving home of user ...`,
`Adopted user ...` and `Enabled automatic login ... from the next boot`.

To see the guest's screen: `limactl screenshot <instance> -o shot.png`. It returns "no
data" when the limactl app is hidden (Cmd-H). Unhide it first:

```bash
osascript -e 'tell application "System Events" to set visible of (first process whose unix id is '"$(cat ~/.lima/<instance>/ha.pid)"') to true'
```

## Open points for upstream (#5516)

- **First boot stops at the login window when the home moves.** Auto-login only starts on
  the second boot. Workloads that need a GUI session on the first boot would need a
  reboot (or a working way to make loginwindow log in) in fakecloudinit.
- **The marker is removed once `Start` returns, not once provisioning succeeds.** If the
  first boot dies before Setup Assistant runs, provisioning doesn't retry. The next boot
  has no password file, and `createUser` falls back to `sysadminctl`, but `.AppleSetupDone`
  is gone, so Setup Assistant would run interactively.
- **The password is stored in plain text** in `lima.yaml` and on cidata, as for the classic
  path's `~/password`.
- **The `kcpassword` encoding is reverse engineered.** The 11-byte key and 12-byte padding
  are what macOS has used for years, and were confirmed on 27.2.
- **`GuestProvisioningMovesHome` compares paths as strings.** `/Users/foo/` with a trailing
  slash would count as a move.
- Whether the knob is needed at all, or whether provisioning should be automatic when host
  and guest are 27+ (with at most an optional password).
- Still blocked on a tagged Code-Hex/vz v4 release and lima moving to it (Z1).
