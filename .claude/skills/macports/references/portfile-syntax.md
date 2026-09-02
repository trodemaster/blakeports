# Portfile Syntax Reference

Comprehensive guide to Portfile structure, syntax, and common patterns.

## Table of Contents
- [Basic Structure](#basic-structure)
- [Required Fields](#required-fields)
- [PortGroups](#portgroups)
- [Dependencies](#dependencies)
- [Build Configuration](#build-configuration)
- [Variants](#variants)
- [Platform Checks](#platform-checks)
- [Common Patterns](#common-patterns)

## Basic Structure

### Standard Portfile template
```tcl
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4

PortSystem          1.0
PortGroup           github 1.0

github.setup        owner repo version
revision            0

categories          category subcategory
maintainers         {@username domain} openmaintainer
license             MIT

description         Short one-line description

long_description    {*}${description}. Extended description providing \
                    more detail about the software and its capabilities.

checksums           rmd160  HASH \
                    sha256  HASH \
                    size    SIZE

depends_build-append \
                    path:bin/pkg-config:pkgconfig

depends_lib-append  port:openssl \
                    port:zlib

configure.args      --enable-feature \
                    --disable-other

variant feature description {
    configure.args-append --with-feature
    depends_lib-append port:feature-lib
}

notes "
    Post-installation instructions for users.
"
```

## Required Fields

### PortSystem
```tcl
PortSystem          1.0                # Always required, always 1.0
```

### Name and Version
```tcl
# Standard naming
name                myport
version             1.2.3
revision            0                  # Increment for Portfile changes without version bump

# Using github PortGroup (sets name and version)
github.setup        owner repo 1.2.3
github.setup        owner repo 1.2.3 v  # With version prefix (v1.2.3)
```

### Categories
```tcl
categories          devel               # Single category
categories          net security        # Multiple categories (first is primary)
```

### Maintainers
```tcl
maintainers         {@username provider} openmaintainer
maintainers         {@user1 domain} {@user2 domain} openmaintainer
maintainers         nomaintainer        # No active maintainer
```

Common providers: `github`, `icloud.com`, `gmail`, domain names

### License
```tcl
license             MIT
license             GPL-3
license             {GPL-2+ BSD}        # Dual licensed
license             Apache-2
license             public-domain
```

### Description
```tcl
description         Brief one-line description of the software

long_description    {*}${description}. Extended description with more \
                    detail about features, capabilities, and use cases. \
                    Wrap lines at 80 characters using backslash.
```

### Homepage
```tcl
homepage            https://example.com

# Automatically set by github PortGroup:
# homepage          https://github.com/owner/repo
```

### Master Sites and Checksums
```tcl
# Manual distfile specification
master_sites        https://example.com/releases/
distname            ${name}-${version}

# Checksums (required)
checksums           rmd160  1234567890abcdef1234567890abcdef12345678 \
                    sha256  abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab \
                    size    123456

# GitHub PortGroup automatically sets master_sites from github.setup
```

## PortGroups

### github 1.0
```tcl
PortGroup           github 1.0

github.setup        owner repo 1.2.3        # Basic setup
github.setup        owner repo 1.2.3 v      # Version prefix (v1.2.3)
github.tarball_from releases                # Use releases instead of tarball
github.tarball_from archive                 # Use archive (default)
```

**Which `tarball_from` to use:**
- `archive` (default) — git-generated tarball of the tag. Fine for most ports.
- `releases` — an explicit release asset the maintainer uploaded. Prefer this when it
  exists: release assets are immutable, whereas git-generated tarballs have historically
  changed bytes for the same tag ("stealth" distfile changes).
- `tarball` — deprecated, do not use in new ports.

When using `releases` and the asset filename carries a tag prefix or doesn't match the
repo name, set `distname` explicitly:

```tcl
github.setup        translate translate 2.4.0
github.tarball_from releases
distname            translate-toolkit-${version}
```

### obsolete 1.0
For retiring a port. Keep the port name and version, bump `revision` by 1, delete all
other code and the `files/` directory.

```tcl
PortGroup           obsolete 1.0
# port to be removed after 2026-06
replaced_by         newportname            # omit if nothing replaces it
```

### stub 1.0
For a port that produces no meaningful build output (umbrella/metapackage, or a
`*_select` base port).

```tcl
PortGroup           stub 1.0
```

### makefile 1.0
For projects with a plain `Makefile` and no configure script.

```tcl
PortGroup           makefile 1.0
```

Pre-PortGroup idiom (still seen in older Portfiles):

```tcl
use_configure       no
build.args-append   CC=${configure.cc} \
                    CFLAGS="${configure.cflags}" \
                    LDFLAGS="${configure.ldflags}"
destroot.args       prefix=${destroot}${prefix}
```

### conflicts_build 1.0
Declare ports that must NOT be active during the build (headers/libs that would be
picked up wrongly), without making them runtime conflicts.

```tcl
PortGroup           conflicts_build 1.0
conflicts_build     someport
```

### select 1.0
Debian-style alternatives for CLI commands. Create a base port (e.g. `foo_select`, use
the `stub` PortGroup) with one subport per provider; users switch with:

```bash
port select --list foo
port select --set  foo foo-3.9
port select --show foo
```

### cmake 1.1
```tcl
PortGroup           cmake 1.1

# Automatically configures CMake build
# Sets configure.cmd to cmake
# Sets up build directory
```

### python 1.0
```tcl
PortGroup           python 1.0

python.versions     39 310 311 312
python.default_version 311

# Creates subports: py39-name, py310-name, py311-name, py312-name
```

### compiler_blacklist_versions 1.0
```tcl
PortGroup           compiler_blacklist_versions 1.0

# Blacklist compilers that don't work
compiler.blacklist-append {clang < 700}
```

### legacysupport 1.1
```tcl
PortGroup           legacysupport 1.1

# Adds compatibility shims for older macOS
legacysupport.newest_darwin_requires_legacy 13  # macOS 10.9 and older need support
```

### Active use flag
```tcl
PortGroup           active_variants 1.1

# Require dependency built with specific variant
require_active_variants openssl quic
```

## Dependencies

### Build dependencies
```tcl
depends_build-append \
                    path:bin/pkg-config:pkgconfig
```

Used only during compilation, not installed in the final environment.

**Don't add `port:autoconf`/`port:automake`/`port:libtool` here if `use_autoreconf`, `use_autoconf`, or `use_automake` is set** — MacPorts base (`portconfigure.tcl`) adds those deps for you automatically. Declaring them manually is redundant and gets flagged in review. Only add them explicitly if the port needs autotools *without* setting one of those `use_*` options.

### Library dependencies
```tcl
depends_lib-append  port:openssl \
                    port:zlib \
                    path:lib/libssl.dylib:openssl
```

Linked libraries required at runtime.

### Runtime dependencies
```tcl
depends_run-append  port:python311 \
                    port:bash
```

Required at runtime but not linked.

### Extract dependencies
```tcl
depends_extract-append \
                    port:unzip
```

### Fetch dependencies
```tcl
depends_fetch-append \
                    port:wget
```

### Path-based dependencies
```tcl
depends_lib-append  path:lib/libssl.dylib:openssl
depends_lib-append  path:bin/perl:perl5
```

Use `path:` when a file has multiple possible providers (e.g. `libssl` from `openssl`
*or* `libressl`) — the port after the last `:` is only the fallback to install if the
file is missing, not a hard requirement on that specific port.

### Undeclared ("opportunistic") dependencies
A build may pick up a library that is installed but not declared in the Portfile. It
works on your machine and breaks for anyone who later uninstalls that port. Fix it by
either declaring the real dependency (`depends_lib-append port:foo`) or explicitly
disabling the optional feature (`configure.args-append --disable-foo`). Trace mode finds
these — see debugging.md.

### Conflicts must be declared on BOTH sides
`conflicts` is only checked against currently-active ports. If port A conflicts with
port B, put `conflicts B` in A *and* `conflicts A` in B, or the collision is missed
depending on install order.

```tcl
# in portA/Portfile
conflicts           portB
```

**How resolution actually works** (from MacPorts base, `macports.tcl` `_mportispresent`):
1. MacPorts first checks its install receipt — is the literal named port (e.g. `pkgconfig`) already active?
2. If not, and the depspec has a `lib:`/`bin:`/`path:` prefix, it falls back to a **filesystem existence test** (`_libtest`/`_bintest`/`_pathtest`) — does the file exist anywhere under `${prefix}`, regardless of which port put it there?
3. Only a bare `port:foo` depspec requires that *specific* port — there's no fallback check.

The `:portname` suffix on a `path:`/`lib:`/`bin:` spec is only the **fallback provider** — used to install something if the file is missing, not the primary check.

**Practical effect:** path-style depends are satisfied by *anything* that provides the file (another port, a variant, the base OS), so they avoid forcing installation of one specific port when the actual build requirement is just "this file exists." Use `port:` only when you genuinely need that specific named port active.

**Standard idiom — always use path-style for these two** (confirmed as the dominant convention across macports-ports, and what reviewers flag if you use `port:` instead):
```tcl
depends_build-append \
                    path:bin/pkg-config:pkgconfig

depends_lib-append  path:lib/pkgconfig/glib-2.0.pc:glib2
```

## Build Configuration

### Configure arguments
```tcl
configure.args      --prefix=${prefix} \
                    --enable-feature \
                    --disable-other \
                    --with-ssl=${prefix}

# Remove default args
configure.args-delete --enable-nls

# Append args
configure.args-append --with-extra
```

### Build arguments
```tcl
build.args          VERBOSE=1
build.target        all
```

### Install arguments
```tcl
destroot.args       PREFIX=${destroot}${prefix}
destroot.destdir    DESTDIR=${destroot}
```

### Build systems

#### Autotools
```tcl
use_autoconf        yes
use_automake        yes
use_autoreconf      yes

# Custom configure
configure.cmd       ./autogen.sh
```

Each `use_*` option above automatically adds the matching `port:autoconf`/`port:automake`/`port:libtool` to `depends_build` — do not declare those deps yourself alongside these options (see [Dependencies](#dependencies)).

Set `use_autoreconf yes` whenever a `patchfiles` entry touches `configure.ac`,
`Makefile.am`, or `configure.in` — the generated `configure`/`Makefile.in` must be
rebuilt from the patched sources. Release tarballs usually ship a pre-built `configure`
so this isn't needed; git checkouts and `-devel` ports usually are.

#### CMake
```tcl
PortGroup           cmake 1.1

configure.args-append \
                    -DENABLE_FEATURE=ON \
                    -DBUILD_SHARED_LIBS=ON

# Override the PortGroup default build type (default is usually MinSizeRel/RelWithDebInfo)
cmake.build_type    Release

# Point CMake at a dependency installed under a versioned subdir (e.g. libfmt9)
depends_lib-append  port:libfmt9
cmake.module_path-append \
                    ${prefix}/lib/libfmt9/cmake
```

#### Meson
```tcl
PortGroup           meson 1.0

configure.args-append \
                    -Dfeature=enabled
```

#### Custom build
```tcl
use_configure       no

build {
    system -W ${worksrcpath} "${configure.cc} -o ${name} ${name}.c"
}

destroot {
    xinstall -m 755 ${worksrcpath}/${name} ${destroot}${prefix}/bin/
}
```

## Variants

### Basic variant
```tcl
variant feature description {
    configure.args-append --with-feature
}
```

### Variant with dependencies
```tcl
variant gui description {Enable GUI support} {
    depends_lib-append port:gtk3
    configure.args-replace --disable-gui --enable-gui
}
```

### Default variant
```tcl
default_variants    +ssl +iconv
```

### Conflicting variants
```tcl
variant mysql57 conflicts mysql8 description {Use MySQL 5.7} {
    depends_lib-append port:mysql57
}

variant mysql8 conflicts mysql57 description {Use MySQL 8.0} {
    depends_lib-append port:mysql8
}
```

### Universal variant
```tcl
# Enable universal binary support
universal_variant   yes

# Disable universal binary support
universal_variant   no
```

## Platform Checks

### Darwin version checks
```tcl
platform darwin {
    # All macOS versions
}

platform darwin 20 {
    # macOS 11 (Big Sur)
}

platform darwin {
    if {${os.major} >= 20} {
        # macOS 11 and newer
        configure.args-append --enable-modern-feature
    }
}
```

Darwin version mapping:
- 19 = macOS 10.15 (Catalina)
- 20 = macOS 11 (Big Sur)
- 21 = macOS 12 (Monterey)
- 22 = macOS 13 (Ventura)
- 23 = macOS 14 (Sonoma)
- 24 = macOS 15 (Sequoia)

### Architecture checks
```tcl
platform darwin {
    if {${build_arch} eq "arm64"} {
        # Apple Silicon specific
    }
    
    if {${build_arch} eq "x86_64"} {
        # Intel specific
    }
}
```

### Requiring a modern C++ standard on older OS versions
Prefer `compiler.cxx_standard` over a hand-rolled `compiler.blacklist` — it picks a
capable compiler and pulls in the build dependency automatically.

```tcl
compiler.cxx_standard 2017
```

### Declaring a port unbuildable on some OS versions
`known_fail yes` marks the port as expected-to-fail (keeps it out of buildbot noise);
the `pre-fetch` abort gives the user a clear message instead of a deep build error.

```tcl
if {${os.platform} eq "darwin" && ${os.major} < 18} {
    known_fail      yes
    pre-fetch {
        ui_error "${name} @${version} requires macOS 10.14 or later."
        return -code error "incompatible macOS version"
    }
}
```

### Applying a fix only on certain OS versions
```tcl
if {${os.platform} eq "darwin" && ${os.major} >= 22} {
    patchfiles-append   patch-ventura-and-newer.diff
}
```

## Common Patterns

### Patches
```tcl
patchfiles          patch-fix-build.diff \
                    patch-disable-tests.diff

# Patch from files/ directory, applied automatically
```

### Post-patch modifications
```tcl
post-patch {
    reinplace "s|/usr/local|${prefix}|g" ${worksrcpath}/Makefile
    reinplace "s|python|python${python.version}|g" ${worksrcpath}/setup.py
}
```

### Placeholder patches
Keep `${prefix}` out of the committed `.diff` so it stays portable and easy to rebase:

```tcl
patchfiles          patch-deps-tool-path.diff   # contains @@PREFIX@@

post-patch {
    reinplace -W ${worksrcpath} "s|@@PREFIX@@|${prefix}|g" deps/build_deps.sh
}
```

When resolving a patch conflict later, restore the `@@PREFIX@@` token — don't leave your
local `/opt/local` baked into the diff.

### Tcl in Portfiles
```tcl
# Derive a value from the version
version             0.3.8
set branch          [join [lrange [split ${version} .] 0 1] .]   # -> 0.3
master_sites        https://example.com/download/${branch}/

# Loop over matched files, templating a shim into place
foreach bin [glob -tails -directory ${destroot}${prefix}/libexec/bin dart?*] {
    xinstall -m 0755 ${filespath}/shim.in ${destroot}${prefix}/bin/${bin}
    reinplace "s|@@BIN@@|${prefix}/libexec/bin/${bin}|g" ${destroot}${prefix}/bin/${bin}
}

# Expand a glob into separate arguments (works in xinstall/move/copy/delete too)
xinstall -m 0755 {*}[glob ${worksrcpath}/target/*/release/${name}-{a,b}] \
    ${destroot}${prefix}/bin/
```

Use `notes { ... }` (braces) rather than `notes " ... "` when the text contains `$`,
`[`, or backslashes you don't want substituted.

### Custom extract
```tcl
extract.mkdir       yes
extract.only        ${distname}${extract.suffix}
```

### Non-standard distfile / worksrcdir
```tcl
extract.suffix      .tgz                  # non-.tar.gz archive extension
worksrcdir          ${distname}/src       # build happens in a subdir of the extract
```

Choose between overriding `distname` and overriding `distfiles` based on what
`worksrcdir` needs to end up being.

### Stealth distfile updates
When upstream replaces the bytes of a distfile at the *same URL* (checksums suddenly
mismatch and you did not change `version`), don't just update the checksums — old
downloads and mirrors still disagree. Bump into a versioned subdir:

```tcl
# Stealth update YYYY-MM-DD; remove on next version bump
dist_subdir         ${name}/${version}_1
```

Or pin to the MacPorts mirror copy and ignore upstream churn entirely:

```tcl
master_sites        macports_distfiles
```

### Sharing a distfile cache across ports
```tcl
dist_subdir         ruby                  # several ports fetch the same tarball once
```

### Multiple distfiles
Tag each `master_sites`/`distfiles` entry and give each file its own `checksums` block
(filename first):

```tcl
github.setup        joshkunz ashuffle 3.13.3 v
github.tarball_from archive
master_sites        ${github.master_sites}:ashuffle
distfiles           ${distname}${extract.suffix}:ashuffle

checksums           ${distname}${extract.suffix} \
                    rmd160  aaaa... \
                    sha256  bbbb... \
                    size    85824
```

The same applies when a `patchfiles` entry needs to be downloaded (tag it and add a
`checksums` block).

### Dummy master_sites URL
When the download URL cannot end in the filename:

```tcl
master_sites        https://example.com/source/download/${commit}/?dummy=
```

### Git submodules in an incomplete tarball
```tcl
fetch.type          git
post-fetch {
    system -W ${worksrcpath} "git submodule update --init --recursive"
}
```

### Not clobbering user config on upgrade
```tcl
post-destroot {
    move ${destroot}${prefix}/etc/foo.conf \
         ${destroot}${prefix}/etc/foo.conf.sample
}
post-activate {
    if {![file exists ${prefix}/etc/foo.conf]} {
        copy ${prefix}/etc/foo.conf.sample ${prefix}/etc/foo.conf
    }
}
```

### Preserving empty directories
`destroot` drops empty dirs. Keep ones the program expects for user files:

```tcl
destroot.keepdirs-append \
                    ${destroot}${prefix}/etc/haproxy
```

### Binary-archive distributability
`license` controls whether MacPorts may distribute a prebuilt archive of the port. When
copying another port's Portfile, re-check its license against the actual source.

```bash
port_binary_distributable.tcl -v <portname>   # why a port is / isn't distributable
```

```tcl
license_noconflict  somedep      # suppress a false-positive license conflict with a dep
```

### Case-sensitive filesystem
The MacPorts buildbot runs on case-sensitive filesystems; a port that only builds on the
default case-insensitive macOS FS will fail there. Watch buildbot for
case-sensitivity-only failures.

### Post-destroot
```tcl
post-destroot {
    # Install documentation
    xinstall -d ${destroot}${prefix}/share/doc/${name}
    xinstall -m 644 {*}[glob ${worksrcpath}/docs/*.md] \
        ${destroot}${prefix}/share/doc/${name}
    
    # Install example configs
    xinstall -d ${destroot}${prefix}/etc/${name}
    xinstall -m 644 ${worksrcpath}/example.conf \
        ${destroot}${prefix}/etc/${name}/example.conf.sample
}
```

### Livecheck
```tcl
# GitHub releases
github.livecheck.regex {([0-9.]+)}

# Custom regex
livecheck.type      regex
livecheck.url       ${homepage}/downloads/
livecheck.regex     ${name}-(\[0-9.\]+)${extract.suffix}

# Disable livecheck
livecheck.type      none
```

### Subports
```tcl
subport ${name}4 {
    version         4.0.0
    revision        0
    
    conflicts       ${name}3
    
    checksums       rmd160  ... \
                    sha256  ... \
                    size    ...
}

if {${subport} eq ${name}} {
    # Main port specific
} else {
    # Subport specific
}
```

### Notes
```tcl
notes "
To use ${name}, add the following to your shell profile:

    export PATH=${prefix}/libexec/${name}/bin:\$PATH

Then run: ${name} --help
"
```

### Test phase
```tcl
test.run            yes
test.target         check

# Custom test
test {
    system -W ${worksrcpath} "./run-tests.sh"
}
```

## Variable Reference

### Standard variables
```tcl
${prefix}           # /opt/local
${destroot}         # Staging directory
${worksrcpath}      # Extracted source directory
${filespath}        # files/ directory
${name}             # Port name
${version}          # Port version
${revision}         # Port revision
${workpath}         # Work directory
${distname}         # Distribution filename
${distpath}         # Downloaded file location
```

### Build variables
```tcl
${configure.cc}     # C compiler
${configure.cxx}    # C++ compiler
${configure.cflags} # C compiler flags
${configure.ldflags} # Linker flags
${build_arch}       # Architecture (arm64, x86_64)
${os.major}         # Darwin major version
${os.platform}      # Platform (darwin)
```

## Style Guide

### Indentation
- Use 4 spaces, no tabs
- Align continuation lines

### Alignment
```tcl
# Good
depends_lib-append  port:openssl \
                    port:zlib

# Bad
depends_lib-append port:openssl \
port:zlib
```

### Line length
- Keep lines under 80 characters
- Use backslash for continuation

### Comments
```tcl
# Section headers
# Configuration options
# Explanation for non-obvious choices
```
