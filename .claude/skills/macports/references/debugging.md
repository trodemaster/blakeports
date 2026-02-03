# MacPorts Build Debugging Guide

Techniques for diagnosing and fixing port build failures.

## Table of Contents
- [Reading Build Logs](#reading-build-logs)
- [Common Error Patterns](#common-error-patterns)
- [Build Phase Debugging](#build-phase-debugging)
- [Work Directory Inspection](#work-directory-inspection)
- [Environment Issues](#environment-issues)
- [Dependency Problems](#dependency-problems)

## Reading Build Logs

### Locate the log
```bash
port logfile <portname>                  # Print log path
tail -f $(port logfile <portname>)       # Follow in real-time
cat $(port logfile <portname>) | less    # Browse full log
```

### Log structure
```
:msg:main ---> Computing dependencies for <portname>
:debug:main Executing org.macports.main
:msg:main ---> Fetching distfiles for <portname>
:msg:main ---> Verifying checksums for <portname>
:msg:main ---> Extracting <portname>
:msg:main ---> Configuring <portname>
:error:configure Failed to configure <portname>
```

### Key sections to check
1. **Dependency computation** - Missing dependencies
2. **Fetch phase** - Download failures
3. **Checksum phase** - Integrity mismatches
4. **Configure phase** - Configuration errors
5. **Build phase** - Compilation errors
6. **Destroot phase** - Installation staging errors

### Search patterns
```bash
# Find errors
grep -i error $(port logfile <portname>)

# Find warnings
grep -i warning $(port logfile <portname>)

# Find failed phases
grep :error: $(port logfile <portname>)

# Context around error
grep -A 10 -B 5 error $(port logfile <portname>)
```

## Common Error Patterns

### Checksum Mismatch
**Error:**
```
Error: Checksum (rmd160) mismatch for <distfile>
Error: Checksum (sha256) mismatch for <distfile>
```

**Solution:**
```bash
sudo port clean --dist <portname>        # Clear cached download
sudo port checksum <portname>            # Get correct checksums
# Update Portfile with new checksums
```

### Missing Dependencies
**Error:**
```
error: 'some_header.h' file not found
/usr/bin/ld: cannot find -lsomelib
```

**Solution:**
1. Identify missing library/header
2. Find which port provides it: `port provides /path/to/file`
3. Add to Portfile dependencies:
```tcl
depends_lib-append port:missing-port
```

### Compiler Errors
**Error:**
```
error: use of undeclared identifier
error: no member named 'foo' in 'bar'
clang: error: unsupported option '-std=gnu++17'
```

**Solutions:**
- Update to newer compiler variant
- Add compiler flags in Portfile
- Apply upstream patches
- Check if newer version fixes issue

### Configure Failures
**Error:**
```
configure: error: C compiler cannot create executables
configure: error: Package requirements (foo >= 1.0) were not met
```

**Solution:**
```bash
# Check what configure detected
cat $(port work <portname>)/*/config.log

# Common fixes:
# 1. Add missing dependencies
# 2. Set configure args in Portfile
# 3. Add pkg-config to depends_build
```

### Build Phase Errors
**Error:**
```
make: *** [target] Error 1
ninja: build stopped: subcommand failed
```

**Solution:**
1. Examine actual compilation error above the make/ninja error
2. Common causes:
   - Missing includes → add dependencies
   - Wrong flags → adjust in Portfile
   - Incompatible code → apply patches

### Destroot Phase Errors
**Error:**
```
error: Files intended to be installed outside of destroot
error: reinplace pattern not matched
```

**Solution:**
1. Check destroot commands in Portfile
2. Verify paths use ${destroot} prefix
3. Ensure reinplace patterns match file content

## Build Phase Debugging

### Test individual phases
```bash
# Clean slate
sudo port clean --all <portname>

# Run phases one at a time
sudo port fetch <portname>
sudo port checksum <portname>
sudo port extract <portname>
sudo port patch <portname>
sudo port configure <portname>         # Often where issues appear
sudo port build <portname>
sudo port destroot <portname>
```

### Debug mode
```bash
sudo port -d install <portname>        # Enable debug output
```

Debug output shows:
- Exact commands executed
- Variable values
- File operations
- Phase transitions

### Keep work directory
```bash
sudo port -k install <portname>        # Keep going on errors
```

Allows inspection of partial builds.

## Work Directory Inspection

### Navigate to work directory
```bash
cd $(port work <portname>)
```

### Directory structure
```
work/
├── <portname>-<version>/              # Extracted source
├── .macports.<portname>.state         # Phase tracking
└── .macports.*.dir/                   # Additional metadata
```

### Inspect extracted source
```bash
cd $(port work <portname>)/<portname>-<version>
ls -la                                 # Check files extracted
cat config.log                         # Check configure output
cat CMakeCache.txt                     # Check CMake config (if CMake)
```

### Check patched files
```bash
# After patch phase
cd $(port work <portname>)/<portname>-<version>
cat path/to/patched/file.c             # Verify patch applied
```

### Manual build testing
```bash
cd $(port work <portname>)/<portname>-<version>

# Try configure manually
./configure --prefix=/opt/local

# Try build manually
make

# Check for missing tools
which cmake
which ninja
```

## Environment Issues

### PATH problems
```bash
echo $PATH                             # Should include /opt/local/bin
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
```

### Xcode/CLT issues
```bash
xcode-select -p                        # Check Xcode path
xcode-select --install                 # Install Command Line Tools
pkgutil --pkg-info=com.apple.pkg.CLTools_Executables  # Check CLT version
```

### MacPorts itself
```bash
port version                           # Check MacPorts version
sudo port selfupdate                   # Update MacPorts
sudo port sync                         # Sync port index
```

### Architecture issues
```bash
uname -m                               # Check architecture (arm64/x86_64)
arch -x86_64 sudo port install <portname>  # Force x86_64 on Apple Silicon
```

### Conflicting installations
Check for conflicts with Homebrew, Fink, or other package managers:
```bash
which <command>                        # Should show /opt/local/bin
brew list                              # Check Homebrew conflicts
```

## Dependency Problems

### Verify dependencies installed
```bash
port deps <portname>                   # List required dependencies
port installed | grep <dep>            # Check if dependency installed
```

### Install dependencies manually
```bash
sudo port install <dependency>         # Install missing dependency
```

### Circular dependencies
**Error:**
```
Error: Unable to execute port: Could not open file: /opt/local/var/macports/sources/...
```

**Solution:**
1. Check for circular dependency chains
2. Install dependencies in specific order
3. May need to deactivate conflicting port temporarily

### Version conflicts
```bash
port installed <portname>              # Check installed versions
sudo port uninstall inactive           # Remove old versions
sudo port upgrade <portname>           # Upgrade to latest
```

### Build vs runtime dependencies
Ensure correct dependency types in Portfile:

```tcl
depends_build-append  port:cmake \     # Only needed during build
                      port:pkgconfig

depends_lib-append    port:openssl \   # Needed at runtime
                      port:zlib

depends_run-append    port:python311   # Runtime only, not linked
```

## Platform-Specific Issues

### macOS version checks
```bash
sw_vers                                # Check macOS version
```

Some ports may need platform checks in Portfile:
```tcl
platform darwin {
    if {${os.major} >= 20} {
        # macOS 11+ specific configuration
    }
}
```

### Apple Silicon (arm64) issues
Common issues on M-series Macs:
- x86_64-only dependencies
- Architecture detection failures
- Universal binary problems

```bash
file $(which <binary>)                 # Check binary architecture
lipo -info <binary>                    # Check universal binary
```

## Advanced Debugging

### Trace mode
```bash
sudo port -t install <portname>        # Enable trace mode
```

Shows system calls and file access patterns.

### Custom log level
```bash
sudo port -v install <portname>        # Verbose
sudo port -d install <portname>        # Debug
```

### Interactive debugging
```bash
# After configure phase completes
cd $(port work <portname>)/<portname>-<version>

# Manually run build commands to isolate issue
make VERBOSE=1                         # Verbose make
cmake --build . --verbose              # Verbose CMake
```

## Getting Help

### Check port notes
```bash
port notes <portname>                  # Port-specific notes
```

### Search for similar issues
1. Check MacPorts Trac: https://trac.macports.org
2. Search GitHub issues
3. Check upstream project issues

### Report bugs
Include in bug reports:
1. Full build log: `cat $(port logfile <portname>)`
2. System info: `sw_vers && uname -m`
3. MacPorts version: `port version`
4. Xcode version: `xcodebuild -version`
5. Port info: `port info <portname>`
6. Dependencies: `port deps <portname>`
