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
| FUSE mount | **Works** via FSKit (`fskit` in mount flags). Listing correct (share is empty); unmount from afpc is broken (see 7) |
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
7. **Unmount is broken on macOS (netatalk_client bug).** On
   `afpc fs unmount`, afpfsd logs `FUSE unmount not supported - volume
   remains mounted` and returns failure. `afpc fs exit` then made afpfsd
   exit with the volume still mounted. That left the FSKit volume orphaned:
   `mount`, `ls` and `umount -f` all hung in uninterruptible wait. Recovery
   was `kill -9` of the `io.macfuse.app.fsmodule.macfuse` appex (user-owned;
   SIGTERM was ignored), after which everything unwound. To unmount safely
   for now, run `umount /Volumes/guestshare` **while afpfsd is still
   running**, then `afpc fs exit`. Never exit afpfsd with a volume mounted.
8. **Empty listing: correct.** The darkstar session confirmed GuestShare
   (`/media/blake/jonesfarm/GuestShare`) is empty. The server log shows the
   share enumerated at 12:56:25, then `dsi_stream_read` unexpected EOF when
   afpfsd exited (no clean logout). A file-read test needs a file in the
   share; the darkstar session will add one only with the user's OK.

## Next steps

Done 2026-10-11: helper installed (step 1 of the old plan; the manual
helper install wasn't needed) and the first guest mount worked.

1. If a read test is wanted, ask the user to OK the darkstar session adding
   a file to GuestShare.
2. Fix the macOS unmount path in afpfsd (`fuse/commands.c`, the "FUSE
   unmount not supported" branch); `unmount(2)` on the mount point or
   libfuse3's unmount should work with FSKit. Keep it a blakeports patch;
   no upstream activity until tested and the user approves.
3. Mount test procedure (desktop Terminal, or `open -a Terminal x.command`
   from Claude, which gets Local Network permission via Terminal). Tell the
   darkstar session before and after:
   ```
   mkdir -p /Volumes/guestshare
   /opt/local/bin/afpc fs mount -a guest 192.168.234.23:guestshare /Volumes/guestshare
   mount | grep guestshare; ls -la /Volumes/guestshare
   umount /Volumes/guestshare          # while afpfsd is still running
   /opt/local/bin/afpc fs exit
   ```
4. Then decide what belongs in a port: the netatalk_client FSKit and
   unmount patches, and a `port:macfuse` note that FSKit mounts need the
   privileged helper (`macfuse.app/Contents/MacOS/macfuse install
   --components privileged-helpers`, run locally). Bump `netatalk_client`
   revision then (not bumped while testing).

## Debugging tips

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
