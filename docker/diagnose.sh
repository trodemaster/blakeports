#!/bin/bash
# Diagnose Docker path and SSH key issues

set -e

cd "$(dirname "$0")" || exit 1

echo "🔍 Docker Path Diagnostics"
echo "=================================================="
echo ""

# Show current working directory
echo "📍 Current Working Directory:"
echo "   PWD: $PWD"
echo ""

# Check SSH key location
echo "🔑 SSH Key Status:"
if [ -f ./ssh_keys/oldmac ]; then
    echo "   ✅ File exists: ./ssh_keys/oldmac"
    ls -lh ./ssh_keys/oldmac
    file ./ssh_keys/oldmac
else
    echo "   ❌ File NOT found: ./ssh_keys/oldmac"
    echo ""
    echo "   To create SSH key:"
    echo "   1. Get OLDMAC_KEY from GitHub repository secrets"
    echo "   2. Run: echo \"\$OLDMAC_KEY\" > ./ssh_keys/oldmac"
    echo "   3. Run: chmod 600 ./ssh_keys/oldmac"
fi
echo ""

# Check docker-compose path resolution
echo "🐳 Docker Compose Volume Paths:"
echo "   Host path: ${PWD}/ssh_keys/oldmac"
echo "   Container path: /home/runner/.ssh/oldmac"
echo ""

# Test if Docker can access the paths
echo "🧪 Docker Environment:"
if command -v docker &> /dev/null; then
    echo "   ✅ Docker installed"
    docker --version
else
    echo "   ❌ Docker not found"
fi
echo ""

# Show Lima/VM context if available
if command -v lima &> /dev/null; then
    echo "🖥️  Lima VM Status:"
    LIMA_HOME=${LIMA_HOME:-$HOME/.lima}
    if [ -S "$LIMA_HOME/default/sock/docker.sock" ]; then
        echo "   ✅ Lima default VM is running"
        echo "   Docker socket: $LIMA_HOME/default/sock/docker.sock"
    else
        echo "   ❌ Lima default VM is not running"
        echo "   To start: limactl start default"
    fi
else
    echo "🖥️  Lima not found (Docker Desktop may be running instead)"
fi
echo ""

# Check .env file
echo "📄 Environment File (.env):"
if [ -f .env ]; then
    echo "   ✅ File exists: .env"
    if grep -q "RUNNER_TOKEN_TENFIVE" .env; then
        echo "   ✅ Contains RUNNER_TOKEN_TENFIVE"
    else
        echo "   ❌ Missing RUNNER_TOKEN_TENFIVE"
    fi
else
    echo "   ❌ File NOT found: .env"
    echo "   Run: bash setup-runners.sh"
fi
echo ""

echo "=================================================="
echo "✅ Diagnostics complete"
