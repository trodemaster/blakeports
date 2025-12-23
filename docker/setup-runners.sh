#!/bin/bash
# Setup script for Docker Legacy Runners
# Run this in your terminal with: bash docker/setup-runners.sh

set -e

cd "$(dirname "$0")" || exit 1

echo "🔧 Setting up Docker Legacy Runners..."
echo ""

# Resolve IP addresses for legacy VMs
echo "🌐 Resolving IP addresses for legacy VMs..."

# Function to resolve mDNS hostname to IP using ping
resolve_ip() {
    local hostname=$1
    local ip
    
    # Use ping to resolve hostname and extract IP
    # ping output format: "PING hostname (IP):"
    ip=$(ping -c 1 -W 2 "$hostname" 2>/dev/null | grep "^PING" | sed -n 's/.*(\([^)]*\)).*/\1/p')
    
    echo "$ip"
}

# Resolve IPs
TENFIVE_IP=$(resolve_ip "tenfive-runner.local")
TENSEVEN_IP=$(resolve_ip "tenseven-runner.local")

if [ -z "$TENFIVE_IP" ]; then
    echo "⚠️  Could not resolve tenfive-runner.local - runners may not be accessible"
else
    echo "✅ tenfive-runner.local → $TENFIVE_IP"
fi

if [ -z "$TENSEVEN_IP" ]; then
    echo "⚠️  Could not resolve tenseven-runner.local - runners may not be accessible"
else
    echo "✅ tenseven-runner.local → $TENSEVEN_IP"
fi

echo ""

# Check if .env already exists with tokens
if [ -f .env ] && grep -q "RUNNER_TOKEN_TENFIVE=[a-zA-Z0-9_-]" .env && grep -q "RUNNER_TOKEN_TENSEVEN=[a-zA-Z0-9_-]" .env; then
    echo "✅ .env file already configured with tokens"
else
    echo "📝 Creating/updating .env file with generated tokens..."
    
    # Create empty .env if it doesn't exist
    [ ! -f .env ] && touch .env
    
    echo ""
    echo "🔐 Generating runner registration tokens..."
    
    # Generate tokens
    echo "   Generating token for tenfive-runner..."
    TENFIVE_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
    
    echo "   Generating token for tenseven-runner..."
    TENSEVEN_TOKEN=$(gh api repos/trodemaster/blakeports/actions/runners/registration-token --method POST --jq '.token')
    
    # Write tokens and IPs to .env (create fresh file)
    cat > .env << EOF
# GitHub Actions Runner Registration Tokens
# Generated: $(date)
# Tokens expire after 1 hour. Regenerate as needed.

RUNNER_TOKEN_TENFIVE=$TENFIVE_TOKEN
RUNNER_TOKEN_TENSEVEN=$TENSEVEN_TOKEN

# Legacy VM IP Addresses (resolved on macOS host for container connectivity)
TENFIVE_VM_IP=$TENFIVE_IP
TENSEVEN_VM_IP=$TENSEVEN_IP
EOF
    
    echo ""
    echo "✅ .env created with tokens and VM IP addresses"
fi

echo ""
echo "🚀 Ready to start containers!"
echo ""
echo "Next steps:"
echo "1. Verify SSH connectivity to your VMs:"
echo "   ssh admin@tenfive-runner.local \"uname -a\""
echo "   ssh admin@tenseven-runner.local \"uname -a\""
echo ""
echo "2. Build and start containers:"
echo "   docker compose build"
echo "   docker compose up -d"
echo ""
echo "3. Check status:"
echo "   docker compose ps"
echo "   docker compose logs -f"
echo ""
