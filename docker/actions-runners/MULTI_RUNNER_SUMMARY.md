# Multi-Runner Setup Summary

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  GitHub Repository Push                      │
│            (e.g., textproc/bstring/Portfile)                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│           GitHub Actions Workflow Triggered                  │
│         (build-legacy-bstring-multi.yml)                     │
└──────────┬────────────────────────────┬─────────────────────┘
           │                            │
           │ (parallel execution)       │
           │                            │
           ▼                            ▼
┌──────────────────────┐    ┌──────────────────────┐
│  TenFive Job         │    │  TenSeven Job        │
│  runs-on: tenfive    │    │  runs-on: tenseven   │
└──────────┬───────────┘    └──────────┬───────────┘
           │                            │
           ▼                            ▼
┌──────────────────────┐    ┌──────────────────────┐
│ Runner 1 (TenFive)   │    │ Runner 2 (TenSeven)  │
│ Container            │    │ Container            │
│ Labels:              │    │ Labels:              │
│  - self-hosted       │    │  - self-hosted       │
│  - tenfive           │    │  - tenseven          │
│  - macos-10-5        │    │  - macos-10-7        │
└──────────┬───────────┘    └──────────┬───────────┘
           │                            │
           │ SSH                        │ SSH
           ▼                            ▼
┌──────────────────────┐    ┌──────────────────────┐
│ Mac OS X 10.5 VM     │    │ Mac OS X 10.7 VM     │
│ (TenFive)            │    │ (TenSeven)           │
│ - MacPorts installed │    │ - MacPorts installed │
│ - Builds bstring     │    │ - Builds bstring     │
└──────────────────────┘    └──────────────────────┘
```

## Key Benefits

### ✅ True Parallel Execution
Both VMs build **simultaneously**, not sequentially!

**Example Timeline:**
```
Without multi-runner (sequential):
├─ TenFive build: 45 min ─┤├─ TenSeven build: 30 min ─┤
Total: 75 minutes

With multi-runner (parallel):
├─ TenFive build:  45 min ─┤
├─ TenSeven build: 30 min ─┤
Total: 45 minutes (saves 30 min!)
```

### ✅ No Queuing
Each runner handles its own VM - no waiting!

### ✅ Independent Failures
If TenFive fails, TenSeven continues building.

### ✅ Better Resource Utilization
Builds run concurrently across available hardware.

## Quick Setup (5 minutes)

### Prerequisites
- GitHub CLI installed and authenticated: `gh auth login`
- Docker and docker-compose installed

### 1. One-Command Setup
```bash
cd /Users/blake/code/blakeports/docker/actions-runners
./quickstart-multi.sh
```

That's it! The script will:
- Generate runner registration tokens using `gh` CLI
- Create environment files automatically
- Build and start all runners

### Manual Setup (if needed)
```bash
# Generate registration tokens and create env files
./setup-multi-runners.sh

# Then start runners
docker-compose -f docker-compose-multi.yml up -d
```

### 2. Verify in GitHub
Go to: https://github.com/trodemaster/blakeports/settings/actions/runners

You should see:
- ✅ `docker-runner-tenfive` (Idle/Active)
- ✅ `docker-runner-tenseven` (Idle/Active)

### 3. Test the Setup
```bash
gh workflow run build-legacy-bstring.yml -f os_selection=all
```

Both VMs will build in parallel!

## Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose-multi.yml` | Multi-runner Docker configuration |
| `.env` | Single config file for all runners |
| `setup-multi-runners.sh` | Generates tokens and creates .env |
| `quickstart-multi.sh` | Builds and starts all runners |

### .env File Structure

```bash
# Shared configuration (applies to all runners)
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
GITHUB_TOKEN=<auto-generated>
RUNNER_WORKDIR=_work

# Per-runner configuration
TENFIVE_RUNNER_NAME=docker-runner-tenfive
TENFIVE_LABELS=tenfive,macos-10-5,legacy-macos

TENSEVEN_RUNNER_NAME=docker-runner-tenseven
TENSEVEN_LABELS=tenseven,macos-10-7,legacy-macos

# Add more runners by adding variables!
```

**Benefits of single .env:**
- All configurations in one place
- Shared values (repo, token) defined once
- Easy to add new runners - just add 2 variables
- Clean, maintainable structure

## GitHub Configuration

### Repository Variables Needed
- `TENFIVE_IP` - TenFive VM IP address
- `TENFIVE_USERNAME` - SSH username for TenFive
- `TENSEVEN_IP` - TenSeven VM IP address
- `TENSEVEN_USERNAME` - SSH username for TenSeven

### Repository Secrets Needed
- `TENFIVE_KEY` - SSH private key for TenFive VM
- `TENSEVEN_KEY` - SSH private key for TenSeven VM

## Workflow Updates

Old workflow (single runner, sequential):
```yaml
jobs:
  build-all:
    runs-on: [self-hosted, docker, ssh-capable]
    # Builds happen one after another
```

