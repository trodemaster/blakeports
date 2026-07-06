# axpbox — upstream patch notes

Info needed to submit the local patches to upstream
[lenticularis39/axpbox](https://github.com/lenticularis39/axpbox) later.
Both patches were developed and verified against **v1.1.2**
(tag `v1.1.2`, commit `d26f87b`) on macOS 26 (Tahoe) arm64, built via
this port with MacPorts `libsdl` (sdl12-compat over SDL2) and `libpcap`.

## Patch 1: SDL detection broken on macOS

**File:** `files/patch-cmake-sdl-detection.diff` (touches `CMakeLists.txt`)

**Problem:** `check_include_file("SDL/SDL.h" HAVE_SDL)` compiles a probe
program containing `int main(void)`. SDL 1.2's `SDL_main.h` does
`#define main SDL_main` when `__MACOSX__` (or `__WIN32__`) is defined, so
the probe fails to compile on macOS even when SDL is installed —
`error: conflicting types for 'SDL_main'`. Result: `HAVE_SDL` is always
0 on macOS and SDL graphics support is silently disabled.

**Fix:** replace the compile-test with
`find_path(SDL_INCLUDE_DIR NAMES SDL/SDL.h)`, which only checks header
existence (no compilation, so no macro conflict) and honors
`CMAKE_SYSTEM_PREFIX_PATH` / standard prefix search the same way the
working `find_package(PCAP)` detection does. Sets `HAVE_SDL` and adds
`include_directories(${SDL_INCLUDE_DIR})`.

**Upstream framing:** not macOS-specific in principle — any platform
where `SDL_main.h` remaps `main` hits this. Windows MSVC builds likely
dodge it only because they don't use this code path the same way.

## Patch 2: SDL GUI must run on the macOS main thread

**File:** `files/patch-macos-gui-main-thread.diff` (touches
`src/SystemComponent.hpp`, `src/System.cpp`, `src/Cirrus.{hpp,cpp}`,
`src/S3Trio64.{hpp,cpp}`, `src/gui/sdl.cpp`)

**Problem:** each VGA card spawns a worker thread (`CCirrus::run()` /
`CS3Trio64::run()`) that performs *all* SDL work: `SDL_Init(SDL_INIT_VIDEO)`,
window creation via `SDL_SetVideoMode` (from `dimension_update()`), and
event pumping via `SDL_PollEvent`. On macOS, Cocoa requires all of these
on the process main thread. First failure observed (macOS 26, sdl12-compat
2.x over SDL2):

```
*** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
reason: 'API misuse: setting the main menu on a non-main thread.'
  5 libSDL2-2.0.0.dylib  Cocoa_RegisterApp
  ...
 10 axpbox               bx_sdl_gui_c::specific_init
 12 axpbox               CCirrus::run
```

Pre-initializing SDL on the main thread is NOT sufficient — Cocoa's
`nextEventMatchingMask` (reached from `SDL_PollEvent`) also hard-throws
off the main thread on modern macOS, so the whole GUI loop has to move.

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
5. `bx_sdl_gui_c::palette_change()`: NULL-guard `sdl_screen`. The CPU
   thread reaches this via VGA DAC writes (`write_b_3c9`) and can race
   screen creation/replacement — observed as a
   `KERN_INVALID_ADDRESS at 0x8` segfault in
   `palette_change → SDL_MapRGB(sdl_screen->format, ...)`. This race
   exists upstream on all platforms (GUI thread vs CPU thread); the
   guard turns a crash into a missed palette write during mode changes.

**Non-Apple platforms:** completely unchanged — the thread spawn path is
kept verbatim in the `#else` branch; `run_gui_step()` is compiled but
never called.

**Exception behavior note:** on Apple, exceptions from GUI code now
propagate to `main_sim()`'s existing `catch (CException&)` (clean
shutdown) instead of being swallowed by the device thread's catch that
just set `myThreadDead`.

## Verification performed (evidence for the PR)

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
  eager init and the NULL guard together.

## Patch 3: SIGABRT in CSerial::stop_threads() during shutdown

**File:** `files/patch-serial-stop-threads.diff` (touches `src/Serial.cpp`)

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

**Verification (repro + fix, macOS 26 arm64, 2026-07-05):**

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

- [ ] Fork lenticularis39/axpbox, branch from `main` (note: `main` is at
      1.1.3-dev — `CMakeLists.txt` says `VERSION 1.1.3`; re-verify the
      patches apply/behave there, the touched code is unchanged since
      v1.1.2 as of 2026-05)
- [ ] Apply the patches (they are `-p0` MacPorts-style diffs; use
      `patch -p0 < ...` from the repo root, then commit as normal git
      changes)
- [ ] Separate PRs suggested: the CMake detection fix and the serial
      shutdown fix are each trivially reviewable on their own (and the
      serial fix is platform-independent); the threading change deserves
      its own discussion
- [ ] Reference upstream context: README already lists "SDL keyboard
      (partly works, but easily breaks)" under known issues; wiki VGA
      page documents the SDL GUI as supported — macOS is just broken
- [ ] Include the crash stack + `NSInternalInconsistencyException`
      reason string in the PR body (they're quoted above)
- [ ] Mention testing: macOS 26 arm64, sdl12-compat/SDL2; ideally also
      smoke-test a Linux build to show no regression (CI covers this too)
- [ ] Follow the lima PR precedent for tone/structure:
      https://github.com/lima-vm/lima/pull/5036 (same class of bug:
      GUI work must happen on the process main thread on macOS)
- [ ] Contact if needed: upstream bug reports go to GitHub issues;
      `PACKAGE_BUGREPORT` in CMakeLists is tglozar@gmail.com

## Local port wiring (for reference)

- `Portfile` applies both patches via `patchfiles`; SDL dependency is
  `port:libsdl` (default sdl12-compat backend — deliberately chosen over
  legacy `libsdl12`)
- If upstream merges either patch, drop the corresponding
  `files/patch-*.diff` and `patchfiles` entry when bumping the port to
  the release containing it
