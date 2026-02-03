# MacPorts Port Command Reference

Comprehensive reference for `port` command usage in development workflows.

## Table of Contents
- [Common Commands](#common-commands)
- [Developer Commands](#developer-commands)
- [Build Phase Commands](#build-phase-commands)
- [Debugging Commands](#debugging-commands)
- [Dependency Management](#dependency-management)
- [Information Commands](#information-commands)

## Common Commands

### port install
Install a port with dependencies.

```bash
port install <portname>              # Basic install
sudo port install <portname>         # Install (requires sudo)
sudo port install -sv <portname>     # Verbose output (recommended for debugging)
sudo port install -d <portname>      # Debug mode with detailed output
sudo port install -k <portname>      # Keep going despite errors
```

### port uninstall
Remove an installed port.

```bash
sudo port uninstall <portname>           # Uninstall specific port
sudo port uninstall <portname> @version  # Uninstall specific version
sudo port -f uninstall <portname>        # Force uninstall
sudo port uninstall inactive             # Remove all inactive versions
```

### port clean
Clean build artifacts and downloads.

```bash
sudo port clean <portname>               # Clean build directory
sudo port clean --dist <portname>        # Clean downloaded files (critical for checksum updates)
sudo port clean --work <portname>        # Clean work directory only
sudo port clean --all <portname>         # Clean everything
```

### port lint
Check Portfile syntax and quality.

```bash
port lint <portname>                     # Basic lint check
port lint --nitpick <portname>           # Strict compliance checking (use before PR)
```

**Common lint warnings to fix:**
- Line length over 80 characters
- Missing long_description
- Inconsistent indentation
- Missing maintainer openmaintainer

### port checksum
Verify or update checksums.

```bash
port checksum <portname>                 # Verify checksums
sudo port checksum <portname>            # Shows correct checksums on mismatch
```

**Checksum workflow:**
1. Update version in Portfile
2. Keep old checksums (don't remove)
3. Run `sudo port checksum <portname>`
4. Copy new checksum line from error output
5. Update Portfile with new values
6. Verify: `sudo port checksum <portname>`

## Developer Commands

### port test
Run test suite if defined.

```bash
sudo port test <portname>                # Run tests
sudo port test -sv <portname>            # Verbose test output
```

### port work
Show work directory path.

```bash
port work <portname>                     # Print work directory path
cd $(port work <portname>)               # Navigate to work directory
```

Work directory structure:
```
work/
├── <portname>-<version>/    # Extracted source
└── .macports.*/             # MacPorts build metadata
```

### port dir
Show port directory path.

```bash
port dir <portname>                      # Print Portfile directory
cd $(port dir <portname>)                # Navigate to port directory
```

### port fetch
Download distribution files.

```bash
sudo port fetch <portname>               # Download distfiles
sudo port fetch --check-vulnerabilities  # Security check
```

## Build Phase Commands

Run individual build phases for debugging:

```bash
sudo port configure <portname>           # Run configure phase only
sudo port build <portname>               # Run build phase only
sudo port destroot <portname>            # Run destroot phase only
sudo port install <portname>             # Run all phases through install
```

**Phase order:**
1. fetch - Download source
2. checksum - Verify integrity
3. extract - Unpack archive
4. patch - Apply patches
5. configure - Run configure script
6. build - Compile source
7. test - Run tests (optional)
8. destroot - Stage installation
9. install - Install to system

## Debugging Commands

### port logfile
Show build log location.

```bash
port logfile <portname>                  # Print log path
cat $(port logfile <portname>)           # View log
tail -f $(port logfile <portname>)       # Follow log in real-time
```

### port provides
Find which port provides a file.

```bash
port provides /usr/local/bin/somecommand
```

### port contents
List installed files.

```bash
port contents <portname>                 # List all installed files
port contents <portname> | grep bin      # Find binaries
```

### port notes
Show post-install notes.

```bash
port notes <portname>                    # Display usage notes
```

## Dependency Management

### port deps
Show dependencies.

```bash
port deps <portname>                     # Runtime dependencies
port deps --index <portname>             # All dependencies with types
```

### port rdeps
Show reverse dependencies (what depends on this port).

```bash
port rdeps <portname>                    # Ports depending on this
```

### port dependents
Show installed ports that depend on this.

```bash
port dependents <portname>               # Installed dependents
```

## Information Commands

### port info
Display port information.

```bash
port info <portname>                     # Basic info
port info --variants <portname>          # Show variants
port info --maintainer <portname>        # Show maintainer
port info --depends <portname>           # Show dependencies
```

### port search
Search for ports.

```bash
port search <keyword>                    # Search by name/description
port search --name <keyword>             # Search names only
port search --regex <pattern>            # Regex search
```

### port list
List ports.

```bash
port list                                # List all ports
port list <portname>                     # Check if port exists
```

### port installed
Show installed ports.

```bash
port installed                           # All installed
port installed <portname>                # Specific port versions
port installed active                    # Only active versions
```

### port outdated
Show ports with updates available.

```bash
port outdated                            # All outdated ports
```

### port variants
List available variants.

```bash
port variants <portname>                 # Show all variants
```

## Index Management

### portindex
Regenerate port index (required after Portfile changes).

```bash
portindex                                # Regenerate in current directory
portindex /path/to/ports                 # Regenerate in specific path
```

**When to run:**
- After creating new Portfile
- After modifying existing Portfile
- Before testing local changes
- After syncing from upstream

## Environment Variables

Useful environment variables for development:

```bash
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
export MANPATH=/opt/local/share/man:$MANPATH
```

## Common Workflows

### Testing a modified port
```bash
portindex
port lint --nitpick <portname>
sudo port clean --dist <portname>
sudo port uninstall <portname>
sudo port install -sv <portname>
```

### Updating checksums
```bash
# 1. Update version in Portfile
# 2. Keep old checksums
sudo port checksum <portname>           # Get new checksums
# 3. Update Portfile with values from error
sudo port checksum <portname>           # Verify
```

### Debugging build failure
```bash
sudo port install -sv <portname>         # Verbose install
cat $(port logfile <portname>)           # Read full log
cd $(port work <portname>)               # Inspect work directory
sudo port configure <portname>           # Test configure phase
```

### Creating new port
```bash
# 1. Create category/portname/Portfile
# 2. Write Portfile
portindex                                # Update index
port lint --nitpick <portname>           # Check syntax
sudo port install -sv <portname>         # Test build
```
