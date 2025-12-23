# GitHub Actions Self-Hosted Runner with OpenSSH 9.x
# Based on Ubuntu 24.04 (Noble Numbat)
# Automatically builds for the host platform (arm64, amd64, etc.)
FROM ubuntu:24.04

# Docker automatically sets these to match the build context
ARG TARGETPLATFORM

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set runner version (can be overridden at build time)
ARG RUNNER_VERSION=2.321.0

# Determine the correct architecture suffix for downloads based on target platform
# TARGETPLATFORM is automatically set by Docker to the host architecture
# Examples: linux/amd64, linux/arm64, linux/arm/v7, etc.
RUN case "${TARGETPLATFORM}" in \
        linux/amd64) RUNNER_ARCH="x64" DRONE_ARCH="amd64" ;; \
        linux/arm64|linux/arm64/v8) RUNNER_ARCH="arm64" DRONE_ARCH="arm64" ;; \
        *) echo "Error: Unsupported platform ${TARGETPLATFORM}"; exit 1 ;; \
    esac && \
    echo "Building for ${TARGETPLATFORM}" && \
    echo "Using runner arch: ${RUNNER_ARCH}, drone-ssh arch: ${DRONE_ARCH}" && \
    echo "${RUNNER_ARCH}" > /tmp/runner_arch.txt && \
    echo "${DRONE_ARCH}" > /tmp/drone_arch.txt

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    openssh-client \
    ca-certificates \
    sudo \
    tzdata \
    libicu74 \
    avahi-daemon \
    avahi-utils \
    libnss-mdns \
    && rm -rf /var/lib/apt/lists/*

# Verify OpenSSH version (should be 9.x)
RUN ssh -V

# Pre-install drone-ssh binary to avoid repeated downloads in workflows
# Detects architecture and downloads the appropriate binary
ARG DRONE_SSH_VERSION=1.8.1
RUN DRONE_ARCH=$(cat /tmp/drone_arch.txt) && \
    curl -L -o /usr/local/bin/drone-ssh \
    https://github.com/appleboy/drone-ssh/releases/download/v${DRONE_SSH_VERSION}/drone-ssh-${DRONE_SSH_VERSION}-linux-${DRONE_ARCH} && \
    chmod +x /usr/local/bin/drone-ssh && \
    drone-ssh --version

# Create runner user with sudo access
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/runner

# Download and extract GitHub Actions runner
# Detects architecture and downloads the appropriate runner binary
RUN RUNNER_ARCH=$(cat /tmp/runner_arch.txt) && \
    curl -o actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz

# Install runner dependencies
RUN ./bin/installdependencies.sh

# Create SSH directory for runner user
RUN mkdir -p /home/runner/.ssh && \
    chmod 700 /home/runner/.ssh

# Copy SSH keys if they exist in build context
# Place your SSH keys in ./ssh_keys/ before building
COPY --chmod=600 ssh_keys/* /home/runner/.ssh/

# Create work directory with proper permissions
RUN mkdir -p /home/runner/_work && \
    chown -R runner:runner /home/runner && \
    chmod 700 /home/runner/.ssh

# Configure avahi for mDNS support (allows .local hostname resolution)
RUN mkdir -p /etc/avahi/services && \
    echo "<?xml version=\"1.0\" standalone='no'?>" > /etc/avahi/services/runner.service && \
    echo "<!DOCTYPE service-group SYSTEM \"avahi-service.dtd\">" >> /etc/avahi/services/runner.service && \
    echo "<service-group>" >> /etc/avahi/services/runner.service && \
    echo "  <name replace-wildcards=\"yes\">GitHub Runner (%h)</name>" >> /etc/avahi/services/runner.service && \
    echo "  <service>" >> /etc/avahi/services/runner.service && \
    echo "    <type>_ssh._tcp</type>" >> /etc/avahi/services/runner.service && \
    echo "    <port>22</port>" >> /etc/avahi/services/runner.service && \
    echo "  </service>" >> /etc/avahi/services/runner.service && \
    echo "</service-group>" >> /etc/avahi/services/runner.service

# Switch to runner user
USER runner

# Copy entrypoint script
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/home/runner/entrypoint.sh"]

