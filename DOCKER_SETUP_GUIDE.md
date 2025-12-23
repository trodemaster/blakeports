# Docker Legacy Runner Setup Guide

This guide walks you through setting up the GitHub Actions Docker runners for legacy macOS VMs on your local system.

## Prerequisites

✅ SSH key (`oldmac`) placed in `docker/ssh_keys/`
✅ `.gitignore` configured to protect SSH keys
⚠️ Need to complete:
- Verify legacy VM hostnames/IPs are reachable
- Authenticate `gh` CLI
- Generate runner tokens
- Create `.env` configuration
- Start Docker containers

## Step 1: Verify Legacy VMs Are Reachable

Test SSH connectivity to your legacy VMs:

```bash
# Test tenfive connectivity
ssh admin@tenfive-runner.local "uname -a"
# OR if using IP address:
ssh admin@192.168.x.x "uname -a"

# Test tenseven connectivity
ssh admin@tenseven-runner.local "uname -a"
# OR if using IP address:
ssh admin@192.168.x.x "uname -a"
```

**Note the actual hostnames or IP addresses you use.** Update the `.env` file with these values.

## Step 2: Authenticate gh CLI

Your `gh` CLI token needs to be refreshed:

```bash
gh auth login -h github.com
# Follow the prompts to authenticate
# Verify: gh auth status
```

## Step 3: Create `.env` Configuration File

```bash
cd /Users/blake/Developer/blakeports/docker
cp example.env .env
```

Edit `.env` and update:

### Required Changes

1. **LEGACY_TENFIVE_HOSTNAME** - Set to your actual tenfive VM hostname/IP
   ```bash
   LEGACY_TENFIVE_HOSTNAME=tenfive-runner.local  # or your IP/hostname
   ```

2. **LEGACY_TENSEVEN_HOSTNAME** - Set to your actual tenseven VM hostname/IP
   ```bash
   LEGACY_TENSEVEN_HOSTNAME=tenseven-runner.local  # or your IP/hostname
   ```

3. **Verify GitHub configuration**
   ```bash
   GITHUB_OWNER=trodemaster
   GITHUB_REPO=blakeports
   LEGACY_USERNAME=admin
   ```

## Step 4: Generate Runner Registration Tokens

Each runner needs a unique token. Run these commands in the `docker/` directory:

```bash
cd /Users/blake/Developer/blakeports/docker

# Generate token for tenfive runner
TENFIVE_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENFIVE=$TENFIVE_TOKEN"
# Copy the output and add to .env

# Generate token for tenseven runner
TENSEVEN_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
echo "RUNNER_TOKEN_TENSEVEN=$TENSEVEN_TOKEN"
# Copy the output and add to .env
```

**Important**: Tokens expire after 1 hour, so generate them shortly before starting containers.

## Step 5: Verify SSH Key Permissions

```bash
ls -la docker/ssh_keys/oldmac
# Should show: -rw------- (600 permissions)
```

If permissions are wrong:
```bash
chmod 600 docker/ssh_keys/oldmac
```

## Step 6: Build and Start Docker Containers

```bash
cd /Users/blake/Developer/blakeports/docker

# Build the Docker images
docker compose build

# Start the containers
docker compose up -d

# Check status
docker compose ps

# View logs (follow mode, Ctrl+C to exit)
docker compose logs -f
```

## Step 7: Verify Runners Register on GitHub

Once containers are running, check GitHub to see if runners appear:

```bash
# List all runners
gh api repos/trodemaster/blakeports/actions/runners

# Check specific runner status
gh api repos/trodemaster/blakeports/actions/runners --jq '.runners[] | "\(.name): \(.status)"'
```

**Expected behavior**:
- Runners start as `offline` (container needs to connect to VM)
- Once SSH to legacy VM succeeds, they become `online`
- Check container logs to debug SSH connectivity

## Step 8: Troubleshooting

### Runners stay offline

Check container logs for SSH connectivity issues:

```bash
docker compose logs tenfive-runner | grep "SSH connection"
docker compose logs tenfive-runner | grep "ERROR"
```

Common issues:
- VM hostname not resolving → verify with `ping` or `nslookup`
- SSH key permissions wrong → run `chmod 600 docker/ssh_keys/oldmac`
- SSH algorithm mismatch → entrypoint.sh should handle this automatically
- VM not running or SSH port (22) blocked by firewall

### Container exits immediately

```bash
docker compose logs tenfive-runner
# Check for:
# - SSH key missing/wrong permissions
# - Invalid registration token (expired?)
# - GitHub API unreachable
```

### Test SSH manually from container

```bash
docker compose exec tenfive-runner bash
ssh -F ~/.ssh/config tenfive "echo test"
```

## Step 9: Using Runners in Workflows

Once runners are `online`, use them in GitHub Actions workflows:

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

  build-lion:
    runs-on: [self-hosted, tenseven]
    steps:
      - uses: actions/checkout@v4
      - name: Build on macOS 10.7 (Lion)
        run: sudo port -v install myport

  build-any-legacy:
    runs-on: [self-hosted, ssh-legacy-capable]
    steps:
      - uses: actions/checkout@v4
      - name: Build on any legacy macOS
        run: sudo port -v install myport
```

## Useful Commands

```bash
cd /Users/blake/Developer/blakeports/docker

# View status
docker compose ps

# View live logs
docker compose logs -f

# View logs for specific container
docker compose logs -f tenfive-runner

# Stop containers (but keep volumes/state)
docker compose stop

# Stop and remove containers (keeps volumes)
docker compose down

# Full cleanup (removes everything including volumes)
docker compose down -v

# Restart containers
docker compose restart

# Execute command in running container
docker compose exec tenfive-runner bash
```

## Next Steps After Setup

1. Commit the `.gitignore` file to git:
   ```bash
   git add docker/ssh_keys/.gitignore
   git commit -m "docker: add ssh_keys directory with .gitignore to protect SSH keys"
   ```

2. **DO NOT commit** `.env` file (it's gitignored for security)

3. **DO NOT commit** SSH key files (they're gitignored)

4. Test with a simple workflow to verify containers work correctly

## Reference Documents

- `docker/README.md` - Comprehensive architecture and design documentation
- `docker/docker-compose.yml` - Service and volume definitions
- `docker/entrypoint.sh` - Container startup script and SSH configuration logic
- `docker/Dockerfile` - Container image build instructions
- `docker/Makefile` - Automation targets (if available)
