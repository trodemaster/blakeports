# axpbox — upstream patch notes

Info needed to submit the local patches to upstream
[lenticularis39/axpbox](https://github.com/lenticularis39/axpbox) later.

**Status as of the v1.2.0 rebase (2026-07):** v1.2.0 pulled in a large
backport from the [ES40-Emu/es40](https://github.com/ES40-Emu/es40)
fork (PR [#129](https://github.com/lenticularis39/axpbox/pull/129)),
which is now where upstream says active development actually happens
("please go there for the latest improvements and speedups" — v1.2.0
release notes). That backport substantially rewrote the files these
patches touch: `CMakeLists.txt` switched from bundled SDL 1.2 to
`find_package(SDL3 CONFIG)`, and `S3Trio64.{hpp,cpp}` gained a new
firmware-reset pause/resume mechanism (`PauseThread`/`PauseAck`) that
`Cirrus.{hpp,cpp}` did not receive. Both remaining patches were
rebased by hand against v1.2.0 and are build-verified (patches apply
with `patch -p0`, zero fuzz, zero rejects; `axpbox --help` runs). The
deep runtime verification from the original v1.1.2 work (ROM boot,
SDL window visible, telnet-attached serial ports, SIGABRT repro) has
**not** been redone against v1.2.0 — that requires a firmware ROM
image and manual interactive testing (see "Verification performed"
below, which still describes the v1.1.2 results only).

**Open question before submitting:** given upstream's own redirect,
it's worth checking whether ES40-Emu/es40 already has working macOS
support (its own CI, threading model, etc.) before investing in a PR
against lenticularis39/axpbox, which may see limited review attention
going forward.

## Patch 1: SDL detection broken on macOS — DROPPED, no longer applicable

This patch (`files/patch-cmake-sdl-detection.diff`, touched
`CMakeLists.txt`) is obsolete as of v1.2.0 and was removed from the
port. v1.2.0 replaced the old `check_include_file("SDL/SDL.h",
HAVE_SDL)` probe — which broke on macOS because SDL 1.2's
`SDL_main.h` does `#define main SDL_main`, conflicting with the
probe's own `int main(void)` test program — with
`find_package(SDL3 CONFIG QUIET)`. `find_package` doesn't compile a
test program, so the bug this patch worked around does not exist in
v1.2.0. Nothing to submit upstream for this one.

## Patch 2: SDL GUI must run on the macOS main thread

**File:** `files/patch-macos-gui-main-thread.diff` (touches
`src/SystemComponent.hpp`, `src/System.cpp`, `src/Cirrus.{hpp,cpp}`,
`src/S3Trio64.{hpp,cpp}`). No longer touches `src/gui/sdl.cpp` — see
below.

**Problem:** each VGA card spawns a worker thread (`CCirrus::run()` /
`CS3Trio64::run()`) that performs *all* SDL work: init, window
creation, and event pumping. On macOS, Cocoa requires all of this on
the process main thread. (Original crash evidence, from v1.1.2 on
SDL2/sdl12-compat, quoted for reference — the exact backtrace will
differ under SDL3 but the underlying Cocoa main-thread constraint is
unchanged and not SDL-version-specific):

```
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
reason: 'API misuse: setting the main menu on a non-main thread.'
  5 libSDL2-2.0.0.dylib  Cocoa_RegisterApp
  ...
 10 axpbox               bx_sdl_gui_c::specific_init
 12 axpbox               CCirrus::run
```

**Fix (all behavior changes under `#if defined(__APPLE__)`):**

1. `CSystemComponent` gains `virtual bool run_gui_step() { return false; }`
   (mirrors the existing empty-default `start_threads`/`check_state`
   pattern).
2. `CCirrus`/`CS3Trio64::start_threads()`: on Apple, don't spawn the GUI
   thread; print `cirrus(main)`/`s3(main)`; **eagerly** call
   `bx_gui->init(...)` right there — `start_threads()` runs on the main
   thread from `CSystem::Run()` *before* `release_threads()` frees the
   CPUs, so the SDL screen deterministically exists before the guest VGA
   BIOS programs the card.
3. `run_gui_step()` on both cards: one pass of the `run()` loop body —
   10 × (`handle_events` + 10 ms sleep), then `update()` + `flush()`,
   all under `bx_gui->lock()`. Returns true.
4. `CSystem::Run()` main loop: on Apple, call `run_gui_step()` on every
   component; if any stepped, skip the loop's own 100 ms sleep (the GUI
   step sleeps ~100 ms internally, preserving the watchdog cadence —
   both loops were already 100 ms/iteration by design).
5. `CS3Trio64` specifically (new in v1.2.0 — `Cirrus` has no equivalent):
   the upstream `PauseThread`/`PauseAck` firmware-reset mechanism (added
   in the ES40 backport, keeps the SDL window alive across a firmware
   reset instead of tearing it down) is mirrored on the Apple path.
   `stop_threads()` sets `PauseThread` and returns immediately instead of
   spin-waiting on `PauseAck` (there's no separate thread to wait on);
   `run_gui_step()` checks `PauseThread` after its event-handling pass
   and, if set, clears the screen once and skips `update()`/`flush()`
   until unpaused — matching what `run()` does on non-Apple platforms.

**No longer needed — `bx_sdl_gui_c::palette_change()` NULL-guard:** the
v1.1.2 patch NULL-guarded `sdl_screen` in `set_color()` because the CPU
thread could reach a `SDL_MapRGB(sdl_screen->format, ...)` call while
the screen surface was being created/replaced (`KERN_INVALID_ADDRESS`
segfault). In v1.2.0's SDL3 rewrite, `palette_change()` is a stub
(`return 1;` — 8bpp indexed-palette handling was dropped in favor of
direct ARGB32 texture upload in `graphics_frame_update()`), and that
function itself already NULL-guards `sdl_texture`/`sdl_renderer`
before touching them. The race no longer exists; nothing to submit for
this part either.

**Non-Apple platforms:** completely unchanged — the thread spawn path is
kept verbatim in the `#else` branch; `run_gui_step()` is compiled but
never called.

## Verification performed (v1.1.2 — not yet redone against v1.2.0)

This section describes the original v1.1.2 verification and is kept
for reference; it has not been repeated against v1.2.0 (needs a
firmware ROM image + interactive telnet testing, see top of file).

- Config: `gui = sdl`, `pci0.1 = cirrus` with `rom/vgabios-0.6a.bin`
  (VGABIOS 0.7b build, the non-cirrus-named binary from
  https://download-mirror.savannah.gnu.org/releases/vgabios/vgabios-0.7b-bin.tgz —
  upstream wiki warns the "cirrus" one doesn't work), `pci0.7 = ali`
  with `vga_console = true`, SRM ROM `cl67srmrom.exe`.
- Both serial ports must have telnet clients attached before construction
  proceeds (blocking `accept()` in `CSerial` constructor — pre-existing
  behavior).
- Result: `Start threads: cpu0 srl0 srl1 ide0 ide1 cirrus(main) ali kbd`,
  guest VGA BIOS banner (`cirrus: VGABios $Id: vgabios.c 226 ...`), SRM
  console boots, SDL window visible on the desktop, process stable at
  ~100% CPU (one emulated CPU), user-confirmed working window.
- Without patch 2: 100% reproducible NSException crash at GUI init.
- With patch 2 but without the eager-init part (lazy init on first
  `run_gui_step`): intermittent SIGSEGV in `palette_change` — keep the
  eager init and the NULL guard together. (Note: this NULL guard no
  longer exists as of v1.2.0 — see above.)

## Patch 3: SIGABRT in CSerial::stop_threads() during shutdown

**File:** `files/patch-serial-stop-threads.diff` (touches `src/Serial.cpp`).
Unchanged in shape from the v1.1.2 version — `Serial.cpp`'s
`stop_threads()` is structurally identical in v1.2.0 (only a cosmetic
brace-style difference), so this patch just needed re-diffing, not
redesigning.

**Problem:** `CSerial::stop_threads()` only joins the serial thread when it
is NOT blocked in `accept()`:

```cpp
if (!acceptingSocket) {
  myThread->join();
}
myThread = nullptr;   // joinable thread destroyed -> std::terminate()
```

If shutdown happens while a serial port is waiting for a (re)connection
(`acceptingSocket == true` — e.g. a telnet client disconnected), the
`unique_ptr` reset destroys a still-joinable `std::thread`, which per the
C++ standard calls `std::terminate()` → `abort()` (SIGABRT). Observed
stack: main thread in `main_sim → CSystem::stop_threads →
CSerial::stop_threads + 112 → std::terminate → abort`, with both serial
threads sitting in `__accept`.

**Not macOS-specific** — this aborts on any platform whenever the emulator
shuts down while a serial port is in the waiting state. It surfaces more
readily with patch 2 because clean shutdown paths (SDL_QUIT from window
close or SDL's signal handlers) now actually execute on macOS instead of
being swallowed by the device thread's catch block.

**Fix:** `detach()` the thread when it's blocked in `accept()` — it cannot
be woken portably (closing a listening socket does not reliably unblock
`accept()` on all platforms, notably macOS), and the process is exiting
anyway.

**Verification (repro + fix, macOS 26 arm64, 2026-07-05, against v1.1.2 —
not yet redone against v1.2.0):**

- Repro procedure: boot to SRM, connect telnet clients to both serial
  ports (construction blocks on `accept()` until then), disconnect both
  clients so the serial threads re-enter `accept()`
  (`-SRL-I-WAITFOR: Waiting for a new connection...` in the log), then
  send SIGTERM.
- Unpatched binary: 100% reproducible SIGABRT (exit code 134), crash
  report shows `CSerial::stop_threads → std::terminate → abort` with
  both serial threads in `__accept`. Reproduced twice on separate runs.
- Patched binary, same procedure: exit code 0, no crash report, log
  shows the complete graceful path:
  `Exiting gracefully: User requested shutdown (sdl.cpp:1035)` →
  `Stop threads: cpu0 srl0 srl1 ide0 ide1 ali kbd` →
  `%FLS-I-SAVEST: Flash state saved to rom/flash.rom` →
  `%DPR-I-SAVEST: DPR state saved to rom/dpr.rom`.
- Side effect worth mentioning in the PR: because shutdown now completes
  instead of aborting, Flash/DPR NVRAM state is actually persisted on
  exit — SRM environment variables survive across runs. Before the fix
  (and on macOS before patch 2), the save-state code was unreachable on
  this path.
- Note the SIGTERM→graceful chain: SDL installs SIGINT/SIGTERM handlers
  by default and converts them to SDL_QUIT, which the GUI event loop
  turns into the graceful-exit exception (sdl.cpp:1035). So "kill <pid>"
  exercises the same code path as closing the window.

## Submission checklist

- [ ] Decide lenticularis39/axpbox vs. ES40-Emu/es40 as the PR target
      (see "Open question" at top) before doing anything else
- [ ] Re-run the full runtime verification (ROM boot, SDL window,
      telnet-attached serial ports, SIGTERM repro) against v1.2.0 —
      only build-level verification (patches apply cleanly, port
      builds, `axpbox --help` runs) has been done so far
- [ ] Fork the chosen repo, branch from its default branch
- [ ] Apply the patches (they are `-p0` MacPorts-style diffs; use
      `patch -p0 < ...` from the repo root, then commit as normal git
      changes)
- [ ] Separate PRs suggested: the threading change (patch 2) and the
      serial shutdown fix (patch 3, platform-independent) are each
      independently reviewable
- [ ] Include the crash stack + `NSInternalInconsistencyException`
      reason string in the PR body for patch 2 (quoted above, from the
      v1.1.2/SDL2 repro — re-capture against v1.2.0/SDL3 if possible)
- [ ] Mention testing: macOS, arm64; ideally also smoke-test a Linux
      build to show no regression (CI covers this too)
- [ ] Follow the lima PR precedent for tone/structure:
      https://github.com/lima-vm/lima/pull/5036 (same class of bug:
      GUI work must happen on the process main thread on macOS)
- [ ] Contact if needed: upstream bug reports go to GitHub issues;
      `PACKAGE_BUGREPORT` in CMakeLists is tglozar@gmail.com

## Local port wiring (for reference)

- `Portfile` applies both remaining patches via `patchfiles`; SDL
  dependency is `port:SDL3` (v1.2.0 requirement, replacing the old
  `port:libsdl`)
- If upstream merges patch 2 or 3, drop the corresponding
  `files/patch-*.diff` and `patchfiles` entry when bumping the port to
  the release containing it
