`# GitHub Actions Self-Hosted Runners for Legacy macOS VMs

Docker-based GitHub Actions self-hosted runners with OpenSSH 9.x support for executing workflows on legacy macOS VMs (10.5-10.10).

## Directory Structure

```
docker/
├── Dockerfile              # Ubuntu 24.04 base with GitHub Actions runner & OpenSSH 9.x
├── entrypoint.sh           # Runner registration, SSH monitoring, and conditional startup
├── docker-compose.yml      # Multi-service orchestration (tenfive, tenseven + templates)
├── Makefile                # Automation for build, deployment, token generation, cleanup
├── example.env             # Environment configuration template
├── .env                    # Live environment (populated by Makefile, .gitignore'd)
├── README.md               # Comprehensive guide (this file)
├── SETUP.md                # Detailed setup and troubleshooting
└── ssh_keys/               # SSH key directory
    ├── .gitignore          # Prevents SSH keys from git commits
    ├── .gitkeep            # Maintains directory structure in git
    └── oldmac              # SSH private key (read-only, not committed)
```

## Architecture Overview

**Per-VM Container Model**: Each Docker container runs a single GitHub Actions runner instance targeting one legacy macOS VM. The runner registers with GitHub immediately but only accepts jobs once SSH connectivity to the target legacy VM is verified.

**Key Design Decisions:**

1. **Immediate Registration, Conditional Activation**: Runners register with GitHub on startup but remain in `offline` state until SSH connection succeeds. This allows:
   - Verification that runners are registered and available for activation
   - Conditional job execution based on SSH proxy readiness
   - Non-blocking container startup (no waiting for legacy VM availability)

2. **SSH Monitoring Loop**: After registration, a background SSH monitor process:
   - Checks connectivity every 30 seconds
   - Starts the runner service when SSH succeeds
   - Stops the runner service if SSH is lost
   - Continues monitoring indefinitely
   - Logs all state changes

3. **Docker Compose v2**: Uses native `docker compose` command (not deprecated `docker-compose`)

4. **Makefile Automation**: Single `make build` command orchestrates the full pipeline:
   - Environment setup
   - Token generation
   - Image building
   - Container startup
   - Verification

**Supported Legacy macOS Versions:**

| Version | Runner Name | Status | .local hostname |
|---------|-------------|--------|-----------------|
| 10.5 (Leopard) | `tenfive-runner` | ✅ Enabled | `tenfive.local` |
| 10.7 (Lion) | `tenseven-runner` | ✅ Enabled | `tenseven.local` |
| 10.6 (Snow Leopard) | `tensix-runner` | 📝 Template | `tensix.local` |
| 10.8 (Mountain Lion) | `teneight-runner` | 📝 Template | `teneight.local` |
| 10.9 (Mavericks) | `tennine-runner` | 📝 Template | `tennine.local` |
| 10.10 (Yosemite) | `tenten-runner` | 📝 Template | `tenten.local` |

## Quick Start with Makefile

The simplest way to deploy:

```bash
cd docker

# One command does everything:
# - Checks dependencies (gh, docker, docker compose)
# - Creates .env file
# - Generates registration tokens
# - Builds Docker images
# - Starts containers
# - Displays status
make build
```

View logs in real-time:
```bash
make logs
```

Check runner status on GitHub:
```bash
gh api repos/trodemaster/blakeports/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

Clean up (unregister from GitHub, stop containers, remove volumes):
```bash
make clean
```

## Makefile Targets

| Target | Purpose |
|--------|---------|
| `make build` | Build images, start containers, generate tokens (integrated) |
| `make up` | Start containers (part of `make build`) |
| `make down` | Stop containers |
| `make logs` | Follow container logs in real-time |
| `make status` | Show container status |
| `make clean` | Full cleanup (unregister from GitHub, remove volumes) |
| `make token-tenfive` | Generate token for tenfive runner |
| `make token-tenseven` | Generate token for tenseven runner |

## Manual Setup

If you prefer manual setup without the Makefile:

### 1. SSH Key Setup

```bash
# Copy OLDMAC_KEY from GitHub secrets to local file
echo "$OLDMAC_KEY" > ssh_keys/oldmac
chmod 600 ssh_keys/oldmac
```

