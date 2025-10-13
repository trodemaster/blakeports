# Multi-Runner Setup for Legacy macOS Testing

This setup creates dedicated GitHub Actions runners for each legacy macOS VM, enabling true parallel execution of long-running builds.

## Architecture

```
GitHub Workflow Trigger
       |
       ├──> Runner 1 (tenfive)  ──SSH──> Mac OS X 10.5 VM
       |
       └──> Runner 2 (tenseven) ──SSH──> Mac OS X 10.7 VM
```

Each runner has custom labels to target specific VMs, ensuring builds run in parallel without queuing.

## Directory Structure

```
docker/actions-runners/
├── Dockerfile                  # Shared by all runners
├── docker-compose-multi.yml    # Multi-runner configuration
├── .env.tenfive               # TenFive runner config
├── .env.tenseven              # TenSeven runner config
├── example.env                 # Template
└── MULTI_RUNNER_SETUP.md      # This file
```

## Quick Setup

### 1. Create Environment Files

```bash
cd /Users/blake/code/blakeports/docker/actions-runners

# Create TenFive runner config
cat > .env.tenfive << 'EOF'
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
GITHUB_TOKEN=ghp_YOUR_TOKEN_HERE
RUNNER_NAME=docker-runner-tenfive
RUNNER_WORKDIR=_work
CUSTOM_LABELS=tenfive,macos-10-5
EOF

# Create TenSeven runner config
cat > .env.tenseven << 'EOF'
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
GITHUB_TOKEN=ghp_YOUR_TOKEN_HERE
RUNNER_NAME=docker-runner-tenseven
RUNNER_WORKDIR=_work
CUSTOM_LABELS=tenseven,macos-10-7
EOF
```

### 2. Start All Runners

```bash
# Start both runners
docker-compose -f docker-compose-multi.yml up -d

# Check status
docker-compose -f docker-compose-multi.yml ps

# View logs for both
docker-compose -f docker-compose-multi.yml logs -f

# View logs for specific runner
docker-compose -f docker-compose-multi.yml logs -f tenfive-runner
docker-compose -f docker-compose-multi.yml logs -f tenseven-runner
```

### 3. Verify Runners in GitHub

Go to: https://github.com/trodemaster/blakeports/settings/actions/runners

You should see:
- ✅ `docker-runner-tenfive` - Labels: `self-hosted`, `Linux`, `X64`, `tenfive`, `macos-10-5`
- ✅ `docker-runner-tenseven` - Labels: `self-hosted`, `Linux`, `X64`, `tenseven`, `macos-10-7`

## Workflow Configuration

### Single VM Targeting

```yaml
jobs:
  build-tenfive:
    runs-on: [self-hosted, tenfive]  # Only runs on TenFive runner
    steps:
      - name: Build on TenFive
        ...

  build-tenseven:
    runs-on: [self-hosted, tenseven]  # Only runs on TenSeven runner
    steps:
      - name: Build on TenSeven
        ...
```

### Parallel Execution

Both jobs start **immediately** when triggered, running in parallel on separate runners.

## Management Commands

### Start All Runners
```bash
docker-compose -f docker-compose-multi.yml up -d
```

### Stop All Runners
```bash
docker-compose -f docker-compose-multi.yml down
```

### Restart Specific Runner
```bash
docker-compose -f docker-compose-multi.yml restart tenfive-runner
docker-compose -f docker-compose-multi.yml restart tenseven-runner
```

### View Logs
```bash
# All runners
docker-compose -f docker-compose-multi.yml logs -f

# Specific runner
docker-compose -f docker-compose-multi.yml logs -f tenfive-runner
```

### Stop Specific Runner
```bash
docker-compose -f docker-compose-multi.yml stop tenfive-runner
docker-compose -f docker-compose-multi.yml start tenfive-runner
```

### Rebuild After Updates
```bash
docker-compose -f docker-compose-multi.yml down
docker-compose -f docker-compose-multi.yml build --no-cache
docker-compose -f docker-compose-multi.yml up -d
```

