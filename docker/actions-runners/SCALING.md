# Scaling Docker Runner for Multiple Legacy macOS VMs

This document describes how to scale the Docker runner setup to support multiple legacy macOS versions.

## Overview

The Docker runner is designed to connect to legacy macOS VMs (Snow Leopard through Yosemite) that cannot run GitHub Actions natively. The setup is built to scale horizontally to support many VMs simultaneously.

## Supported Legacy macOS Versions

The Docker runner with OpenSSH 9.x is designed for these legacy macOS versions:

| Version | Release | Status | SSH Compatibility |
|---------|---------|--------|-------------------|
| Snow Leopard (10.6) | 2009 | ❌ Planned | OpenSSH 5.2 |
| Lion (10.7) | 2011 | ✅ Working | OpenSSH 5.6 |
| Mountain Lion (10.8) | 2012 | ❌ Planned | OpenSSH 5.9 |
| Mavericks (10.9) | 2013 | ❌ Planned | OpenSSH 6.2 |
| Yosemite (10.10) | 2014 | ❌ Planned | OpenSSH 6.2 |

**Note**: Newer macOS versions (El Capitan+) should use native GitHub Actions runners or other approaches.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions Workflow                                      │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ Job: runs-on: [self-hosted, docker, ssh-capable]     │   │
│ │ Uses: appleboy/ssh-action@v1                          │   │
│ └───────────────┬───────────────────────────────────────┘   │
└─────────────────┼─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│ Docker Runner (darkstar host)                                │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Ubuntu 24.04 + OpenSSH 9.6p1                            │ │
│ │ - GitHub Actions Runner                                 │ │
│ │ - SSH Keys: oldmac, snowleopard, etc.                   │ │
│ │ - Labels: docker, ssh-capable                           │ │
│ └─────────────┬───────────────────────────────────────────┘ │
└───────────────┼───────────────────────────────────────────┘
                │
                │ SSH Connections
                ├──────────────┬──────────────┬──────────────┐
                ▼              ▼              ▼              ▼
      ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐
      │ Lion VM    │  │ SnowLeo VM │  │ Mavericks  │  │ Yosemite   │
      │ 10.7.5     │  │ 10.6.8     │  │ 10.9.5     │  │ 10.10.5    │
      │ (running)  │  │ (stopped)  │  │ (stopped)  │  │ (stopped)  │
      └────────────┘  └────────────┘  └────────────┘  └────────────┘
```

## Configuration Strategy

### 1. SSH Keys Organization

Store multiple SSH keys in the `ssh_keys/` directory:

```
docker/actions-runners/ssh_keys/
├── oldmac              # Lion (10.7) VM
├── oldmac.pub
├── snowleopard         # Snow Leopard (10.6) VM
├── snowleopard.pub
├── mountainlion        # Mountain Lion (10.8) VM
├── mountainlion.pub
├── mavericks           # Mavericks (10.9) VM
├── mavericks.pub
├── yosemite            # Yosemite (10.10) VM
└── yosemite.pub
```

**All keys are copied into the Docker container at build time** (line 48 in Dockerfile).

### 2. GitHub Repository Variables

Use repository variables for non-sensitive VM configuration:

```bash
# Per-VM Configuration
gh variable set LION_IP --body "192.168.234.9"
gh variable set LION_USERNAME --body "blake"

gh variable set SNOWLEOPARD_IP --body "192.168.234.10"
gh variable set SNOWLEOPARD_USERNAME --body "blake"

gh variable set MAVERICKS_IP --body "192.168.234.11"
gh variable set MAVERICKS_USERNAME --body "blake"
```

### 3. GitHub Secrets

Store SSH private keys as secrets (one per VM):

```bash
# Per-VM SSH Keys
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/oldmac' \
  | gh secret set LION_KEY

ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/snowleopard' \
  | gh secret set SNOWLEOPARD_KEY

ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/mavericks' \
  | gh secret set MAVERICKS_KEY
```

### 4. Workflow Pattern

Create reusable workflow for each legacy macOS version:

```yaml
# .github/workflows/hello-lion.yml
name: Hello Lion VM

