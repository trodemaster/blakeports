# lima-devl B2: the sshd Full Disk Access preset had a broken code requirement

**Date:** 2026-11-26
**Port:** `sysutils/lima-devl`, patch B2 (`patch-06-b2-tcc.diff`, lima-devl branch `upstream-pr/b2-tcc`)
**Status:** fixed in B2 r15 and verified on a rebuilt macOS 27.2.1 guest: SSH sessions get Full Disk Access.

## Summary

B2 lets Lima write TCC (privacy permission) entries into a macOS guest's
system TCC database while it patches the disk, before the first boot. Its
`sshd-full-disk-access` preset was meant to do what System Settings' "Allow
full disk access for remote users" does. It never worked: SSH sessions on the
macOS 26 and 27 runner VMs got `Operation not permitted` on protected
folders.

The entry was written and kept, but its code requirement (the `csreq`
column) was corrupt. The hex literal in the source had one extra zero byte,
so the requirement decoded as `identifier "com.apple.sshd-keygen-wrapper"
and never`, which no program can satisfy. tccd checks a client against its
stored requirement, so the entry never matched.

## Evidence

Guest: `macos-27` (macOS 27.2.1), rebuilt 2026-11-26 with a limactl built
from the port's patches (B2 r14). The VM was stopped, its disk attached
read-only on the host (`diskutil image attach --readOnly --noMount`), the
Data volume mounted read-only, and a copy of
`/Library/Application Support/com.apple.TCC/TCC.db` read with `sqlite3`.

| service | client | auth_value | csreq bytes | written |
|---|---|---|---|---|
| `kTCCServiceSystemPolicyAllFiles` | `/usr/libexec/sshd-keygen-wrapper` | 2 | 61 | disk patch |
| `kTCCServiceAccessibility` | `com.apple.Terminal` | 2 | 48 | disk patch |
| `kTCCServicePostEvent` | `com.apple.Terminal` | 2 | 48 | disk patch |
| `kTCCServiceSystemPolicyAllFiles` | `/Volumes/cidata/lima-guestagent` | 2 | 40 (see below) | disk patch |

Decoding the stored requirements with `csreq -r- -t < blob`, compared
with `codesign -dr - <binary>`:

| client | stored requirement | real designated requirement |
|---|---|---|
| sshd-keygen-wrapper | `identifier "com.apple.sshd-keygen-wrapper" and never` | `identifier "com.apple.sshd-keygen-wrapper" and anchor apple` |
| Terminal | `identifier "com.apple.Terminal" and anchor apple` | same |

The stored sshd blob next to the one `csreq -b` compiles:

```
stored  (61): ... 6170 7065 7200 0000 0000 0000 03
correct (60): ... 6170 7065 7200 0000 0000 0003
```

The identifier is 29 bytes, so it needs 3 pad bytes before the next opcode.
The literal had 4, which turned the `anchor apple` opcode (`00000003`) into
`00000000` (`never`) followed by a stray `03`. The blob's own length field
still said 60.

What each entry actually did on the guest:

| entry | effect |
|---|---|
| guest agent Full Disk Access (written with NULL csreq) | works: P1's home-folder move needs it and succeeded |
| sshd Full Disk Access (corrupt csreq) | no effect |
| Terminal Accessibility (correct csreq) | no effect: a command run in Terminal reports `AXIsProcessTrusted` false |

The Terminal entry shows that some entries are ignored even with a correct
requirement, as was already known. The sshd entry was a separate,
self-inflicted failure.

## Fix

lima-devl commit "fix(tcc): correct the sshd-keygen-wrapper csreq blob" on
`upstream-pr/b2-tcc` (also in `macports/p1-port`):

- Replaced the hex with the 60-byte blob from
  `csreq -r='identifier "com.apple.sshd-keygen-wrapper" and anchor apple' -b`.
  Both preset blobs now match `csreq` output byte for byte.
- Changed the source comment, which said the blobs were captured from a
  macOS 15 VM, to give the `csreq` command that generates them.
- Added `TestPresetCSReqs` (`pkg/guestpatch/macos/tcc_darwin_test.go`),
  which decodes each preset blob, checks the length field, padding and
  opcodes, and checks the identifier. It fails on the old hex
  (`60 (int) != 61 (int): length field must match blob length`).

Port: `patch-06` regenerated (B2 r15). `patch-12` changed only in test-file
context (P1 r13).

Follow-up the same day: B2 r16 dropped the Terminal preset (its rows are kept
but ignored), so only the sshd blob remains; r17 made B2 presets only (no
custom entries), with unknown presets rejected in vz `Configure`. B2 is now one
commit, "vz: write TCC entries into macOS guests before the first boot".

## Verification

