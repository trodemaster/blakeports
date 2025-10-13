#!/bin/bash
# Setup script for multi-runner environment
# This creates the .env files needed for each runner

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "  Multi-Runner Setup for BlakePorts"
echo "=================================================="
echo ""

# Check if GitHub token is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <github_token>"
    echo ""
    echo "Generate a token at: https://github.com/settings/tokens"
    echo "Required scopes: repo (full control)"
    echo ""
    echo "Example:"
    echo "  $0 ghp_YOUR_TOKEN_HERE"
    exit 1
fi

GITHUB_TOKEN="$1"

# Create .env.tenfive
echo "Creating .env.tenfive..."
cat > .env.tenfive << EOF
# GitHub Actions Runner Configuration - TenFive (Mac OS X 10.5)
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
GITHUB_TOKEN=${GITHUB_TOKEN}
RUNNER_NAME=docker-runner-tenfive
RUNNER_WORKDIR=_work
CUSTOM_LABELS=tenfive,macos-10-5,legacy-macos
EOF

# Create .env.tenseven
echo "Creating .env.tenseven..."
cat > .env.tenseven << EOF
# GitHub Actions Runner Configuration - TenSeven (Mac OS X 10.7)
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports
GITHUB_TOKEN=${GITHUB_TOKEN}
RUNNER_NAME=docker-runner-tenseven
RUNNER_WORKDIR=_work
CUSTOM_LABELS=tenseven,macos-10-7,legacy-macos
EOF

echo ""
echo "✅ Environment files created successfully!"
echo ""
echo "Files created:"
echo "  - .env.tenfive"
echo "  - .env.tenseven"
echo ""
echo "Next steps:"
echo "  1. Review the files if needed"
echo "  2. Start runners: docker-compose -f docker-compose-multi.yml up -d"
echo "  3. Check status: docker-compose -f docker-compose-multi.yml ps"
echo "  4. View logs: docker-compose -f docker-compose-multi.yml logs -f"
echo ""

