#!/bin/bash
# Verify SSH key and start Docker runners
# Run this in your terminal from the docker directory

set -e

echo "🔍 Verifying Docker Runner Setup"
echo "=================================================="
echo ""

cd "$(dirname "$0")" || exit 1

# Step 1: Verify SSH key exists
echo "🔑 Step 1: SSH Key Verification"
SSH_KEY_PATH="/Users/blake/Developer/blakeports/docker/ssh_keys/oldmac"

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ ERROR: SSH key file not found!"
    echo "   Path: $SSH_KEY_PATH"
    echo ""
    echo "   To create it:"
    echo "   1. Get the OLDMAC_KEY from GitHub secrets"
    echo "   2. Run:"
    echo "      echo \"\$OLDMAC_KEY\" > $SSH_KEY_PATH"
    echo "      chmod 600 $SSH_KEY_PATH"
    exit 1
fi

if [ ! -r "$SSH_KEY_PATH" ]; then
    echo "❌ ERROR: SSH key is not readable!"
    echo "   Run: chmod 600 $SSH_KEY_PATH"
    exit 1
fi

echo "✅ SSH key found and readable:"
ls -lh "$SSH_KEY_PATH"
echo ""

# Step 2: Check .env file
echo "📄 Step 2: Environment File Verification"
if [ ! -f ".env" ]; then
    echo "❌ ERROR: .env file not found!"
    echo "   Run: bash setup-runners.sh"
    exit 1
fi

if ! grep -q "RUNNER_TOKEN_TENFIVE=" .env; then
    echo "❌ ERROR: Missing RUNNER_TOKEN_TENFIVE in .env"
    echo "   Run: bash setup-runners.sh"
    exit 1
fi

if ! grep -q "RUNNER_TOKEN_TENSEVEN=" .env; then
    echo "❌ ERROR: Missing RUNNER_TOKEN_TENSEVEN in .env"
    echo "   Run: bash setup-runners.sh"
    exit 1
fi

echo "✅ .env file has required tokens"
echo ""

# Step 3: Verify Lima can access the paths
echo "🖥️  Step 3: Lima VM Verification"
if ! command -v lima &> /dev/null; then
    echo "⚠️  WARNING: Lima not found, assuming Docker Desktop"
else
    LIMA_CHECK=$(lima test -f "$SSH_KEY_PATH" 2>/dev/null && echo "✅" || echo "❌")
    echo "Lima can access SSH key: $LIMA_CHECK"
fi
echo ""

# Step 4: Show docker-compose volumes
echo "📋 Step 4: Docker Compose Configuration"
echo "   tenfive-runner volume:"
grep -A1 "tenfive-runner:" docker-compose.yml | grep "ssh_keys"
echo ""

# Step 5: Ready to go
echo "=================================================="
echo "✅ All checks passed!"
echo ""
echo "Ready to start containers:"
echo ""
echo "  docker compose build      # Build images"
echo "  docker compose up -d      # Start containers"
echo "  docker compose ps         # Check status"
echo "  docker compose logs -f    # View logs"
echo ""