`make rebuild-27` (lima_mac) with a limactl built from the port's patches
at B2 r15 / P1 r13 (`2.3.0-dev.20261126b`), 2026-11-26 18:05–18:16. Guest
macOS 27.2.1. The guest came up at the desktop with no permission prompts,
and the macOS_27 runner re-registered.

From an SSH session (`limactl shell`), with no other change:

| check | B2 r14 | B2 r15 |
|---|---|---|
| `ls "/Library/Application Support/com.apple.TCC/"` | Operation not permitted | `REG.db  TCC.db` |
| `ls ~/Library/Mail` | Operation not permitted | `V10` |
| `sqlite3` read of the system TCC.db | not possible | works |
| stored sshd requirement | `... and never` (61 bytes) | `... and anchor apple` (60 bytes) |

The sshd preset now does what "Allow full disk access for remote users"
does, with SIP on and no prompt.

**Guest agent requirement.** Lima writes the guest agent's entry with a
NULL csreq. On the rebuilt guest the row holds a 40-byte requirement,
`cdhash H"7696dc32..."`, which is the agent binary's own designated
requirement (`codesign -dr -`; the binary is ad-hoc signed). So tccd
accepted the NULL row and recorded the binary's cdhash on first use. A
later Lima version ships a different agent binary with a different cdhash.
Not tested: whether the entry still applies to that binary. P1 needs Full
Disk Access only on the first boot, for the home move.

## Research notes

These are from Google AI Mode answers (2026-11-26), checked against primary
sources where noted. AI Mode summaries are leads, not evidence.

- **tccd validates `csreq`.** AI Mode said a row whose code requirement is
  NULL or doesn't match the binary is ignored. The mismatch half is
  confirmed above. The NULL half is not: the guest agent's row, written
  with a NULL csreq, works.
- **The supported way** to grant SSH Full Disk Access without the GUI is an
  MDM-delivered PPPC (Privacy Preferences Policy Control) profile, with a
  `SystemPolicyAllFiles` entry for `/usr/libexec/sshd-keygen-wrapper`,
  identifier type `path`, and code requirement
  `identifier "com.apple.sshd-keygen-wrapper" and anchor apple` (Der
  Flounder, below). `profiles` can't install PPPC payloads without MDM.
- **`MDMOverrides.plist`** is generated from installed profiles. AI Mode
  said a hand-written one is reconciled away at boot. Not tested.
- **`tccutil`** only resets entries; it can't grant them.
- **Cirrus Labs' Tart templates.** AI Mode said they turn on "Allow full
  disk access for remote users" by typing keystrokes. The templates (checked
  at `d6a3774`, 2026-10-31) don't do that. They type keystrokes to turn on
  Remote Login and Screen Sharing in System Settings, disable SIP in
  Recovery (`disable-sip.pkr.hcl`), and then run
  `scripts/update-tcc-database.sh` in the booted guest. That script uses
  `sqlite3` to insert Accessibility, ScreenCapture, PostEvent and
  AppleEvents rows for `sshd-keygen-wrapper`, `osascript`, Python and
  `tart-guest-agent`, all with a NULL csreq, into both the system and the
  user database. It writes no Full Disk Access row for sshd. Not an option
  here: the runner guests keep SIP on, so TCC entries come only from
  Lima's pre-boot disk patch.
- **macOS 27 moved the per-user TCC database** into a per-user
  ProtectedSystem container
  (`/private/var/containers/Data/ProtectedSystem/*/Data/Library/Application Support/com.apple.TCC/TCC.db`).
  Cirrus' script finds it from tccd's open files. This is consistent with
  Lima's disk patcher being unable to write user-level entries.

## References

- Lima issue: [lima-vm/lima#4754](https://github.com/lima-vm/lima/issues/4754) (macOS guest: grant ssh sessions FullDiskAccess)
- Der Flounder, [Enabling full disk access for SSH on macOS Big Sur using a management profile](https://derflounder.wordpress.com/2021/09/29/enabling-full-disk-access-for-ssh-on-macos-big-sur-using-a-management-profile/) (2021-09-29)
- Cirrus Labs, [macos-image-templates](https://github.com/cirruslabs/macos-image-templates): `templates/vanilla-*.pkr.hcl`, `templates/disable-sip.pkr.hcl`, `scripts/update-tcc-database.sh`
- Cirrus Labs, [packer-plugin-tart#79](https://github.com/cirruslabs/packer-plugin-tart/issues/79) (keystroke-driven Remote Login setup)
- Tools: `csreq(1)`, `codesign -dr -`, `sqlite3`
- Related lima-devl docs: `sysutils/lima-devl/TODO.md`, `sysutils/lima-devl/P1-FLOW.md`
