#!/bin/bash

# GitHub Actions Runner Container Build Script
# This script builds or rebuilds the Docker container image with all prerequisites
# and the latest GitHub Actions runner software.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
IMAGE_NAME="github-runner"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
NO_CACHE="false"
FORCE_REBUILD="false"
SHOW_HELP="false"

# Detect host platform and runner architecture
HOST_ARCH=$(uname -m)
case $HOST_ARCH in
    x86_64)
        PLATFORM="linux/amd64"
        RUNNER_ARCH="x64"
        ;;
    arm64|aarch64)
        PLATFORM="linux/arm64"
        RUNNER_ARCH="arm64"
        ;;
    *)
        echo -e "${YELLOW}Warning: Unsupported architecture $HOST_ARCH. Only x86_64 and arm64/aarch64 are supported.${NC}"
        echo -e "${YELLOW}Defaulting to linux/amd64 with x64 runner${NC}"
        PLATFORM="linux/amd64"
        RUNNER_ARCH="x64"
        ;;
esac

# Function to show help
show_help() {
    echo "GitHub Actions Runner Container Build Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --image-name NAME     Docker image name (default: github-runner)"
    echo "  --tag TAG            Docker image tag (default: latest)"
    echo "  --no-cache           Build without using Docker cache"
    echo "  --force              Force rebuild even if image exists"
    echo "  --platform PLATFORM  Target platform (default: detected from host - $PLATFORM)"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build with default settings"
    echo "  $0 --no-cache                        # Build without cache"
    echo "  $0 --force                           # Force rebuild"
    echo "  $0 --tag v1.0.0                     # Build with custom tag"
    echo "  $0 --platform linux/amd64            # Build for specific platform"
    echo ""
    echo "Current settings:"
    echo "  Image: $FULL_IMAGE_NAME"
    echo "  Platform: $PLATFORM (detected from host)"
    echo "  Architecture: $HOST_ARCH"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --image-name)
            IMAGE_NAME="$2"
            FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="true"
            shift
            ;;
        --force)
            FORCE_REBUILD="true"
            shift
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --help)
            SHOW_HELP="true"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help if requested
if [ "$SHOW_HELP" = "true" ]; then
    show_help
    exit 0
fi

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running or not accessible${NC}"
    exit 1
fi

# Check if image already exists
if docker image inspect "$FULL_IMAGE_NAME" >/dev/null 2>&1; then
    if [ "$FORCE_REBUILD" = "false" ]; then
        echo -e "${YELLOW}Image $FULL_IMAGE_NAME already exists.${NC}"
        echo "Use --force to rebuild or --help for more options."
        exit 0
    else
        echo -e "${YELLOW}Force rebuild requested. Removing existing image...${NC}"
        docker rmi "$FULL_IMAGE_NAME" || true
    fi
fi

# Build command with platform and architecture build argument
BUILD_CMD="docker build --platform $PLATFORM --build-arg RUNNER_ARCH=$RUNNER_ARCH -t $FULL_IMAGE_NAME ."

# Add no-cache flag if requested
if [ "$NO_CACHE" = "true" ]; then
    BUILD_CMD="$BUILD_CMD --no-cache"
fi

# Display build information
echo -e "${BLUE}Building GitHub Actions Runner Container${NC}"

echo "=============================================="
echo -e "Image Name: ${GREEN}$FULL_IMAGE_NAME${NC}"
echo -e "Platform: ${GREEN}$PLATFORM${NC}"
echo -e "Architecture: ${GREEN}$HOST_ARCH${NC}"
echo -e "Runner Arch: ${GREEN}$RUNNER_ARCH${NC}"
echo -e "No Cache: ${GREEN}$NO_CACHE${NC}"
echo -e "Force Rebuild: ${GREEN}$FORCE_REBUILD${NC}"
echo ""

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in current directory${NC}"
    exit 1
fi

# Check if runner-setup.sh exists
if [ ! -f "runner-setup.sh" ]; then
    echo -e "${RED}Error: runner-setup.sh not found in current directory${NC}"
    exit 1
fi

echo -e "${BLUE}Starting build process...${NC}"
echo "Command: $BUILD_CMD"
echo ""

# Execute the build
if eval $BUILD_CMD; then
    echo ""
    echo -e "${GREEN}✅ Build completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}Image Details:${NC}"
    docker images "$FULL_IMAGE_NAME" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Run './build-and-deploy.sh' to generate Docker Compose configuration"
    echo "2. Run 'docker-compose up -d' to start the runners"
    echo ""
    echo -e "${BLUE}To run the container with bash shell:${NC}"
    echo "  docker run --rm -it $FULL_IMAGE_NAME /bin/bash"
    echo ""
    echo -e "${BLUE}To see what's installed:${NC}"
    echo "  docker run --rm $FULL_IMAGE_NAME ls -la /tmp/runner/"
    echo ""
    echo -e "${BLUE}To run with environment variables (for testing):${NC}"
    echo "  docker run --rm -it -e GITHUB_TOKEN=your_token -e GITHUB_OWNER=your_owner -e GITHUB_REPOSITORY=your_repo -e RUNNER_WORKDIR=/tmp/runner -e RUNNER_LABELS=test,self-hosted $FULL_IMAGE_NAME /bin/bash"
else
    echo ""
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi
