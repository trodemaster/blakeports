# CLAUDE.md - AI Assistant Guide for BlakePorts

## Project Overview

BlakePorts is a personal MacPorts repository with custom ports and automated CI/CD workflows. It serves as:
1. A development environment for MacPorts Portfiles
2. A staging area before submitting ports to the official macports-ports repository
3. A CI/CD pipeline for testing ports across multiple macOS versions

## Repository Structure

```
blakeports/
├── .github/workflows/     # GitHub Actions workflow definitions
├── _resources/            # MacPorts build system files (synced from upstream)
│   ├── macports1.0/      # MacPorts core resources
│   └── port1.0/          # Port groups, compilers, fetch settings
├── audio/                 # Audio category ports
│   └── nrsc5/            # HD Radio software-defined radio
├── devel/                 # Development category ports
│   └── libcbor/          # CBOR protocol library
├── emulators/            # Emulator category ports
│   └── previous/         # NeXT computer emulator
├── net/                   # Networking category ports
│   ├── netatalk/         # AFP file server (with netatalk4 subport)
│   └── openssh9-client/  # Legacy SSH compatibility client
├── security/             # Security category ports
│   ├── libfido2/         # FIDO2 authentication library
│   └── vault/            # HashiCorp Vault
├── textproc/             # Text processing category ports
│   └── bstring/          # Better String library
├── docker/               # Docker configurations for runners
├── scripts/              # Build and utility scripts
├── PortIndex             # MacPorts port index file
├── PortIndex.quick       # Quick port index lookup
└── setupenv.bash         # Environment setup for MacPorts
```

## Key Files

| File | Purpose |
|------|---------|
| `setupenv.bash` | Sources MacPorts environment (PATH, MANPATH) |
| `PortIndex` | Generated port index - run `portindex` to regenerate |
| `.cursorrules` | Comprehensive MacPorts development rules and conventions |
| `README.md` | User-facing documentation with quick reference |

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/installmacports` | Installs MacPorts and configures BlakePorts as default source |
| `scripts/install-deps` | Installs dependencies for a port (build + runtime or runtime-only) |
| `scripts/syncfromgitports` | Syncs `_resources` and port directories from upstream MacPorts |
| `scripts/fulltest` | Comprehensive test - recreates runners and triggers all builds |
| `scripts/ghrunner` | GitHub runner management script |

## CI/CD Architecture

### Self-Hosted Runners
- Runners are managed by [jibb-runners](https://github.com/trodemaster/jibb-runners) tool
- Each runner runs in an isolated tart VM
- Base VMs: `macOS_15` (Sequoia) and `macOS_26` (Tahoe Beta)

### Matrix Build Strategy
All port builds run in parallel on multiple macOS versions:
- **macOS 15 (Sequoia)** - Latest stable
- **macOS 26 (Tahoe)** - Beta preview

### Workflow Naming Conventions
- `build-<portname>.yml` - Standard port build for modern macOS
- `build-legacy-<portname>.yml` - Builds for older macOS versions (10.6-10.8)
- `vmwvm-*.yml` - VM lifecycle management workflows

## Development Workflow

### Creating/Modifying a Port

1. **Edit the Portfile**:
   ```bash
   # Portfiles are in: category/portname/Portfile
   vim devel/libcbor/Portfile
   ```

2. **Update the port index**:
   ```bash
   portindex
   ```

3. **Lint the Portfile**:
   ```bash
   port lint --nitpick <portname>
   ```

4. **Test locally**:
   ```bash
   # Clean any existing installation
   sudo port uninstall <portname>
   sudo port clean --dist <portname>

   # Build and install
   sudo port install -sv <portname>
   ```

### Version Update Workflow

1. Update version number in Portfile
2. **Keep existing checksums** (do NOT remove them)
3. Run `sudo port checksum <portname>` to get new checksums from error output
4. Update Portfile with new checksums
5. Run `sudo port checksum <portname>` again to verify
6. Test the build

### Triggering CI Builds

```bash
# Trigger individual workflows
gh workflow run "Build libcbor"
gh workflow run "Build netatalk"

