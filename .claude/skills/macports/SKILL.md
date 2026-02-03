---
name: macports
description: MacPorts package manager development workflow including Portfile creation, updates, testing, debugging build failures, and port command usage. Use when working with MacPorts ports, Portfiles, port testing, version updates, checksum updates, dependency management, build debugging, or any MacPorts development tasks.
---

# MacPorts Development

## Overview

Comprehensive guide for MacPorts port development workflows: creating and updating Portfiles, testing ports, debugging build failures, and mastering the `port` command-line tool.

## Core Workflows

### 1. Checking for Updates

Check if any GitHub-hosted or SVN-hosted ports have new versions available:

```bash
scripts/check-updates.sh                 # Check all ports in current directory
```

The script will:
- Find all Portfiles using GitHub PortGroup or SVN fetch
- Query GitHub API for latest releases
- Query SourceForge RSS feeds for SVN release commits
- Compare current version/revision with latest
- Display color-coded results (✓ up to date, ✗ update available)

**Supported sources:**
- GitHub-hosted ports (via GitHub API)
- SourceForge SVN ports (via RSS feed parsing for "Releasing" commits)

**Script available:** `scripts/check-updates.sh` automates version checking.

### 2. Testing a Port

Standard test sequence for any port modification:

```bash
portindex                                # Regenerate port index
port lint --nitpick <portname>           # Strict compliance check
sudo port uninstall <portname>           # Remove existing installation
sudo port clean --dist <portname>        # Clear downloaded files
sudo port install -sv <portname>         # Install with verbose output
```

**Script available:** `scripts/test-port.sh <portname>` automates this sequence.

### 3. Updating Port Version

When bumping version number:

1. Update `version` field in Portfile
2. **Keep existing checksums** (do NOT delete)
3. Run `sudo port checksum <portname>`
4. MacPorts will fail and output correct checksums
5. Copy checksum line from error output
6. Update Portfile with new checksums
7. Run `sudo port checksum <portname>` again to verify
8. Test the build

**Why keep old checksums:** MacPorts needs them present to fetch the new file and calculate correct checksums.

**Script available:** `scripts/update-checksums.sh <portname>` guides this workflow.

### 4. Creating New Port

```bash
# 1. Create directory structure
mkdir -p category/portname
cd category/portname

# 2. Create Portfile (use template from assets/Portfile.template)

# 3. Generate checksums
portindex
sudo port checksum portname

# 4. Test
port lint --nitpick portname
sudo port install -sv portname
```

**Template available:** `assets/Portfile.template` provides standard structure.

### 5. Submitting to MacPorts (Creating PRs)

**CRITICAL REQUIREMENTS**:
- Always show commit messages and PR descriptions to user for review BEFORE submitting
- MacPorts PRs must contain **exactly ONE commit** - squash/amend if needed
- Port lint must pass with **0 errors and 0 warnings** (use `--nitpick`)
- **GitHub pull requests are STRONGLY PREFERRED** over Trac tickets (faster workflow)

Reference: https://guide.macports.org/chunked/project.contributing.html

#### Commit Message Format (Official MacPorts Guidelines)

Reference: https://trac.macports.org/wiki/CommitMessages

**Subject line** (50-55 characters, max 60):
- List modified ports first, followed by colon
- Be specific - avoid vague subjects like "Update to latest version"
- Include version numbers when updating
- Use glob notation for multiple related ports (e.g., "py3*-numpy:", "clang-3.[6-9]:")

Examples:
```
portname: update to 3.0.3
autoconf, libtool: fix build on arm64
py3*-numpy: add maintainer handle
```

**Blank line** - Required between subject and body

**Body** (wrap at 72 characters):
- Say what the commit itself cannot - provide context
- What was previous behavior, why incorrect, how this changes it
- Don't just translate the diff into English
- Use full URLs for Trac tickets: https://trac.macports.org/ticket/12345
- For GitHub PRs: full URL or #n syntax
- Do NOT mention checksums updates (always required, redundant)

**Keywords** (for Trac integration):
- "References", "Addresses", "See": adds comment to ticket
- "Closes", "Fixes": closes ticket and adds comment

Example:
```
portname: update to 3.0.3

* update to version 3.0.3
* add maintainer's github handle
* remove obsolete patches

Closes: https://trac.macports.org/ticket/12345
```

**What to avoid:**
- ❌ Revision numbers (SVN r1234, git SHA)
- ❌ "Update checksums" (always required)
- ❌ Overly detailed implementation explanations
- ❌ Describing what the software does

#### PR Description Format

**ALWAYS use the official MacPorts PR template** as the starting point.

📋 **Template:** See [pr-template.md](references/pr-template.md) for the complete official template.