on:
  workflow_dispatch:
    inputs:
      vm_ip:
        description: 'Override Lion VM IP'
        required: false
        type: string
      message:
        description: 'Custom message'
        required: false
        default: 'Hello from GitHub Actions!'

env:
  VM_IP: ${{ inputs.vm_ip || vars.LION_IP }}
  VM_USERNAME: ${{ vars.LION_USERNAME }}

jobs:
  hello-vm:
    runs-on: [self-hosted, docker, ssh-capable]
    steps:
      - uses: actions/checkout@v4
      
      - name: SSH to Lion VM
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ env.VM_IP }}
          username: ${{ env.VM_USERNAME }}
          key: ${{ secrets.LION_KEY }}
          script: |
            echo "Running on Lion VM"
            sw_vers
```

## Adding a New Legacy macOS VM

Follow these steps to add support for a new legacy macOS VM:

### Step 1: Generate SSH Key Pair

```bash
# On the Docker host (darkstar)
cd ~/code/blakeports/docker/actions-runners/ssh_keys/

# Generate key for the new VM (e.g., mountainlion)
ssh-keygen -t rsa -b 4096 -f mountainlion -C "mountainlion-vm" -N ""

# Set proper permissions
chmod 600 mountainlion
chmod 644 mountainlion.pub
```

### Step 2: Deploy Public Key to VM

```bash
# Copy public key to the VM
ssh-copy-id -i mountainlion.pub blake@192.168.234.11

# Or manually:
cat mountainlion.pub | ssh blake@192.168.234.11 \
  'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
```

### Step 3: Rebuild Docker Container

```bash
# On darkstar
cd ~/code/blakeports/docker/actions-runners/

# Rebuild to include new SSH key
docker compose down
docker compose build --no-cache
docker compose up -d
```

### Step 4: Configure GitHub Variables

```bash
# Set repository variables (non-sensitive)
gh variable set MOUNTAINLION_IP --body "192.168.234.11"
gh variable set MOUNTAINLION_USERNAME --body "blake"
```

### Step 5: Configure GitHub Secret

```bash
# Set SSH key secret (sensitive)
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/mountainlion' \
  | gh secret set MOUNTAINLION_KEY
```

### Step 6: Create Workflow

Create `.github/workflows/hello-mountainlion.yml`:

```yaml
name: Hello Mountain Lion VM

on:
  workflow_dispatch:
    inputs:
      vm_ip:
        description: 'Override VM IP'
        required: false
        type: string
  workflow_call:
    inputs:
      vm_ip:
        required: false
        type: string

env:
  VM_IP: ${{ inputs.vm_ip || vars.MOUNTAINLION_IP }}
  VM_USERNAME: ${{ vars.MOUNTAINLION_USERNAME }}

jobs:
  hello-vm:
    runs-on: [self-hosted, docker, ssh-capable]
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify Configuration
        run: |
          if [ -z "$VM_IP" ]; then
            echo "Error: VM_IP not set"
            exit 1
          fi
          echo "Connecting to: $VM_USERNAME@$VM_IP"
      
      - name: SSH to Mountain Lion VM
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ env.VM_IP }}
          username: ${{ env.VM_USERNAME }}
          key: ${{ secrets.MOUNTAINLION_KEY }}
          script: |
            echo "=================================================="
            echo "  Hello from Mountain Lion VM!"
            echo "=================================================="
            sw_vers
            uname -a
```

### Step 7: Test

```bash
# Test the workflow
gh workflow run hello-mountainlion.yml

