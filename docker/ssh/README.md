# SSH Legacy Proxy

A Docker container that acts as an SSH proxy/jump host to bridge modern OpenSSH 10+ clients with legacy SSH servers (OpenSSH 5.x/6.x) that only support deprecated cryptographic algorithms like `ssh-rsa` and `ssh-dss`.

## Problem

Modern OpenSSH versions (10.0+) have completely removed support for deprecated algorithms:
- `ssh-rsa` (SHA-1 based)
- `ssh-dss` (DSA with 1024-bit keys)

This makes it impossible to connect directly to older systems like:
- Mac OS X 10.6 (Snow Leopard) - OpenSSH 5.2
- Mac OS X 10.7 (Lion) - OpenSSH 5.6
- Mac OS X 10.8 (Mountain Lion) - OpenSSH 5.9
- Various legacy Linux/Unix systems

## Solution

This container runs OpenSSH 9.x (from Debian Bookworm), which still supports legacy algorithms when explicitly enabled. It acts as a jump host that:

1. **Accepts** modern crypto connections from OpenSSH 10+ clients (Ed25519, ECDSA, rsa-sha2-256/512)
2. **Connects** to legacy systems using deprecated algorithms (ssh-rsa, ssh-dss)

## Quick Start

### Option A: Interactive Setup (Recommended)

```bash
cd docker/ssh
./setup.sh           # Interactive setup with guided configuration
make up              # Start the proxy
```

### Option B: Manual Setup

### 1. Build the Container

```bash
cd docker/ssh
make build           # or: docker compose build
```

### 2. Set Up SSH Keys

Create a `keys` directory with your private keys for legacy systems:

```bash
mkdir -p keys
chmod 700 keys

# Copy your private key for old systems
cp ~/.ssh/oldmac keys/
chmod 600 keys/*
```

### 3. Generate SSH Key for Proxy Access

Generate a key on your modern client to authenticate to the proxy:

```bash
# On your modern system
ssh-keygen -t ed25519 -f ~/.ssh/ssh-proxy -C "ssh-proxy"

# Create authorized_keys for the proxy
mkdir -p keys
cat ~/.ssh/ssh-proxy.pub > keys/authorized_keys
chmod 644 keys/authorized_keys
```

### 4. Start the Container

```bash
make up              # or: docker compose up -d
```

### 5. Configure SSH Client

Add to your `~/.ssh/config`:

```ssh-config
# The SSH proxy container
Host ssh-proxy
  Hostname localhost
  Port 2222
  User sshproxy
  IdentityFile ~/.ssh/ssh-proxy
  
# Legacy Mac OS X 10.7 system via proxy
Host tenseven
  Hostname tenseven.local
  User blake
  ProxyJump ssh-proxy
  IdentityFile ~/.ssh/oldmac
```

### 6. Connect

```bash
# Connect to legacy system through proxy
ssh tenseven

# Or use ProxyCommand directly
ssh -o ProxyCommand="ssh -W %h:%p ssh-proxy" blake@tenseven.local
```

## Architecture

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────────┐
│  Modern Client  │         │  SSH Proxy   │         │  Legacy Server  │
│  OpenSSH 10.0   │────────▶│  OpenSSH 9.x │────────▶│  OpenSSH 5.6    │
│                 │  Ed25519│  (Container) │ ssh-rsa │  (Mac OS X 10.7)│
└─────────────────┘         └──────────────┘         └─────────────────┘
     Modern Crypto              Bridge                  Legacy Crypto
```

## Configuration

### Enable Additional Legacy Algorithms

If you need to support even older systems, edit `ssh_config` and uncomment:

```
# Very old key exchange algorithms
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1

# Old ciphers
Ciphers +aes128-cbc,3des-cbc,aes192-cbc,aes256-cbc
```

### Custom Port

To change the exposed port, edit `docker-compose.yml`:

```yaml
ports:
  - "2222:2222"  # Change first number to desired host port
```

### Add More Keys

Mount additional keys by adding to `docker-compose.yml`:

```yaml
volumes:
  - ./keys:/home/sshproxy/.ssh:ro
  - ./additional-keys:/home/sshproxy/.ssh/extra:ro
```

## Common Operations

### Using Make (Recommended)

```bash
make help            # Show all available commands
make up              # Start proxy
make down            # Stop proxy
make restart         # Restart proxy
make logs            # View logs (follow mode)
make shell           # Open shell in container
make test            # Test proxy connection
make status          # Show detailed status
```

### Using Docker Compose Directly

```bash
docker compose up -d      # Start
docker compose down       # Stop
docker compose logs -f    # View logs
docker compose ps         # Status
```

## Troubleshooting

### Check Container Status

```bash
make status          # Detailed status report
make logs            # View live logs
```

### Test Proxy Connection

```bash
# Quick test using make
make test

# Or manually
ssh -p 2222 sshproxy@localhost

# Verbose debugging
ssh -vvv -p 2222 sshproxy@localhost

# Test full proxy chain to legacy system
make test-legacy
```

### Test Legacy Connection from Inside Container

```bash
# Execute shell in container
make shell

# Try connecting to legacy system
ssh -v blake@tenseven.local
```

### Common Issues

**Connection refused:**
- Ensure container is running: `make status`
- Check logs: `make logs`

**Permission denied (publickey):**
- Verify authorized_keys is mounted: `make shell` then `cat ~/.ssh/authorized_keys`
- Check key permissions: `ls -la keys/`

**Unable to negotiate:**
- Legacy system needs even older algorithms - edit `ssh_config`
- Check supported algorithms: `make shell` then `ssh -Q cipher`

## Security Considerations

### Why This Is Safer Than Enabling Legacy Crypto System-Wide

1. **Isolation**: Legacy algorithms are contained in the proxy, not system-wide
2. **Audit Trail**: All legacy connections pass through a single point
3. **Network Segmentation**: Can restrict proxy to internal/trusted networks only
4. **Easy Deprecation**: Remove container when legacy systems are retired

### Best Practices

1. **Restrict Network Access**: Only allow proxy to connect to known legacy systems
2. **Use Strong Keys**: Use Ed25519 or ECDSA keys for proxy authentication
3. **Monitor**: Review proxy logs regularly
4. **Temporary**: Plan to upgrade or retire legacy systems

### Network Restrictions

Add to `docker-compose.yml` to restrict outbound access:

```yaml
networks:
  ssh-proxy-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

## Alternatives Considered

1. **SSH -o Options**: Doesn't work - OpenSSH 10 removed algorithm support entirely
2. **Downgrade OpenSSH**: Security risk, affects entire system
3. **VPN to Legacy Network**: Still need compatible SSH client
4. **Upgrade Legacy Systems**: Best option, but not always possible

## Maintenance

### Update Container

```bash
make rebuild        # Rebuild from scratch
# or
docker compose pull
docker compose up -d --build
```

### Backup Configuration

```bash
tar czf ssh-proxy-backup.tar.gz keys/ docker-compose.yml ssh_config sshd_config
```

## Related Documentation

- [OpenSSH Legacy Options](https://www.openssh.com/legacy.html)
- [OpenSSH 10.0 Release Notes](https://www.openssh.com/releasenotes.html#10.0p1)
- [SSH ProxyJump](https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Proxies_and_Jump_Hosts)

## License

This configuration is part of the blakeports project and follows the same license.

