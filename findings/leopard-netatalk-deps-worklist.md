# Worklist: netatalk dependencies that need fixes on Leopard

Started 2026-11-01. netatalk is identical to upstream (4.6.1), but on Mac OS
X 10.5 (i386 and ppc) it only builds because blakeports overrides some of
its dependencies with fixes that upstream doesn't have. This list works
through them one at a time, with the same discipline as
[icu](icu-libgcc-leopard.md), so each upstream PR is needed, minimal and
proven. Once a fix is upstream, its blakeports override is deleted.

## Method, per port

1. **Reproduce** with upstream's current Portfile, verbatim, built from
   source on cleaned Leopard VMs (i386 and ppc). Record the exact error and
   which compiler MacPorts picked.
2. **Root cause:** why that compiler, why it fails, and on which OS/arch/Xcode
   combinations it can happen. Check upstream (project issue tracker) and
   Trac for existing reports, PRs and fixes.
3. **Minimal fix**, conditioned on the actual cause rather than an OS
   version where possible. One change, nothing unrelated.
4. **Verify the fix** on the affected VMs from a clean install.
5. **Verify no change elsewhere:** the compiler each Portfile picks on every
   builder (no build needed), plus builds on every builder.
6. **Write up** the evidence in `findings/<port>-<topic>.md`.
7. **Draft** the commit message and PR text for review; nothing is posted
   without approval. Reference the Trac ticket; never mention blakeports.
8. After merge, **delete the override** from blakeports.

Tooling:

- The `Test port` workflow (`.github/workflows/test-port.yml`) builds one
  port on chosen runners from a `test/<port>` branch whose Portfile is
  upstream's verbatim, with the candidate change in `Portfile.fixed`
  (`-f portfile=tree|fixed`). Each job first reports the compiler both
  Portfiles pick on that runner (`scripts/portcompiler.tcl`).
- Run `MacPorts Cleanup` on the runners first.
- Trace mode is not evidence on these VMs (see
  [icu](icu-libgcc-leopard.md)); use build logs, `otool -L` and
  `port dependents`.

## Ports

