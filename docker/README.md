# Docker Containers for BlakePorts

This directory contains Docker containers used for development, testing, and infrastructure support for the BlakePorts project.

## Structure

```
docker/
├── actions-runners/        # Specialized runners for legacy macOS/MacPorts testing
│   ├── Dockerfile          # Ubuntu 24.04 with GitHub Actions runner and OpenSSH 9.x
│   ├── entrypoint.sh       # Runner registration and startup script
│   ├── docker-compose.yml  # Container orchestration configuration
│   ├── example.env         # Environment variable template
│   └── README.md           # Detailed setup and usage documentation
└── github-runners/         # General-purpose GitHub Actions runners
    ├── Dockerfile          # Ubuntu 24.04 with HashiCorp tools
    ├── docker-compose.yml  # Multi-runner orchestration
    ├── runner-setup.sh     # Dynamic runner registration script
    ├── runner-build-container.sh  # Build automation script
    ├── runner-cleanup.sh   # Runner management and cleanup
    ├── env.example         # Environment variables template
    └── README.md           # Setup and scaling documentation
```

## Available Containers

### GitHub Actions Self-Hosted Runners (`actions-runners/`)

Specialized Docker-based GitHub Actions runners with OpenSSH 9.x support for connecting to legacy macOS VMs and MacPorts testing.

**Features:**
- Ubuntu 24.04 base with OpenSSH 9.x client
- Auto-registration with GitHub on startup
- SSH capabilities for connecting to target VMs
- Support for legacy SSH algorithms (compatible with Mac OS X 10.7, etc.)
- Easy deployment via Docker Compose

**Quick Start:**
```bash
cd docker/actions-runners
cp example.env .env
# Edit .env with your GitHub token and repository info
docker-compose up -d
```

**Use Case:**
This runner is designed to execute GitHub Actions workflows that need to SSH into legacy VMs (like Mac OS X 10.7) that can't run GitHub Actions natively. It complements the existing `scripts/ghrunner` tool which manages tart/lima/VMware VM-based runners.

See `actions-runners/README.md` for detailed documentation.

### General-Purpose GitHub Actions Runners (`github-runners/`)

Scalable Docker-based GitHub Actions runners for general CI/CD workloads with HashiCorp tool support.

**Features:**
- Ubuntu 24.04 base with latest GitHub Actions runner
- HashiCorp tools (Terraform, Consul, Vault, etc.)
- Dynamic scaling with unique runner names
- Automated build and cleanup scripts
- Docker-in-Docker support for advanced workflows
- Easy scaling with docker-compose --scale

**Quick Start:**
```bash
cd docker/github-runners
cp env.example .env
# Edit .env with your GitHub details
./runner-build-container.sh
docker-compose up -d --scale github-runner=3
```

**Use Case:**
General-purpose runners for CI/CD pipelines that need HashiCorp infrastructure tools or Docker build capabilities.

See `github-runners/README.md` for detailed documentation.

## Legacy Systems Access

There are two approaches for connecting to legacy SSH servers (Mac OS X 10.6-10.8, older Linux systems) that only support deprecated algorithms:

### Option 1: Docker Runner (GitHub Actions)

Use the `actions-runners/` Docker container which includes OpenSSH 9.x:

```yaml
# In your GitHub Actions workflow
jobs:
  ssh-to-legacy-vm:
    runs-on: [self-hosted, docker, ssh-capable]
    steps:
      - uses: appleboy/ssh-action@v1
        with:
          host: legacy-vm
          username: admin
          key: ${{ secrets.SSH_KEY }}
          script: |
            uname -a
            sw_vers
```

### Option 2: MacPorts openssh9-client

For direct CLI access outside of GitHub Actions:

```bash
# Install openssh9-client from MacPorts
sudo port install openssh9-client

# Connect to legacy systems
ssh9 hostname
```

Configuration is managed in `/opt/local/etc/ssh9/ssh_config`.

## Future Plans

Future containers may include:
- Specialized build environments for cross-compilation
- Testing containers for port validation
- Additional runner types for different platforms

## Security Notes

1. **Sensitive Data**: Never commit secrets or credentials to the repository
2. **Network Isolation**: Containers should be on isolated networks when possible
3. **Regular Updates**: Keep base images updated for security patches
4. **Minimal Privileges**: Containers run with minimal required permissions

## License

These Docker configurations are part of the blakeports project and follow the project license.

