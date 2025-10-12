# SSH Legacy Proxy - Architecture & Design

## Problem Statement

OpenSSH 10.0 and later have **completely removed** support for legacy cryptographic algorithms:
- `ssh-rsa` (SHA-1 based host keys)
- `ssh-dss` (DSA with 1024-bit keys)
- Various legacy key exchange algorithms
- Old cipher suites

These algorithms cannot be re-enabled via configuration options because they have been removed from the codebase entirely for security reasons.

This creates a compatibility barrier when connecting to legacy systems:
- Mac OS X 10.6 (Snow Leopard) - OpenSSH 5.2p1
- Mac OS X 10.7 (Lion) - OpenSSH 5.6p1
- Mac OS X 10.8 (Mountain Lion) - OpenSSH 5.9p1
- Legacy Linux/Unix systems
- Embedded devices with old SSH servers

## Solution Architecture

### Design Principles

1. **Isolation**: Keep legacy crypto contained, not system-wide
2. **Transparency**: Works with standard SSH ProxyJump
3. **Security**: Modern crypto for client connections, legacy only for final hop
4. **Maintainability**: Easy to deploy, update, and eventually deprecate

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SSH Communication Flow                       │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐          ┌──────────────┐          ┌──────────────┐
│              │          │              │          │              │
│   Modern     │  Modern  │  SSH Proxy   │  Legacy  │   Legacy     │
│   Client     │  Crypto  │  Container   │  Crypto  │   Server     │
│              │  ────▶   │              │  ────▶   │              │
│ OpenSSH 10.0 │          │ OpenSSH 9.x  │          │ OpenSSH 5.6  │
│              │          │   (Debian)   │          │              │
└──────────────┘          └──────────────┘          └──────────────┘
     macOS                   Docker                   Mac OS X 10.7
     Sequoia                 Container                Lion

┌─────────────────────────────────────────────────────────────────────┐
│                    Cryptographic Algorithms Used                     │
└─────────────────────────────────────────────────────────────────────┘

Client → Proxy:                    Proxy → Legacy Server:
  • Ed25519 host keys                • ssh-rsa host keys
  • ECDSA (nistp256/384/521)        • ssh-dss host keys
  • rsa-sha2-256/512                • Legacy key exchange
  • Modern key exchange              • Old cipher suites
  • Strong ciphers
```

### Container Components

#### 1. SSH Server (sshd)

**Purpose**: Accept incoming connections from modern clients

**Configuration** (`sshd_config`):
- Listens on port 2222
- Uses modern host keys (RSA, ECDSA, Ed25519)
- Requires public key authentication only
- Enables TCP forwarding (essential for ProxyJump)
- No password authentication
- Standard security hardening

**Why port 2222?**
- Avoids conflicts with host SSH on port 22
- Clearly indicates non-standard SSH service
- Easy to firewall separately

#### 2. SSH Client (ssh)

**Purpose**: Make outbound connections to legacy systems

**Configuration** (`ssh_config`):
- Enables legacy host key algorithms: `+ssh-rsa,ssh-dss`
- Enables legacy public key algorithms: `+ssh-rsa`
- Optional legacy key exchange and ciphers (commented by default)
- Connection keep-alive settings
- Agent forwarding enabled

**The `+` syntax**: Adds algorithms to the default list rather than replacing it

#### 3. Base System

**Container Base**: Debian Bookworm (12) slim
- Small footprint (~100MB)
- OpenSSH 9.x from Debian repositories
- Well-maintained security updates

**Why Debian Bookworm?**
- Stable, long-term support
- OpenSSH 9.x still supports legacy algorithms when enabled
- Regular security updates
- Minimal attack surface

#### 4. User Setup

**Proxy User** (`sshproxy`):
- Non-root user for SSH access
- Home directory: `/home/sshproxy/`
- SSH keys directory: `/home/sshproxy/.ssh/`
- Member of `ssh` group

**Authentication**:
- Public key only (no passwords)
- Keys mounted from host via Docker volume
- Separate from legacy system keys

## Security Analysis

### Threat Model

**What we protect against:**
1. ✅ System-wide exposure to weak crypto
2. ✅ Accidental use of legacy algorithms for modern systems
3. ✅ Credential exposure (no passwords, keys only)
4. ✅ Container escape (runs unprivileged)

**What we don't protect against:**
1. ❌ Man-in-the-middle on legacy system connections (use trusted networks)
2. ❌ Compromised legacy systems (inherent to any legacy access)
3. ❌ Cryptographic weaknesses in ssh-rsa/ssh-dss (accept as legacy risk)

### Security Benefits vs. Alternatives

| Approach | System-Wide Risk | Auditability | Easy Removal |
|----------|-----------------|--------------|--------------|
| **Docker Proxy** | ✅ Low | ✅ Centralized | ✅ Yes |
| Downgrade OpenSSH | ❌ High | ❌ System-wide | ❌ No |
| Custom OpenSSH Build | ⚠️ Medium | ⚠️ Scattered | ⚠️ Difficult |
| VPN to Legacy Net | ⚠️ Medium | ⚠️ Depends | ⚠️ Complex |

### Least Privilege

1. **Container isolation**: Separate namespace, cgroups, limited syscalls
2. **No root access**: SSH user is unprivileged
3. **Read-only keys**: Keys mounted read-only into container
4. **Network segmentation**: Container on isolated bridge network
5. **Resource limits**: CPU and memory limits via Docker

### Audit Trail

All proxy connections pass through a single point:
```bash
# Monitor all connections
docker compose logs -f

# See who connected when
docker compose logs | grep "Accepted publickey"

# Track outbound connections
docker compose logs | grep "Connection to"
```

## Technical Implementation

### Docker Networking

**Default Setup** (Bridge Network):
```yaml
networks:
  ssh-proxy-net:
    driver: bridge
