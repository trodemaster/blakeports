# Quick Reference Guide for Legacy macOS VMs

## Adding a New Legacy macOS VM (TL;DR)

```bash
# 1. Generate SSH key on darkstar
ssh darkstar
cd ~/code/blakeports/docker/actions-runners/ssh_keys/
ssh-keygen -t rsa -b 4096 -f newvm -C "newvm" -N ""

# 2. Copy public key to VM
ssh-copy-id -i newvm.pub blake@NEW_VM_IP

# 3. Pull changes and rebuild Docker container
cd ~/code/blakeports
git pull
cd docker/actions-runners/
docker compose down
docker compose build --no-cache
docker compose up -d

# 4. Configure GitHub (from local machine)
gh variable set NEWVM_IP --body "NEW_VM_IP"
gh variable set NEWVM_USERNAME --body "blake"
cat <(ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/newvm') | gh secret set NEWVM_KEY

# 5. Create workflow from template
cp .github/workflows/hello-legacyvm.template.yml .github/workflows/hello-newvm.yml
# Edit the file and replace {VERSION}, {version}, {Version Name}

# 6. Test
gh workflow run hello-newvm.yml
gh run watch $(gh run list --workflow=hello-newvm.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| SSH Key | `{version}` (lowercase) | `snowleopard`, `mountainlion` |
| Variable | `{VERSION}_IP`, `{VERSION}_USERNAME` (uppercase) | `MOUNTAINLION_IP` |
| Secret | `{VERSION}_KEY` (uppercase) | `SNOWLEOPARD_KEY` |
| Workflow | `hello-{version}.yml` (lowercase) | `hello-yosemite.yml` |

## Common Commands

### Docker Container Management

```bash
# Start the runner
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose up -d'

# Stop the runner
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose down'

# View logs
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose logs -f'

# Rebuild after adding SSH keys
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose down && docker compose build --no-cache && docker compose up -d'

# Check SSH keys in container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ls -la /home/runner/.ssh/'

# Test SSH connection from container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ssh -i /home/runner/.ssh/oldmac blake@192.168.234.9 "sw_vers"'
```

### GitHub Configuration

```bash
# List all variables
gh variable list

# List all secrets
gh secret list

# Set a new variable
gh variable set MOUNTAINLION_IP --body "192.168.234.11"
gh variable set MOUNTAINLION_USERNAME --body "blake"

# Set a new secret
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/mountainlion' | gh secret set MOUNTAINLION_KEY

# Delete variable
gh variable delete OLDVM_IP

# Delete secret
gh secret delete OLDVM_KEY
```

### Workflow Management

```bash
# List all workflows
gh workflow list

# Run a workflow manually
gh workflow run hello-lion.yml

# Run with custom inputs
gh workflow run hello-lion.yml -f vm_ip=192.168.234.9 -f message="Custom message!"

# Watch the latest run
gh run watch $(gh run list --workflow=hello-lion.yml --limit 1 --json databaseId --jq '.[0].databaseId')

# View run details
gh run view RUN_ID

# View failed logs only
gh run view RUN_ID --log-failed
```

### SSH Key Management

```bash
# Generate new SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/newvm -C "newvm" -N ""

# Copy public key to VM
ssh-copy-id -i ~/.ssh/newvm.pub blake@VM_IP

# Test SSH connection
ssh -i ~/.ssh/newvm blake@VM_IP "sw_vers"

# Change key permissions (if needed)
chmod 600 ~/.ssh/newvm
chmod 644 ~/.ssh/newvm.pub
```

## Current VM Status

| VM | IP | Username | SSH Key | Status |
|----|----|----|---------|---------|
| Lion (10.7) | 192.168.234.9 | blake | oldmac | ✅ Working |
| Snow Leopard (10.6) | - | blake | snowleopard | ⏳ Not configured |
| Mountain Lion (10.8) | - | blake | mountainlion | ⏳ Not configured |
| Mavericks (10.9) | - | blake | mavericks | ⏳ Not configured |
| Yosemite (10.10) | - | blake | yosemite | ⏳ Not configured |

## Troubleshooting Quick Fixes

### Workflow fails with "can't connect without a private SSH key"

```bash
# Check if secret is set
gh secret list | grep LION_KEY

# Re-set the secret
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/oldmac' | gh secret set LION_KEY
```

### Workflow fails with "VM_IP not set"

```bash
# Check if variable is set
gh variable list | grep LION_IP

# Set the variable
gh variable set LION_IP --body "192.168.234.9"
```

### SSH connection times out

```bash
# Test from container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ssh -v -i /home/runner/.ssh/oldmac blake@192.168.234.9 "echo OK"'

# Check if VM is running
ssh darkstar '/Applications/VMware\ Fusion.app/Contents/Public/vmrun list'
```

### New SSH key not working

```bash
# Rebuild container to include new keys
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose down && docker compose build --no-cache && docker compose up -d'

# Verify key is in container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose exec github-runner ls -la /home/runner/.ssh/ | grep newvm'
```

## Example: Adding Mountain Lion VM

```bash
# On darkstar: Generate and deploy SSH key
ssh darkstar << 'EOF'
  cd ~/code/blakeports/docker/actions-runners/ssh_keys/
  ssh-keygen -t rsa -b 4096 -f mountainlion -C "mountainlion-vm" -N ""
  ssh-copy-id -i mountainlion.pub blake@192.168.234.11
  exit
EOF

# Rebuild Docker container
ssh darkstar 'source ~/.bash_profile && cd ~/code/blakeports/docker/actions-runners && docker compose down && docker compose build --no-cache && docker compose up -d'

# Configure GitHub
gh variable set MOUNTAINLION_IP --body "192.168.234.11"
gh variable set MOUNTAINLION_USERNAME --body "blake"
ssh darkstar 'cat ~/code/blakeports/docker/actions-runners/ssh_keys/mountainlion' | gh secret set MOUNTAINLION_KEY

# Create workflow
cp .github/workflows/hello-legacyvm.template.yml .github/workflows/hello-mountainlion.yml

# Edit workflow (replace placeholders)
# {VERSION} -> MOUNTAINLION
# {version} -> mountainlion
# {Version Name} -> Mountain Lion

# Commit and push
git add .github/workflows/hello-mountainlion.yml
git commit -m "workflows: add Mountain Lion VM support"
git push

# Test
gh workflow run hello-mountainlion.yml
gh run watch $(gh run list --workflow=hello-mountainlion.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Links

- [Detailed Scaling Guide](./SCALING.md)
- [Full Documentation](./README.md)
- [Setup Instructions](./SETUP.md)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [appleboy/ssh-action](https://github.com/appleboy/ssh-action)

