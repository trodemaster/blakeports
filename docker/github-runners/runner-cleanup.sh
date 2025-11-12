#!/bin/bash

set -e

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading environment variables from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Check required environment variables
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable is not set"
    echo "Please set it in your .env file or export it directly"
    exit 1
fi

if [ -z "$GITHUB_OWNER" ]; then
    echo "Error: GITHUB_OWNER environment variable is not set"
    echo "Please set it in your .env file or export it directly"
    exit 1
fi

if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "Error: GITHUB_REPOSITORY environment variable is not set"
    echo "Please set it in your .env file or export it directly"
    exit 1
fi

echo "GitHub Actions Runner Cleanup Tool"
echo "=================================="
echo "Repository: ${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
echo ""

# Set GitHub token for gh CLI
export GH_TOKEN="$GITHUB_TOKEN"

# Function to list all runners
list_runners() {
    echo "Fetching current runners..."
    gh api "/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners" \
        --jq '.runners[] | "\(.id)\t\(.name)\t\(.status)\t\(.os)"' \
        | column -t -s $'\t' -N "ID,Name,Status,OS"
}

# Function to remove a specific runner by ID
remove_runner() {
    local runner_id="$1"
    local runner_name="$2"
    
    echo "Removing runner: $runner_name (ID: $runner_id)"
    
    # Get removal token
    REMOVAL_TOKEN=$(gh api "/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners/remove-token" \
        --jq '.token')
    
    if [ -z "$REMOVAL_TOKEN" ] || [ "$REMOVAL_TOKEN" = "null" ]; then
        echo "Error: Failed to get removal token for runner $runner_id"
        return 1
    fi
    
    # Remove the runner
    if gh api -X DELETE "/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners/$runner_id" >/dev/null 2>&1; then
        echo "✅ Successfully removed runner: $runner_name"
        return 0
    else
        echo "❌ Failed to remove runner: $runner_name"
        return 1
    fi
}

# Function to remove all offline runners
remove_offline_runners() {
    echo "Removing all offline runners..."
    
    local offline_runners
    offline_runners=$(gh api "/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners" \
        --jq '.runners[] | select(.status == "offline") | "\(.id) \(.name)"')
    
    if [ -z "$offline_runners" ]; then
        echo "No offline runners found."
        return 0
    fi
    
    local removed_count=0
    local failed_count=0
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local runner_id=$(echo "$line" | cut -d' ' -f1)
            local runner_name=$(echo "$line" | cut -d' ' -f2-)
            
            if remove_runner "$runner_id" "$runner_name"; then
                ((removed_count++))
            else
                ((failed_count++))
            fi
        fi
    done <<< "$offline_runners"
    
    echo ""
    echo "Cleanup Summary:"
    echo "  ✅ Removed: $removed_count runners"
    echo "  ❌ Failed: $failed_count runners"
}

# Function to remove all runners
remove_all_runners() {
    echo "⚠️  WARNING: This will remove ALL runners from the repository!"
    echo "Repository: ${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Operation cancelled."
        return 0
    fi
    
    local all_runners
    all_runners=$(gh api "/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners" \
        --jq '.runners[] | "\(.id) \(.name)"')
    
    if [ -z "$all_runners" ]; then
        echo "No runners found."
        return 0
    fi
    
    local removed_count=0
    local failed_count=0
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local runner_id=$(echo "$line" | cut -d' ' -f1)
            local runner_name=$(echo "$line" | cut -d' ' -f2-)
            
            if remove_runner "$runner_id" "$runner_name"; then
                ((removed_count++))
            else
                ((failed_count++))
            fi
        fi
    done <<< "$all_runners"
    
    echo ""
    echo "Cleanup Summary:"
    echo "  ✅ Removed: $removed_count runners"
    echo "  ❌ Failed: $failed_count runners"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  list              List all runners in the repository"
    echo "  remove-offline    Remove all offline runners"
    echo "  remove-all        Remove ALL runners (with confirmation)"
    echo "  help              Show this help message"
    echo ""
    echo "Environment Variables (can be set in .env file):"
    echo "  GITHUB_TOKEN      GitHub Personal Access Token"
    echo "  GITHUB_OWNER      GitHub username or organization"
    echo "  GITHUB_REPOSITORY Repository name"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 remove-offline"
    echo "  $0 remove-all"
}

# Main script logic
case "${1:-list}" in
    "list")
        list_runners
        ;;
    "remove-offline")
        remove_offline_runners
        ;;
    "remove-all")
        remove_all_runners
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac
