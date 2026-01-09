# Legacy Curl Bootstrap: Distfile Pre-Fetch Implementation

## Problem Statement

Legacy macOS versions (10.5-10.11) running on VMs cannot download from modern HTTPS servers using their system `curl` due to outdated SSL/TLS libraries. This creates a circular dependency:

1. Need MacPorts curl to fetch from modern servers (GitHub, distfiles.macports.org)
2. But installing MacPorts curl requires downloading distfiles
3. Which fails because system curl cannot handle modern HTTPS

**Error seen in logs:**
```
Connection timed out during banner exchange
Connection to [IP] port 22 timed out
```

This is because the legacy system cannot complete the TLS handshake with GitHub/modern servers.

## Solution Overview

### Architecture

The solution uses a three-phase approach:

1. **Phase 1 (Container)**: Use modern curl in the GitHub Actions container to download all distfiles
2. **Phase 2 (Transfer)**: SCP the distfiles to the legacy VM's MacPorts distfiles directory
3. **Phase 3 (Installation)**: MacPorts `port install` finds files locally and skips network downloads

### Workflow

```
Host System (local MacPorts)      Container (GitHub Actions)      Legacy VM
        │                                    │                      │
        ├─ Run cache-distfiles               │                      │
        │   (port fetch curl ...)            │                      │
        │                                    │                      │
        ├─ Copy to cache dir ───────────────>│ /config/distfiles-cache/
        │   ~/jibb-runners/                  │   (mounted volume)
        │   docker/config/                   │
        │   distfiles-cache/                 │
        │                                    │
        │                          Run prefetch-distfiles
        │                                    │
        │                          Copy from cache to /tmp
        │                                    │
        │                          SCP files ──────────────────────>│ /tmp/prefetch-distfiles/
        │                                    │                      │
        │                                    │         sudo mv to /opt/local/var/macports/distfiles/
        │                                    │         sudo chmod 644
        │                                    │                      │
        │                                    │           port install curl
        │                                    │           (finds files locally,
        │                                    │            NO network needed)
        │                                    │                      │
        │                                    │<────── MacPorts updated
```

**IMPORTANT**: 
1. Run `./scripts/cache-distfiles` on the host BEFORE running the workflow
2. The cache directory is mounted into containers at `/config/distfiles-cache/`
3. The prefetch script copies from cache (no network downloads in container)

## Implementation

### Files Created/Modified

#### 1. `scripts/prefetch-distfiles` (NEW)

**Purpose**: Download all required distfiles in container and transfer to legacy VM

**Features**:
- Hardcoded list of 18 distfiles for minimal curl build
- Downloads via `https://distfiles.macports.org/` (reliable, modern HTTPS)
- Fallback URLs for upstream sources (GitHub, GNU, etc)
- SSH/SCP to transfer files to VM
- Three-phase process with detailed logging
- Automatic cleanup of temporary files

**Dependency Tree Included**:
```
curl +ssl (minimal)
├── zlib
├── openssl3
│   └── zlib (already have)
├── pkgconfig
│   └── libiconv
│       └── gperf
├── libiconv (already have)
├── perl5.34
│   └── db48, gdbm
│       └── gettext, gettext-runtime
│           └── gettext-tools-libs
│               └── ncurses
├── readline
│   └── ncurses (already have)
└── xz (extract tool)
    unzip (extract tool)
```

**Total**: 18 unique distfiles (~150MB total)

#### 2. `scripts/updatemacports` (MODIFIED)

**Changes**:
- Modified curl installation to use minimal variants: `-brotli -http2 -idn -psl -zstd +ssl`
- Added comment about pre-fetched distfiles
- Checks for locally available distfiles before attempting download

**Reasoning for variants**:
- `-brotli`: Requires openssl → circular dependency
- `-http2`: Requires nghttp2 → additional complex dependencies
- `-idn`: Requires libidn2 → psl → additional deps
- `-psl`: Additional dependency chain
- `-zstd`: Less critical
- `+ssl`: OpenSSL provides modern TLS, no circular dep

#### 3. `.github/workflows/update-macports-legacy.yml` (MODIFIED)

**New Step**: "Pre-fetch distfiles for curl bootstrap"

