# Platform cutoffs

Ports in BlakePorts that refuse to install below a minimum OS version, and
why. A cutoff is set with `platforms {darwin >= N}` in the Portfile; MacPorts
then reports the port as unsupported on older systems instead of trying to
build it.

Keep this table in step with the Portfiles. To list every cutoff:

```bash
grep -rn --include=Portfile -E '^platforms .*>=' . | grep -v _resources
```

## Cutoffs

| Port | Minimum | Darwin | Set in | Why |
|---|---|---|---|---|
| [libfido2](security/libfido2/Portfile) | 10.6 Snow Leopard | `>= 10` | `fb25df2` | Leopard compat code is broken; not worth fixing ([details](#libfido2)) |
| [libtpms](security/libtpms/Portfile) | 10.7 Lion | `>= 11` | `f3e7e7f` | Fails on Leopard PPC; not worth fixing ([details](#libtpms-swtpm)) |
| [swtpm](sysutils/swtpm/Portfile) | 10.7 Lion | `>= 11` | `f3e7e7f` | Needs libtpms, and libusb on Leopard ([details](#libtpms-swtpm)) |
| [nrsc5](audio/nrsc5/Portfile) | 10.7 Lion | `>= 11` | `f3e7e7f` | libusb and doxygen fail on 10.5/10.6 ([details](#nrsc5)) |
| [vd_agent](sysutils/vd_agent/Portfile) | macOS 11 Big Sur | `>= 20` | `5d147a1` | Not recorded; the port also requires Xcode 15 or later |
| [netatalk_client](net/netatalk_client/Portfile) | macOS 12 Monterey | `>= 21` | `7f979a5` | Matches macFUSE 5.x's own minimum |
| [SwiftKHD](sysutils/SwiftKHD/Portfile) | macOS 13 Ventura | `>= 22` | `7400e96` | Upstream requires macOS 13 or later |
| [omlx-app](aqua/omlx-app/Portfile) | macOS 15 Sequoia | `>= 24` | `78b72ad` | Requires macOS 15; a `pre-fetch` check also enforces it |

## Legacy cutoffs in detail

These were set on 2026-10-23 after cache runs on the legacy VMs. The policy is
not to carry fixes for systems this old when a port fails there. Lion (10.7)
and later built every port below.

### libfido2

- **Leopard i386:** clang with `-Werror` rejects the 10.5-only compat code
  that `patch-hid_osx.diff` added to `src/hid_osx.c`. That code returns the
  address of a local buffer (`path`), reads the uninitialized `s`, and
  leaves `dev` unused.
- **Leopard PPC:** it only built because `patch-werror.diff` hid those errors,
  so the device-path function was probably broken there too.
- **Removed with the cutoff:** both 10.5-only patches and the Leopard workflow
  inputs.
- **Cache:** the PPC archive cached before the cutoff
  (`libfido2-1.17.0_0.darwin_9.ppc`) is still on `packages.jibb.tv`.

### libtpms, swtpm

- **libtpms on Leopard PPC (GCC 15):**
  `tpm2/RunCommand.c:105: 'noreturn' function does return [-Werror]`.
  `_plat__Fail()` is declared noreturn and ends in `longjmp()`, which Leopard's
  `<setjmp.h>` doesn't mark noreturn. `configure.ac` hardcodes `-Werror` in
  `AM_CFLAGS`.
- **swtpm:** depends on libtpms. On Leopard i386 it also needs libusb (below).
- **Snow Leopard:** built both, but the cutoff is Lion because 10.6 wasn't
  otherwise tested. swtpm's archive also failed to submit there.

### nrsc5

nrsc5 needs libusb through rtl-sdr, plus doxygen to build:

- **Leopard PPC:** upstream libusb fails in `os/darwin_usb.c:995`, because
  `kUSBVendorString` and the related IOKit constants aren't in the 10.5 SDK.
- **Leopard i386:** libusb's toolchain dependency `gcc15-libcxx` refuses to
  build while `libunwind-headers` is active.
- **Snow Leopard:** doxygen fails to build.

The port's `legacysupport` PortGroup only provided `strnlen` for darwin 10
and older, so it was removed with the cutoff.

## Adding a cutoff

1. Put `platforms {darwin >= N}` after `license` in the Portfile, with a
   one-line comment giving the reason.
2. Remove anything that only applied below the cutoff: `os.major` patch
   branches, patch files, and `legacysupport` lines that no longer apply.
3. Drop the inputs and matrix entries for the excluded systems from
   `.github/workflows/build-<port>.yml`.
4. Run `portindex`, then `port lint --nitpick <port>`.
5. Add a row here, plus a detail section if the reason takes more than a
   line.

## Darwin versions

| Darwin | macOS | Darwin | macOS |
|---|---|---|---|
| 9 | 10.5 Leopard | 20 | 11 Big Sur |
| 10 | 10.6 Snow Leopard | 21 | 12 Monterey |
| 11 | 10.7 Lion | 22 | 13 Ventura |
| 12 | 10.8 Mountain Lion | 23 | 14 Sonoma |
| 13 | 10.9 Mavericks | 24 | 15 Sequoia |
| 14 | 10.10 Yosemite | 25 | 26 Tahoe |
| 15 | 10.11 El Capitan | 27 | 27 (Darwin skipped 26) |
