#!/bin/bash
# GitHub Actions Runner Entrypoint Script
# Registers and starts a self-hosted runner with dynamic token generation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function to deregister runner on exit
cleanup() {
    print_info "Caught signal, removing runner..."
    if [ -f "/home/runner/.runner" ]; then
        ./config.sh remove --token "${RUNNER_TOKEN}"
    fi
    exit 0
}

# Trap signals for cleanup
trap cleanup SIGTERM SIGINT SIGQUIT

# Validate required environment variables
if [ -z "$GITHUB_OWNER" ]; then
    print_error "GITHUB_OWNER environment variable is required"
    exit 1
fi

if [ -z "$GITHUB_REPO" ]; then
    print_error "GITHUB_REPO environment variable is required"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GITHUB_TOKEN environment variable is required (Personal Access Token)"
    exit 1
fi

# Set defaults if not provided
RUNNER_NAME="${RUNNER_NAME:-docker-runner-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

# Generate GitHub runner registration token
print_info "Generating GitHub runner registration token..."
print_info "Repository: $GITHUB_OWNER/$GITHUB_REPO"

RUNNER_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token | jq -r '.token')

if [ -z "$RUNNER_TOKEN" ] || [ "$RUNNER_TOKEN" = "null" ]; then
    print_error "Failed to generate runner registration token"
    print_error "Check that your GITHUB_TOKEN has the correct permissions"
    print_error "Required: 'repo' scope for private repos or 'public_repo' for public repos"
    exit 1
fi

print_success "Registration token generated successfully"

# Generate runner labels based on system
print_info "Detecting system information..."
OS_TYPE=$(uname -s)
ARCH=$(uname -m)

# Generate labels
RUNNER_LABELS="self-hosted,Linux,docker,ssh-capable"

case "$ARCH" in
    "x86_64")
        RUNNER_LABELS="$RUNNER_LABELS,X64"
        ;;
    "aarch64"|"arm64")
        RUNNER_LABELS="$RUNNER_LABELS,ARM64"
        ;;
    *)
        RUNNER_LABELS="$RUNNER_LABELS,$ARCH"
        ;;
esac

# Add Ubuntu version label
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ -n "$VERSION_ID" ]; then
        RUNNER_LABELS="$RUNNER_LABELS,ubuntu-${VERSION_ID}"
    fi
fi

# Add custom labels from environment variable
if [ -n "$CUSTOM_LABELS" ]; then
    RUNNER_LABELS="$RUNNER_LABELS,$CUSTOM_LABELS"
fi

print_info "Runner name: $RUNNER_NAME"
print_info "Runner labels: $RUNNER_LABELS"
print_info "Working directory: $RUNNER_WORKDIR"

# Configure runner
print_info "Configuring GitHub Actions runner..."
./config.sh \
    --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --work "${RUNNER_WORKDIR}" \
    --unattended \
    --replace

if [ $? -ne 0 ]; then
    print_error "Failed to configure runner"
    exit 1
fi

print_success "Runner configured successfully"

# Start runner
print_info "Starting GitHub Actions runner..."
print_info "Runner is now listening for jobs..."

# Run the runner (this blocks until runner exits)
./run.sh

# If we get here, runner exited normally
print_info "Runner stopped"

