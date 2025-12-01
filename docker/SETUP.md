# GitHub Actions Self-Hosted Runners (Docker) - Setup Guide

Docker-based GitHub Actions self-hosted runner containers with OpenSSH 9.x support for connecting to legacy macOS VMs (10.5-10.10).

## Quick Start with Makefile (Recommended)

The simplest way to deploy everything in one command:

```bash
cd docker

# This single command does everything:
# - Checks dependencies (gh, docker, docker compose)
# - Creates .env file from example.env
# - Generates unique tokens for each runner
# - Builds Docker images
# - Starts containers
# - Displays status
make build
```

**First Run Only**: You'll need the SSH key:

```bash
# Copy SSH key from GitHub Secrets
echo "$OLDMAC_KEY" > ssh_keys/oldmac
chmod 600 ssh_keys/oldmac
```

Then run `make build`.

### Verify Deployment

```bash
# Check container status
make status

# View logs
make logs

# Check GitHub registration
gh api repos/trodemaster/blakeports/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

### Common Operations

```bash
# Stop containers
make down

# Completely clean up (unregister from GitHub, remove volumes)
make clean

# Restart after cleanup
make build
```

## Manual Setup (Without Makefile)

If you prefer to set up manually:

### 1. Copy SSH Key

```bash
cd docker

# Copy OLDMAC_KEY secret from GitHub repository settings
echo "$OLDMAC_KEY" > ssh_keys/oldmac
chmod 600 ssh_keys/oldmac

# Verify permissions
ls -l ssh_keys/oldmac  # Should show: -rw------- (600)
```

### 2. Configure Environment

```bash
cp example.env .env
```

Edit `.env`:
```bash
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports

# Legacy VM hostnames (.local hostname resolution)
LEGACY_TENFIVE_HOSTNAME=tenfive-runner.local
LEGACY_TENSEVEN_HOSTNAME=tenseven-runner.local

# Shared SSH username for all legacy VMs
LEGACY_USERNAME=admin
```

### 3. Generate Registration Tokens

Each runner needs a unique token (valid for 1 hour):

```bash
# Generate token for tenfive runner
TENFIVE_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENFIVE=$TENFIVE_TOKEN" >> .env

# Generate token for tenseven runner
TENSEVEN_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENSEVEN=$TENSEVEN_TOKEN" >> .env
```

### 4. Build and Start

```bash
# Build images
docker compose build

# Start all active runners
docker compose up -d

# Verify
docker compose ps
docker compose logs -f
```

## Architecture

**Per-VM Design**: One container per legacy macOS VM

- **Container**: Runs on modern Ubuntu 24.04 with GitHub Actions runner
- **SSH Proxy**: Connects to target legacy VM via SSH
- **Execution**: Workflow commands run on the legacy VM, not the container
- **Result**: GitHub Actions workflows execute on legacy macOS 10.5-10.10

**Runner Lifecycle**:
1. Container starts → SSH key and config verified
2. Runner registers with GitHub (shows as `offline`)
3. Background SSH monitor starts checking connectivity every 30 seconds
4. When SSH succeeds → Runner service starts → Runner becomes `online` on GitHub
5. When SSH fails → Runner service stops → Runner becomes `offline` on GitHub
6. Monitor continues checking and will auto-restart when SSH returns

## Supported macOS Versions

| Version | Runner | Status | Container Image |
|---------|--------|--------|-----------------|
| 10.5 (Leopard) | `tenfive-runner` | ✅ Active | `docker-tenfive-runner` |
| 10.7 (Lion) | `tenseven-runner` | ✅ Active | `docker-tenseven-runner` |
| 10.6 (Snow Leopard) | `tensix-runner` | 📝 Template | Uncomment in docker-compose.yml |
| 10.8 (Mountain Lion) | `teneight-runner` | 📝 Template | Uncomment in docker-compose.yml |
| 10.9 (Mavericks) | `tennine-runner` | 📝 Template | Uncomment in docker-compose.yml |
| 10.10 (Yosemite) | `tenten-runner` | 📝 Template | Uncomment in docker-compose.yml |

## Makefile Reference

| Command | Purpose |
|---------|---------|
| `make build` | Full pipeline: dependencies → config → tokens → images → start |
| `make up` | Start containers (included in `make build`) |
| `make down` | Stop containers |
| `make logs` | Follow container logs (Ctrl+C to exit) |
| `make status` | Show container status |
| `make token-tenfive` | Generate fresh token for tenfive runner |
| `make token-tenseven` | Generate fresh token for tenseven runner |
| `make clean` | Full cleanup: unregister from GitHub, remove volumes, stop containers |

## Usage in GitHub Actions Workflows

### Target Specific macOS Version

```yaml
jobs:
  build-leopard:
    runs-on: [self-hosted, tenfive]
    steps:
      - uses: actions/checkout@v4
      - name: Build on macOS 10.5 (Leopard)
        run: |
          uname -a
          sw_vers
          sudo port -v install myport
```

### Target Any Legacy Runner

```yaml
jobs:
  build-legacy:
    runs-on: [self-hosted, ssh-legacy-capable]
    steps:
      - uses: actions/checkout@v4
      - name: Build on any legacy macOS
        run: sudo port -v install myport
```

### Available Runner Labels

| Label | Meaning |
|-------|---------|
| `self-hosted` | Self-hosted runner (not GitHub-hosted) |
| `Linux` | Container runs Linux |
| `docker` | Running in Docker container |
| `ssh-capable` | OpenSSH client available |
| `ssh-legacy-capable` | Legacy SSH algorithms configured |
| `legacy-macos` | Targets legacy macOS VM |
| `tenfive` | macOS 10.5 (Leopard) |
| `tenseven` | macOS 10.7 (Lion) |
| `ubuntu-24.04` | Container OS version |
| `X64` | CPU architecture |

### With SSH Action

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, tenfive]
    steps:
      - uses: actions/checkout@v4
      - uses: appleboy/ssh-action@v1
        with:
          host: tenfive.local
          username: ${{ vars.LEGACY_USERNAME }}
          key: ${{ secrets.OLDMAC_KEY }}
          script: |
            cd /opt/local/var/macports/build
            sudo port -v install myport
```

## Scaling to Additional VMs

### Add macOS 10.8 (Mountain Lion)

1. **Uncomment** `teneight-runner` service in `docker-compose.yml`

2. **Update `.env`**:
   ```bash
   LEGACY_TENEIGHT_HOSTNAME=teneight-runner.local
   RUNNER_TOKEN_TENEIGHT=<will-be-generated>
   ```

3. **Regenerate environment and deploy**:
   ```bash
   # Makefile automatically detects new runner
   make build
   ```

   OR manually:
   ```bash
   # Generate token
   TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
   echo "RUNNER_TOKEN_TENEIGHT=$TOKEN" >> .env
   
   # Deploy
   docker compose up -d teneight-runner
   ```

## Container Management

### View Status```bash
# Rebuild images (without cache)
docker-compose build --no-cache

# Rebuild and restart
docker-compose down && docker-compose build --no-cache && docker-compose up -d
```

## Scaling to New Legacy VMs

### Add Mac OS X 10.6 (Snow Leopard) Runner

1. **Uncomment service** in `docker-compose.yml`:
   ```yaml
   # tensix-runner:
   #   ...
   ```
   Remove the `#` from the beginning of each line.

2. **Add to `.env`**:
   ```bash
   LEGACY_TENSIX_IP=192.168.1.102
   RUNNER_TOKEN_TENSIX=<generate-new-token>
   RUNNER_NAME_TENSIX=tensix-runner
   CUSTOM_LABELS_TENSIX=ssh-legacy-capable,legacy-macos
   ```

3. **Generate token**:
   ```bash
   gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token'
   ```

4. **Start**:
   ```bash
   docker-compose up -d tensix-runner
   ```

Repeat the same pattern for other commented runners (teneight, tennine, tenten).

## Runner Token Management

**Important**: Each runner instance requires a unique registration token.

### Why Unique Tokens?

GitHub generates a unique runner ID for each registration. When you run multiple containers, each must register independently with its own token.

### Token Lifecycle

- **Valid for**: 1 hour after generation
- **Regenerate**: Before tokens expire, using the `gh` CLI command
- **Storage**: Keep in `.env` file (gitignored for security)
- **Rotation**: Recommended to rotate tokens periodically for security

### Generate Tokens Programmatically

```bash
#!/bin/bash
# generate-all-tokens.sh

GITHUB_OWNER="trodemaster"
GITHUB_REPO="blakeports"

for VM in tenfive tenseven tensix teneight tennine tenten; do
    TOKEN=$(gh api repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runners/registration-token --method POST --jq '.token')
    echo "RUNNER_TOKEN_${VM^^}=$TOKEN"
done
```

