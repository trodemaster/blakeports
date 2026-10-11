# macFUSE (FSKit) for netatalk_client +fuse: notes and status

`port:macfuse` comes from the official ports
tree (`fuse/macfuse`, 5.4.0 at the time of writing). These are notes on
getting `netatalk_client +fuse` mounting through macFUSE's FSKit backend on
far-star.

Last updated: 2026-10-11 (far-star session blakeports-87, which took over from
the umac session).

## Ground rules (from the user)

- FSKit only. No macFUSE kernel extension, so no reduced boot security.
- No upstream activity on FUSE: no issues, PRs or questions to macFUSE or
  netatalk-client.
- MacPorts must only touch `/opt/local`. Anything outside it is a manual step
  the user approves.
- Live mount tests are guest-only against the darkstar Netatalk server
  (`192.168.234.23`, volume `guestshare`). Bomb20 is off-limits. Tell the
  darkstar server session ("Netatalk server startup via systems") before a
  test starts and after it ends.
- Revisit at the console, not over SSH (see "Helper install" below).

## Status

| Piece | State |
|---|---|
| netatalk_client 1.0.0 +fuse, FSKit patch | Committed `3213dfd`. CI passes on macOS 15, 26, 27 |
| Local install on far-star | `netatalk_client @1.0.0_0+fuse` and `macfuse @5.4.0_0`, clean install |
| `/Library/Filesystems/macfuse.fs` | Symlink to `/opt/local/Library/Filesystems/macfuse.fs` (manual, approved) |
| FSKit extension "macFUSE" | Enabled in System Settings. "macFUSE (local)" stays off; AFP doesn't need it |
| AFP connect to darkstar as guest | Works when started from a GUI session (AFP3.4, Netatalk4.6.0dev) |
| macFUSE privileged helper | Installed 2026-10-11 via `macfuse install --components privileged-helpers` from a local Terminal; admin prompt appeared |
| FUSE mount | **Works** via FSKit (`fskit` in mount flags). Listing correct (share is empty); `afpc fs unmount` and `fs exit` work with the unmount patch (see 7) |
| `/Volumes/guestshare` | Gone; removed by the forced unmount. Recreate (`mkdir`) before the next mount |
| Running processes | None. afpfsd exited, nothing mounted (checked 12:59) |

## What we found, in order

1. **`/dev/macfuse0` check.** afpfsd (`fuse/commands.c`) refused every mount
   on macOS unless `/dev/macfuse0` existed. Only the kernel extension creates
   it. It also reported the failure with `printf` to its own stdout, so
   `afpc` exited 1 with no message. Fixed locally by
   `net/netatalk_client/files/patch-fuse-macos-fskit.diff` (+fuse only).
   On macOS it requires the device only if present, and passes
   `-obackend=fskit` when absent. Other platforms keep the `/dev/fuse` check,
   now logged to the client.
2. **FSKit limits** (macFUSE wiki, "FUSE Backends"):
   - mount points must be under `/Volumes`
   - backend selected with `-o backend=fskit`; libfuse3 only
   - the kernel extension is still macFUSE's default
   - slower I/O than the kernel backend
   - no `fuse_context`, no notifications, most mount options unimplemented
   - since macFUSE 5.2, libfuse mounts over XPC through `MFMount.framework`
3. **Extension registration.** The FSKit modules live in
   `macfuse.fs/Contents/Resources/macfuse.app/Contents/Extensions/`. They
   register only after `macfuse.app` is opened once, then must be enabled
   under System Settings → General → Login Items & Extensions → File System
   Extensions.
4. **Local Network privacy.** Non-Apple binaries started from the Claude
   session got `EHOSTUNREACH` ("No route to host") to darkstar. The session
   runs inside a tmux server with no GUI, so macOS can't show a prompt.
   Apple binaries (`nc`, `ping`) are exempt and connected fine. Start the
   mount from a Terminal.app window on the desktop (or a `.command` file
   opened with `open`). Reading an existing mount from the Claude shell
   works.
