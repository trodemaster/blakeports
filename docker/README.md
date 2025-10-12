# Docker Containers for BlakePorts

This directory contains Docker containers used for development, testing, and infrastructure support for the BlakePorts project.

## Structure

```
docker/
└── actions-runners/        # GitHub Actions self-hosted runners
    ├── Dockerfile          # Ubuntu 24.04 with GitHub Actions runner and OpenSSH 9.x
    ├── entrypoint.sh       # Runner registration and startup script
    ├── docker-compose.yml  # Container orchestration configuration
    ├── example.env         # Environment variable template
    ├── .gitignore          # Ignore sensitive files
    └── README.md           # Detailed setup and usage documentation
```

## Available Containers

### GitHub Actions Self-Hosted Runners (`actions-runners/`)

Docker-based GitHub Actions runners with OpenSSH 9.x support for connecting to legacy VMs.

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