## Troubleshooting

### Runners show as `offline` on GitHub

**Expected Behavior**: Runners start as `offline` until SSH succeeds.

**Check SSH Status**:
```bash
make logs | grep "SSH connection"
```

**When SSH becomes available**:
- SSH monitor detects success
- Starts runner service
- Runner transitions to `online`

**If SSH never succeeds**:
1. Verify legacy VM is reachable:
   ```bash
   ping tenfive-runner.local
   ssh admin@tenfive-runner.local "echo test"
   ```

2. Check SSH key:
   ```bash
   ls -l docker/ssh_keys/oldmac  # Should show: -rw------- (600)
   ```

3. Check container logs:
   ```bash
   docker compose logs tenfive-runner | head -50
   ```

### Registration token expired

**Symptom**: Container exits with "Token invalid or expired"

**Solution**: Generate fresh tokens and restart:
```bash
make token-tenfive
make token-tenseven
docker compose restart
```

### Container exits immediately

**Check logs**:
```bash
docker compose logs tenfive-runner
```

**Common causes**:
- SSH key missing or wrong permissions
- Registration token expired
- GitHub API unreachable
- Environment variables missing or wrong

### SSH connection fails repeatedly

**Debug SSH manually**:
```bash
# Enter container
docker compose exec tenfive-runner /bin/bash

# Try SSH connection
ssh -F ~/.ssh/config tenfive -v
```

**Check SSH config**:
```bash
docker compose exec tenfive-runner cat ~/.ssh/config
```

**Verify legacy VM**:
```bash
# From host machine
ssh admin@tenfive-runner.local "uname -a"
```

### Port conflicts

**Symptom**: "Port already in use" error

**Solution**: Find and stop existing containers:
```bash
docker ps
docker stop <container-id>
docker rm <container-id>
```

## Container Management

### View Status

```bash
# Docker Compose status
docker compose ps

# GitHub runner status
gh api repos/trodemaster/blakeports/actions/runners --jq '.runners[] | {name, status, busy}'
```

### View Logs

```bash
# All containers, live
make logs

# Specific container
docker compose logs -f tenfive-runner

# Last 100 lines
docker compose logs --tail 100 tenfive-runner

# Search for errors
docker compose logs tenfive-runner | grep ERROR
```

### Restart Containers

```bash
# Restart all
docker compose restart

# Restart specific
docker compose restart tenfive-runner

# Full restart (cleaner)
docker compose down && docker compose up -d
```

### Remove Everything

```bash
# Stop and remove (keeps volumes)
docker compose down

# Full cleanup (removes volumes, unregisters from GitHub)
make clean
```

## Environment Variables

**In `.env` file**:

```bash
# GitHub Configuration
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports

# Legacy VM Configuration (one set per runner)
LEGACY_TENFIVE_HOSTNAME=tenfive-runner.local
LEGACY_TENSEVEN_HOSTNAME=tenseven-runner.local
LEGACY_USERNAME=admin

# Runner Registration Tokens (auto-generated by Makefile)
RUNNER_TOKEN_TENFIVE=<token>
RUNNER_TOKEN_TENSEVEN=<token>

# Runner Names and Labels (optional, has defaults)
RUNNER_NAME_TENFIVE=tenfive-runner
RUNNER_WORKDIR=_work
CUSTOM_LABELS_TENFIVE=ssh-legacy-capable,legacy-macos
```

See `example.env` for complete reference.

## SSH Connection Details

### Legacy SSH Algorithms Required

Mac OS X 10.5-10.10 only support deprecated SSH algorithms. These are configured in entrypoint.sh:

```
HostKeyAlgorithms ssh-rsa
PubkeyAcceptedKeyTypes ssh-rsa
KexAlgorithms diffie-hellman-group1-sha1
Ciphers aes128-cbc
MACs hmac-sha1
StrictHostKeyChecking no
ConnectTimeout 10
```

### Validation Process

When container starts:
1. SSH key verified (must exist and be readable)
2. SSH config file generated with legacy algorithms
3. Background monitor starts checking connectivity every 30 seconds
4. GitHub registration proceeds immediately (non-blocking)
5. Runner shows as `offline` until SSH succeeds
6. When SSH succeeds, runner service starts and transitions to `online`

### Manual SSH Testing

```bash
# From container
docker compose exec tenfive-runner bash
ssh -F ~/.ssh/config tenfive -v

# From host
ssh admin@tenfive-runner.local "sw_vers"
```