# Monitor builds
gh run view -w              # Open in browser
gh run view --log-failed    # View failed logs
```

## Portfile Conventions

### Required Structure
```tcl
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4

PortSystem          1.0
PortGroup           github 1.0    # if using GitHub

github.setup        owner repo version [tag_prefix]
revision            0

categories          category
maintainers         {@trodemaster icloud.com:manuals-unread2u} openmaintainer
license             LICENSE

description         Short description
long_description    {*}${description}, extended details.

checksums           rmd160  HASH \
                    sha256  HASH \
                    size    SIZE

# dependencies, configure args, variants...
```

### Indentation
- Use 4 spaces, no tabs
- Align values with consistent spacing

### Dependencies
- `depends_build` - Build-time only (compilers, tools)
- `depends_lib` - Library dependencies (linked)
- `depends_run` - Runtime dependencies

## Commit Message Standards

### Subject Line Format
- Start with port name: `libfido2: update to 1.15.0`
- Keep under 55 characters (max 60)
- Be specific about the change

### Body Format
- Separate from subject with blank line
- Wrap at 72 characters
- Use full URLs for tickets/PRs
- Explain the "why" not just the "what"

### Examples
```
libfido2: update to version 1.15.0

* add support for new USB HID features
* fix build issues on macOS 14+

Closes: https://trac.macports.org/ticket/67890
```

```
netatalk: new port, version 4.4.0

Open Source AFP fileserver for Unix-like systems.

* supports Time Machine backups
* Spotlight search integration
* modern authentication support
```

## MacPorts Submission Workflow

When ready to submit to official macports-ports:

1. **Create branch**: `git checkout -b category/portname-new-port`
2. **Copy files**: from blakeports to macports-ports
3. **Run lint**: `port lint category/portname`
4. **Commit**: following MacPorts commit standards
5. **Create PR**: with testing checklist

See `.cursorrules` for detailed PR templates and guidelines.

## Common Commands Quick Reference

```bash
# Environment setup
source ./setupenv.bash

# Port index management
portindex                          # Regenerate index

# Testing
port lint --nitpick <portname>     # Strict lint check
port deps <portname>               # Show dependencies
sudo port install -sv <portname>   # Verbose install

# Cleanup
sudo port uninstall <portname>     # Remove port
sudo port clean --dist <portname>  # Clear downloads

# Checksum workflow
sudo port checksum <portname>      # Verify/get checksums

# Runner management (requires jibb-runners)
cd ../jibb-runners
./ghrunner.sh -list                # Check runner status
./ghrunner.sh -tart macOS_15       # Start runner
./ghrunner.sh -remove macOS_15     # Remove runner
```

## Important Notes for AI Assistants

1. **Always run `portindex`** after modifying any Portfile
2. **Never remove checksums** when updating versions - MacPorts needs them to show correct values
3. **Use `port lint --nitpick`** for strict compliance checking
4. **Source `setupenv.bash`** before running port commands in workflows
5. **Matrix builds run on both macOS 15 and 26** - ensure compatibility
6. **The `_resources` directory is synced from upstream** - don't modify directly
7. **Check `.cursorrules`** for comprehensive MacPorts development standards
8. **URLs must be formatted as clickable links** in all documentation and PR descriptions

## Troubleshooting

### Checksum Mismatches
```bash
sudo port clean --dist <portname>
sudo port checksum <portname>
# Copy new checksums from error output
```

### Port Not Found
```bash
portindex                    # Regenerate port index
sudo port sync              # Sync MacPorts index
```

### Runner Issues
```bash
cd ../jibb-runners
./ghrunner.sh -remove <runner>
./ghrunner.sh -tart <runner>
```

### Build Failures
```bash
gh run view --log --job "build-<port> (<runner>)"
```
