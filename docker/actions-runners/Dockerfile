# GitHub Actions Self-Hosted Runner with OpenSSH 9.x
# Based on Ubuntu 24.04 (Noble Numbat)
FROM ubuntu:24.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set runner version (can be overridden at build time)
ARG RUNNER_VERSION=2.321.0

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
    && rm -rf /var/lib/apt/lists/*

# Verify OpenSSH version (should be 9.x)
RUN ssh -V

# Pre-install drone-ssh binary to avoid repeated downloads in workflows
ARG DRONE_SSH_VERSION=1.8.1
RUN curl -L -o /usr/local/bin/drone-ssh \
    https://github.com/appleboy/drone-ssh/releases/download/v${DRONE_SSH_VERSION}/drone-ssh-${DRONE_SSH_VERSION}-linux-amd64 && \
    chmod +x /usr/local/bin/drone-ssh && \
    drone-ssh --version

# Create runner user with sudo access
RUN useradd -m -s /bin/bash runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/runner

# Download and extract GitHub Actions runner
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

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

# Switch to runner user
USER runner

# Copy entrypoint script
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/home/runner/entrypoint.sh"]

