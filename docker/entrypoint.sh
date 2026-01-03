#!/bin/bash
# GitHub Actions Runner Entrypoint Script
# Registers and starts a self-hosted runner with SSH proxy to legacy VMs
# Configuration is read from /config/runners.json (mounted from host)

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

# Configuration file path
CONFIG_FILE="/config/runners.json"

# Cleanup function to deregister runner on exit
cleanup() {
    print_info "Caught signal, removing runner..."
    # Try to stop avahi-daemon if running
    sudo pkill -f "avahi-daemon" 2>/dev/null || true
    if [ -f "/home/runner/.runner" ]; then
        # Re-read token from config in case it changed
        local current_token
        current_token=$(jq -r ".runners.${RUNNER_ID}.token // empty" "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$current_token" ]; then
            ./config.sh remove --token "$current_token"
        fi
    fi
    exit 0
}

# Trap signals for cleanup
trap cleanup SIGTERM SIGINT SIGQUIT

# Start avahi-daemon for mDNS/Bonjour resolution (optional - may fail in some environments)
print_info "Starting avahi-daemon for mDNS support..."
if sudo /usr/sbin/avahi-daemon -D 2>&1 | grep -q "daemonized"; then
    print_success "avahi-daemon started successfully"
else
    print_warning "avahi-daemon not available (mDNS resolution may not work)"
fi

# Give avahi a moment to initialize
sleep 1

# Validate required environment variables (from docker-compose)
if [ -z "$RUNNER_ID" ]; then
    print_error "RUNNER_ID environment variable is required"
    exit 1
fi

if [ -z "$RUNNER_NAME" ]; then
    print_error "RUNNER_NAME environment variable is required"
    exit 1
fi

# Wait for config file to be available (with timeout)
print_info "Waiting for configuration file..."
WAIT_COUNT=0
MAX_WAIT=60
while [ ! -f "$CONFIG_FILE" ]; do
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        print_error "Configuration file not found after ${MAX_WAIT}s: $CONFIG_FILE"
        print_error "Run 'ghrunner -vmware $RUNNER_ID' to generate configuration"
        exit 1
    fi
done
print_success "Configuration file found: $CONFIG_FILE"

# Read configuration from JSON file
read_config() {
    local key=$1
    local value
    value=$(jq -r ".runners.${RUNNER_ID}.${key} // empty" "$CONFIG_FILE" 2>/dev/null)
    echo "$value"
}

read_github_config() {
    local key=$1
    local value
    value=$(jq -r ".github.${key} // empty" "$CONFIG_FILE" 2>/dev/null)
    echo "$value"
}

# Read runner configuration
RUNNER_TOKEN=$(read_config "token")
VM_IP=$(read_config "vm_ip")
VM_HOSTNAME=$(read_config "vm_hostname")
VM_USER=$(read_config "vm_user")
SSH_KEY_NAME=$(read_config "ssh_key")
CUSTOM_LABELS=$(read_config "labels")
GITHUB_OWNER=$(read_github_config "owner")
GITHUB_REPO=$(read_github_config "repo")

# Validate required config values
if [ -z "$RUNNER_TOKEN" ]; then
    print_error "Runner token not found in config for: $RUNNER_ID"
    print_error "Run 'ghrunner -vmware $RUNNER_ID' to generate a token"
    exit 1
fi

if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
    print_error "GitHub owner/repo not configured in $CONFIG_FILE"
    exit 1
fi

if [ -z "$VM_HOSTNAME" ]; then
    print_error "VM hostname not configured for runner: $RUNNER_ID"
    exit 1
fi

if [ -z "$VM_USER" ]; then
    print_error "VM user not configured for runner: $RUNNER_ID"
    exit 1
fi

if [ -z "$SSH_KEY_NAME" ]; then
    print_error "SSH key name not configured for runner: $RUNNER_ID"
    exit 1
fi

# Determine SSH target - VM_IP is required (set by ghrunner script)
if [ -z "$VM_IP" ]; then
    print_error "VM IP address not set for runner: $RUNNER_ID"
    print_error "Run 'ghrunner -vmware $RUNNER_ID' to resolve VM IP"
    exit 1
fi
SSH_TARGET="$VM_IP"

print_info "Configuration loaded for runner: $RUNNER_ID"
print_info "Repository: $GITHUB_OWNER/$GITHUB_REPO"
print_info "VM target: $VM_HOSTNAME ($VM_IP)"

# Configure SSH for legacy VM access
print_info "Configuring SSH connection to legacy VM..."
SSH_CONFIG_FILE="/home/runner/.ssh/config"
SSH_KEY_PATH="/config/ssh_keys/${SSH_KEY_NAME}"

