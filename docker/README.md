# Docker Containers for BlakePorts

This directory contains Docker containers used for development, testing, and infrastructure support for the BlakePorts project.

## Structure

```
docker/
├── ssh/                    # SSH proxy for legacy systems
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── sshd_config
│   ├── ssh_config
│   └── README.md
│
└── actions-runners/        # GitHub Actions runners (future)
    └── .gitkeep
```

## Containers

### SSH Legacy Proxy (`ssh/`)

A bridge container running OpenSSH 9.x that enables modern OpenSSH 10+ clients to connect to legacy SSH servers that only support deprecated algorithms (ssh-rsa, ssh-dss).

**Use cases:**
- Connecting to Mac OS X 10.6-10.8 systems
- Accessing legacy Linux/Unix servers
- Testing old macOS VMs in CI/CD

See [ssh/README.md](ssh/README.md) for detailed documentation.

### GitHub Actions Runners (`actions-runners/`)

Future location for custom GitHub Actions runner containers.

## Common Operations

### Build All Containers

```bash
# Build SSH proxy
cd docker/ssh
docker compose build
```

### Start Services

```bash
# Start SSH proxy
cd docker/ssh
docker compose up -d
```

### View Logs

```bash
# SSH proxy logs
cd docker/ssh
docker compose logs -f
```

### Stop Services

```bash
# Stop SSH proxy
cd docker/ssh
docker compose down
```

## Security Notes

1. **Sensitive Data**: Never commit SSH private keys or secrets to the repository
2. **Network Isolation**: Containers should be on isolated networks when possible
3. **Regular Updates**: Keep base images updated for security patches
4. **Minimal Privileges**: Containers run with minimal required permissions

## Requirements

- Docker Engine 20.10+
- Docker Compose 2.0+

## License

These Docker configurations are part of the blakeports project and follow the project license.

