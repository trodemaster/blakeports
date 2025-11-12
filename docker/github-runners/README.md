# GitHub Actions Self-Hosted Runner with Docker Compose

This setup provides a scalable GitHub Actions self-hosted runner using Docker Compose with Ubuntu Noble Numbat (24.04) containers.

**Note**: This setup has been moved from the macsl repository to consolidate all GitHub Actions runner functionality for blakeports under `blakeports/docker/github-runners/`.

## Quick Start

1. **Set up environment variables:**
   ```bash
   cp env.example .env
   # Edit .env with your GitHub details
   ```

2. **Build the container image:**
   ```bash
   ./runner-build-container.sh
   ```

3. **Start the runners:**
   ```bash
   # Start 1 runner (default)
   docker-compose up -d

   # Start 3 runners (with unique hostname-based suffixes)
   docker-compose up -d --scale github-runner=3

   # Start 6 runners (with unique hostname-based suffixes)
   docker-compose up -d --scale github-runner=6
   ```

## Configuration

### Environment Variables

Create a `.env` file with the following variables:

```bash
# Required
GITHUB_TOKEN=your_github_personal_access_token
GITHUB_OWNER=your_github_username_or_org
GITHUB_REPOSITORY=your_repository

# Optional (with defaults)
RUNNER_LABELS=ubuntu,ubuntu-24.04,noble,self-hosted
```

### GitHub Personal Access Token

Your GitHub PAT needs specific permissions for self-hosted runner management. Create a new token at [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens).

#### Required Scopes for Repository-Level Runners

For repository-scoped runners (recommended), your token needs:

- ✅ **`repo`** - Full control of private repositories
  - Includes: `repo:status`, `repo_deployment`, `public_repo`, `repo:invite`, `security_events`
- ✅ **`workflow`** - Update GitHub Action workflows
- ✅ **`admin:repo_hook`** - Full control of repository hooks (optional, for webhooks)
- ✅ **`write:packages`** - Upload packages to GitHub Package Registry (optional)

#### Required Scopes for Organization-Level Runners

For organization-scoped runners, your token needs:

- ✅ **`admin:org`** - Full control of organizations and teams
- ✅ **`repo`** - Full control of private repositories
- ✅ **`workflow`** - Update GitHub Action workflows

#### Token Creation Steps

1. Go to [GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens)
2. Click "Generate new token (classic)"
3. Set expiration (recommended: 90 days or custom)
4. Select the required scopes listed above
5. Click "Generate token"
6. Copy the token and update your `.env` file

#### Testing Token Permissions

Verify your token has the correct permissions:

```bash
# Test token access
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Test runner API access
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token
```

If you get a 404 error on the runner API test, your token doesn't have the required permissions.

## Architecture

This setup uses a two-stage approach:

1. **Build Time**: The `runner-build-container.sh` script builds a custom Docker image with:
   - Ubuntu 24.04 base image (ARM64 native for macOS)
   - All required dependencies (curl, git, jq, etc.)
   - GitHub Actions runner binary (latest version)
   - HashiCorp repository for additional tools

2. **Runtime**: Docker Compose starts containers that:
   - Configure the runner with your GitHub repository
   - Start the runner service
   - Handle scaling and management

## Benefits of This Approach

- **Fast Startup**: Dependencies are pre-installed in the image
- **Consistent Environment**: Same base image for all runners
- **Easy Scaling**: Use `--scale` to run multiple runners
- **Version Control**: Runner version is locked at build time
- **Additional Tools**: HashiCorp tools (Terraform, Consul, etc.) available
- **Native Performance**: ARM64 containers on ARM64 hosts

## Container Build Script (runner-build-container.sh)

This script handles the complete Docker image build process:

### Features
- **Host Architecture Detection**: Automatically detects ARM64 (macOS) or x86_64 (Linux) hosts
- **Platform-Specific Builds**: Builds native containers for your host architecture
- **Latest Runner Version**: Automatically fetches and installs the latest GitHub Actions runner
- **Repository Configuration**: Adds HashiCorp repository for additional tools
- **Build Optimization**: Uses Docker layer caching and provides build options

### Usage Examples

```bash
# Basic build
./runner-build-container.sh

# Force rebuild (no cache)
./runner-build-container.sh --force

# Custom image name and tag
./runner-build-container.sh --image-name my-runner --tag v1.0

# Build with no cache
./runner-build-container.sh --no-cache

# Show help
./runner-build-container.sh --help
```

## Scaling Runners

Docker Compose makes scaling simple. Each runner gets a unique name:

```bash
# Start 1 runner
docker-compose up -d

# Start 3 runners (each with unique hostname-based suffix)
docker-compose up -d --scale github-runner=3

# Start 6 runners (each with unique hostname-based suffix)
docker-compose up -d --scale github-runner=6

# Scale down to 2 runners (keeps containers 1 and 2)
docker-compose up -d --scale github-runner=2
```

**Runner Naming Convention**: `runner-docker-ubuntu-noble-<HOSTNAME_SUFFIX>`
- Each scaled instance gets a unique 8-character hex suffix from its container hostname
- Example names: `runner-docker-ubuntu-noble-1d1fcad1`, `runner-docker-ubuntu-noble-25aea1d9`
- Runner names are unique and automatically generated for each container

## Management

### View running containers
```bash
docker-compose ps
```

### View logs
```bash
# All runners
docker-compose logs -f

# Specific runner (by container name)
docker logs macsl-github-runner-1
```

### Stop all runners
```bash
docker-compose down
```

### Update runners
```bash
docker-compose down
./runner-build-container.sh --force
docker-compose up -d --scale github-runner=6
```

### Clean up runners manually
```bash
# List all runners in your repository
./runner-cleanup.sh list

# Remove offline runners only
./runner-cleanup.sh remove-offline

# Remove ALL runners (with confirmation)
./runner-cleanup.sh remove-all
```

## Troubleshooting

### Check runner status
```bash
./runner-cleanup.sh list
```

### View runner logs
```bash
docker logs macsl-github-runner-1
```

### Test runner connectivity
```bash
# Check if a specific runner is connected
docker exec macsl-github-runner-1 ps aux | grep Runner.Listener
```

## Security Considerations

- The containers run with privileged access for Docker-in-Docker support
- Docker socket is mounted read-only
- Each runner has its own volume for data isolation
- Consider using Docker secrets for sensitive data in production

## File Structure

```
.
├── docker-compose.yml              # Main Docker Compose configuration
├── Dockerfile                      # Container image definition
├── runner-setup.sh                 # Runner configuration script
├── runner-build-container.sh       # Container build script
├── runner-cleanup.sh               # Manual runner cleanup script
├── env.example                     # Environment variables template
└── README.md                       # This file
```
