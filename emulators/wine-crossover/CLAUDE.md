# wine-crossover — working notes

Personal port: Wine built from CodeWeavers' CrossOver source tarball.
**Never PR to macports-ports.** Targets macOS 27 on Apple silicon (M1–M5)
only; the Unix side is x86_64 and runs under Rosetta 2.

**Never build or install this on far-star.** Build and test through CI on the
`macOS_27` runner (Lima VM `macos-27`), or experiment on that VM through the
ghrunnerd MCP (`vm_exec` on `ghrunnerd-far-star`, id `macos-27`).

## Status (2026-10-26)

CI is green on 2567ce0 ([run 40273813956](https://github.com/trodemaster/blakeports/actions/runs/40273813956)):

| Check | Result |
|---|---|
| Build (wine + private gnutls + DXVK) | pass, ~6 min on the VM |
| `wine --version`, x86_64 binaries, private dylibs relocated | pass |
| winemac.so links OpenGL.framework | pass |
| 64-bit and 32-bit (wow64) `cmd.exe` | pass |
| HTTPS via WinHttp → schannel → private gnutls, 64 + 32-bit | pass (status 200) |
| DXVK D3D11 device + clear + readback, 64 + 32-bit | pass, FL 11_0 on "Apple Paravirtual device" |
| `wine-dxvk install/status/uninstall` | pass |
| wined3d (OpenGL) D3D11 | **fails 0x8007000e** on the headless VM — report-only, untested on a real display |

Nothing has been run on real hardware yet. No game or Steam has been tried.

## What gets built

- `crossover-sources-26.3.0.tar.gz` from media.codeweavers.com (Wine 11.0 +
  CodeWeavers patches). Only `sources/wine`, `sources/gnutls` and
  `sources/dxvk` are extracted.
- **wine**: new-WoW64 (`--enable-archs=i386,x86_64`), no separate wine64.
  configure.args copied from `emulators/wine-stable`.
- **gmp 6.3.0, nettle 3.10, gnutls 3.8.3**: built x86_64 into
  `${workpath}/cxdeps` in pre-configure (`proc cx_build_dep`), installed to
  `${prefix}/libexec/wine-crossover/lib` with install names rewritten and
  re-signed in post-destroot. wine dlopen()s gnutls by absolute path
  (`ac_cv_lib_soname_gnutls`). nettle comes from GNU's nettle-3.10.tar.gz
  because the tarball copy lacks its generated files (otherwise identical).
- **DXVK 1.10.3**: built with meson + mingw-w64 in post-build (d3d9 off),
  installed to `${prefix}/lib/dxvk/{x86_64,i386}-windows`. Off by default;
  `wine-dxvk install|uninstall|status` switches the current `$WINEPREFIX`.
- From MacPorts, +universal: freetype, gettext-runtime, libpcap, libsdl2,
  MoltenVK-latest (stock, not CodeWeavers' fork). Run deps: wine-gecko 2.47.4,
  wine-mono 10.4.1.
- Not built: the tarball's MoltenVK fork, gstreamer, glib, vkd3d dir, etc.
  Not available at all: CrossOver.app (GUI, bottles, CrossTie) and D3DMetal.

Files: `Portfile`, `files/patch-dxvk-*.diff`, `files/wine-dxvk`. CI:
`.github/workflows/build-wine-crossover.yml` and
`.github/wine-crossover/d3d11test.c`. Cutoff recorded in
`PLATFORM_CUTOFFS.md` (`platforms {darwin >= 27}`).

## Gotchas (each cost a CI run)

- **Xcode 27 muniversal bug.** `/usr/bin/libtool` accepts non-Mach-O input,
  so muniversal's lipo → libtool → diff merge turns per-arch-differing headers
  into `!<arch>` archives (gmp.h, ffi.h, ffitarget.h). Any universal port with
  such headers is corrupted. That is why gnutls/nettle/gmp are built
  privately. Unfixed upstream; no Trac ticket filed yet.
- **Build deps get arch-checked too.** base upgrades `depends_build` to
  +universal for an x86_64 port; glslang's tree pulled in libffi +universal and
  broke python314. Fixed with `depends_skip_archcheck-append` for every build
  tool. Add any new build dep to that list.
- **Keep `--without-opengl`.** On macOS it only skips the EGL check (X11 and
  Wayland drivers). winemac.drv always builds its CGL OpenGL code.
  `--with-opengl` makes configure fail with "EGL 64-bit development files not
  found".
- **DXVK vs stock MoltenVK.** CX's DXVK expects CodeWeavers' MoltenVK, which
  fakes geometryShader / shaderCullDistance / tessellationShader.
  `patch-dxvk-macos-features.diff` requests them only if supported (same idea
  as Gcenx/DXVK-macOS f8470ed7). The other two patches fix gcc 15 / newer
  mingw headers.
- gnutls' nettle_* configure checks link only `-lhogweed` and all fail on
  macOS; pass `LIBS=-lnettle`.
- Tcl: a variable named `env` collides with the `env` array — hence `cx_env`.
- In CI shell steps, never pipe a multi-line producer into `grep -q` under
  `pipefail` (SIGPIPE); capture to a variable first.

## Working on the runner VM

- Rosetta 2 is installed on `macos-27` (user approved).
- The VM login shell is zsh (no word splitting); run build scripts with bash.
- MacPorts drops privileges to `macports`, which can't read `~` on the VM;
  put scratch overlays in `/Users/Shared`, and remove them when done.
- In-VM runner: no snapshots. Installing/removing ports is fine; don't make
  system changes that can't be reversed by hand.
- After any +universal build of a port with arch-specific headers, scan for
  corruption: `grep -l '^!<arch>' /opt/local/include/**/*.h`.
- Cached distfiles live in `/opt/local/var/macports/distfiles/wine-crossover`.
- Fetching job logs from far-star:
  `gh api --allow-escape-sequences repos/trodemaster/blakeports/actions/jobs/<id>/logs`
  (sandbox needs `results-receiver.actions.githubusercontent.com`,
  `*.actions.githubusercontent.com`, `*.blob.core.windows.net`).

## Next steps

1. **Real hardware test** on the user's Mac: install the port, make a prefix,
   `wine-dxvk install`, try the Steam installer and a D3D11 game. Also check
   whether wined3d/OpenGL works with a real display.
2. **D3DMetal (Game Porting Toolkit)** — waiting on the user to download the
   GPTK disk image from developer.apple.com (Apple ID required; the license
   forbids redistribution, and blakeports is public, so binaries never go in
   the repo). Plan:
   - separate port `wine-crossover-d3dmetal`, DMG as a hand-placed distfile
     (on the user's Mac and on the `macos-27` runner);
   - install GPTK `redist/lib` (D3DMetal.framework, libd3dshared.dylib,
     wine-side d3d11/d3d12/dxgi DLLs) to a private dir, not over
     wine-crossover's own files;
   - `wine-d3dmetal install|uninstall|status`, like `wine-dxvk`;
   - first experiment on the VM to learn where Wine 11 needs the files and
     whether GPTK's DLLs are ABI-compatible with CX 26's Wine 11.
   - Limits: 64-bit D3D11/D3D12 only; the VM's paravirtual GPU may not
     support D3DMetal, so the real test may have to happen on hardware.
   - GPTK 4 (WWDC 2026) is unverified to still ship the D3DMetal DMG; 3.0 is
     fine if that is what's offered.
3. Optional: `+gstreamer` (media playback in games/launchers), DXVK d3d9,
   a Trac ticket for the Xcode 27 libtool/muniversal bug (short, facts only,
   show the text to the user before posting).
