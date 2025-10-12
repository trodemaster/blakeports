# SSH Proxy Container for Legacy Systems
# Bridges modern OpenSSH 10+ clients with legacy SSH servers (OpenSSH 5.x/6.x)
# that only support deprecated algorithms like ssh-rsa and ssh-dss

FROM debian:bookworm-slim

LABEL maintainer="blake@blakeports"
LABEL description="SSH proxy supporting legacy algorithms for connecting to older systems"

# Install OpenSSH server (Debian Bookworm has OpenSSH 9.x)
# OpenSSH 9 still supports legacy algorithms when explicitly enabled
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        openssh-client \
        ca-certificates \
        curl \
        vim-tiny \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd

# Create privilege separation directory
RUN mkdir -p /run/sshd

# Generate host keys (modern algorithms for incoming connections)
RUN ssh-keygen -A

# Copy SSH server configuration
COPY sshd_config /etc/ssh/sshd_config

# Copy SSH client configuration (for outbound connections to legacy systems)
COPY ssh_config /etc/ssh/ssh_config.d/legacy.conf

# Create a proxy user (for authenticated access to the proxy)
RUN useradd -m -s /bin/bash sshproxy && \
    mkdir -p /home/sshproxy/.ssh && \
    chmod 700 /home/sshproxy/.ssh && \
    chown -R sshproxy:sshproxy /home/sshproxy/.ssh

# Expose SSH port
EXPOSE 2222

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD nc -z localhost 2222 || exit 1

# Run SSH daemon in foreground
CMD ["/usr/sbin/sshd", "-D", "-e", "-p", "2222"]