### 2. Environment Configuration

```bash
cp example.env .env
```

Edit `.env`:
```bash
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
LEGACY_TENFIVE_HOSTNAME=tenfive-runner.local
LEGACY_TENSEVEN_HOSTNAME=tenseven-runner.local
LEGACY_USERNAME=admin
```

### 3. Generate Registration Tokens

```bash
# Generate token for tenfive runner
TENFIVE_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENFIVE=$TENFIVE_TOKEN" >> .env

# Generate token for tenseven runner
TENSEVEN_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENSEVEN=$TENSEVEN_TOKEN" >> .env
```

### 4. Build and Deploy

```bash
docker compose build
docker compose up -d
```

## Runner Behavior

### Registration Phase
1. Container starts
2. SSH key and configuration verified
3. Runner registers with GitHub (unique token per instance)
4. Runner appears on GitHub as `offline`

### SSH Monitoring Phase
1. Background process starts (PID logged)
2. Checks SSH connectivity every 30 seconds
3. **When SSH succeeds**: 
   - Starts runner service
   - Runner becomes `online` on GitHub
   - Runner begins accepting jobs
4. **If SSH fails/lost**:
   - Stops runner service  
   - Runner becomes `offline` on GitHub
   - SSH monitoring continues

### Idle Phase
When SSH is available:
- Runner listens for jobs from GitHub
- Executes workflows on target legacy VM via SSH proxy
- Returns results to GitHub

When SSH is unavailable:
- Runner remains registered but offline
- No jobs are queued
- SSH monitoring continues every 30 seconds
- Runner will auto-reactivate when SSH succeeds

## SSH Configuration Details

All containers use the same SSH configuration with legacy algorithm support:

```
Host <VM_HOSTNAME>
    HostKeyAlgorithms ssh-rsa
    PubkeyAcceptedKeyTypes ssh-rsa
    KexAlgorithms diffie-hellman-group1-sha1
    Ciphers aes128-cbc
    MACs hmac-sha1
    StrictHostKeyChecking no
    ConnectTimeout 10
```

These settings are required for compatibility with Mac OS X 10.5-10.10.

## Implementation Details: Legacy Runner SSH Proxy Architecture

This section documents the Docker runner implementation for legacy macOS VM SSH proxy support, aligned with the `PLANNED_IMPROVEMENTS.md` workflow consolidation requirements.

### Design Goals

1. **Per-VM Container**: One Docker container per legacy VM for clean separation of concerns
2. **Unique Tokens**: Each runner instance registers with GitHub using a unique token
3. **Simple SSH Key Management**: Single shared SSH key mounted read-only into all containers
4. **Legacy Algorithm Support**: SSH configured with deprecated but necessary algorithms for 10.5-10.10 compatibility
5. **Easy Scaling**: Commented templates in docker-compose.yml for future VM versions

### File Structure

```
docker/
├── Dockerfile              # Ubuntu 24.04, OpenSSH 9.x, GitHub runner
├── entrypoint.sh           # Per-VM SSH config & validation
├── docker-compose.yml      # Multi-service: tenfive, tenseven (+ commented templates)
├── example.env             # Per-VM configuration template
├── README.md               # Comprehensive setup & troubleshooting guide
└── ssh_keys/
    ├── .gitignore          # Prevents SSH keys from git commits
    ├── .gitkeep            # Keeps directory in git
    └── oldmac              # SSH private key (not committed)
```

### Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Host                              │
│  ┌──────────────────────┐  ┌──────────────────────┐         │
│  │  tenfive-runner      │  │  tenseven-runner     │         │
│  │  (Ubuntu 24.04)      │  │  (Ubuntu 24.04)      │         │
│  │                      │  │                      │         │
│  │ ┌────────────────┐   │  │ ┌────────────────┐   │         │
│  │ │ GitHub Actions │   │  │ │ GitHub Actions │   │         │
│  │ │ Runner         │   │  │ │ Runner         │   │         │
│  │ └────────────────┘   │  │ └────────────────┘   │         │
│  │        ↓             │  │        ↓             │         │
│  │ ┌────────────────┐   │  │ ┌────────────────┐   │         │
│  │ │ SSH Client     │   │  │ │ SSH Client     │   │         │
│  │ │ (Legacy Algos) │   │  │ │ (Legacy Algos) │   │         │
│  │ └────────────────┘   │  │ └────────────────┘   │         │
│  └──────────────────────┘  └──────────────────────┘         │
│           │ SSH                      │ SSH                    │
│           │ (RSA, DH1,               │ (RSA, DH1,             │
│           │  AES-CBC)                │  AES-CBC)              │
├───────────┼──────────────────────────┼─────────────────────┤
│ Network   │                          │                       │
│           ↓                          ↓                       │
│    ┌────────────────┐         ┌────────────────┐            │
│    │ Mac OS X 10.5  │         │ Mac OS X 10.7  │            │
│    │ (tenfive VM)   │         │ (tenseven VM)  │            │
│    └────────────────┘         └────────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

### SSH Algorithm Configuration

The entrypoint.sh configures OpenSSH with legacy algorithms matching the `scripts/ghrunner` approach:

```bash
# Legacy SSH Options (from ghrunner script)
HostKeyAlgorithms ssh-rsa
PubkeyAcceptedKeyTypes ssh-rsa
KexAlgorithms diffie-hellman-group1-sha1
Ciphers aes128-cbc
MACs hmac-sha1
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null
ConnectTimeout 10
```