5. **Privileged helper.** With the AFP session up, macFUSE needs its launch
   daemon `io.macfuse.app.launchservice.daemon`. It provides the XPC service
   `io.macfuse.mount` that libfuse's FSKit path uses. It isn't installed:
   - `macfuse.app` tries to install it with SMJobBless on demand.
   - From SSH/tmux it fails with `-60007`; the session can't show a prompt.
   - Run via `macfuse.app/Contents/MacOS/macfuse install --components privileged-helpers` (not on PATH; full path in Next steps) in a desktop
     Terminal window (opened over SSH with `open x.command`), authd denied it
     in 8 ms (`-60005`), and SecurityAgent never ran. No password prompt
     appeared.
   - The account is admin, the Mac isn't MDM-enrolled, and the
     `com.apple.ServiceManagement.blesshelper` rule is stock (authenticate
     admin).
   - The official macFUSE `.pkg` presumably installs the helper itself. The
     MacPorts port doesn't, so FSKit mounts can't work out of the box with
     `port:macfuse`. This is inference, not confirmed.
6. **Signing: fine.** The port runs `install_name_tool` on `MFMount`,
   `libfuse*.dylib` and `macFUSE.framework`, then re-signs them ad hoc
   (`codesign -fs -`). AMFI logs them as "adhoc signed ... not valid", but
   afpfsd loads them, and the validly signed helper (team `3T5GSNBU6W`)
   accepted the ad-hoc `MFMount` client over `io.macfuse.mount`. The mount
   came up as `macfuse://<uuid> on /Volumes/guestshare (macfuse, ..., fskit)`.
7. **Unmount: two separate problems.** Seen on 2026-10-11:
   `afpc fs unmount /Volumes/guestshare` failed with "Unmount failed ... try
   using 'umount'", and afpfsd logged `FUSE unmount not supported - volume
   remains mounted on /Volumes/guestshare`. `afpc fs exit` then made afpfsd
   exit with the volume still mounted (darkstar logged `dsi_stream_read`
   EOF, no clean logout). The orphaned volume froze `mount`, `ls` and
   `umount -f` in uninterruptible wait (state `U`).
   - **(a) netatalk_client has no programmatic unmount on macOS, by
     design.** `fuse/daemon.c` `fuse_unmount_volume()` only implements
     `fuse_exit()` plus a SIGPIPE wake of the FUSE thread under
     `#if !defined(__APPLE__) && FUSE_USE_VERSION >= 30`. On macOS it logs
     "Programmatic unmount not supported on this platform" and returns -1,
     and `lib/afp.c` `afp_unmount_volume()` turns that into the warning
     above. `afpc fs exit` doesn't unmount first. This is netatalk_client's
     gap, not macFUSE's, and it applies to the kernel backend too.
   - **(b) The hang after the daemon dies is a known macFUSE FSKit bug.**
     It's [macfuse/macfuse#1201](https://github.com/macfuse/macfuse/issues/1201),
     open, filed 2026-09-18 against 5.4.0 on macOS 26.6.2. When the file
     system process dies, the FSKit module never notices, so the volume
     stays mounted and `umount` and in-flight requests block. The
     maintainer (bfleischer) confirmed it: the FSKit backend doesn't yet
     honor `daemon_timeout` and some channel errors aren't handled.
     Workarounds: kill that volume's `io.macfuse.app.fsmodule.macfuse`
     process (what we did; it ignored SIGTERM here and needed `kill -9`,
     unlike the issue's report), or kill `fskitd`, which force-unmounts all
     FSKit volumes. Nothing to add upstream; it already matches our
     observation.
   - **Without the patch:** `umount /Volumes/guestshare` while afpfsd is
     still running, then `afpc fs exit`. Never exit an unpatched afpfsd with
     a volume mounted.
   - **Fixed in blakeports for (a):** `files/patch-fuse-macos-unmount.diff`
     (commit `b28dfca`) adds a `__APPLE__` branch to
     `fuse_unmount_volume()`: `unmount(2)` on the mount point, then join the
     FUSE thread. `fs exit` already unmounts mounted volumes through
     `fuse_forced_ending_hook()`, so it needed no separate change. CI passed
     on 15, 26 and 27 (run 38173199182). On far-star (clean install,
     2026-10-11 13:44), `afpc fs unmount` returned 0 and the volume went
     away; `afpc fs exit` with a volume mounted unmounted it, and every
     afpfsd process exited. Nothing hung. `afpc` still prints "Writing:
     Broken pipe" on `fs exit`, as it did before the patch.
   - **No clean AFP logout: the cause was a crash (fixed for unmount).**
     A capture at 13:51 showed the client never sent FPLogout. lldb at 13:55
     then caught afpfsd dying with `EXC_BAD_ACCESS` in `start_fuse_thread`
     right after the unmount. Five crash reports from 13:44 to 13:55 in
     `~/Library/Logs/DiagnosticReports/afpfsd-*.ips` are identical.
     - **Cause:** `process_mount()` in `fuse/commands.c` passes
       `start_fuse_thread()` a pointer to a struct on its own stack, then
       returns once the mount is up. When unmount ends `fuse_main()`, the
       thread writes `fuse_result`/`fuse_errno`/`wait` into that long-dead
       frame. The command thread is gone and its stack unmapped, so SIGSEGV.
       This is an upstream bug on every platform. Before our unmount patch
       `fuse_main()` never returned on macOS, so it never showed; on Linux
       the write probably lands in cached stack memory and goes unnoticed.
     - **Fix:** `files/patch-fuse-thread-arg-lifetime.diff` (commit
       `b311744`, CI run 38174315826 green on 15/26/27). The arg goes on the
       heap with two references; the handler and the thread each drop one,
       and the last one frees it. `fuse_options` is `strdup`ed, since it
       pointed into the handler's `req` too.
     - **Result (13:58, clean install):** no new crash reports.
       `afpc fs unmount` now prints "Volume unmounted", and the wire shows
       FPFlush, then FPLogout (AFP 20) with an OK reply, then FIN. That's a
       clean logout.
     - **`afpc fs exit`: fixed (two patches).**
       - **Starved main loop:** after `trigger_exit()` the main loop
         (`lib/loop.c`) stops reading server sockets, so unmounting from the
         forced-ending hook waited out DSI timeouts and ended in a reset.
         Fix: `files/patch-fuse-exit-unmount.diff` makes `process_exit()`
         in `fuse/commands.c` unmount every mounted volume itself before
         returning, while replies still flow.
       - **Duplicate exit commands:** `afpc fs exit` goes to the manager
         daemon. Its `cleanup_all_children()` (`fuse/daemon.c`) sends the
         exit byte to every `/tmp/afp_server-<uid>*` socket it globs, then
         again to each tracked child, so a mount daemon gets two exits.
         lldb (14:05) showed the second exit find no volume still in the
         mounted state (the first was mid-`unmount(2)`), trigger exit, and
         the daemon die mid-unmount. That left the FSKit volume hung, the
         process stuck in state `E`, and no FPLogout. Fix: the same patch
         holds a mutex across `process_exit()`'s unmount loop (commit
         `ea15c00`, CI run 38174978868 green).
       - **Manager kill logic doesn't help:** the manager's SIGTERM/SIGKILL
         escalation targets the pid it forked. That process exits right
         away, because the mount daemon forks again to daemonize, so the
         signals never reach the real daemon.
       - **Result (14:07, clean install, capture):** both `fs unmount` and
         `fs exit` sessions end with FPFlush, then FPLogout (OK), then FIN.
         The exit session closed 26 ms after the command. No crashes,
         nothing hung, afpfsd gone.
       - **"Writing: Broken pipe": fixed.** The mount daemon's
         `perror("Writing")` fired when it replied to the manager's exit
         command after the manager had already closed the socket, once per
         duplicate exit. `files/patch-fuse-manager-exit-reply.diff` (commit
         `9d893b9`, CI green) makes `cleanup_all_children()` skip tracked
         children already reached through its socket glob, and makes
         `send_exit_to_socket()` read until the child closes (15 s
         `SO_RCVTIMEO`). Tested 14:19: no message, and both sessions still
         end with FPLogout (OK), then FIN.

