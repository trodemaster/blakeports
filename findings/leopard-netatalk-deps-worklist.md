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
| 1 | libarchive | `compiler.blacklist-append *gcc-4.2` (ICE in `archive_write_pax_header`) | ppc, i386 | [#74268](https://trac.macports.org/ticket/74268) open | tobypeterson | **in progress** |
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

- [ ] Does 3.8.11 still ICE with gcc-4.2, on ppc and on i386?
- [ ] Which compilers does MacPorts try on 10.5 (Xcode 3.1.4) for this
      port, in what order? Is llvm-gcc-4.2 also affected, or only Apple
      gcc-4.2? That decides `gcc-4.2` versus `*gcc-4.2`.
- [ ] Does the compiler it falls back to build and pass a basic check on
      both arches?
- [ ] Is the compiler unchanged on 10.6–10.11 and modern macOS?
- [ ] Anything else on #74268 (ballapete's test failures with gcc15) that
      matters for the fix?

Runs: (none yet)
