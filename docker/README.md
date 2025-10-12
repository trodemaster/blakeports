# Docker Containers for BlakePorts

This directory contains Docker containers used for development, testing, and infrastructure support for the BlakePorts project.

## Structure

```
docker/
└── actions-runners/        # GitHub Actions runners (future)
    └── .gitkeep
```

## Planned Containers

### GitHub Actions Runners (`actions-runners/`)

Future location for custom GitHub Actions runner containers for specialized build environments.

## Legacy Systems Access

For connecting to legacy SSH servers (Mac OS X 10.6-10.8, older Linux systems) that only support deprecated algorithms like `ssh-rsa`, use the **openssh9-client** MacPorts port instead:

```bash
# Install openssh9-client from MacPorts
sudo port install openssh9-client

# Connect to legacy systems
ssh9 hostname
```

Configuration is managed in `/opt/local/etc/ssh9/ssh_config`.

## Future Plans

Future containers may include:
- Custom GitHub Actions runners for specific macOS versions
- Specialized build environments for cross-compilation
- Testing containers for port validation

## Security Notes

1. **Sensitive Data**: Never commit secrets or credentials to the repository
2. **Network Isolation**: Containers should be on isolated networks when possible
3. **Regular Updates**: Keep base images updated for security patches
4. **Minimal Privileges**: Containers run with minimal required permissions

## License

These Docker configurations are part of the blakeports project and follow the project license.