## Scaling to Additional VMs

### Add New Runner (e.g., 10.8 Mountain Lion)

1. **Uncomment in docker-compose.yml**:
   - Find the `teneight-runner:` section
   - Remove all `#` characters from that service block

2. **Update `.env`**:
   ```bash
   LEGACY_TENEIGHT_HOSTNAME=teneight-runner.local
   RUNNER_TOKEN_TENEIGHT=<will-be-generated>
   ```

3. **Deploy with Makefile**:
   ```bash
   make build
   ```
   Makefile will auto-detect and generate token.

   OR manually:
   ```bash
   TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
   echo "RUNNER_TOKEN_TENEIGHT=$TOKEN" >> .env
   docker compose up -d teneight-runner
   ```

## Token Rotation Strategy

**Recommended**: Regenerate tokens periodically for security:

```bash
# Generate fresh tokens
make token-tenfive
make token-tenseven

# Restart with new tokens
docker compose restart
```

This keeps tokens fresh and limits impact if a token is compromised.

## Performance Notes

- **First build**: ~30 seconds (downloads Ubuntu base image, ~1.37GB)
- **Subsequent builds**: ~5 seconds (uses cache)
- **Container startup**: ~5 seconds
- **SSH check interval**: 30 seconds
- **Registration to GitHub**: < 10 seconds
- **Status transition (offline→online)**: Usually < 1 minute once SSH available

## Getting Help

### Check Logs for Errors

```bash
# All errors
docker compose logs tenfive-runner | grep ERROR

# All warnings
docker compose logs tenfive-runner | grep WARNING

# Full output
docker compose logs tenfive-runner
```

### Verify Setup

```bash
# Check files
ls -la docker/
ls -la docker/ssh_keys/oldmac

# Check GitHub CLI
gh auth status

# Check Docker
docker --version
docker compose version

# Check runners on GitHub
gh api repos/trodemaster/blakeports/actions/runners
```

### Common Issues Checklist

- [ ] SSH key exists: `ls -l docker/ssh_keys/oldmac`
- [ ] SSH key permissions correct: `chmod 600 docker/ssh_keys/oldmac`
- [ ] `.env` file created from `example.env`
- [ ] Environment variables populated
- [ ] Legacy VM is reachable via SSH from host
- [ ] GitHub CLI authenticated: `gh auth status`
- [ ] Docker and docker compose installed and updated
- [ ] Firewall allows SSH (port 22) to legacy VM

## See Also

- `README.md` - Comprehensive guide and design decisions
- `example.env` - Environment variable reference
- `docker-compose.yml` - Service and volume definitions
- `entrypoint.sh` - Startup script and SSH configuration
- `Makefile` - Automation targets**Symptom**: Runner appears in GitHub but doesn't pick up jobs

**Solutions**:
1. Check labels: `gh api repos/trodemaster/blakeports/actions/runners | jq '.runners[].labels'`
2. Verify label selector: Workflow uses correct `runs-on` label
3. Check runner capacity: Ensure runner isn't already running a job

### OpenSSH Version Issues

**Verify correct version**:
```bash
docker-compose exec tenfive-runner ssh -V
# Expected: OpenSSH_9.x or later
```

## Security

1. **SSH Keys**:
   - Store `ssh_keys/oldmac` securely (already gitignored)
   - Mount as read-only in docker-compose.yml
   - Use strong key-based authentication

2. **Runner Tokens**:
   - Store in `.env` (gitignored)
   - Generate unique token per instance
   - Rotate periodically
   - Don't commit `.env` to git

3. **Network**:
   - Legacy VMs should be on isolated/private network
   - SSH on standard port 22 (can be customized)
   - Consider SSH key rotation policy

4. **Permissions**:
   - Runners execute as non-root `runner` user
   - SSH key files have `600` (read-write owner only)
   - Container has no special privileges

## Integration with Existing Infrastructure

This runner complements:
- **scripts/ghrunner**: Manages tart/lima/VMware VM-based runners (full VMs)
- **GitHub-hosted runners**: Modern macOS runners (macOS_15, macOS_26)
- **docker/github-runners**: General-purpose HashiCorp tool runners

Use Docker SSH proxy runners for: legacy VM SSH execution
Use ghrunner script for: Full VM spin-up and management
Use GitHub-hosted for: Modern macOS builds

## License

This Docker runner configuration is part of the blakeports project and follows the project license.

