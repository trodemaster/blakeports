# netatalk-client upstream issue candidates

Bugs we found while getting `netatalk_client +fuse` working on macOS 27 with
macFUSE FSKit. They're held back so we don't flood the maintainers: file one
at a time, once the previous one has had a response.

Rules (see `CLAUDE.md`): netatalk-client only, never macFUSE. Facts only:
observed behaviour, pinned code links, documented sources. No patches or PR
offers. Keep each one short, and show the user the text before posting.

All of these were checked against `main` at
[0a8be2e](https://github.com/Netatalk/netatalk-client/commit/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03)
on 2026-10-20. The observations came from the 1.0.0 build. Before filing,
check `main` again and search issues and PRs for duplicates.

## Filed

| Issue | Topic | Date |
|---|---|---|
| [#386](https://github.com/Netatalk/netatalk-client/issues/386) | FSKit backend support: `/dev/macfuse0` check, no macOS unmount, `/Volumes` mount point | 2026-10-20 |

## Candidates (suggested order)

### 1. Truncating through an open fork is skipped (data corruption)

- **Observed:** `: > f`, `truncate -s 0 f`, `O_TRUNC`, `ftruncate` and
  overwriting with shorter content leave the server file at its old length,
  with the old tail after the new bytes. Truncating by path alone (no file
  handle) works. Reproduced with `rw-test.sh` against GuestShare.
- **Cause:** `fuse_setattr` and `fuse_truncate` send FPSetForkParms only when
  the new size differs from `fp->size`. `ml_open()` zeroes `fp`, so
  `fp->size` is 0, and truncating to 0 is never sent. lldb showed
  `FUSE_SET_ATTR_SIZE` arrive with a handle and SetForkParms skipped.
- **Code:** [fuse_fs.c L668](https://github.com/Netatalk/netatalk-client/blob/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03/fuse/fuse_fs.c#L668),
  [L1103](https://github.com/Netatalk/netatalk-client/blob/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03/fuse/fuse_fs.c#L1103)
- **Platforms:** shared code, so Linux is likely affected too. Not tested
  there.
- **Duplicates:** none. Closest is #332 (AFP 2.2 copy loses custom icons),
  which is unrelated.
- **Local fix:** `files/patch-fuse-truncate-open-fork.diff`

### 2. FUSE thread writes into a returned stack frame

- **Observed:** after `afpc fs unmount`, afpfsd crashed with
  `EXC_BAD_ACCESS` in `start_fuse_thread`. There were five identical
  `~/Library/Logs/DiagnosticReports/afpfsd-*.ips` reports, and the client
  never sent FPLogout.
- **Cause:** `process_mount()` passes `start_fuse_thread()` a pointer to a
  `struct start_fuse_thread_arg` on its own stack, then returns once the
  mount is up. When `fuse_main()` returns, the thread writes `fuse_result`,
  `fuse_errno` and `wait` into that dead frame. `fuse_options` also points
  into the handler's request.
- **Code:** [commands.c L721-L736](https://github.com/Netatalk/netatalk-client/blob/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03/fuse/commands.c#L721-L736)
- **Platforms:** all. It only showed on macOS once unmount made
  `fuse_main()` return there; on Linux the write may land in unused stack.
- **Duplicates:** none. #23, PR #202 and PR #370 fixed the *volume* being
  freed during unmount. This is a different pointer; cite #370 as "not
  this".
- **Local fix:** `files/patch-fuse-thread-arg-lifetime.diff`

### 3 + 4. FUSE daemon shutdown (file as one issue)

**3. `afpc fs exit` doesn't log out cleanly.**
- **Observed:** with a volume mounted, `afpc fs exit` ended the AFP session
  with a reset instead of FPFlush, then FPLogout, then FIN (packet
  capture).
- **Cause:** `process_exit()` only logs "Exiting". After exit is triggered,
  the main loop (`lib/loop.c`) stops reading server sockets, so the
  unmount in the forced-ending hook waits out DSI timeouts.
- **Code:** [commands.c L587](https://github.com/Netatalk/netatalk-client/blob/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03/fuse/commands.c#L587)
- **Context:** PR #105 deliberately left out programmatic unmount on macOS,
  so this path only runs on Linux upstream (and on macOS once #386 is
  addressed). Observed only on macOS with our unmount patch.

**4. The manager sends each mount daemon two exit commands.**
- **Observed:** the mount daemon printed `Writing: Broken pipe` on
  `afpc fs exit`. lldb showed a second exit arrive mid-unmount, trigger exit,
  and kill the daemon, leaving the volume mounted.
- **Cause:** `cleanup_all_children()` sends exit to every globbed
  `/tmp/afp_server-<uid>*` socket, then again to each tracked child, and
  closes without reading the reply. Its SIGTERM/SIGKILL fallback targets the
  pid it forked, but the mount daemon forks again to daemonize, so the
  signals miss it.
- **Code:** [daemon.c L501-L549](https://github.com/Netatalk/netatalk-client/blob/0a8be2e8333cb8bf84ed5e63de01cb589e1b7b03/fuse/daemon.c#L501-L549)
- **Related:** #368 (manager state diverging from the system). Same area,
  different bug.
- **Local fixes:** `files/patch-fuse-exit-unmount.diff`,
  `files/patch-fuse-manager-exit-reply.diff`

## Not filing

- **"Volume  unmounted" with an empty name:** seen on the 1.0.0 build;
  almost certainly fixed by PR #370. Confirm at the next mount test.
- **`df` shows 3.5 GiB / 0 used:** server side (darkstar logs "user quota did
  not work").
- **Fixed 128 KB reads (`rx_quantum` in `lib/afp.c`):** the user says the
  speed is good enough.
- **Mount shows up in `mount` a moment after `afpc fs mount` returns:** minor.
  File only if it breaks scripts.