# Verify SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    print_error "SSH key not found: $SSH_KEY_PATH"
    print_error "SSH keys should be stored in config/ssh_keys/ directory"
    exit 1
fi

# Copy SSH key to runner's home with proper permissions
cp "$SSH_KEY_PATH" "/home/runner/.ssh/${SSH_KEY_NAME}"
chmod 600 "/home/runner/.ssh/${SSH_KEY_NAME}"
print_info "SSH key found: $SSH_KEY_PATH"

# Create SSH config with legacy algorithms
cat > "$SSH_CONFIG_FILE" << EOF
Host $VM_HOSTNAME
    HostName $SSH_TARGET
    User $VM_USER
    IdentityFile /home/runner/.ssh/${SSH_KEY_NAME}
    HostKeyAlgorithms ssh-rsa
    PubkeyAcceptedKeyTypes ssh-rsa
    KexAlgorithms diffie-hellman-group1-sha1
    Ciphers aes128-cbc
    MACs hmac-sha1
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ConnectTimeout 10
EOF

chmod 600 "$SSH_CONFIG_FILE"
print_success "SSH config created for $VM_HOSTNAME -> $SSH_TARGET"

# Generate runner labels based on system and VM
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

# Add VM hostname as label for workflow targeting
RUNNER_LABELS="$RUNNER_LABELS,$VM_HOSTNAME"

# Add custom labels from config
if [ -n "$CUSTOM_LABELS" ]; then
    RUNNER_LABELS="$RUNNER_LABELS,$CUSTOM_LABELS"
fi

print_info "Runner name: $RUNNER_NAME"
print_info "Runner labels: $RUNNER_LABELS"
print_info "Working directory: ${RUNNER_WORKDIR:-_work}"
print_info "SSH proxy target: $VM_HOSTNAME -> $SSH_TARGET"

# Configure runner
print_info "Configuring GitHub Actions runner..."
./config.sh \
    --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
    --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --work "${RUNNER_WORKDIR:-_work}" \
    --unattended \
    --replace

if [ $? -ne 0 ]; then
    print_error "Failed to configure runner"
    exit 1
fi

print_success "Runner configured and registered successfully"

# Background function to continuously monitor SSH connectivity and manage runner service
monitor_ssh_connectivity() {
    local retry_delay=30
    local ssh_connected=false
    local runner_active=false
    
    print_info "SSH monitor: Starting continuous SSH connectivity checks every ${retry_delay}s..."
    
    while true; do
        if ssh -F "$SSH_CONFIG_FILE" "$VM_HOSTNAME" "echo 'SSH connection successful'" >/dev/null 2>&1; then
            if [ "$ssh_connected" = false ]; then
                print_success "SSH connection to $VM_HOSTNAME ($SSH_TARGET) ESTABLISHED"
                ssh_connected=true
                
                # Start runner service if not already running
                if [ "$runner_active" = false ]; then
                    print_info "SSH successful - starting GitHub Actions runner service..."
                    if ./run.sh &
                    then
                        RUN_PID=$!
                        runner_active=true
                        print_success "Runner service started (PID: $RUN_PID)"
                    else
                        print_error "Failed to start runner service"
                    fi
                fi
            fi
        else
            if [ "$ssh_connected" = true ]; then
                print_warning "SSH connection to $VM_HOSTNAME LOST"
                ssh_connected=false
                
                # Stop runner service if it's running
                if [ "$runner_active" = true ] && [ -n "$RUN_PID" ]; then
                    print_warning "SSH lost - stopping GitHub Actions runner service..."
                    if kill $RUN_PID 2>/dev/null; then
                        runner_active=false
                        print_warning "Runner service stopped"
                    fi
                fi
            else
                print_warning "SSH connection to $VM_HOSTNAME ($SSH_TARGET) unavailable"
            fi
        fi
        
        sleep $retry_delay
    done
}

# Start SSH monitoring in background AFTER config.sh completes
print_info "Starting background SSH connectivity monitor..."
monitor_ssh_connectivity &
SSH_MONITOR_PID=$!
print_info "SSH monitor started (PID: $SSH_MONITOR_PID) - will check connectivity every 30s"

print_info "Runner registered but NOT YET ACTIVE - waiting for SSH connectivity..."
print_info "SSH monitor (PID: $SSH_MONITOR_PID) will start runner service once SSH connection succeeds"
print_info ""
print_info "Waiting indefinitely - runner will be started by SSH monitor when SSH becomes available..."
print_info ""

# Wait indefinitely for the monitor process (this prevents container exit)
wait $SSH_MONITOR_PID
