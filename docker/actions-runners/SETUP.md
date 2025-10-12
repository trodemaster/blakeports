# Quick Setup Guide for Docker GitHub Actions Runner

This guide will help you get the Docker-based GitHub Actions runner up and running quickly.

## Prerequisites Checklist

- [ ] Docker installed and running
- [ ] GitHub Personal Access Token (PAT) created
- [ ] SSH access to darkstar host (hypervisor)
- [ ] SSH keys for accessing legacy VMs

## Step-by-Step Setup

### 1. Generate GitHub Personal Access Token

1. Go to: https://github.com/settings/tokens
2. Click "Generate new token" → "Generate new token (classic)"
3. Give it a descriptive name: `blakeports-docker-runner`
4. Select scopes:
   - [x] `repo` (full control of private repositories)
5. Click "Generate token"
6. **IMPORTANT**: Copy the token immediately (you won't see it again)

### 2. Configure the Runner

```bash
cd /Users/blake/code/blakeports/docker/actions-runners

# Copy the example environment file
cp example.env .env

# Edit the .env file with your values
nano .env
```

Update these values in `.env`:
```bash
GITHUB_OWNER=trodemaster          # Your GitHub username
GITHUB_REPO=blakeports
GITHUB_TOKEN=ghp_YOUR_TOKEN_HERE  # Paste your PAT here
RUNNER_NAME=docker-runner-darkstar
```

### 3. Build and Start the Runner

```bash
# Build the Docker image
docker-compose build

# Start the runner in detached mode
docker-compose up -d

# Check the logs to verify registration
docker-compose logs -f
```

You should see output like:
```
✅ Registration token generated successfully
✅ Runner configured successfully
✅ Runner is now listening for jobs...
```

### 4. Verify Runner Registration

1. Go to: https://github.com/YOUR_USERNAME/blakeports/settings/actions/runners
2. You should see your runner listed with status "Idle" (green)
3. Note the labels: `self-hosted`, `Linux`, `docker`, `ssh-capable`, `X64`, `ubuntu-24.04`

### 5. Configure GitHub Secrets for TenSeven VM

For the hello-tenseven workflow to work, you need these secrets:

1. Go to: https://github.com/YOUR_USERNAME/blakeports/settings/secrets/actions
2. Add these secrets:
   - `TENSEVEN_USERNAME`: SSH username for Mac OS X 10.7 VM (e.g., `admin`)
   - `TENSEVEN_KEY`: SSH private key for accessing the VM
   - `HYPERVISOR_HOST`: Already exists (darkstar hostname)
   - `HYPERVISOR_USERNAME`: Already exists
   - `HYPERVISOR_KEY`: Already exists

### 6. Test the Setup

Run the hello world workflow:

1. Go to: https://github.com/YOUR_USERNAME/blakeports/actions/workflows/hello-tenseven.yml
2. Click "Run workflow"
3. Optionally enter a custom message
4. Click "Run workflow"

The workflow will:
1. Start the Mac OS X 10.7 VM on darkstar
2. SSH into it from the Docker runner
3. Display system information
4. Clean up the VM automatically

## Troubleshooting

### Runner Not Appearing

Check logs:
```bash
docker-compose logs
```

Common issues:
- Invalid GitHub token → Regenerate token with correct scopes
- Wrong repository name → Check GITHUB_OWNER and GITHUB_REPO in .env
- Network issues → Ensure Docker has internet access

### Runner Shows Offline

```bash
# Restart the runner
docker-compose restart

# If that doesn't work, recreate it
docker-compose down
docker-compose up -d
```

### SSH Connection to VM Fails

1. Verify SSH keys are mounted:
   ```bash
   docker-compose exec github-runner ls -la /home/runner/.ssh
   ```

2. Test SSH manually:
   ```bash
   docker-compose exec github-runner ssh -V  # Check OpenSSH version
   ```

3. Check GitHub secrets are set correctly

## Managing the Runner

### Stop the Runner
```bash
docker-compose down
```

### Restart the Runner
```bash
docker-compose restart
```

### View Logs
```bash
docker-compose logs -f
```

### Update the Runner
```bash
# Update RUNNER_VERSION in .env if needed
nano .env

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## Next Steps

- Review the full documentation in `README.md`
- Explore the hello-tenseven workflow as a template
- Create additional workflows using the Docker runner
- Consider running multiple runners for parallel job execution

## Support

- Main documentation: `docker/actions-runners/README.md`
- Docker documentation: `docker/README.md`
- GitHub Actions docs: https://docs.github.com/en/actions