# Watch it run
gh run watch $(gh run list --workflow=hello-mountainlion.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Naming Conventions

To maintain consistency across multiple VMs:

### SSH Keys
- **Format**: `{version_name}` (lowercase, no spaces)
- **Examples**: `lion`, `snowleopard`, `mountainlion`, `mavericks`, `yosemite`

### Repository Variables
- **Format**: `{VERSION}_IP`, `{VERSION}_USERNAME` (uppercase)
- **Examples**: `LION_IP`, `MOUNTAINLION_USERNAME`

### Repository Secrets
- **Format**: `{VERSION}_KEY` (uppercase)
- **Examples**: `LION_KEY`, `SNOWLEOPARD_KEY`

### Workflows
- **Format**: `hello-{version}.yml` (lowercase, hyphenated)
- **Examples**: `hello-lion.yml`, `hello-mountainlion.yml`

## Scaling Considerations

### Single Docker Runner vs Multiple Runners

**Current Setup: Single Docker Runner** (Recommended)
- ✅ One runner can connect to all legacy VMs
- ✅ All SSH keys bundled in one container
- ✅ Simpler management
- ✅ Less resource overhead
- ⚠️ Single point of failure
- ⚠️ Jobs queue if multiple VMs need access simultaneously

**Alternative: Multiple Docker Runners**
- Each runner dedicated to one macOS version
- More complex but higher availability
- Better for high-volume testing

For most use cases, **a single Docker runner is sufficient** because:
1. Legacy VM jobs are typically short-lived
2. VMs are started on-demand (not always running)
3. Parallel job execution is rare for legacy systems

### Performance

The Docker runner can handle:
- **SSH connections**: Near-instantaneous (< 1 second)
- **Concurrent jobs**: Limited by Docker host resources
- **Multiple VMs**: Limited only by SSH key count (no practical limit)

### Maintenance

**When to rebuild the Docker container:**
1. Adding new SSH keys for new VMs
2. Updating GitHub Actions runner version
3. Updating OpenSSH version
4. Changing base Ubuntu version

**No rebuild needed for:**
- Changing VM IP addresses (use repository variables)
- Changing usernames (use repository variables)
- Rotating SSH keys (just update secrets)

## Security Best Practices

1. **SSH Keys**:
   - One unique key per VM
   - 4096-bit RSA minimum
   - Never commit keys to git (`.gitignore` configured)
   - Store private keys as GitHub secrets

2. **Repository Variables**:
   - Use for non-sensitive data only (IPs, usernames)
   - Public in repository settings (visible to contributors)

3. **Secrets**:
   - Use for all sensitive data (SSH keys, passwords)
   - Never log or echo secrets in workflows
   - Rotate periodically

4. **Docker Container**:
   - Run as non-root user (`runner`)
   - SSH keys have 600 permissions
   - Minimal package installation

## Troubleshooting Multi-VM Setup

### VM Connection Issues

```bash
# Check which SSH keys are in the container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ls -la /home/runner/.ssh/'

# Test SSH connection manually from container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ssh -i /home/runner/.ssh/oldmac blake@192.168.234.9 "sw_vers"'
```

### GitHub Variables Not Set

```bash
# List all repository variables
gh variable list

# Set missing variable
gh variable set MOUNTAINLION_IP --body "192.168.234.11"
```

### Secret Not Working

```bash
# List secrets (doesn't show values)
gh secret list

# Update secret
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/mountainlion' | gh secret set MOUNTAINLION_KEY
```

## Future Enhancements

1. **Dynamic VM Discovery**: Auto-detect running VMs and their IPs
2. **Matrix Testing**: Run jobs across all available legacy macOS versions
3. **Health Checks**: Periodic SSH connectivity tests for all VMs
4. **Automated Key Rotation**: Script to rotate SSH keys across all VMs
5. **VM Pooling**: Intelligent job distribution across available VMs

## Summary

The Docker runner setup is designed for horizontal scaling:

| Component | Scalability | Limit |
|-----------|-------------|-------|
| SSH Keys | ✅ Unlimited | Practical: ~10-20 VMs |
| GitHub Variables | ✅ Unlimited | GitHub: 1000 per repo |
| GitHub Secrets | ✅ Unlimited | GitHub: 1000 per repo |
| Docker Runner | ⚠️ Single | Can run multiple instances |
| Concurrent Jobs | ⚠️ Limited | By Docker host resources |

**Current Status**: Supporting 1 VM (Lion), ready to scale to 10+ VMs.

