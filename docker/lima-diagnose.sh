#!/bin/bash
# Diagnose and fix Lima Docker path issues
# Run this directly in your terminal (not in Cursor)

set -e

echo "🔍 Lima Docker Path Diagnostics"
echo "=================================================="
echo ""

# Current directory on macOS
echo "📍 macOS Working Directory:"
echo "   $(pwd)"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ ERROR: Not in docker directory!"
    echo "   Run: cd /Users/blake/Developer/blakeports/docker"
    exit 1
fi

echo "✅ In correct directory"
echo ""

# Check SSH key
echo "🔑 SSH Key File:"
if [ -f "./ssh_keys/oldmac" ]; then
    echo "   ✅ Found: ./ssh_keys/oldmac"
    ls -lh ./ssh_keys/oldmac
else
    echo "   ❌ NOT FOUND: ./ssh_keys/oldmac"
    echo ""
    echo "   To create it:"
    echo "   gh secret view OLDMAC_KEY > ./ssh_keys/oldmac"
    echo "   chmod 600 ./ssh_keys/oldmac"
    exit 1
fi
echo ""

# Get actual macOS path
MACOS_PATH="$(pwd)/ssh_keys/oldmac"
echo "📋 Full macOS Path:"
echo "   $MACOS_PATH"
echo ""

# Check what Lima sees
echo "🖥️  Lima VM View:"
LIMA_RESULT=$(lima test -f "/Users/blake/Developer/blakeports/docker/ssh_keys/oldmac" && echo "✅ Found" || echo "❌ Not found")
echo "   Path in Lima: /Users/blake/Developer/blakeports/docker/ssh_keys/oldmac"
echo "   Status: $LIMA_RESULT"
echo ""

# Check Lima mount
echo "🔗 Lima Mount Points:"
lima ls -la /Users/blake/Developer/blakeports/docker/ssh_keys/ | head -10
echo ""

# Get Lima working directory
echo "📍 Lima Working Directory:"
LIMA_PWD=$(lima pwd)
echo "   $LIMA_PWD"
echo ""

# Show docker-compose volume resolution
echo "🐳 Docker Compose Volumes:"
echo "   From docker-compose.yml:"
echo "   - \${PWD}/ssh_keys/oldmac:/home/runner/.ssh/oldmac:ro"
echo ""
echo "   Will resolve to:"
echo "   - $MACOS_PATH:/home/runner/.ssh/oldmac:ro"
echo ""

# Test docker-compose parsing
echo "🧪 Docker Compose Configuration:"
PWD="$MACOS_PATH" docker compose config --format json 2>/dev/null | jq '.services.tenfive_runner.volumes' 2>/dev/null || {
    echo "   (Manual check needed)"
}
echo ""

echo "=================================================="
echo "✅ Diagnostics complete"
echo ""
echo "Next step:"
echo "  docker compose up -d"
