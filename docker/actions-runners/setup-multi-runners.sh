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

# Repository details
GITHUB_OWNER="trodemaster"
GITHUB_REPO="blakeports"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) not found."
    echo ""
    echo "Please install gh CLI:"
    echo "  macOS:  brew install gh"
    echo "  Linux:  See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo ""
    exit 1
fi

# Check if user is authenticated with gh
if ! gh auth status &> /dev/null; then
    echo "❌ Error: Not authenticated with GitHub CLI."
    echo ""
    echo "Please authenticate first:"
    echo "  gh auth login"
    echo ""
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# Generate registration token using gh CLI
echo "Generating runner registration token..."
GITHUB_TOKEN=$(gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token \
    --jq .token)

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: Failed to generate registration token."
    echo ""
    echo "Make sure you have admin access to the repository:"
    echo "  https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
    exit 1
fi

echo "✅ Registration token generated successfully"
echo ""

# Create single .env file with all runner configurations
echo "Creating .env file with all runner configurations..."
cat > .env << EOF
# GitHub Actions Multi-Runner Configuration
# ==========================================

# Repository Configuration
GITHUB_OWNER=trodemaster
GITHUB_REPO=blakeports

# Runner Registration Token (expires in 1 hour)
GITHUB_TOKEN=${GITHUB_TOKEN}

# Common Configuration
RUNNER_WORKDIR=_work

# TenFive Runner (Mac OS X 10.5)
TENFIVE_RUNNER_NAME=docker-runner-tenfive
TENFIVE_LABELS=tenfive,macos-10-5,legacy-macos

# TenSeven Runner (Mac OS X 10.7)
TENSEVEN_RUNNER_NAME=docker-runner-tenseven
TENSEVEN_LABELS=tenseven,macos-10-7,legacy-macos

# Add more runners here as needed:
# SNOWLEOPARD_RUNNER_NAME=docker-runner-snowleopard
# SNOWLEOPARD_LABELS=snowleopard,macos-10-6,legacy-macos
EOF

echo ""
echo "✅ Environment file created successfully!"
echo ""
echo "File created:"
echo "  - .env"
echo ""
echo "📝 Note: Registration tokens are valid for 1 hour."
echo "   If runners fail to register, run this script again to get a fresh token."
echo ""
echo "Next steps:"
echo "  1. Review the files if needed"
echo "  2. Start runners: docker compose -f docker-compose-multi.yml up -d"
echo "  3. Check status: docker compose -f docker-compose-multi.yml ps"
echo "  4. View logs: docker compose -f docker-compose-multi.yml logs -f"
echo ""
echo "Or use the quickstart script:"
echo "  ./quickstart-multi.sh"
echo ""