New workflow (multi-runner, parallel):
```yaml
jobs:
  build-tenfive:
    runs-on: [self-hosted, tenfive]  # Uses TenFive runner
    
  build-tenseven:
    runs-on: [self-hosted, tenseven]  # Uses TenSeven runner
    # Both jobs run simultaneously!
```

## Daily Operations

### Start All Runners
```bash
docker-compose -f docker-compose-multi.yml up -d
```

### Stop All Runners
```bash
docker-compose -f docker-compose-multi.yml down
```

### View Logs
```bash
# All runners
docker-compose -f docker-compose-multi.yml logs -f

# Specific runner
docker-compose -f docker-compose-multi.yml logs -f tenfive-runner
```

### Check Status
```bash
docker-compose -f docker-compose-multi.yml ps
```

### Monitor Resources
```bash
docker stats github-runner-tenfive github-runner-tenseven
```

## Adding More VMs

To add Mac OS X 10.6 (SnowLeopard):

### 1. Update .env file

Add two lines:
```bash
SNOWLEOPARD_RUNNER_NAME=docker-runner-snowleopard
SNOWLEOPARD_LABELS=snowleopard,macos-10-6,legacy-macos
```

### 2. Copy service in docker-compose-multi.yml

Add a new service using the template (change variable names):
```yaml
snowleopard-runner:
  environment:
    - RUNNER_NAME=${SNOWLEOPARD_RUNNER_NAME}
    - CUSTOM_LABELS=${SNOWLEOPARD_LABELS}
  # ... rest same as other runners
```

### 3. Configure GitHub

- Create variables: `SNOWLEOPARD_IP`, `SNOWLEOPARD_USERNAME`
- Create secret: `SNOWLEOPARD_KEY`

### 4. Update workflows

```yaml
runs-on: [self-hosted, snowleopard]
```

**That's it!** Just 2 variables in `.env` and copy the service definition.

## Troubleshooting

### Runners Not Appearing in GitHub
```bash
# Check logs for registration errors
docker-compose -f docker-compose-multi.yml logs tenfive-runner | grep -i error
```

### Runner Offline After Restart
```bash
# Restart specific runner
docker-compose -f docker-compose-multi.yml restart tenfive-runner
```

### SSH Connection Fails
```bash
# Verify SSH key is mounted
docker exec github-runner-tenfive ls -la /home/runner/.ssh
```

### Out of Resources
```bash
# Check Docker resource usage
docker system df
docker stats

# Clean up if needed
docker system prune -a
```

## Cost Analysis

### Resource Usage Per Runner
- **CPU**: ~5-10% idle, ~20-30% during builds
- **RAM**: ~200-300MB per runner
- **Disk**: ~2GB per runner

### Total for 2 Runners
- **RAM**: ~500MB
- **Disk**: ~4GB
- **Network**: Minimal (SSH traffic only)

Very reasonable for any modern system!

## Performance Comparison

### Single Runner (Sequential)
```
Port: netatalk
├─ TenFive:  60 minutes
└─ TenSeven: 45 minutes
Total: 105 minutes ❌
```

### Multi-Runner (Parallel)
```
Port: netatalk
├─ TenFive:  60 minutes ───┐
└─ TenSeven: 45 minutes ───┤
Total: 60 minutes ✅ (saves 45 min!)
```

### For 3 Ports Daily
Single runner: 315 minutes (5.25 hours)
Multi-runner: 180 minutes (3 hours)
**Daily savings: 2.25 hours!**

## Files Created

```
docker/actions-runners/
├── docker-compose-multi.yml       ← Multi-runner config (uses single .env)
├── .env                           ← Single config for all runners (gitignored)
├── setup-multi-runners.sh         ← Setup script (executable)
├── quickstart-multi.sh            ← Quick start script (executable)
├── MULTI_RUNNER_SETUP.md         ← Detailed setup guide
└── MULTI_RUNNER_SUMMARY.md       ← This file

.github/workflows/
├── build-legacy-bstring-multi.yml ← Updated workflow with labels
└── LEGACY_VM_SETUP.md            ← VM setup guide
```

**Note:** `.env` is auto-generated by setup script and contains sensitive tokens - never commit it!

## Next Steps

1. ✅ Authenticate with GitHub: `gh auth login` (if not already done)
2. ✅ Run: `./quickstart-multi.sh` (generates tokens and starts runners)
3. ✅ Verify runners in GitHub at: https://github.com/trodemaster/blakeports/settings/actions/runners
4. ✅ Test with: `gh workflow run build-legacy-bstring.yml -f os_selection=all`
5. ✅ Watch both VMs build in parallel!
6. ✅ Apply same pattern to libcbor, netatalk, libfido2 workflows

**Pro tip:** The single `.env` file makes it super easy to add more VMs - just add 2 variables per runner!

Enjoy your parallel builds! 🚀

