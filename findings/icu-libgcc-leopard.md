# icu: missing libgcc dependency with clang-11-bootstrap on 10.5

Date: 2026-11-01. MacPorts base 2.12.7, macports-ports at
[ea18740b9ed](https://github.com/macports/macports-ports/commit/ea18740b9ed)
(2026-10-27), icu and icu-devel 78.3_1.

## Summary

On Intel Mac OS X 10.5, the upstream icu and icu-devel ports build with
clang-11-bootstrap against libgcc's libstdc++, link
`${prefix}/lib/libgcc/libstdc++.6.dylib`, and don't declare a dependency on
libgcc. A from-source install on a system without libgcc fails to compile.
Where libgcc is already installed the build succeeds, but libgcc can then be
uninstalled out from under icu, which breaks icu and everything linked to it.

The fix is one dependency line in each port:

```tcl
            # add_deps no also skips the libgcc dependency base adds for
            # macports-libstdc++ (the default on 10.5)
            if {${configure.cxx_stdlib} eq "macports-libstdc++"} {
                depends_lib-append path:lib/libgcc/libgcc_s.1.dylib:libgcc
            }
```

It goes inside the existing clang-11-bootstrap block (darwin 9–17, x86_64 or
i386). It changes nothing for default 10.6+ setups.

## Cause

1. icu uses clang-11-bootstrap on 10.13 and older Intel systems
   ([#71616](https://trac.macports.org/ticket/71616)) and sets
   `configure.compiler.add_deps no` so base doesn't add a dependency on the
   macports-clang port it would otherwise pick.
2. `add_deps no` makes base skip all of
   `portconfigure::add_compiler_port_dependencies`, not just the compiler
   port. For a macports-clang compiler that proc also adds
   `path:lib/libgcc/libgcc_s.1.dylib:libgcc` when `configure.cxx_stdlib` is
   `macports-libstdc++`
   ([#54766](https://trac.macports.org/ticket/54766)), and `port:libcxx` for
   libc++ before 10.7:

   ```tcl
   # port1.0/portconfigure.tcl, add_compiler_port_dependencies (2.12.7)
   if {${configure.cxx_stdlib} eq "macports-libstdc++"} {
       # see https://trac.macports.org/ticket/54766
       depends_lib-append "path:lib/libgcc/libgcc_s.1.dylib:libgcc"
   } elseif {${configure.cxx_stdlib} eq "libc++" && ${os.major} < 11} {
       depends_lib-append "port:libcxx"
   }
   ```

3. `configure.cxx_stdlib` is `macports-libstdc++` whenever `cxx_stdlib` is
   `libstdc++` and `compiler.cxx_standard` is 2011 or later
   (`portconfigure::configure_get_cxx_stdlib`). icu sets 2017. The default
   `cxx_stdlib` is `libstdc++` only on darwin < 10
   (`macports1.0/macports.tcl`), so by default this hits 10.5 only. On 10.6+
   it applies to anyone who sets `cxx_stdlib libstdc++` in macports.conf.
4. clang-11-bootstrap is patched so `-stdlib=macports-libstdc++` uses headers
   from `${prefix}/include/gcc/c++` and links
   `${prefix}/lib/libgcc/libstdc++.6.dylib`, both installed by libgcc. It is
   statically linked itself and doesn't depend on libgcc, so nothing pulls
   libgcc in.

Upstream already handles the same situation in
[libtapi](https://github.com/macports/macports-ports/blob/master/devel/libtapi/Portfile):
it uses clang-11-bootstrap with `add_deps no` and then re-adds its stdlib with
`configure.cxx_stdlib libc++` and `depends_lib-append port:libcxx`.

## Evidence

All builds ran in blakeports CI on the legacy VMware VMs (Intel, i386 on
10.5), each started from a cleaned MacPorts install. The test harness lived on
the `test/icu-libgcc` branch: `devel/icu/Portfile` there was upstream's file
verbatim, with the fixed version alongside as `Portfile.fixed`.

| Run | OS | icu Portfile | Setup | Result |
|---|---|---|---|---|
| [R1](https://github.com/trodemaster/blakeports/actions/runs/41282884939) | 10.5 | upstream | libgcc not installed | **Build fails**: `../common/unicode/localpointer.h:45:10: fatal error: 'memory' file not found`; `CXXFLAGS='-pipe -Os -stdlib=macports-libstdc++ ...'`; deps evaluated: clang-11-bootstrap, cctools, python27 |
| [R2](https://github.com/trodemaster/blakeports/actions/runs/41283331785) | 10.5 | upstream | libgcc preinstalled | Builds; `libicuuc` links `/opt/local/lib/libgcc/libstdc++.6.dylib (compatibility version 7.0.0, current version 7.34.0)` |
| [Harm](https://github.com/trodemaster/blakeports/actions/runs/41284402156) | 10.5 | upstream (from R2) | uninstall libgcc | `libgcc has no dependents.`; `port uninstall libgcc libgcc15` succeeds; `uconv --version` dies with `dyld: Symbol not found: __ZSt14__once_functor` / `Expected in: /usr/lib/libstdc++.6.dylib`; `port rev-upgrade`: `Found 22 broken files`, icu among them |
| [R4](https://github.com/trodemaster/blakeports/actions/runs/41284402156) | 10.5 | fixed | same VM, after the harm test | Builds; `scripts/install-deps icu` now resolves `clang-11-bootstrap cctools python27 libgcc` (upstream: the first three only) |
| [Fixed harm](https://github.com/trodemaster/blakeports/actions/runs/41285420481) | 10.5 | fixed | uninstall libgcc | `icu depends on libgcc`; `Unable to uninstall libgcc @15_0, the following ports depend on it`; `uconv` runs; `No broken files found.` |
| [main](https://github.com/trodemaster/blakeports/actions/runs/41331149979) | 10.5 | fixed (blakeports 03e4c1c) | libgcc not installed | Builds from a cleaned install; `install-deps` resolves `clang-11-bootstrap cctools python27 libgcc`, compiles with `-stdlib=macports-libstdc++` |
| [main](https://github.com/trodemaster/blakeports/actions/runs/41331149979) | 10.6, 26, 27 | fixed (blakeports 03e4c1c) | default | Builds; 10.6 uses `-stdlib=libc++` and resolves no libgcc |
| [all](https://github.com/trodemaster/blakeports/actions/runs/41342698146) | 10.5–10.11, 26, 27 | fixed (blakeports 181ca2e) | every builder cleaned first ([cleanup](https://github.com/trodemaster/blakeports/actions/runs/41342608843)) | All build. Only 10.5 compiles with `-stdlib=macports-libstdc++` and resolves libgcc (`clang-11-bootstrap cctools python27 libgcc`); 10.6 resolves `clang-11-bootstrap cctools python27`, 10.7–10.11 `clang-11-bootstrap`, all with `-stdlib=libc++` |
| [ppc](https://github.com/trodemaster/blakeports/actions/runs/41342971337) | 10.5 PPC | fixed (blakeports 181ca2e) | cleaned first | Builds with `g++-mp-15` (not the clang-11-bootstrap path); libgcc comes from base's normal gcc15 dependencies, so the fix doesn't apply |
| [C1](https://github.com/trodemaster/blakeports/actions/runs/41282890323) | 10.6 | upstream | default | Builds with `-stdlib=libc++`, links `/usr/lib/libc++` (libcxx comes in through icu's declared dependencies) |
| [C2](https://github.com/trodemaster/blakeports/actions/runs/41282890323) | 10.11 | upstream | default | Builds with the system libc++ |
| [Fixed harm](https://github.com/trodemaster/blakeports/actions/runs/41285420481) | 10.6 | fixed | default | Same result as upstream; libgcc not added |

Other checks:

- **The R1 failure is what a real user gets, not an artifact of our setup.**
  On the 10.5 VM, upstream icu's full from-source dependency closure
  (`port rdeps --full`, 44 ports) and its runtime-only closure (`--no-build`)
  contain no libgcc. Nothing else in the build pulls it in.
- **The guard must be `configure.cxx_stdlib`, not the OS version.** Evaluated
  (not built) on 10.6 with a temporary alternate macports.conf
  (`PORTSRC`) setting `cxx_stdlib libstdc++`: `configure.cxx_stdlib` becomes
  `macports-libstdc++`, so the same missing dependency applies. A
  `${os.major} < 10 && ...` condition adds no libgcc there; the
  `configure.cxx_stdlib`-only condition does. With the default config both
  forms add nothing on 10.6.
- **The error text matches unrelated tickets.**
  [#70878](https://trac.macports.org/ticket/70878) and
  [#71782](https://trac.macports.org/ticket/71782) (closed as a duplicate)
  show the same `'memory' file not found`, but they are macOS 15 header
  problems. No ticket covers icu on 10.5 as of 2026-11-01.
  [#65795](https://trac.macports.org/ticket/65795) (harfbuzz-icu, 10.5 i386)
  is unrelated.

## Things that turned out wrong along the way

- **"10.5 has only the gcc 4.0 C++ headers, which lack `<memory>`."** That
  was the first explanation, and it shaped the earlier `os.major < 10` guard
  (blakeports ef1cb48). The compiler isn't using system headers at all:
  `-stdlib=macports-libstdc++` points it at libgcc's headers, which simply
  aren't installed. The OS only matters because it picks the default
  `cxx_stdlib`.
- **Trace mode proves nothing on these VMs.** R2 ran under `port -t` and
  linked libgcc's libstdc++ without a complaint. A test port with no
  dependencies (`tracecheck` on the test branch) then read
  `/opt/local/bin/curl` under `-t` on both 10.5 and 10.6 without being stopped
  ([run](https://github.com/trodemaster/blakeports/actions/runs/41285420481)).
  Trace still applied its own deny rules (`/Library/Frameworks`), but it did
  not hide files from ports outside the dependency tree. Separately, `-j8`
  builds under trace on 10.5 die with `execvp: /bin/sh: Bad file descriptor`;
  `build.jobs=1` avoids that. Dependency proofs on these VMs should use
  `otool -L`, `port dependents`, and an uninstall plus `port rev-upgrade`, as
  above.

## Upstream

- The fix applies identically to `devel/icu/Portfile` and
  `devel/icu-devel/Portfile`; their clang-11-bootstrap blocks are the same.
- Revision bump: where icu already built, the installed files are unchanged;
  only the registered dependency differs, and only for `macports-libstdc++`
  configurations. A bump would rebuild icu and its many dependents on every
  OS to record a dependency on 10.5. Leave that call to the maintainers.
- blakeports carries its icu override only until upstream has the fix; then
  `devel/icu` comes out of blakeports.
