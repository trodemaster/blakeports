#!/bin/bash
# Generate GitHub Actions runner registration token
# Uses gh CLI which must be authenticated

set -e

# Load .env file if it exists
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
fi

# Validate required variables
if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
    echo "Error: GITHUB_OWNER and GITHUB_REPO must be set in .env file"
    exit 1
fi

echo "Generating registration token for $GITHUB_OWNER/$GITHUB_REPO..."

# Generate token using gh CLI
TOKEN=$(gh api repos/$GITHUB_OWNER/$GITHUB_REPO/actions/runners/registration-token --method POST --jq '.token')

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to generate token"
    echo "Make sure gh CLI is authenticated: gh auth login"
    exit 1
fi

echo "Token generated successfully!"
echo ""
echo "Update your .env file with:"
echo "RUNNER_TOKEN=$TOKEN"
echo ""
echo "Or run:"
echo "sed -i '' 's/^RUNNER_TOKEN=.*/RUNNER_TOKEN=$TOKEN/' .env"