**Key requirements:**
- Use the template structure (Description, Type(s), Tested on, Verification)
- Fill in system info using the provided shell command
- Check all applicable verification items
- **Omit the entire Type(s) section if none apply** - update/submission are auto-detected from title, only include Type(s) if bugfix/enhancement/security fix applies
- Keep description concise and focused
- Do NOT repeat commit message verbatim
- Do NOT mention checksums (redundant)
- Do NOT describe software functionality

**Workflow:**
1. Run lint check: `port lint --nitpick category/portname`
2. Fix all warnings and errors
3. Create branch: `git checkout -b category/portname-update-X.Y.Z`
4. Copy/modify files from blakeports to macports-ports
5. Stage changes: `git add category/portname/`
6. Draft commit message (following guidelines above)
7. **SHOW commit message to user for review**
8. Commit after approval: `git commit -m "message"`
9. Push to fork: `git push -u origin branch-name`
10. Draft PR description
11. **SHOW PR description to user for review**
12. Create PR after approval: `gh pr create --repo macports/macports-ports`
13. If changes needed: amend commit, force push with `--force-with-lease`
14. If PR doesn't receive attention within a few days, email macports-dev@lists.macports.org

**For new ports:**
- Set ticket type to "submission" (if using Trac)
- Attach Portfile and any required patchfiles

**For port updates/enhancements:**
- Set ticket type to "enhancement" (misc), "defect" (bug fix), or "update" (version update)
- Cc the maintainer (get via `port info --maintainer portname`)
- Do NOT Cc openmaintainer@macports.org or nomaintainer@macports.org (not real addresses)

**Note**: Feature branches can be force-pushed after amendments. Master branch commits are immutable.

### 6. Debugging Build Failures

When builds fail:

```bash
# View build log
cat $(port logfile <portname>)

# Search for errors
grep -i error $(port logfile <portname>)

# Inspect work directory
cd $(port work <portname>)

# Test individual phases
sudo port configure <portname>
sudo port build <portname>
```

See [debugging.md](references/debugging.md) for comprehensive debugging techniques.

### 7. Creating Patches

For upstream build system issues:
1. Modify source files to fix the issue
2. Create unified diff: `diff -u original.txt modified.txt > patch-name.diff`
3. Place in `files/` directory
4. Add to Portfile: `patchfiles patch-name.diff`
5. Test the patch

**MacPorts approach**: Use system libraries in place, avoid bundling.

## Port Command Usage

### Essential Commands

**Installation:**
```bash
sudo port install -sv <portname>         # Verbose install (recommended)
sudo port install -d <portname>          # Debug mode
```

**Cleanup:**
```bash
sudo port uninstall <portname>           # Remove port
sudo port clean --dist <portname>        # Clear downloads (important!)
sudo port clean --all <portname>         # Clean everything
```

**Quality Checks:**
```bash
port lint --nitpick <portname>           # Strict compliance (use before PR)
port checksum <portname>                 # Verify checksums
```

**Information:**
```bash
port info <portname>                     # Port information
port deps <portname>                     # Show dependencies
port variants <portname>                 # Available variants
port work <portname>                     # Work directory path
port dir <portname>                      # Portfile directory path
port logfile <portname>                  # Build log path
```

**Development:**
```bash
portindex                                # Regenerate port index (after edits)
port test <portname>                     # Run test suite
```

**Full reference:** See [port-commands.md](references/port-commands.md) for comprehensive command documentation.

## Portfile Structure

**IMPORTANT: When creating or modifying Portfiles, consult the official Port Phases reference:**

📚 **https://guide.macports.org/chunked/reference.phases.html**

This comprehensive reference covers all available keywords for each phase:
- **Fetch Phase** - master_sites, distfiles, fetch.type (git/svn/etc)
- **Checksum Phase** - checksums format (rmd160, sha256, size)
- **Extract Phase** - compression formats (use_zip, use_xz, etc)
- **Patch Phase** - patchfiles, patch.args, patch.dir
- **Configure Phase** - configure.args, compiler flags (configure.cflags-append), environment variables
- **Build Phase** - build.cmd, build.args, use_parallel_build
- **Test Phase** - test.run, test.target, test.env
- **Destroot Phase** - destroot.args, destroot.destdir, destroot.keepdirs

**Use this reference to:**
- Choose appropriate configure options and compiler flags
- Set build/configure environment variables correctly
- Handle non-standard build systems (CMake, SCons, etc)
- Debug phase-specific failures
- Understand keyword modifiers (-append, -delete, -replace)

### Minimal Portfile

```tcl
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4

PortSystem          1.0
PortGroup           github 1.0

github.setup        owner repo 1.2.3
revision            0

categories          category
maintainers         {@username provider} openmaintainer
license             MIT

description         Short description

long_description    {*}${description}. Extended details.

checksums           rmd160  HASH \
                    sha256  HASH \
                    size    SIZE

depends_lib-append  port:dependency
```

### Key Sections

