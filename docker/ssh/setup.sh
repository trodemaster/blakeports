#!/bin/bash
# SSH Proxy Setup Script
# Quick setup for the SSH legacy proxy container

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔧 SSH Legacy Proxy Setup"
echo "=========================="
echo ""

# Check Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed"
    echo "Please install Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Error: Docker daemon is not running"
    echo "Please start Docker Desktop"
    exit 1
fi

echo "✅ Docker is installed and running"
echo ""

# Create keys directory if it doesn't exist
if [ ! -d "keys" ]; then
    echo "📁 Creating keys directory..."
    mkdir -p keys
    chmod 700 keys
    echo "✅ Created keys/ directory"
else
    echo "✅ keys/ directory exists"
fi

# Check for authorized_keys
if [ ! -f "keys/authorized_keys" ]; then
    echo ""
    echo "⚠️  No authorized_keys found"
    echo ""
    echo "To authenticate to the proxy, you need to:"
    echo "1. Generate a key: ssh-keygen -t ed25519 -f ~/.ssh/ssh-proxy"
    echo "2. Add it here: cat ~/.ssh/ssh-proxy.pub > keys/authorized_keys"
    echo ""
    read -p "Would you like to do this now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ ! -f "$HOME/.ssh/ssh-proxy" ]; then
            echo "Generating SSH key..."
            ssh-keygen -t ed25519 -f "$HOME/.ssh/ssh-proxy" -C "ssh-proxy-$(whoami)"
        fi
        echo "Adding public key to authorized_keys..."
        cat "$HOME/.ssh/ssh-proxy.pub" > keys/authorized_keys
        chmod 644 keys/authorized_keys
        echo "✅ Key added to authorized_keys"
    fi
fi

# Build container
echo ""
echo "🏗️  Building SSH proxy container..."
docker compose build

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "==========="
echo ""
echo "1. Add legacy SSH keys to the keys/ directory:"
echo "   cp ~/.ssh/oldmac keys/"
echo "   chmod 600 keys/*"
echo ""
echo "2. Start the proxy:"
echo "   docker compose up -d"
echo ""
echo "3. Add to your ~/.ssh/config:"
echo ""
cat << 'EOF'
   Host ssh-proxy
     Hostname localhost
     Port 2222
     User sshproxy
     IdentityFile ~/.ssh/ssh-proxy
   
   Host tenseven
     Hostname tenseven.local
     User blake
     ProxyJump ssh-proxy
     IdentityFile ~/.ssh/oldmac
EOF
echo ""
echo "4. Connect:"
echo "   ssh tenseven"
echo ""

