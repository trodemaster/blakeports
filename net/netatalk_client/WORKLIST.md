# netatalk_client on macOS 27: worklist

One entry per atomic change. Nothing here is posted upstream: the user
approves each text first, and no PR goes in until upstream welcomes one.
Issues may link to the blakeports patch. netatalk-client only, never macFUSE.

Checked against upstream `main` at
[de759669](https://github.com/Netatalk/netatalk-client/commit/de759669de8de71a9e5c89c1612201fdc6ed6e6a)
on 2026-11-23. Search for duplicates again before filing.

Evidence levels: **source** = read in the code; **CI** = shown on the macOS_27
runner; **live** = shown on a FSKit mount. "Live (Oct)" means it was shown
with the 1.0.0-era build in October (see CLAUDE.md) and not repeated since.

## Remaining changes

| # | Change | Patch | Upstream issue | Evidence |
|---|---|---|---|---|
| 1 | Mount without `/dev/macfuse0`, through FSKit | [fskit](files/patch-fuse-macos-fskit.diff) | part of [#386](https://github.com/Netatalk/netatalk-client/issues/386) | source, live |
| 2 | Unmount on macOS | [unmount](files/patch-fuse-macos-unmount.diff) | part of #386 | source, live (`umount(8)` not tested yet) |
| 3 | `/Volumes` mount points macFUSE creates | [volumes](files/patch-fuse-macos-volumes-mountpoint.diff) | part of #386 | source, live |
| 4 | `afpc fs exit` leaves the volume mounted, no logout | none (dropped, see below) | not filed | source, live (fails) |
| 5 | SIGTERM to a mount daemon: no logout | none | not filed | live (fails) |
| 6 | A dead daemon's mount is not released | none | not filed | live (fails) |
| 7 | Manager sends a daemon two exit commands and closes without reading the reply | none (dropped, see below) | not filed | source, live (Oct); "Broken pipe" not seen now |
| 8 | `afpgetstatus host:port` fails | [getstatus](files/patch-getstatus-host-port.diff) | not filed | source, CI |

### 1. Mount without `/dev/macfuse0`

`check_mountpoint()` in `fuse/commands.c` refuses every macOS mount unless
`/dev/macfuse0` exists. Only the kernel extension creates it; FSKit has no
device. Nothing passes `-o backend=fskit`, and the kernel backend is still
macFUSE's default. Test group: `backend`.

### 2. Unmount on macOS

`fuse_unmount_volume()` in `fuse/daemon.c` is compiled out on macOS and
returns -1, so `afpc fs unmount` fails. `afpc fs mount --foreground` also
gives up after one attempt there (`fuse/client.c`). Groups: `unmount`,
`busy`, `foreground`.

### 3. `/Volumes` mount points

FSKit mounts must be under `/Volumes`, which is root's. macFUSE's helper
creates a missing directory there and removes it on unmount, but
`check_mountpoint()` requires it to exist. Group: `mountpoint`.

### 4 to 7. Shutdown

Live, CI run 45334492759 (macOS 27.2.1, macFUSE 5.5.0): after `afpc fs exit`
the daemon ends, but the volume is still mounted 12 s later and the server
logs no logout; the same with two volumes. After SIGTERM the server logs no
logout. After `kill -9` the manager does not release the mount in 15 s.

Likely causes, from source and not proven: on exit the main loop serves no
descriptor while the ending thread unmounts (`lib/loop.c`), as in October;
and `mount_is_dead()` accepts only ENOTCONN. The next run prints the errno.
`mounted` took an unanswered mount(8) for "unmounted" in that run, so its
other exit and dead-daemon passes need repeating.

Before that run:

At de759669 `process_exit()` still only logs, and `cleanup_all_children()`
still sends exit to every globbed socket and again to each tracked child.
PR #410 changed what surrounds them (one unmount alone proceeds, daemons keep
the pid the manager waits for, the manager waits 10 s), so the October
symptoms (no FPLogout, volume left mounted, "Broken pipe") may be gone. Our
two patches are therefore dropped until the `exit` group shows a failure;
the last versions are in git history before this snapshot.

### 8. `afpgetstatus host:port`

Usage says `getstatus [afp_url|ipaddress[:port]]`, but `cmdline/getstatus.c`
brackets every address that has a colon as IPv6, so `127.0.0.1:10548` ends in
`getaddrinfo: nodename nor servname provided`. The `afp://` form works.
Not macOS-specific. Shown by upstream's own `test_afpgetstatus.t` on a
non-default port: 12 of 16 fail.

## Fixed upstream since the last snapshot (patches dropped)

- Truncating through an open fork: PR #394.
- FUSE thread writing into a returned stack frame: PR #410 (row 30).

Port-only, not an upstream bug: MacPorts' macfuse puts a FUSE 2
compatibility `fuse.h` in `${prefix}/include`. Now an include path in the
Portfile instead of a patch.

## macFUSE 5.5.0 (MacPorts since 2026-11-07)

- Fixes the hang after the daemon dies (#1201) and adds `daemon_timeout`.
- Works around an FSKit data corruption bug (#1188): empty READ replies now
  fail with EIO. A file that changes size on the server can give read errors
  (group `remote`).
- Sends FUSE_FLUSH on close and FUSE_REMOVEXATTR. `notify` is still
  unimplemented; #1207 (zero timeouts), #1222 (size changed elsewhere) and
  #1232 (extension stops being enabled) are open.
- Ships a newer privileged helper. Going 5.4.0 to 5.5.0 and back on far-star
  (2026-11-23), the first 5.5.0 mount asked for an admin password, and then
  5.4.0 logged `fsmodule.macfuse-local not enabled` and no longer mounted.
  Whether enabling only "macFUSE" restores it is not known.

## Tests (`tests/`)

Run by `Build netatalk_client` on macOS_27; results show as annotations.

| Test | What | State |
|---|---|---|
| `port test` | upstream's unit tests | pass, CI |
| `upstream-tests.sh` | upstream's `afpcmd`/`afpgetstatus` tests against `port:netatalk` on loopback | 36 pass, 2 skip (Linux only), CI run 45327708994 |
| `fskit-test.sh` | live FSKit mount tests, one group per entry above | 55 of 66 pass, run 45334492759; see below |

Upstream's `test_afpcmd_interactive.t` is Linux-bound (`ps -C`, `/tmp` not
resolved to `/private/tmp`, a local test account) and is not run.

The 11 failures in run 45334492759: items 4 (3 tests), 5 (1) and 6 (1);
3 `umount(8)` tests that never ran `umount` (test bug, fixed, not rerun);
1 mtime test that may be a test fault (reworked, not rerun); and 2 tests of
a file whose size changes on the server, which match macFUSE #1222 and are
now TODO.

The macos-27 VM has macFUSE's helper, the `/Library/Filesystems/macfuse.fs`
link and the "macFUSE" module enabled. Enable modules under **By Category**:
toggles under By App fail with EPERM (macFUSE #1194). Run these tests on the
runners only, not on far-star.