```

**Flow**:
1. Host exposes port 2222 → Container port 2222
2. Container can access host network for legacy systems
3. Container has outbound internet access (for updates)

**Advanced**: Restrict to specific networks via iptables or custom networks

### Volume Mounts

**Keys Volume** (Read-Only):
```yaml
volumes:
  - ./keys:/home/sshproxy/.ssh:ro
```

**Contents**:
- `authorized_keys` - Public keys for accessing proxy
- Legacy private keys (e.g., `oldmac`) - For legacy system auth
- Mounted read-only for security

**Known Hosts Volume** (Persistent):
```yaml
volumes:
  - ssh-proxy-data:/home/sshproxy/.ssh/known_hosts
```

**Purpose**: Persist learned host keys across container restarts

### Health Checks

**Docker Health Check**:
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s \
  CMD nc -z localhost 2222 || exit 1
```

**Purpose**:
- Verify sshd is listening
- Enable Docker orchestration (restart on failure)
- Status visible in `docker compose ps`

**Test Targets**:
```bash
make test         # Test proxy accepts connections
make test-legacy  # Test full chain to legacy system
```

## SSH ProxyJump Mechanics

### How ProxyJump Works

Traditional SSH requires two commands:
```bash
ssh user@proxy
ssh user@legacy-host  # From inside proxy
```

ProxyJump does this automatically:
```ssh-config
Host tenseven
  Hostname tenseven.local
  ProxyJump ssh-proxy
```

**Under the hood**:
1. SSH establishes connection to `ssh-proxy`
2. SSH runs `ssh -W tenseven.local:22` on proxy
3. `-W` creates a tunnel: stdin/stdout → tenseven.local:22
4. Client uses this tunnel for the final connection
5. All crypto negotiation happens over each hop independently

### Equivalent ProxyCommand

```ssh-config
Host tenseven
  ProxyCommand ssh -W %h:%p ssh-proxy
```

**Variables**:
- `%h` - Target hostname (tenseven.local)
- `%p` - Target port (22)

### Why This Works

**Key insight**: Each SSH hop negotiates crypto independently:

```
Client ←──[Modern Crypto]──→ Proxy ←──[Legacy Crypto]──→ Legacy
```

The client never sees or negotiates with the legacy system directly. The proxy terminates the modern connection and initiates a new legacy connection.

## Maintenance & Updates

### Update Strategy

1. **Base Image**: Debian releases security updates regularly
2. **Rebuild**: `make rebuild` pulls latest Debian packages
3. **Frequency**: Monthly or when CVEs announced

### Monitoring

**Key Metrics**:
- Connection success/failure rate
- Failed authentication attempts
- Container health check status
- Resource usage (CPU, memory)

**Log Locations**:
- Container stdout: `make logs`
- SSH auth logs: Inside container at `/var/log/auth.log`
- Docker events: `docker events --filter container=ssh-proxy-legacy`

### Backup & Restore

**Critical Files**:
```bash
docker/ssh/
├── keys/authorized_keys    # Proxy access
├── keys/oldmac            # Legacy system key
├── sshd_config            # Server config
├── ssh_config             # Client config
└── docker-compose.yml     # Container config
```

**Backup**:
```bash
tar czf ssh-proxy-backup.tar.gz docker/ssh/
```

**Restore**:
```bash
tar xzf ssh-proxy-backup.tar.gz
cd docker/ssh && make up
```

## Performance Considerations

### Latency

**Connection Overhead**:
- Additional TLS handshake for proxy hop: ~50-100ms
- Container network overhead: <1ms
- Total added latency: ~50-100ms

**Optimization**:
- Use `ControlMaster` for connection reuse
- Persistent connections reduce handshake frequency

### Resource Usage

**Typical Load**:
- Idle: ~20MB RAM, 0% CPU
- Active connection: ~40MB RAM, <5% CPU
- Max concurrent: Limited by container resources

**Limits** (docker-compose.yml):
```yaml
resources:
  limits:
    cpus: '0.5'
    memory: 256M
```

## Future Considerations

### Deprecation Path

When legacy systems are retired:
1. Remove from SSH config
2. Stop container: `make down`
3. Remove container: `make clean-all`
4. Delete directory: `rm -rf docker/ssh/`

No system-wide changes needed!

### Alternative Approaches Evaluated

**1. Patch OpenSSH 10 to re-enable legacy**
- ❌ Rejected: Requires maintaining custom fork
- ❌ Security risk: Reintroduces removed vulnerabilities

**2. Use OpenSSH 9 system-wide**
- ❌ Rejected: Prevents using modern crypto by default
- ❌ Maintenance burden: Manual updates

**3. VPN to legacy network**
- ⚠️ Partial solution: Still need compatible SSH client
- ⚠️ Complexity: Additional infrastructure

**4. Upgrade legacy systems**
- ✅ Ideal long-term solution
- ❌ Not always feasible (testing old OS versions)

### Port to Other Platforms

**Requirements**:
- Docker runtime
- Network access to legacy systems
- Modern SSH client (for ProxyJump)

**Platforms**:
- ✅ macOS (Docker Desktop)
- ✅ Linux (Docker Engine)
- ✅ Windows (Docker Desktop + WSL2)

## References

- [OpenSSH Legacy Options](https://www.openssh.com/legacy.html)
- [OpenSSH 10.0 Release Notes](https://www.openssh.com/releasenotes.html#10.0p1)
- [SSH ProxyJump Documentation](https://man.openbsd.org/ssh_config.5#ProxyJump)
- [Debian OpenSSH Package](https://packages.debian.org/bookworm/openssh-server)

## License

This architecture is part of the blakeports project. See main LICENSE file.

