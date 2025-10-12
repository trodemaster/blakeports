# blakeports
Personal MacPorts repository with custom ports and automated CI/CD workflows.

## Docker Infrastructure

The `docker/` directory contains containerized tools for development and testing:

### SSH Legacy Proxy

A Docker container that bridges modern OpenSSH 10+ clients with legacy SSH servers that only support deprecated algorithms (ssh-rsa, ssh-dss). Essential for connecting to older macOS systems (10.6-10.8) used in testing.

**Quick Start:**
```bash
cd docker/ssh
./setup.sh           # Interactive setup
docker compose up -d # Start proxy
```

Then add to `~/.ssh/config`:
```ssh-config
Host ssh-proxy
  Hostname localhost
  Port 2222
  User sshproxy
  IdentityFile ~/.ssh/macports

Host tenseven
  Hostname tenseven.local
  User blake
  ProxyJump ssh-proxy
  IdentityFile ~/.ssh/oldmac
```

See [docker/ssh/README.md](docker/ssh/README.md) for complete documentation.

## Scripts

- `scripts/installmacports` - Installs MacPorts and configures BlakePorts as the default source
- `scripts/boop` - Creates an empty commit to trigger GitHub Actions workflows
- `scripts/install-deps` - Installs all dependencies for a given port (build + runtime or runtime-only)
- `scripts/syncfromgitports` - Syncs `_resources` and active port directories from upstream MacPorts repository
- `scripts/fulltest` - **Comprehensive test script** - Recreates all runners and triggers all port builds

### `syncfromgitports` - Sync from MacPorts Repository

Efficiently syncs your BlakePorts repository with the upstream MacPorts repository without requiring a full local clone.

**Key Features:**
- 🔍 **Auto-discovery** - Automatically finds all active ports by scanning for Portfiles
- ⚡ **Efficient syncing** - Uses 4 fallback methods (git archive, GitHub API, sparse checkout, shallow clone)  
- 📊 **Selective operations** - Sync everything, only resources, or only ports
- 🛡️ **Safe by default** - Won't overwrite existing directories without `--force`

**Usage:**
```bash
# Show all discovered active ports
./scripts/syncfromgitports --list-ports

# Sync everything (_resources + all active ports)
./scripts/syncfromgitports --force

# Sync only the _resources directory 
./scripts/syncfromgitports --resources-only --force

# Sync only active port directories
./scripts/syncfromgitports --ports-only --force

# Sync from a specific MacPorts branch
./scripts/syncfromgitports --branch release-2.9

# Show help
./scripts/syncfromgitports --help
```

**What it syncs:**
- `_resources/` - MacPorts build system files, port groups, and configurations
- Active port directories (e.g., `devel/libcbor`, `net/netatalk4`) - Latest versions from MacPorts

### `fulltest` - Comprehensive Testing

Complete end-to-end testing script that recreates the entire CI/CD pipeline from scratch.

**Key Features:**
- 🧹 **Clean slate testing** - Complete teardown and fresh rebuild of all runners
- 🧪 **Complete port coverage** - Triggers builds for all ports in the repository
- 📊 **Matrix validation** - Ensures builds work on both macOS versions
- ⏱️ **Status monitoring** - Waits for runners and tracks build progress
- 🛡️ **Safety checks** - Validates prerequisites and prompts for confirmation

**Usage:**
```bash
# Run comprehensive test (interactive)
./scripts/fulltest

# What it does:
# 1. Removes all existing runners (macOS_15, macOS_26)
# 2. Creates fresh runner VMs 
# 3. Waits for runners to come online
# 4. Triggers all port build workflows
# 5. Shows monitoring commands for tracking progress
```

**When to use:**
- Testing major changes to the CI/CD pipeline
- Validating the entire port collection after upstream sync
- Ensuring runner health after system updates
- Demonstrating the complete workflow to contributors

**Prerequisites:**
- [jibb-runners](https://github.com/trodemaster/jibb-runners) cloned at `../jibb-runners`
- GitHub CLI authenticated (`gh auth login`)
- Base VMs (`macOS_15`, `macOS_26`) available in tart

## Ports

- `audio/nrsc5` - Software-defined radio for NRSC-5 (HD Radio)
- `devel/libcbor` - CBOR protocol implementation library  
- `security/libfido2` - FIDO2 authentication library
- `net/netatalk4` - Apple Filing Protocol (AFP) server

## Self-Hosted Runners

### Setting Up Runners

This repository uses self-hosted GitHub runners managed by the [jibb-runners](https://github.com/trodemaster/jibb-runners) tool. Each runner runs in an isolated tart VM.

**Prerequisites:**
- [Tart](https://tart.run/) - macOS virtualization  
- [GitHub CLI](https://cli.github.com/) - GitHub API access
- Base VMs named `macOS_15` and `macOS_26`

**Start Runners:**
```bash
cd ../jibb-runners

# Start both runners
./ghrunner.sh -tart macOS_15
./ghrunner.sh -tart macOS_26

# Check runner status
./ghrunner.sh -list
```

**Manage Runners:**
```bash
# Remove a stuck runner
./ghrunner.sh -remove macOS_15

# Restart a runner
./ghrunner.sh -remove macOS_15 && ./ghrunner.sh -tart macOS_15
```

### Runner Status Commands

```bash
# List all registered runners with status
./ghrunner.sh -list

# Expected output:
# NAME          STATUS    BUSY    OS      LABELS
# macOS_15      online    false   macOS   self-hosted,macOS,ARM64,tart  
# macOS_26 online    false   macOS   self-hosted,macOS,ARM64,tart
```

## GitHub Actions Workflows

### Multi-macOS Matrix Builds

All port builds run simultaneously on multiple macOS versions to ensure compatibility:

- **macOS 15 (Sequoia)** - Latest stable macOS version
- **macOS 26 Beta** - Preview of upcoming macOS features

Each workflow automatically creates **parallel jobs** for both macOS versions:
- 🔄 **Parallel execution** - Both versions build simultaneously for faster feedback
- ✅ **Compatibility testing** - Ensures ports work across macOS versions  
- 🛡️ **Isolated environments** - Each runner uses dedicated VM instances
- 📊 **Independent results** - Builds can succeed on one version and fail on another

**Matrix Strategy Benefits:**
- Early detection of macOS version-specific issues
- Confidence in port compatibility across the macOS ecosystem
- Faster overall build times through parallelization

### Manual Workflow Triggering

Use the GitHub CLI to manually trigger workflows for debugging without making commits:

```bash
# Trigger individual port workflows
gh workflow run "Build netatalk4"
gh workflow run "Build libfido2" 
gh workflow run "Build libcbor"
gh workflow run "Build nrsc5"

# Note: MacPorts installation is now handled automatically by each build workflow
```

### Monitor Matrix Workflow Runs

**Check Overall Run Status:**
```bash
# List recent runs for a specific workflow
gh run list --workflow=build-libcbor.yml

# View the latest run details with job breakdown
gh run view

# Watch a running workflow in real-time  
gh run watch
```

**View Matrix Job Details:**
```bash
# See individual matrix jobs for latest run
gh run view --json jobs --jq '.jobs[] | {name: .name, runner_name: .runner_name, status: .status, conclusion: .conclusion}'

# Expected output:
# {
#   "name": "build-libcbor (macOS_15)",
#   "runner_name": "macOS_15", 
#   "status": "completed",
#   "conclusion": "success"
# }
# {
#   "name": "build-libcbor (macOS_26)",
#   "runner_name": "macOS_26",
#   "status": "completed", 
#   "conclusion": "success"
# }
```

**Open in Browser (Best Visual Experience):**
```bash
# Open latest run in browser - shows matrix jobs clearly
gh run view -w

# You'll see both jobs with their macOS versions:
# ✅ build-libcbor (macOS_15)
# ✅ build-libcbor (macOS_26)
```

**Check Logs by macOS Version:**
```bash
# View logs for specific matrix job
gh run view --log --job "build-libcbor (macOS_15)"
gh run view --log --job "build-libcbor (macOS_26)"

# View only failed logs across all jobs
gh run view --log-failed
```

**Verify Runner Availability:**
```bash
# Before triggering workflows, ensure both runners are online
cd ../jibb-runners && ./ghrunner.sh -list

# Both should show: STATUS=online, BUSY=false
```

### Benefits of Manual Triggering

- **No commits needed** - Perfect for debugging without polluting git history
- **Quick iteration** - Test changes rapidly during development  
- **Selective testing** - Run only the specific port workflow you're debugging
- **Real-time feedback** - Monitor build progress and logs immediately
- **Multi-version testing** - Each manual trigger tests on both macOS 15 and macOS 26 Beta automatically

### Troubleshooting Matrix Builds

**Issue: Only one job runs instead of two**
```bash
# Check if both runners are online
cd ../jibb-runners && ./ghrunner.sh -list

# If a runner shows offline or busy=true, restart it:
./ghrunner.sh -remove macOS_26
./ghrunner.sh -tart macOS_26
```

**Issue: Matrix job fails on specific macOS version**
```bash
# View logs for the failing job
gh run view --log --job "build-libcbor (macOS_26)"

# Check runner-specific issues
ssh admin@$(tart ip macOS_26_runner) "system_profiler SPSoftwareDataType"
```

**Issue: Runner stuck in busy state**
```bash
# Force restart the stuck runner
./ghrunner.sh -remove macOS_15 && ./ghrunner.sh -tart macOS_15
```

**Quick Health Check:**
```bash
# Verify complete setup
cd ../jibb-runners && ./ghrunner.sh -list
# ✅ Both runners should be: online=true, busy=false

cd ../blakeports && gh workflow run "Build libcbor"
# ✅ Should create 2 parallel jobs
```

## Workflow Structure

All workflows use consolidated setup and matrix strategies for consistency and comprehensive testing:
- **Consolidated setup** - Each workflow uses `./scripts/installmacports` for idempotent MacPorts and BlakePorts configuration
- **Matrix builds** - Each workflow runs on multiple macOS versions (`macOS_15`, `macOS_26`)
- Individual port workflows automatically trigger on changes to their respective directories
- Clean builds with automatic uninstall/cleanup of existing port installations
- Self-hosted runners using isolated tart VMs for each macOS version

## Development

Generate checksums for new ports:
```bash
openssl dgst -rmd160 rrdtool-1.2.23.tar.gz
openssl dgst -sha256 rrdtool-1.2.23.tar.gz
```

## Quick Reference

### Most Common Commands

**Start/Check Runners:**
```bash
cd ../jibb-runners
./ghrunner.sh -list                    # Check runner status
./ghrunner.sh -tart macOS_15          # Start macOS 15 runner  
./ghrunner.sh -tart macOS_26     # Start macOS 26 Beta runner
```

**Trigger Matrix Builds:**
```bash
cd ../blakeports
gh workflow run "Build libcbor"       # Builds on both macOS versions
gh workflow run "Build nrsc5"         # Builds on both macOS versions
```

**Monitor Builds:**
```bash
gh run view -w                        # Open in browser (best view)
gh run view --json jobs --jq '.jobs[] | {name: .name, status: .status}'  # CLI status
```

**Fix Issues:**
```bash
# Restart stuck runner
./ghrunner.sh -remove macOS_26 && ./ghrunner.sh -tart macOS_26

# View specific job logs
gh run view --log --job "build-libcbor (macOS_15)"
```

**Comprehensive Testing:**
```bash
# Full end-to-end test (recreates all runners + builds all ports)
./scripts/fulltest
```