**Workflow**:
1. Transfer both `prefetch-distfiles` and `updatemacports` scripts to VM
2. Run `prefetch-distfiles` which:
   - Downloads files in container
   - SCPs them to VM's distfiles directory
3. Then run `updatemacports` which finds local files

## Testing

### Local Testing (Container)

```bash
# Test script syntax
bash -n scripts/prefetch-distfiles

# Test with debug output (dry run simulation)
# Note: requires actual VM and SSH access
```

### VM Testing (tenseven - Mac OS X 10.7)

1. **Manual test** (before workflow integration):
```bash
cd /Users/blake/Developer/blakeports
ssh tenseven bash << 'EOF'
  # Check distfiles directory after prefetch
  ls -lah /opt/local/var/macports/distfiles/
  
  # Verify curl tarball is present
  ls -lh /opt/local/var/macports/distfiles/curl/curl-8.13.0.tar.xz
EOF
```

2. **Workflow test** (trigger update-macports-legacy):
```bash
gh workflow run "update-macports-legacy.yml" -f run_tenseven=true
```

3. **Expected behavior**:
   - Prefetch downloads ~150MB of distfiles in container
   - Transfers to VM via SCP
   - `port install curl` completes without downloading from internet
   - MacPorts binary is now linked to MacPorts curl

## Distfiles List

All 18 distfiles downloaded via `distfiles.macports.org`:

```
curl/curl-8.13.0.tar.xz                                2.7 MB
zlib/zlib-1.3.1.tar.xz                                 1.3 MB
openssl3/openssl-3.5.4.tar.gz                          53 MB
pkgconfig/pkg-config-0.29.2.tar.gz                     2.0 MB
libiconv/libiconv-1.17.tar.gz                          5.4 MB
gperf/gperf-3.3.tar.gz                                 1.8 MB
perl5.34/perl-5.34.3.tar.xz                            12.8 MB
db48/db-4.8.30.tar.gz                                  ~7 MB
gdbm/gdbm-1.26.tar.gz                                  0.7 MB
gettext/gettext-0.22.5.tar.gz                          26.8 MB
ncurses/ncurses-6.5.tar.gz                             ~3.5 MB
readline/readline-8.2.tar.gz                           ~3 MB
xz/xz-5.8.1.tar.bz2                                    1.9 MB
unzip/unzip60.tar.gz                                   1.4 MB
---
Total: ~150 MB
```

## Troubleshooting

### Prefetch script fails to download a file

The script includes fallback URLs. If both primary and fallback fail:

1. Check curl version in container: `curl --version`
2. Check URL accessibility: `curl -I https://distfiles.macports.org/curl/curl-8.13.0.tar.xz`
3. Add to script's `DISTFILES` array with working URL

### SCP transfer fails

**Symptoms**: "Connection refused" or "permission denied"

**Solutions**:
1. Verify SSH key is loaded: `ssh -i /config/ssh_keys/oldmac -v tenseven`
2. Check VM is running: `ping 192.168.234.110`
3. Verify distfiles directory exists: `ssh tenseven 'ls -ld /opt/local/var/macports/distfiles'`

### Port cannot find distfiles

**Symptoms**: Port still tries to download from internet

**Solutions**:
1. Verify files were transferred: `ssh tenseven 'ls /opt/local/var/macports/distfiles/curl/'`
2. Check permissions: `ssh tenseven 'stat /opt/local/var/macports/distfiles/curl/curl-8.13.0.tar.xz'`
3. Verify checksums match: Compare with `port info curl`

## Success Indicators

When working correctly:

1. ✅ Prefetch script completes without errors
2. ✅ All 18 distfiles appear in VM's distfiles directory
3. ✅ `port install curl` completes in < 10 minutes (no network time)
4. ✅ MacPorts curl is installed: `/opt/local/bin/curl --version`
5. ✅ MacPorts is recompiled with curl: `otool -L /opt/local/bin/port | grep libcurl`

## Future Improvements

1. **Dynamic dependency tree**: Query PortIndex instead of hardcoding distfiles
2. **Retry mechanism**: Implement exponential backoff for transient failures
3. **Progress tracking**: Show download progress in workflow logs
4. **Compression**: Pre-compress distfiles directory, transfer as single tarball
5. **Cache management**: Keep distfiles on runner for subsequent builds
