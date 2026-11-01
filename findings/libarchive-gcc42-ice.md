# libarchive: Apple gcc-4.2 crashes compiling the pax writer

Date: 2026-11-01. MacPorts base 2.12.7, macports-ports at upstream master
(2026-11-01), libarchive 3.8.11_0.

## Summary

On Mac OS X 10.5 (Xcode 3.1.4), MacPorts builds libarchive with Apple's
`gcc-4.2`, which crashes on `libarchive/archive_write_set_format_pax.c` with
`internal compiler error: Bus error`, on both i386 and ppc. libarchive
doesn't build there at all.

The fix is one line, blacklisting exactly that compiler:

```tcl
# Apple gcc-4.2 crashes (Bus error) in archive_write_pax_header
# https://trac.macports.org/ticket/74268
compiler.blacklist-append gcc-4.2 apple-gcc-4.2
```

MacPorts then picks Xcode 3.1's `llvm-gcc-4.2` on 10.5, which builds it on
both arches. The compiler doesn't change on 10.6 through macOS 27 (on our
builders). Not a revision bump: the change only affects configurations that
failed to build.

Trac: [#74145](https://trac.macports.org/ticket/74145) (barracuda156,
3.8.8, ppc) and [#74268](https://trac.macports.org/ticket/74268)
(ballapete, 3.8.9/3.8.10, ppc), both open. Upstream closed
[libarchive#3189](https://github.com/libarchive/libarchive/issues/3189) as a
compiler bug ("triggers on OS X 10.5 & 10.6 with GCC 4.2"), so no source fix
is coming.

## Why these compilers

MacPorts picks the first usable compiler from a list that depends on the
Xcode version (`portconfigure::get_apple_compilers_xcode_version`, base
2.12.7):

| Xcode | Order |
|---|---|
| 3.1 (10.5) | `gcc-4.2 llvm-gcc-4.2 apple-gcc-4.2 gcc-4.0` |
| 3.2 (10.6) | `gcc-4.2 llvm-gcc-4.2 clang gcc-4.0` |
| 4.0–4.1 | `llvm-gcc-4.2 clang gcc-4.2` |
| 4.2 | `llvm-gcc-4.2 clang` |
| 4.3–4.6 | `clang llvm-gcc-4.2` |
| 5+ | `clang` |

- `gcc-4.2` is Apple's GCC 4.2.1 (build 5577 in Xcode 3.1, 5666.3 in Xcode
  3.2). `apple-gcc-4.2` is the apple-gcc42 port, also build 5666.3. #3189's
  reporter hit the crash with GCC 4.2 on both 10.5 and 10.6, so both are
  blacklisted.
- `llvm-gcc-4.2` is a different compiler (GCC front end, LLVM back end) and
  is not affected; see below. Blacklisting `*gcc-4.2` would also drop it and
  push 10.5 to `gcc-4.0`, which works too but isn't needed.
- On our 10.6 VM (Xcode 4.2), base already rules out llvm-gcc-4.2 and Xcode's
  clang for libarchive and picks `macports-clang-3.7`, with or without the
  blacklist.

## Evidence

All runs used the `Test port` workflow from the `test/libarchive` branch,
where `archivers/libarchive/Portfile` was upstream's file verbatim and
`Portfile.fixed` the candidate. Each job reports the compiler both Portfiles
pick on that machine (`scripts/portcompiler.tcl`, no build) before building.

| Run | Builders | Portfile | Result |
|---|---|---|---|
| [41350828016](https://github.com/trodemaster/blakeports/actions/runs/41350828016) | 10.5 i386 and ppc, cleaned | upstream | **Fails** on both: picks `gcc-4.2`; `libarchive/archive_write_set_format_pax.c:682: internal compiler error: Bus error` |
| [41351791328](https://github.com/trodemaster/blakeports/actions/runs/41351791328) | 10.5 i386 | `gcc-4.2` blacklisted (picks `llvm-gcc-4.2`) | Builds; smoke test passes; `port test`: 957 tests, 2 fail |
| [41352472924](https://github.com/trodemaster/blakeports/actions/runs/41352472924) | 10.5 i386 | `*gcc-4.2` blacklisted (picks `gcc-4.0`) | Builds; smoke test passes; `port test`: the same 2 of 957 fail, same counts |
| [41353225724](https://github.com/trodemaster/blakeports/actions/runs/41353225724) | 10.5 i386 | candidate (picks `llvm-gcc-4.2`) | Builds; smoke test passes; `port test` the same |
| [41353357546](https://github.com/trodemaster/blakeports/actions/runs/41353357546) | 10.5 ppc | candidate (picks `llvm-gcc-4.2`) | Builds; smoke test passes; `port test` the same |
| [41357335230](https://github.com/trodemaster/blakeports/actions/runs/41357335230) | all 11 builders, cleaned first ([cleanup](https://github.com/trodemaster/blakeports/actions/runs/41357219792)) | candidate | All build and pass the smoke test. Compiler, upstream → candidate: 10.5 i386 and ppc `gcc-4.2` → `llvm-gcc-4.2`; 10.6 `macports-clang-3.7` both; 10.7–10.11, 15, 26, 27 `clang` both |

The smoke test writes a pax archive with `bsdtar --format pax` (a regular
file, 256 KiB of random data, a symlink and a 120-character name, which needs
a pax extended header), lists it, extracts it and compares with `diff -r`.

`port test` on 10.5 fails `test_acl_platform_nfs4` (80 failures) and
`test_read_disk_directory_traversals` (3 failures) with every working
compiler (`llvm-gcc-4.2` on i386 and ppc, `gcc-4.0` on i386), and
ballapete's gcc15 build on #74268 failed the same tests. They are 10.5
platform behaviour, unrelated to the compiler and to this fix.

Submitted 2026-11-01 as
[macports/macports-ports#36316](https://github.com/macports/macports-ports/pull/36316).

## Alternatives considered

- **`*gcc-4.2`** (falls back to `gcc-4.0`): builds and tests the same on
  i386, and is what blakeports used first. Not chosen because it also drops
  `llvm-gcc-4.2`, which works; the narrow blacklist removes only the broken
  compiler and keeps base's own order.
- **A bootstrap compiler** (`clang-11-bootstrap` on Intel, `gcc10-bootstrap`
  on ppc, since clang-11-bootstrap has no ppc support). No dependency cycle
  (both build only from bootstrap ports), but upstream uses them where a port
  needs a newer compiler than the system has and sits under MacPorts clang
  (openssl3, libressl, icu, libomp, libcxx, libtapi). libarchive builds with
  the Xcode compilers, and there are no 10.5 binaries, so every 10.5 user
  would build gcc10-bootstrap (and on Intel clang-11-bootstrap) first, under
  cmake's whole dependency tree. For cmake's dependencies on old systems
  upstream keeps clang-3.7 (`lang/llvm-3.7`: "kept around in order to build
  cmake (or its dependencies)"), which is what 10.6 already uses here.

## Notes

- The blakeports override is upstream's 3.8.11 port plus exactly this
  change (it was 3.8.10 with `*gcc-4.2` before this analysis). Delete it
  once the fix is merged upstream.
- Our comment on #74268 (2026-10-21) suggested blacklisting on powerpc only.
  The crash happens on i386 too, so the fix isn't arch-specific.