**Why these algorithms?**
- `ssh-rsa`: Only key type supported by legacy VMs
- `diffie-hellman-group1-sha1`: Legacy key exchange algorithm (weak but necessary)
- `aes128-cbc`: Older cipher mode (legacy VMs don't support modern GCM modes)
- `hmac-sha1`: Legacy message authentication code

### Per-VM Runner Configuration

Each service in `docker-compose.yml` follows this pattern:

```yaml
service-name-runner:
  environment:
    # GitHub config (shared)
    - GITHUB_OWNER=trodemaster
    - GITHUB_REPO=blakeports
    
    # Runner registration (unique per instance)
    - RUNNER_TOKEN=${RUNNER_TOKEN_SERVICE}
    - RUNNER_NAME=${RUNNER_NAME_SERVICE:-service-name-runner}
    
    # SSH proxy target (per-VM)
    - VM_IP=${LEGACY_SERVICEIP}
    - VM_HOSTNAME=service-name
    - VM_USER=${LEGACY_USERNAME:-admin}
    - SSH_KEY_NAME=oldmac
  
  volumes:
    # SSH key (read-only, shared)
    - ./ssh/keys/oldmac:/home/runner/.ssh/oldmac:ro
    # Work directory (unique per service)
    - runner-work-service:/home/runner/_work
```

**Key Points:**
- `RUNNER_TOKEN_*`: Each runner gets unique token (generated per instance)
- `VM_IP`: Per-VM network address
- `VM_HOSTNAME`: Used for SSH config and runner labels
- `SSH_KEY_NAME`: Points to mounted key file

### Entrypoint Script Flow

The `entrypoint.sh` executes this sequence on container startup:

1. **Validate environment**: Check all required `VM_*`, `GITHUB_*`, `RUNNER_TOKEN` vars
2. **Verify SSH key**: Ensure key file exists at `/home/runner/.ssh/oldmac`
3. **Generate SSH config**: Create `/home/runner/.ssh/config` with legacy algorithms
4. **Validate SSH connectivity**: Test connection to target VM (6 retries, 10-second timeout each)
5. **Generate labels**: Build runner labels including VM hostname (e.g., `tenfive`)
6. **Register with GitHub**: Call `config.sh` with unique token
7. **Start runner**: Execute `run.sh` to listen for workflow jobs

**SSH validation with retries:**
```bash
MAX_RETRIES=6        # 60 seconds total (6 × 10s)
RETRY_DELAY=10       # Seconds between attempts
ConnectTimeout=10    # Per-attempt timeout
```

### GitHub Secrets/Variables Integration

Aligned with `PLANNED_IMPROVEMENTS.md` consolidation:

**Repository Secrets:**
- `OLDMAC_KEY` - Single SSH private key for all legacy VMs

**Repository Variables:**
- `LEGACY_TENFIVE_HOSTNAME` - Fixed hostname for 10.5 VM (e.g., `tenfive-runner.local`)
- `LEGACY_TENSEVEN_HOSTNAME` - Fixed hostname for 10.7 VM (e.g., `tenseven-runner.local`)
- `LEGACY_TENSIX_HOSTNAME` - (future) Fixed hostname for 10.6 VM
- `LEGACY_TENEIGHT_HOSTNAME` - (future) Fixed hostname for 10.8 VM
- `LEGACY_TENNINE_HOSTNAME` - (future) Fixed hostname for 10.9 VM
- `LEGACY_TENTEN_HOSTNAME` - (future) Fixed hostname for 10.10 VM
- `LEGACY_USERNAME` - Shared SSH username (default: `admin`)

## Docker Design Choices

### 1. **One Container Per Legacy VM**

**Rationale**: Clean separation of concerns, independent resource allocation, and simplified SSH configuration per target.

**Benefits**:
- Easier to debug which runner has SSH issues
- Can restart individual runners without affecting others
- Simpler container logs (per-VM context)
- Scales horizontally by uncommenting templates

**Trade-off**: Slightly more Docker overhead vs. single multi-VM container

### 2. **Ubuntu 24.04 Base Image**

**Rationale**: Modern, stable, long-term support, excellent GitHub Actions runner compatibility.

**Why not Alpine**: Alpine lacks glibc compatibility with some GitHub Actions tools, causing runtime failures.

**Why not Debian**: Ubuntu has better GitHub Actions runner documentation and community support.

### 3. **Immediate Registration, Conditional Activation**

**Previous Approach**: Blocked on SSH connectivity during startup (60+ second delay, failed startup if SSH unavailable)

**Current Approach**: 
- Register immediately (< 10 seconds)
- Show as `offline` on GitHub
- Monitor SSH in background
- Auto-start when ready

**Benefits**:
- Faster container startup (no blocking)
- Better visibility (registered ≠ active)
- Flexible deployment (runners available before legacy VMs online)
- Non-blocking infrastructure
- Clear separation between registration and activation

### 4. **Background SSH Monitoring Loop**

**Rationale**: Automated, continuous health checking without manual intervention.

**Implementation**:
- Runs after registration in separate background process
- 30-second check interval (configurable)
- Starts runner service when SSH succeeds → runner becomes `online`
- Stops runner service when SSH fails → runner becomes `offline`
- Persistent logging of all state changes
- Runs indefinitely, doesn't block main process

**Benefits**:
- Automatic recovery when SSH returns
- Clear audit trail in logs
- Prevents job queueing when proxy unavailable
- Simple troubleshooting (check logs for SSH state)
- No manual restart needed

### 5. **Docker Compose v2 (Native)**

**Change**: Migrated from deprecated `docker-compose` command to native `docker compose` v2

**Why v2**: 
- Built into Docker Engine (no separate installation)
- Better performance (Go-based vs. Python)
- Active development and support
- Clearer error messages

**Migration Impact**:
- All Makefile commands updated
- All documentation updated
- No functional changes to docker-compose.yml
- Backward compatible with existing configurations

### 6. **Makefile Automation**

**Rationale**: Single entry point for complex multi-step deployment pipeline.

**Workflow** (all in `make build`):
```
Verify dependencies (gh, docker, docker compose)
    ↓
Create .env from example.env (if missing)
    ↓
Generate registration tokens (one per active runner)
    ↓
Check SSH key permissions
    ↓
Build Docker images
    ↓
Start containers
    ↓
Wait and verify container status
    ↓
Report runner status on GitHub
```

**Key Targets**:
- `make build` - Complete build & deploy pipeline
- `make up` - Start containers only
- `make down` - Stop containers only
- `make logs` - Follow container logs
- `make status` - Check current status
- `make clean` - Full cleanup (unregister from GitHub, remove volumes)

**Benefits**:
- Repeatable, consistent deployments
- Error checking at each step
- Clear progress reporting
- No manual token generation steps
- Automated dependency verification
- Integrated cleanup with GitHub unregistration

### 7. **Environment File Management (.env)**

**Approach**:
- `example.env` - Tracked template (no secrets)
- `.env` - Generated live file (.gitignore'd)
- Makefile populates `.env` from `example.env`
- Docker Compose loads environment from `.env`

**Benefits**:
- Secrets never in git history
- Clear template for new deployments
- Environment-specific configuration
- CI/CD friendly (can be populated by GitHub Actions)
- Easy to audit (see example.env for structure)

### 8. **Legacy SSH Algorithm Support**

**Necessity**: Mac OS X 10.5-10.10 only support deprecated SSH algorithms that modern OpenSSH 9.x disabled by default.

**Configured in entrypoint.sh**:
```bash
HostKeyAlgorithms ssh-rsa
PubkeyAcceptedKeyTypes ssh-rsa
KexAlgorithms diffie-hellman-group1-sha1
Ciphers aes128-cbc
MACs hmac-sha1
StrictHostKeyChecking no
ConnectTimeout 10
```

**Security Considerations**:
- These algorithms are considered weak by modern standards
- Usage is restricted to isolated internal legacy VMs
- Not exposed to internet-facing services
- Alternative: Full system modernization (not feasible for legacy MacPorts ecosystem)

## Troubleshooting

### Runner shows as `offline` on GitHub

Check SSH connectivity in logs:
```bash
make logs | grep -i "ssh connection"
```

Expected when SSH unavailable:
```
[WARNING] SSH connection to tenfive unavailable
```

Expected when SSH available:
```
[SUCCESS] SSH connection to tenfive ESTABLISHED
```

When SSH becomes available, runner will automatically transition to `online`.

### SSH connection fails repeatedly

1. Verify SSH key exists and has correct permissions:
   ```bash
   ls -l docker/ssh_keys/oldmac
   # Should show: -rw------- (600)
   ```

2. Test SSH manually from container:
   ```bash
   docker compose exec tenfive-runner ssh -F ~/.ssh/config tenfive echo test
   ```

3. Check SSH configuration in container:
   ```bash
   docker compose exec tenfive-runner cat ~/.ssh/config
   ```

### Container exits immediately

Check logs for errors:
```bash
docker compose logs tenfive-runner | head -50
```

Common causes:
- SSH key file not found (wrong path or permissions)
- Registration token expired (regenerate with `make token-tenfive`)
- GitHub API unreachable (network issue)
- Missing environment variables (check `.env` file)

### Registration token expired

Tokens expire after 1 hour. Regenerate:
```bash
make token-tenfive
make token-tenseven
```

Then restart containers:
```bash
docker compose restart
```

## Maintenance & Operations

### View Logs

```bash
# Follow all runner logs in real-time
make logs

# View specific runner (last 50 lines)
docker compose logs --tail 50 tenfive-runner

# Search logs for SSH status
docker compose logs tenfive-runner | grep "SSH connection"
```

### Check Status

```bash
# Docker status
make status

# GitHub status
gh api repos/trodemaster/blakeports/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

### Restart Runners

```bash
# Restart all
docker compose restart

# Restart specific runner
docker compose restart tenfive-runner
```

Runners will re-register and go through SSH monitoring again.

### Completely Clean Up

```bash
make clean
```

This:
- Unregisters runners from GitHub (via API)
- Stops containers
- Removes volumes (runner state)
- Cleans up networks

### Activate Additional Legacy VM

To add Mac OS X 10.8 (Mountain Lion):

1. **Uncomment** `teneight-runner` section in `docker-compose.yml`

2. **Add to `.env`**:
   ```bash
   LEGACY_TENEIGHT_HOSTNAME=teneight-runner.local
   RUNNER_TOKEN_TENEIGHT=<will-be-generated>
   ```

3. **Deploy**:
   ```bash
   make build
   ```

Makefile will detect new runner and generate token automatically.

## Security Notes

1. **SSH Keys**: Never commit SSH keys to git. Use `.gitignore` and GitHub Secrets.
2. **Tokens**: Registration tokens expire after 1 hour. Always generate fresh tokens.
3. **Network**: Containers should be on isolated networks when deploying to untrusted environments.
4. **Updates**: Regularly rebuild images to pick up base image security patches.
5. **Credentials**: Never hardcode credentials. Use environment variables and GitHub Secrets.

## License

These Docker configurations are part of the blakeports project and follow the project license.

