#!/bin/bash
# Quick start script for multi-runner setup

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "=================================================="
echo "  BlakePorts Multi-Runner Quick Start"
echo "=================================================="
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
echo "Checking dependencies..."
if ! command_exists docker; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

if ! command_exists docker-compose; then
    echo "❌ docker-compose not found. Please install docker-compose first."
    exit 1
fi

echo "✅ Dependencies OK"
echo ""

# Check for .env file
if [ ! -f .env ]; then
    echo "⚠️  Environment file not found."
    echo ""
    echo "Running setup to generate registration tokens..."
    echo ""
    ./setup-multi-runners.sh
    
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Setup failed. Please resolve the issues above."
        exit 1
    fi
    echo ""
fi

echo "✅ Environment file ready"
echo ""

# Build and start runners
echo "Building Docker images (this may take a few minutes)..."
docker-compose -f docker-compose-multi.yml build

echo ""
echo "Starting runners..."
docker-compose -f docker-compose-multi.yml up -d

echo ""
echo "Waiting for runners to initialize..."
sleep 5

echo ""
echo "=================================================="
echo "  Runner Status"
echo "=================================================="
docker-compose -f docker-compose-multi.yml ps

echo ""
echo "=================================================="
echo "  Next Steps"
echo "=================================================="
echo ""
echo "1. Check runner logs:"
echo "   docker-compose -f docker-compose-multi.yml logs -f"
echo ""
echo "2. Verify runners in GitHub:"
echo "   https://github.com/trodemaster/blakeports/settings/actions/runners"
echo ""
echo "   You should see:"
echo "   - docker-runner-tenfive (labels: tenfive, macos-10-5)"
echo "   - docker-runner-tenseven (labels: tenseven, macos-10-7)"
echo ""
echo "3. Test with a workflow:"
echo "   gh workflow run build-legacy-bstring.yml -f os_selection=all"
echo ""
echo "4. Monitor builds:"
echo "   https://github.com/trodemaster/blakeports/actions"
echo ""
echo "=================================================="
echo "  Management Commands"
echo "=================================================="
echo ""
echo "Stop all runners:"
echo "  docker-compose -f docker-compose-multi.yml down"
echo ""
echo "Restart a specific runner:"
echo "  docker-compose -f docker-compose-multi.yml restart tenfive-runner"
echo "  docker-compose -f docker-compose-multi.yml restart tenseven-runner"
echo ""
echo "View resource usage:"
echo "  docker stats github-runner-tenfive github-runner-tenseven"
echo ""
echo "✅ Setup complete!"
echo ""

