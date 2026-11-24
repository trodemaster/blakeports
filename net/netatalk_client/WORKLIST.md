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
| 2 | Unmount on macOS | [unmount](files/patch-fuse-macos-unmount.diff) | part of #386 | source, live |
| 3 | `/Volumes` mount points macFUSE creates | [volumes](files/patch-fuse-macos-volumes-mountpoint.diff) | part of #386 | source, live |
| 4 | `afpc fs exit` leaves the volume mounted, no logout | [exit-reply](files/patch-fuse-manager-exit-reply.diff) | not filed | source, live (fixed) |
| 5 | SIGTERM to a mount daemon: not unmounted, no logout | none | not filed | source, live (fails) |
| 6 | A dead daemon's mount is not released | none | not filed | source, live (fails) |
| 7 | Manager sends a daemon two exit commands | in 4's patch | not filed | source |
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

All live on macOS 27.2.1, macFUSE 5.5.0, upstream de759669.

**4.** The manager's `send_exit_to_socket()` writes the command byte, then
shuts the socket down and closes it. The mount daemon's
`fuse_scan_extra_fds()` sets SO_RCVTIMEO after accept(), and closes the
connection if that fails. macOS refuses setsockopt() with EINVAL once the
peer has closed (a socketpair shows it, and the byte is still readable), so
the command is dropped unread. The manager waits 10 s, then its SIGTERM ends
the daemon with the volume mounted (see 5). The patch keeps the connection
until the daemon answers. Linux is not known to be affected.

The October `exit-unmount` patch changed nothing alone and is not needed
with this one (runs 45338753151, 45340300388), so it is gone.

**5.** SIGTERM sets `exit_program = 2` (`lib/loop.c`), which leaves the main
loop without the unmounting hook. The foreground mount's SIGTERM passes.

**6.** After `kill -9`, stat(2) on the mount gives ENXIO (6);
`mount_is_dead()` accepts only ENOTCONN. Access to the dead mount hangs over
25 s in some runs and fails in others (test 34); cause unknown.

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
| `fskit-test.sh` | live FSKit mount tests, one group per entry above | see the runs below |

Upstream's `test_afpcmd_interactive.t` is Linux-bound (`ps -C`, `/tmp` not
resolved to `/private/tmp`, a local test account) and is not run.

Runs (tests changed after the first; 65 and 66 match macFUSE #1222: TODO):

| Run | Exit patches | Failures |
|---|---|---|
| 45334492759 | none | 11, some test faults |
| 45338383682 | none | exit 25, 27, 30; SIGTERM 31, 33; dead 34, 35 |
| 45338753151 | exit-unmount | the same seven |
| 45339838075 | both | 31, 33, 35 |
| 45340300388 | exit-reply | 31, 33, 34, 35 |

The macos-27 VM has macFUSE's helper, the `/Library/Filesystems/macfuse.fs`
link and the "macFUSE" module enabled. Enable modules under **By Category**:
toggles under By App fail with EPERM (macFUSE #1194). Run these tests on the
runners only, not on far-star.
