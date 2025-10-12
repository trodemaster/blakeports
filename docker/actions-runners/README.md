# GitHub Actions Self-Hosted Runner (Docker)

This directory contains a Docker-based GitHub Actions self-hosted runner with OpenSSH 9.x support for connecting to legacy VMs.

## Features

- **Ubuntu 24.04 Base**: Modern, stable platform
- **OpenSSH 9.x Client**: Compatible with legacy systems requiring older SSH algorithms
- **Self-Hosted Runner**: Executes GitHub Actions workflows locally
- **SSH Capabilities**: Can connect to target VMs for remote command execution
- **Docker Containerized**: Easy deployment and management
- **Auto-Registration**: Automatically registers with GitHub on startup

## Prerequisites

1. **Docker**: Install Docker Engine or Docker Desktop
   - macOS: [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
   - Linux: [Docker Engine](https://docs.docker.com/engine/install/)

2. **GitHub Personal Access Token (PAT)**:
   - Go to: https://github.com/settings/tokens
   - Click "Generate new token" → "Generate new token (classic)"
   - Required scopes:
     - `repo` (for private repositories)
     - OR `public_repo` (for public repositories only)
   - Copy the token (you'll need it for configuration)

3. **SSH Keys**: Ensure you have SSH keys for accessing target VMs
   - Keys should be in `~/.ssh/` or specify a custom path

## Quick Start

### 1. Configuration

Copy the example environment file and configure it:

```bash
cd docker/actions-runners
cp example.env .env
```

Edit `.env` and set your values:

```bash
GITHUB_OWNER=your-github-username
GITHUB_REPO=blakeports
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
RUNNER_NAME=docker-runner-1
```

### 2. Build and Start

Build the Docker image and start the runner:

```bash
docker-compose build
docker-compose up -d
```

### 3. Verify

Check that the runner is registered:

```bash
# View runner logs
docker-compose logs -f

# Check runner status on GitHub
# Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/actions/runners
```

## Usage

### Starting the Runner

```bash
cd docker/actions-runners
docker-compose up -d
```

### Stopping the Runner

```bash
docker-compose down
```

The runner will automatically deregister from GitHub when stopped gracefully.

### Viewing Logs

```bash
# Follow logs in real-time
docker-compose logs -f

# View last 100 lines
docker-compose logs --tail=100
```

### Rebuilding the Runner

If you need to update the runner or change configuration:

```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## Using in Workflows

Once the runner is registered, use it in your workflows with the `runs-on` label:

```yaml
jobs:
  my-job:
    runs-on: [self-hosted, docker, ssh-capable]
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Run commands
        run: echo "Running on Docker runner!"
```

### Available Labels

The runner automatically provides these labels:
- `self-hosted` - Self-hosted runner
- `Linux` - Linux OS
- `docker` - Running in Docker
- `ssh-capable` - Has OpenSSH client
- `X64` or `ARM64` - Architecture
- `ubuntu-24.04` - Ubuntu version

## SSH Access to VMs

The runner can SSH into target VMs using the `appleboy/ssh-action`:

```yaml
jobs:
  ssh-to-vm:
    runs-on: [self-hosted, docker]
    steps:
      - name: Execute commands on remote VM
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VM_HOST }}
          username: ${{ secrets.VM_USERNAME }}
          key: ${{ secrets.VM_SSH_KEY }}
          script: |
            uname -a
            hostname
            uptime
```

### SSH Key Configuration

By default, the runner mounts `~/.ssh` as read-only. To use custom SSH keys:

1. **Option 1**: Place keys in `~/.ssh/` on the host
2. **Option 2**: Specify custom path in `.env`:
   ```bash
   SSH_KEY_PATH=/path/to/custom/ssh/keys
   ```
3. **Option 3**: Pass keys via GitHub Secrets (recommended for security)

## Running Multiple Runners

To run multiple runners simultaneously:

1. Create separate `.env` files:
   ```bash
   cp .env .env.runner1
   cp .env .env.runner2
   ```

2. Edit each file with unique `RUNNER_NAME` values:
   ```bash
   # .env.runner1
   RUNNER_NAME=docker-runner-1
   
   # .env.runner2
   RUNNER_NAME=docker-runner-2
   ```

3. Start with explicit env files:
   ```bash
   docker-compose --env-file .env.runner1 up -d
   docker-compose --env-file .env.runner2 up -d
   ```

## Troubleshooting

### Runner Not Appearing on GitHub

1. **Check logs**: `docker-compose logs`
2. **Verify token**: Ensure `GITHUB_TOKEN` has correct permissions
3. **Check repository**: Verify `GITHUB_OWNER` and `GITHUB_REPO` are correct
4. **Token expiration**: PATs expire; generate a new one if needed

### SSH Connection Issues

1. **Check SSH keys**: Ensure keys are mounted correctly
   ```bash
   docker-compose exec github-runner ls -la /home/runner/.ssh
   ```

2. **Test SSH manually**:
   ```bash
   docker-compose exec github-runner ssh -V  # Check OpenSSH version
   docker-compose exec github-runner ssh user@host  # Test connection
   ```

3. **Check key permissions**: Private keys should be mode 600
   ```bash
   chmod 600 ~/.ssh/id_rsa
   ```

### Runner Registration Fails

1. **Check API access**:
   ```bash
   curl -H "Authorization: token YOUR_TOKEN" \
     https://api.github.com/repos/OWNER/REPO/actions/runners
   ```

2. **Verify token scopes**: Token needs `repo` or `public_repo` scope

3. **Check Docker logs**: `docker-compose logs`

### OpenSSH Version Check

Verify OpenSSH version in the container:

```bash
docker-compose exec github-runner ssh -V
# Expected: OpenSSH_9.6p1 Ubuntu-3ubuntu13.5, OpenSSL 3.0.13 30 Jan 2024
```

## Advanced Configuration

### Custom Runner Version

Override the runner version in `.env`:

```bash
RUNNER_VERSION=2.321.0
```

Check available versions: https://github.com/actions/runner/releases

### Custom Labels

Add additional labels in `.env`:

```bash
CUSTOM_LABELS=production,us-west-2,gpu
```

### Resource Limits

Edit `docker-compose.yml` to set CPU/memory limits:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 4G
```

## Security Considerations

1. **Never commit `.env`**: The `.gitignore` file prevents this
2. **Rotate tokens regularly**: Generate new PATs periodically
3. **Read-only SSH keys**: Keys are mounted read-only by default
4. **Non-root user**: Runner executes as `runner` user, not root
5. **Token permissions**: Use minimal required scopes for PAT

## Maintenance

### Updating the Runner

GitHub periodically releases new runner versions:

1. Check for updates: https://github.com/actions/runner/releases
2. Update `RUNNER_VERSION` in `.env`
3. Rebuild: `docker-compose build --no-cache`
4. Restart: `docker-compose up -d`

### Cleanup

Remove everything (runner, volumes, images):

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (deletes work directory)
docker-compose down -v

# Remove images
docker-compose down --rmi all
```

## Integration with Existing Scripts

This runner complements the existing `scripts/ghrunner` script:
- **ghrunner**: Manages tart/lima/VMware VM-based runners
- **docker runner**: Containerized runner with SSH capabilities

Use the Docker runner for jobs that need to SSH into VMs without spinning up a full VM runner.

## Support

For issues or questions:
1. Check GitHub Actions documentation: https://docs.github.com/en/actions
2. Review Docker logs: `docker-compose logs`
3. Consult the blakeports repository documentation

## License

This Docker runner configuration is part of the blakeports project and follows the project license.

