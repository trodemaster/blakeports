FROM ubuntu:24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_WORKDIR=/tmp/runner

# Install system dependencies and add custom repositories
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    ca-certificates \
    tar \
    gnupg \
    lsb-release \
    libicu-dev \
    libicu74 \
    libkrb5-3 \
    zlib1g \
    libssl3 \
    liblttng-ust1t64 \
    liblttng-ust-common1t64 \
    liblttng-ust-ctl5t64 \
    libnuma1 \
    && rm -rf /var/lib/apt/lists/*

# Add HashiCorp GPG key and repository
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && chmod a+r /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

# Update package lists with new repositories
RUN apt-get update

# Create runner directory
RUN mkdir -p ${RUNNER_WORKDIR}

# Accept build argument for runner architecture
ARG RUNNER_ARCH=x64

# Download and install GitHub Actions runner during build
RUN cd ${RUNNER_WORKDIR} && \
    # Get the latest GitHub Actions runner version
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//') && \
    echo "Installing GitHub Actions runner version: ${RUNNER_VERSION} for architecture: ${RUNNER_ARCH}" && \
    # Download and extract the runner
    curl -o actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
    # Make scripts executable
    chmod +x config.sh run.sh

# Copy setup script
COPY runner-setup.sh /runner-setup.sh
RUN chmod +x /runner-setup.sh

# Set working directory
WORKDIR ${RUNNER_WORKDIR}

# Expose the runner work directory
VOLUME ["${RUNNER_WORKDIR}"]

# Default command
CMD ["/runner-setup.sh"]
