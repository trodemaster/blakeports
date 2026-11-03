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
| `AGENTS.md` | Agent instructions for session workflow |
| `findings/` | Write-ups of CI investigations (evidence and conclusions); index in `findings/README.md` |
| `PLATFORM_CUTOFFS.md` | Ports with a minimum OS (`platforms {darwin >= N}`), why, and how to add one — update it with any new cutoff |

## Open Work

Keep this list current: add items when work is left for a later session,
remove them when done. Detail lives in the linked findings.

**Leopard netatalk dependencies** — work through
[findings/leopard-netatalk-deps-worklist.md](findings/leopard-netatalk-deps-worklist.md)
one port at a time (reproduce with upstream's Portfile on cleaned 10.5 i386
and ppc, minimal fix, verify on all builders, write up, draft PR for review):

- [ ] **icu** — upstream PR [#36312](https://github.com/macports/macports-ports/pull/36312)
  open (icu and icu-devel), changes requested. 2026-11-03: switched to
  `path:share/doc/libgcc/README:libgcc` (0e7f8be7138), re-tested and
  commented; waiting on barracuda156 and mohd-akram. Test branch
  `test/icu-libgcc` on origin. After merge: delete `devel/icu` and that
  branch, then cache
  upstream icu on packages.jibb.tv (left out until then by choice).
- [ ] **libarchive** — upstream PR [#36316](https://github.com/macports/macports-ports/pull/36316)
  open. After merge: delete `archivers/libarchive` and the
  `test/libarchive` branch on origin.
- [ ] **libevent** — next. Trac [#74414](https://trac.macports.org/ticket/74414);
  blakeports patch guards `#pragma GCC diagnostic` for gcc ≥ 12. Reproduce
  on 10.5 i386 and ppc first (only ppc seen so far).
- [ ] **libgcrypt** — widen `gcc-4.2` blacklist to `*gcc-4.2` (llvm-gcc-4.2
  fails on McEliece asm, i386). No Trac ticket; re-prove on upstream 1.12.4.
- [ ] **python314** — `_hmac` SIMD blake2 needs `posix_memalign` on 10.5;
  blakeports presets the `-msse`/`-mavx2` checks to no. Re-prove on
  upstream 3.14.10; [#73578](https://trac.macports.org/ticket/73578) is
  closed (`_blake2`).

**Port updates:**

- [ ] **snowemu 1.6.0** — upstream PR [#36318](https://github.com/macports/macports-ports/pull/36318)
  open; blakeports main already has it (CI passed on 27, 26 and 15).
  After merge: delete the `emulators/snowemu-update-1.6.0` branch on the
  fork. Test basic app launch if a reviewer asks.

**Infrastructure reminders:**

- [ ] Back up the packages.jibb.tv signing key,
  darkstar `/var/lib/macports-packages/key/.signify.key`.
- [ ] umac ghrunnerd: pull actions_runners `cc706bd` (launchd
  `ProcessType` `Interactive`), render the plist into
  `~/Library/LaunchAgents` and reload the agent, then restart macos-15
  through ghrunnerd. Check with `ps -M` (31T, not 20T/4T); see
  machine-cfg `kb/LAUNCHD_PROCESS_TYPE.md`.
- [ ] Rebuild darkstar's ghrunnerd binary: its actions_runners checkout
  pulled ghrunnerd `netres.go` changes (2026-11-01) that aren't built yet.
- [ ] machine-cfg: local main has diverged from origin, and `stash@{0}`
  duplicates a far-star settings edit. Reconcile, then drop the stash.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/installmacports` | Installs MacPorts and configures BlakePorts as default source |
| `scripts/preparemacports` | Run by every CI job: regenerates PortIndex, runs syncports, configures the packages.jibb.tv binary cache |
| `scripts/cleanupmacports` | Uninstalls every port except curl and git (MacPorts Cleanup workflow, modern and legacy) |
| `scripts/syncports` | Syncs the official ports tree when it is more than a day old |
| `scripts/install-deps` | Installs dependencies for a port (build + runtime or runtime-only) |
| `scripts/syncfromgitports` | Syncs `_resources` and port directories from upstream MacPorts |
| `scripts/check-updates.sh` | Reports ports with newer upstream releases and others' macports-ports PRs; `--all` adds blakeports-only ports (see the `check-updates` skill) |
| `scripts/fulltest` | Comprehensive test - recreates runners and triggers all builds |
| `scripts/ghrunner` | GitHub runner management script |
| `scripts/portcompiler.tcl` | Prints the compiler (and blacklist) each Portfile picks on this machine, without building: `port-tclsh scripts/portcompiler.tcl <dir>...` |

## CI/CD Architecture

### Self-Hosted Runners
- Modern macOS runners run in Lima VMs (`vz`), started from the
  [lima_mac](../lima_mac) Makefile and registered with `scripts/ghrunner -lima`
- Legacy runners (10.5–10.11, PPC) are Linux docker runners that SSH into
  VMware VMs on darkstar, managed with `scripts/ghrunner -start-group legacy`

| Runner | Lima instance | Host | Start with |
|---|---|---|---|
| `macOS_26` | `macos-26` | this machine | `make runner-26` in `~/Developer/lima_mac` |
| `macOS_27` | `macos-27` | this machine | `make runner-27` in `~/Developer/lima_mac` |
| `macOS_15` | `macos-15` | umac | started manually by the user — don't start it here |

**Manage runners through ghrunnerd first.** Each host (darkstar, far-star, umac)
runs a `ghrunnerd` MCP server, registered here as `ghrunnerd-darkstar`,
`ghrunnerd-far-star` and `ghrunnerd-umac`. Use the `ghrunnerd` skill
(`.claude/skills/ghrunnerd/`) for any status, start, stop, restart, log or
snapshot work; the `make runner-NN` flow below is the fallback.

`make runner-NN` boots the VM if it isn't running, then (re)registers the
runner via `scripts/ghrunner` unless GitHub already reports it online.
Virtualization.framework allows only **2 macOS VMs per host**, so this machine
can run 26 and 27 together but not a third.

In a sandboxed Claude session, `limactl start`/`stop` (and so `make runner-NN`)
must run with the sandbox disabled; `limactl list` and `limactl shell` work
sandboxed. If jobs sit queued, check runner status first:

```bash
gh api repos/trodemaster/blakeports/actions/runners \
  --jq '.runners[] | "\(.name)\t\(.status)"'
```

Queued jobs fail after 24h waiting for a runner. If `macOS_15` is offline,
dispatch without it: `gh workflow run "Build <Portname>" -f run_macos15=false`.

### Matrix Build Strategy
**Modern builds** (automatic on push/PR):
- **macOS 26 (Tahoe)** - Latest stable
- **macOS 27** - Latest

**Optional modern builds** (manual workflow dispatch only):
- **macOS 15 (Sequoia)** - Previous stable

**Legacy builds** (manual workflow dispatch only):
- **Mac OS X 10.5 (Leopard)** - Legacy platform
- **Mac OS X 10.7 (Lion)** - Legacy platform

### Workflow Naming Conventions
- `build-<portname>.yml` - Consolidated workflow supporting both modern and legacy builds
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

**Automatic triggers** (push/PR):
- Only runs modern builds (macOS 15, macOS 26)
- Legacy builds never run automatically

**Manual triggers** (workflow_dispatch):

```bash
# Trigger modern-only builds (default)
gh workflow run "Build libcbor"
gh workflow run "Build netatalk"

# Trigger with legacy platform builds
gh workflow run "Build libcbor" -f run_legacy=true
gh workflow run "Build netatalk" -f run_legacy=true -f branch=main

# Monitor builds
gh run view -w              # Open in browser
gh run view --log-failed    # View failed logs
```

**Workflow inputs**:
- `branch`: Branch to build from (default: main)
- `run_legacy`: Run legacy platform builds (10.5, 10.7) - default: false

### Testing a Candidate Fix (`Test port` workflow)

`.github/workflows/test-port.yml` builds one port on chosen runners, for
upstream-PR investigations (see `findings/`). Use a `test/<port>` branch
whose `<category>/<port>/Portfile` is upstream's verbatim and whose
`Portfile.fixed` holds the candidate change:

```bash
gh workflow run "Test port" --ref test/libarchive \
  -f port=libarchive -f runners="leopard, leopard-ppc" -f portfile=fixed \
  -f port_test=true -f check='...smoke test...'
# -f build=false: only report the compiler each Portfile picks (fast, all runners)
```

- Each job first reports the compiler both Portfiles pick on that runner,
  then (if `build`) installs deps, cleans and builds from source.
- `--ref` runs the workflow file **from that branch**: after changing the
  workflow on main, merge main into the test branch before dispatching.
- Run `MacPorts Cleanup` first for a clean-VM result. On leopard-ppc, wait
  for the runner to be online after any `runner_up`.
- Stage files explicitly when committing on test branches (`git commit -a`
  once swept a findings edit onto one).

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
- Use full URLs for tickets/PRs, except GitHub issues and PRs in other
  repos (macports/macports-ports above all): a blakeports commit that
  links one adds a "referenced this" entry to that PR's timeline. Name it
  in words instead ("upstream snowemu 1.6.0 PR"). Links in file content
  (CLAUDE.md, findings/) don't do this; only commit messages, and issue
  or PR text, do. Trac URLs are fine.
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

Claude's shell already has MacPorts on `PATH` — do not source `setupenv.bash`
in an interactive Claude session. `setupenv.bash` is only needed in CI
workflows, which start from a bare shell.

```bash
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

# Runner management
cd ~/Developer/lima_mac && make runner-26   # Boot VM + register runner
cd ~/Developer/lima_mac && make status      # limactl list
scripts/ghrunner -list                      # Registered runners
scripts/ghrunner -remove macOS_26           # De-register a runner
scripts/ghrunner -lima macos-26             # Register (VM must be running)
```

## Important Notes for AI Assistants

1. **Always run `portindex`** after modifying any Portfile
2. **Never remove checksums** when updating versions - MacPorts needs them to show correct values
3. **Use `port lint --nitpick`** for strict compliance checking
4. **Source `setupenv.bash`** before running port commands in CI workflows only — Claude's interactive shell already has MacPorts on `PATH`, so don't source it there
5. **Matrix builds run on macOS 27, 26 and 15** - ensure compatibility
6. **The `_resources` directory is synced from upstream** - don't modify directly
7. **Check `.cursorrules`** for comprehensive MacPorts development standards
8. **URLs must be formatted as clickable links** in all documentation and PR descriptions
9. **Check [Open Work](#open-work) at session start** and update it before ending a session

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
scripts/ghrunner -remove macOS_26
cd ~/Developer/lima_mac && make runner-26
# VZErrorDomain Code=6 on start = 2-VM limit reached; stop another macOS VM
```

### Build Failures
```bash
gh run view --log --job "build-<port> (<runner>)"
```