| # | Port | blakeports fix | Arch (as found) | Trac | Maintainer | Status |
|---|---|---|---|---|---|---|
| 0 | icu | depend on libgcc under `macports-libstdc++` | i386 | none | mohd-akram | PR [#36312](https://github.com/macports/macports-ports/pull/36312) open |
| 1 | libarchive | `compiler.blacklist-append *gcc-4.2` (ICE in `archive_write_pax_header`) | ppc, i386 | [#74145](https://trac.macports.org/ticket/74145), [#74268](https://trac.macports.org/ticket/74268) open | tobypeterson | PR [#36316](https://github.com/macports/macports-ports/pull/36316) open ([findings](libarchive-gcc42-ice.md)) |
| 2 | libevent | patch: `#pragma GCC diagnostic` only for gcc ≥ 12 | ppc (i386 untested) | [#74414](https://trac.macports.org/ticket/74414) open | jerryyhom | to do |
| 3 | libgcrypt | widen `gcc-4.2` blacklist to `*gcc-4.2` (llvm-gcc-4.2 fails on McEliece asm) | i386 | none | Schamschula | to do |
| 4 | python314 | preset `-msse`/`-mavx2` checks to no on 10.5 (`_hmac` needs `posix_memalign`) | 10.5 | [#73578](https://trac.macports.org/ticket/73578) closed (`_blake2`, same family) | jmroot | to do |

Upstream has moved since the blakeports copies were made (libarchive
3.8.10 → 3.8.11, libgcrypt 1.12.3 → 1.12.4, python314 3.14.7 → 3.14.10), so
every failure is re-proven against the current upstream version first.

## 1. libarchive

Upstream: 3.8.11. Our comment on #74268 (2026-10-21) proposed blacklisting
gcc-4.2 on powerpc only; blakeports later hit the same ICE on Intel 10.5
and blacklisted it on every arch. libarchive closed
[#3189](https://github.com/libarchive/libarchive/issues/3189) as a gcc-4.2
bug, so no upstream source fix is coming.

Questions:

- [x] Does 3.8.11 still ICE with gcc-4.2? Yes, on both i386 and ppc,
      same line (`archive_write_set_format_pax.c:682`).
- [x] Which compilers does MacPorts try, in what order? See below. On
      Xcode 3.1 the next after `gcc-4.2` is `llvm-gcc-4.2`.
- [x] Is llvm-gcc-4.2 affected? No. It builds on i386 and ppc, the smoke
      test passes, and `port test` matches gcc-4.0 exactly.
- [x] Is `apple-gcc-4.2` affected? Treat as yes: #3189's reporter hit the
      ICE "on OS X 10.5 & 10.6 with GCC 4.2"; 10.6's Xcode 3.2 gcc-4.2 is
      build 5666.3, the same as the apple-gcc42 port.
- [x] Is the compiler unchanged on 10.6–10.11 and modern macOS? Yes on our
      builders (Xcode 4.2–8.2.1, CLT 26/27). Xcode 3.2 on 10.6 would move
      from gcc-4.2 (which ICEs) to llvm-gcc-4.2.
- [x] ballapete's gcc15 test failures on #74268? The same two tests fail on
      i386 with both gcc-4.0 and llvm-gcc-4.2 (957 run, 2 fail:
      `test_acl_platform_nfs4`, `test_read_disk_directory_traversals`), so
      they are 10.5 platform issues, independent of the compiler and of
      this fix.

Candidate: `compiler.blacklist-append gcc-4.2 apple-gcc-4.2`, blacklisting
exactly Apple's gcc-4.2 and letting base pick the next compiler, rather than
`*gcc-4.2` (which also drops llvm-gcc-4.2) or an OS/arch condition.

Compiler order (base 2.12.7, `get_apple_compilers_xcode_version`):
Xcode 3.1 (our 10.5 VMs): `gcc-4.2 llvm-gcc-4.2 apple-gcc-4.2 gcc-4.0`;
Xcode 3.2: `gcc-4.2 llvm-gcc-4.2 clang gcc-4.0`; Xcode 4.0–4.1:
`llvm-gcc-4.2 clang gcc-4.2`; Xcode 4.2: `llvm-gcc-4.2 clang`; Xcode
4.3–4.6: `clang llvm-gcc-4.2`; Xcode 5+: `clang`. On ppc, MacPorts gcc
comes before MacPorts clang in the fallback.

Runs:

| Run | Builders | Portfile | Result |
|---|---|---|---|
| [41350699595](https://github.com/trodemaster/blakeports/actions/runs/41350699595) | 10.6–10.11, 26, 27 | compiler check only, upstream and `*gcc-4.2` | Same compiler with both everywhere: 10.6 (Xcode 4.2) `macports-clang-3.7` (base already rules out llvm-gcc-4.2 and Xcode clang there), 10.7–27 `clang` |
| [41350828016](https://github.com/trodemaster/blakeports/actions/runs/41350828016) | 10.5 i386, cleaned | upstream 3.8.11 | **Fails**: picks `gcc-4.2`; `libarchive/archive_write_set_format_pax.c:682: internal compiler error: Bus error`. With `*gcc-4.2` it would pick `gcc-4.0` |
| [41350828016](https://github.com/trodemaster/blakeports/actions/runs/41350828016) | 10.5 ppc, cleaned | upstream 3.8.11 | **Fails** the same way: picks `gcc-4.2`; `archive_write_set_format_pax.c:682: internal compiler error: Bus error` |
| [41351520047](https://github.com/trodemaster/blakeports/actions/runs/41351520047) | 10.5 i386 | blacklist `gcc-4.2` only (picks `llvm-gcc-4.2`) | Builds and installs; `llvm-gcc-4.2` compiles `archive_write_set_format_pax.c` |
| [41351791328](https://github.com/trodemaster/blakeports/actions/runs/41351791328) | 10.5 i386 | same, plus smoke test and `port test` | Smoke test passes (pax round trip incl. a 120-char name). `port test`: 4 of 5 programs pass; `libarchive_test` fails `test_acl_platform_nfs4` (80) and `test_read_disk_directory_traversals` (3), the same tests ballapete reported failing with gcc15 on ppc in #74268 |
| [41352472924](https://github.com/trodemaster/blakeports/actions/runs/41352472924) | 10.5 i386 | `*gcc-4.2` (picks `gcc-4.0`), smoke test and `port test` | Smoke test passes. `port test`: same as llvm-gcc-4.2: 957 tests, the same 2 fail with the same counts (80, 3) |
| [41353225724](https://github.com/trodemaster/blakeports/actions/runs/41353225724) | 10.5 i386 and ppc | candidate `gcc-4.2 apple-gcc-4.2` (picks `llvm-gcc-4.2`), smoke test and `port test` | i386: builds, smoke test passes, `port test` 957 run / same 2 fail (80, 3). ppc job cancelled by the runner's SSH health check (fixed in actions_runners a8354f4) |
| [41353357546](https://github.com/trodemaster/blakeports/actions/runs/41353357546) | 10.5 ppc | candidate, retry | Builds with `llvm-gcc-4.2` (4 min), smoke test passes, `port test` 957 run / same 2 fail (80, 3) |

| [41357335230](https://github.com/trodemaster/blakeports/actions/runs/41357335230) | all 11 builders, cleaned | candidate | All build and pass the smoke test; only 10.5 changes compiler (`gcc-4.2` → `llvm-gcc-4.2`) |

Result: [libarchive-gcc42-ice.md](libarchive-gcc42-ice.md). The same ICE was
first reported as [#74145](https://trac.macports.org/ticket/74145)
(barracuda156, 3.8.8, ppc); the PR closes both tickets.