## Adding More Runners

To add a new VM (e.g., SnowLeopard):

1. **Create env file**:
   ```bash
   cat > .env.snowleopard << 'EOF'
   GITHUB_OWNER=trodemaster
   GITHUB_REPO=blakeports
   GITHUB_TOKEN=ghp_YOUR_TOKEN_HERE
   RUNNER_NAME=docker-runner-snowleopard
   RUNNER_WORKDIR=_work
   CUSTOM_LABELS=snowleopard,macos-10-6
   EOF
   ```

2. **Add to docker-compose-multi.yml**:
   ```yaml
   snowleopard-runner:
     build:
       context: .
       dockerfile: Dockerfile
     container_name: github-runner-snowleopard
     env_file: .env.snowleopard
     volumes:
       - snowleopard-work:/home/runner/_work
     restart: unless-stopped
   
   volumes:
     snowleopard-work:
   ```

3. **Start the new runner**:
   ```bash
   docker-compose -f docker-compose-multi.yml up -d snowleopard-runner
   ```

## Resource Considerations

Each runner uses:
- **CPU**: ~5-10% idle, ~20-30% during SSH operations
- **RAM**: ~200-300MB per runner
- **Disk**: ~2GB per runner (Docker image + workspace)

For 2 runners on a typical system:
- Total RAM: ~500MB
- Total Disk: ~4GB

This is very reasonable for modern hardware.

## Benefits of Multi-Runner Setup

### ✅ True Parallelism
All VMs build simultaneously, no queuing

### ✅ Reduced Total Time
Total time = longest build (not sum of all builds)

Example:
- TenFive build: 45 minutes
- TenSeven build: 30 minutes
- **Total time: 45 minutes** (not 75!)

### ✅ Independent Failures
If TenSeven fails, TenFive continues unaffected

### ✅ Better Resource Utilization
Multiple VMs can be building different ports simultaneously

### ✅ Easier Debugging
Logs are separated by runner, easier to troubleshoot specific VMs

## Monitoring

### Check Runner Status
```bash
# All runners
docker ps --filter "name=github-runner"

# Specific runner
docker ps --filter "name=github-runner-tenfive"
```

### Check Resource Usage
```bash
docker stats github-runner-tenfive github-runner-tenseven
```

### Check Disk Usage
```bash
docker system df
```

## Backup and Recovery

### Backup Runner Configurations
```bash
# Backup all env files
tar czf runner-configs-backup.tar.gz .env.*
```

### Remove and Recreate Runners
```bash
# Stop and remove all runners
docker-compose -f docker-compose-multi.yml down -v

# Rebuild and start fresh
docker-compose -f docker-compose-multi.yml build --no-cache
docker-compose -f docker-compose-multi.yml up -d
```

## Security Notes

1. **Never commit .env files** - They contain GitHub tokens
2. **Use repository secrets** for VM credentials (already configured)
3. **Rotate tokens** periodically
4. **Monitor runner activity** in GitHub Actions dashboard

## Troubleshooting

### Runner Not Registering
Check token and repo name:
```bash
docker-compose -f docker-compose-multi.yml logs tenfive-runner | grep -i error
```

### Runner Offline
Restart specific runner:
```bash
docker-compose -f docker-compose-multi.yml restart tenfive-runner
```

### Out of Disk Space
Clean up Docker:
```bash
docker system prune -a --volumes
```

### SSH Connection Issues
Verify SSH key mount:
```bash
docker exec github-runner-tenfive ls -la /home/runner/.ssh
```

## Performance Tuning

### Increase Runner Concurrency
Each runner can handle multiple jobs (default: 1). To increase:

Add to env file:
```bash
RUNNER_CONCURRENCY=2  # Allow 2 jobs per runner
```

### Resource Limits
Add to docker-compose-multi.yml:
```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
```

## Next Steps

1. Start both runners
2. Update workflows to use specific labels (`tenfive`, `tenseven`)
3. Test with a manual workflow dispatch
4. Monitor parallel execution
5. Add more runners as needed for additional VMs