8. **Empty listing: correct.** The darkstar session confirmed GuestShare
   (`/media/blake/jonesfarm/GuestShare`) is empty. The server log shows the
   share enumerated at 12:56:25, then `dsi_stream_read` unexpected EOF when
   afpfsd exited (no clean logout). A file-read test needs a file in the
   share; the darkstar session will add one only with the user's OK.

10. **Read-write test (GuestShare, guest, 2026-10-11 14:22–14:26).**
    "jonesfarm" isn't an AFP volume; it's the ext4 disk on darkstar
    (`/media/blake/jonesfarm`) holding both shares. Bomb20 (`valid users =
    blake`, the user's real data) is off-limits, so the read-write test ran
    on GuestShare, which guest can write. Script: `rw-test.sh` in this
    folder (`rw-test.sh 192.168.234.23 guestshare -a guest`, run from
    Terminal.app; exits non-zero on failure). It works only in
    `netatalk_client-test-<timestamp>`. Phase 1 writes, then
    unmounts to drop caches; phase 2 remounts and verifies from the server,
    then removes the directory.
    - **Passed from the start:** 16 MB random file (sha256 after remount),
      write plus append plus rename, mkdir/rmdir, xattr. The 0.14 s `cp` of
      16 MB is only the write cache; the data does reach the server.
    - **Truncation through an open fork was broken (data-corrupting).**
      `: > f`, `truncate -s 0 f` and overwriting with shorter content left
      the server file at its old length, with the old tail after the new
      bytes. lldb showed `fuse_setattr` getting `FUSE_SET_ATTR_SIZE` with a
      file handle and skipping FPSetForkParms, because the size equalled
      `fp->size`. `ml_open()` zeroes `fp`, so `fp->size` is 0, not the
      file's length, and truncation to 0 was always skipped. Path-only
      `truncate(2)` (no handle) went through `ml_truncate` and worked. This
      is shared code, so Linux is likely affected too.
    - **Fix:** `files/patch-fuse-truncate-open-fork.diff` (commit
      `f08c581`, CI green). It always sends SetForkParms in `fuse_setattr`
      and `fuse_truncate`. Retest at 14:26: all checks pass (FAILS=0),
      including O_TRUNC, ftruncate and the shorter overwrite.

## Next steps

Done 2026-10-11: helper installed (step 1 of the old plan; the manual
helper install wasn't needed) and the first guest mount worked.

1. If a read test is wanted, ask the user to OK the darkstar session adding
   a file to GuestShare.
2. Unmount, exit and logout are fixed (finding 7). The darkstar log
   confirms both 14:07 sessions: "AFP logout by nobody", "client logged
   out" and "AFP statistics", with no EOF or reset. The mount point is handled (finding 9), and "Writing: Broken pipe" is
   gone.
3. Mount test procedure (desktop Terminal, or `open -a Terminal x.command`
   from Claude, which gets Local Network permission via Terminal). Tell the
   darkstar session before and after:
   ```
   /opt/local/bin/afpc fs mount -a guest 192.168.234.23:guestshare /Volumes/guestshare
   mount | grep guestshare; ls -la /Volumes/guestshare
   /opt/local/bin/afpc fs unmount /Volumes/guestshare   # works with the patch
   /opt/local/bin/afpc fs exit
   ```
4. Then decide what belongs in a port: the netatalk_client FSKit and
   unmount patches, and a `port:macfuse` note that FSKit mounts need the
   privileged helper (`macfuse.app/Contents/MacOS/macfuse install
   --components privileged-helpers`, run locally). Don't bump the
   `netatalk_client` revision; to pick up changes locally, run
   `sudo port uninstall netatalk_client && sudo port clean --all
   netatalk_client && sudo port install netatalk_client +fuse`.

## Debugging tips

- **Crashes:** `~/Library/Logs/DiagnosticReports/afpfsd-*.ips`.
- **Wire:** `sudo tcpdump -n -i en0 -U -w x.pcap host 192.168.234.23 and
  tcp port 548`. DSI header is 16 bytes, then the AFP command byte:
  FPLogout 20, FPFlush 10, FPGetVolParms 17, FPGetFileDirParms 34.
- **lldb on the mount daemon** (`afpfsd --socket-id ...`): `sudo lldb -p
  <pid> -s file`. In the file, start with `script
  lldb.debugger.SetAsync(False)` so breakpoint `-C` commands print, and
  detach before the test ends; a stopped daemon blocks FSKit. afpfsd uses
  SIGUSR2 to wake its main loop, so lldb will stop on it unless told to
  pass it (`process handle SIGUSR2 -s false -p true`).
- **Debug logging:** start the manager yourself first (`afpfsd --manager
  --logmethod syslog --loglevel LOG_DEBUG`); mount daemons inherit the
  level. Little shows up in `log show` anyway.

- Run the manager in the foreground with debug logs:
  `afpfsd --manager -d > /tmp/afpfsd.log 2>&1 &`. Per-mount daemons then log
  to stdout too.
- Useful log predicate:
  `process == "afpfsd" OR process CONTAINS "io.macfuse" OR process == "fskitd" OR process == "authd" OR process == "smd"`.
- `pluginkit -m -v -A | grep fuse` shows extension registration. A leading
  `+` means enabled, though enabling via System Settings didn't show `+` here.

## Related: CI runner clock drift

On 2026-10-11 both far-star runner VMs (macos-26, macos-27) went offline
because their clocks had fallen 19-24 minutes behind, so GitHub rejected
their OAuth tokens as expired. Network time was already on. Fixed with
`sudo sntp -sS time.apple.com` in each guest; the runners reconnected without
re-registration. The `runner-<vm>` targets in `lima_mac` could sync the clock
first if this recurs.