**Dependencies:**
- `depends_build` - Build-time only (compilers, build tools)
- `depends_lib` - Runtime libraries (linked)
- `depends_run` - Runtime only (not linked)

**Configuration:**
```tcl
configure.args      --prefix=${prefix} \
                    --enable-feature
```

**Variants:**
```tcl
variant feature description {
    configure.args-append --with-feature
    depends_lib-append port:feature-lib
}
```

**Full syntax reference:** See [portfile-syntax.md](references/portfile-syntax.md) for complete Portfile documentation.

## Build Phase Debugging

### Phase Order

1. `fetch` - Download source
2. `checksum` - Verify integrity  
3. `extract` - Unpack archive
4. `patch` - Apply patches
5. `configure` - Run configure script
6. `build` - Compile source
7. `test` - Run tests (optional)
8. `destroot` - Stage installation
9. `install` - Install to system

### Test Individual Phases

```bash
sudo port configure <portname>           # Test configure only
sudo port build <portname>               # Test build only
sudo port destroot <portname>            # Test destroot only
```

### Inspect Work Directory

```bash
cd $(port work <portname>)               # Navigate to work directory
cd $(port work <portname>)/<portname>-<version>  # Source directory
cat config.log                           # Configure output
```

## Common Issues and Solutions

### Checksum Mismatch
```bash
sudo port clean --dist <portname>        # Clear cached download
sudo port checksum <portname>            # Get correct checksums
```

### Missing Dependencies
```
error: 'some_header.h' file not found
```

**Solution:** Find providing port and add to `depends_lib`:
```bash
port provides /path/to/header.h
```

### Build Errors
```bash
cat $(port logfile <portname>)           # Read full log
grep -B 5 -A 10 error $(port logfile <portname>)  # Error context
```

### Lint Warnings

Fix before submitting:
```bash
port lint --nitpick <portname>
```

Common issues:
- Line length >80 characters
- Missing long_description
- Inconsistent indentation

## Quick Reference

### Standard Test Workflow
```bash
portindex && \
port lint --nitpick <portname> && \
sudo port clean --dist <portname> && \
sudo port uninstall <portname> && \
sudo port install -sv <portname>
```

### Checksum Update Workflow
```bash
# 1. Update version in Portfile (keep old checksums)
sudo port checksum <portname>            # Shows correct checksums
# 2. Copy checksum line from error output to Portfile
sudo port checksum <portname>            # Verify
```

### Debug Build Failure
```bash
sudo port install -sv <portname>         # Verbose install
cat $(port logfile <portname>) | less    # Read log
cd $(port work <portname>)               # Inspect source
```

## Resources

### Scripts (scripts/)

**test-port.sh** - Automate standard port testing workflow  
**update-checksums.sh** - Guide checksum update process  
**check-updates.sh** - Check GitHub-hosted ports for available updates

Execute without reading into context for efficiency.

### References (references/)

**port-commands.md** - Comprehensive `port` CLI reference with all commands, options, and workflows. Load when working with port commands or needing command syntax.

**debugging.md** - Build failure debugging techniques including log analysis, common error patterns, work directory inspection, and environment troubleshooting. Load when diagnosing build failures.

**portfile-syntax.md** - Complete Portfile syntax reference covering structure, PortGroups, dependencies, variants, platform checks, and style guide. Load when writing or modifying Portfiles.

**pr-template.md** - Official MacPorts PR template. **ALWAYS use as the starting point** when creating pull requests. Includes verification checklist and system info helper command.

### Assets (assets/)

**Portfile.template** - Standard Portfile template for new ports

## Best Practices

1. **Always run `portindex`** after modifying Portfiles
2. **Use `port lint --nitpick`** before submitting - must pass with 0 errors and 0 warnings
3. **Clean distribution files** (`--dist`) when updating versions
4. **Keep old checksums** during version updates (MacPorts needs them)
5. **Test with verbose output** (`-sv` flag) for debugging
6. **Inspect build logs** (`port logfile`) when builds fail
7. **Check work directory** for build artifacts and logs
8. **Test individual phases** to isolate failures
9. **Use 4 spaces** for indentation in Portfiles (no tabs)
10. **Align continuation lines** for readability
11. **Always show commit messages and PR descriptions for review** before submitting
12. **Follow official commit message format** - see https://trac.macports.org/wiki/CommitMessages
13. **Subject line: 50-55 characters, max 60** - list ports first with colon
14. **Body: wrap at 72 characters** - provide context, not implementation details
15. **Use full URLs** for Trac tickets and GitHub PRs in commit messages
16. **Don't mention checksums updates** - always required, redundant
17. **Don't mention revision numbers** (SVN r1234, git SHA) in commits
18. **MacPorts PRs must contain exactly ONE commit** - squash or amend if needed
19. **Feature branches can be force-pushed** - use `--force-with-lease` after amends
20. **Use system libraries in place** - avoid bundling frameworks in MacPorts builds
