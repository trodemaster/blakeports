#!/usr/bin/env bash

# Build Tart Base Images Script
# Builds base tart images using packer based on cirrus.base.yml workflow
# Usage: scripts/build_tart_base.sh [15|26]
#   15 = sequoia
#   26 = tahoe

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [VERSION]

Build Tart Base Images
Builds base tart images using packer based on cirrus.base.yml workflow.

Arguments:
    VERSION     macOS version number (required)
                15  = sequoia
                26  = tahoe

Examples:
    $0 15       # Build sequoia base image
    $0 26       # Build tahoe base image

Environment Variables:
    MACOS_IMAGE_TEMPLATES_DIR    Path to macos-image-templates directory
                                  (default: ../macos-image-templates relative to script)

EOF
}

# Function to check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    if ! command -v tart &> /dev/null; then
        missing_deps+=("tart")
    fi
    
    if ! command -v packer &> /dev/null; then
        missing_deps+=("packer")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                "tart")
                    echo "  - Tart: https://tart.run/"
                    ;;
                "packer")
                    echo "  - Packer: https://www.packer.io/"
                    ;;
            esac
        done
        exit 1
    fi
}

# Function to map version number to macOS version name
map_version_to_macos_name() {
    local version=$1
    case "$version" in
        15)
            echo "sequoia"
            ;;
        26)
            echo "tahoe"
            ;;
        *)
            print_error "Unsupported version: $version"
            print_info "Supported versions: 15 (sequoia), 26 (tahoe)"
            exit 1
            ;;
    esac
}

# Function to get disable SIP template for version
get_disable_sip_template() {
    local macos_version=$1
    case "$macos_version" in
        "sequoia"|"tahoe")
            echo "disable-sip-with-username.pkr.hcl"
            ;;
        *)
            print_error "Unknown macOS version: $macos_version"
            exit 1
            ;;
    esac
}

# Function to find macos-image-templates directory
find_macos_image_templates_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check environment variable first
    if [ -n "${MACOS_IMAGE_TEMPLATES_DIR:-}" ]; then
        if [ -d "$MACOS_IMAGE_TEMPLATES_DIR" ]; then
            echo "$MACOS_IMAGE_TEMPLATES_DIR"
            return 0
        else
            print_error "MACOS_IMAGE_TEMPLATES_DIR is set but directory does not exist: $MACOS_IMAGE_TEMPLATES_DIR"
            exit 1
        fi
    fi
    
    # Try relative path from script location (assuming blakeports/scripts)
    local relative_path="$(dirname "$script_dir")/../macos-image-templates"
    if [ -d "$relative_path" ]; then
        echo "$(cd "$relative_path" && pwd)"
        return 0
    fi
    
    # Try absolute path
    if [ -d "/Users/blake/Developer/macos-image-templates" ]; then
        echo "/Users/blake/Developer/macos-image-templates"
        return 0
    fi
    
    print_error "Could not find macos-image-templates directory"
    print_info "Please set MACOS_IMAGE_TEMPLATES_DIR environment variable"
    print_info "Or ensure the directory exists at one of these locations:"
    print_info "  - $(dirname "$script_dir")/../macos-image-templates"
    print_info "  - /Users/blake/Developer/macos-image-templates"
    exit 1
}

# Main build function
build_base_image() {
    local version=$1
    local macos_version
    local disable_sip_template
    local templates_dir
    
    # Map version to macOS name
    macos_version=$(map_version_to_macos_name "$version")
    print_info "Building base image for macOS $macos_version (version $version)"
    
    # Get disable SIP template
    disable_sip_template=$(get_disable_sip_template "$macos_version")
    print_info "Using disable SIP template: $disable_sip_template"
    
    # Find templates directory
    templates_dir=$(find_macos_image_templates_dir)
    print_info "Using templates directory: $templates_dir"
    
    # Change to templates directory
    cd "$templates_dir" || {
        print_error "Failed to change to templates directory: $templates_dir"
        exit 1
    }
    
    # Step 1: Pull vanilla image
    print_info "Step 1: Pulling vanilla image..."
    if ! tart pull "ghcr.io/cirruslabs/macos-$macos_version-vanilla:latest"; then
        print_error "Failed to pull vanilla image"
        exit 1
    fi
    print_success "Vanilla image pulled successfully"
    
    # Step 2: Initialize packer
    print_info "Step 2: Initializing packer..."
    if ! packer init templates/base.pkr.hcl; then
        print_error "Failed to initialize packer"
        exit 1
    fi
    print_success "Packer initialized successfully"
    
    # Step 3: Build base image
    print_info "Step 3: Building base image..."
    if ! packer build -var "macos_version=$macos_version" templates/base.pkr.hcl; then
        print_error "Failed to build base image"
        exit 1
    fi
    print_success "Base image built successfully"
    
    # Step 4: Disable SIP
    print_info "Step 4: Disabling SIP..."
    if ! packer build -var "vm_name=$macos_version-base" "templates/$disable_sip_template"; then
        print_error "Failed to disable SIP"
        exit 1
    fi
    print_success "SIP disabled successfully"
    
    # Step 5: Push base image
    print_info "Step 5: Pushing base image..."
    if ! tart push "$macos_version-base" "ghcr.io/cirruslabs/macos-$macos_version-base:latest"; then
        print_error "Failed to push base image"
        exit 1
    fi
    print_success "Base image pushed successfully"
    
    # Step 6: Cleanup (delete local VM)
    print_info "Step 6: Cleaning up local VM..."
    if ! tart delete "$macos_version-base"; then
        print_warning "Failed to delete local VM (may not exist)"
    else
        print_success "Local VM deleted successfully"
    fi
    
    print_success "Base image build completed successfully for macOS $macos_version"
}

# Main script logic
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    
    # Check for version argument
    if [ $# -lt 1 ]; then
        print_error "Version argument is required"
        usage
        exit 1
    fi
    
    local version=$1
    
    # Validate version
    if [[ ! "$version" =~ ^(15|26)$ ]]; then
        print_error "Invalid version: $version"
        print_info "Supported versions: 15 (sequoia), 26 (tahoe)"
        usage
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Build the base image
    build_base_image "$version"
}

# Run main function with all arguments
main "$@"

