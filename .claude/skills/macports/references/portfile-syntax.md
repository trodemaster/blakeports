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
                    port:pkgconfig

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
                    port:pkgconfig \
                    port:autoconf \
                    port:automake \
                    port:libtool
```

Used only during compilation, not installed in the final environment.

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

Allows flexibility if multiple ports provide the same file.

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

#### CMake
```tcl
PortGroup           cmake 1.1

configure.args-append \
                    -DENABLE_FEATURE=ON \
                    -DBUILD_SHARED_LIBS=ON
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

### Custom extract
```tcl
extract.mkdir       yes
extract.only        ${distname}${extract.suffix}
```

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
