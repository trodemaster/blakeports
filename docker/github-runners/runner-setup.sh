#!/bin/bash

set -e

echo "Configuring GitHub Actions runner..."

# Ensure we're in the runner directory (already set as WORKDIR in Dockerfile)
cd ${RUNNER_WORKDIR}

# Generate unique runner name for scaling
# Use the last 8 characters of the container hostname for uniqueness
CONTAINER_SUFFIX=$(hostname | tail -c 9)
RUNNER_NAME_UNIQUE="runner-docker-ubuntu-noble-${CONTAINER_SUFFIX}"

# Check if runner is already configured  
if [ -f ".runner" ]; then
    echo "Runner already configured. Cleaning up local configuration files..."
    # Remove local configuration files to force clean registration
    # This avoids the need to call GitHub API for runner deletion
    rm -f .runner .credentials .credentials_rsaparams
    echo "Local runner configuration files removed. Will register as new runner."
fi

# Get registration token from GitHub API
echo "Getting registration token from GitHub..."
REGISTRATION_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners/registration-token" \
    | jq -r '.token')

if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "null" ]; then
    echo "Error: Failed to get registration token from GitHub API"
    echo "Check your GITHUB_TOKEN permissions and GITHUB_REPOSITORY setting"
    exit 1
fi

# Configure the runner
echo "Configuring runner with:"
echo "  Repository: ${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
echo "  Runner Name: ${RUNNER_NAME_UNIQUE}"
echo "  Work Directory: ${RUNNER_WORKDIR}"
echo "  Labels: ${RUNNER_LABELS}"

# Run as non-root user to avoid "Must not run with sudo" error
if [ "$(id -u)" = "0" ]; then
    # Create a non-root user if it doesn't exist
    if ! id runner >/dev/null 2>&1; then
        useradd -m -s /bin/bash runner
    fi
    chown -R runner:runner ${RUNNER_WORKDIR}
    # Configure and start runner as non-root user, but keep this process running to handle signals
    su runner -c "cd ${RUNNER_WORKDIR} && ./config.sh --url https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY} --token ${REGISTRATION_TOKEN} --name ${RUNNER_NAME_UNIQUE} --work ${RUNNER_WORKDIR} --labels ${RUNNER_LABELS} --unattended --replace"
    
    echo "Starting GitHub Actions runner..."
    exec su runner -c "cd ${RUNNER_WORKDIR} && ./run.sh"
else
    ./config.sh \
        --url https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY} \
        --token ${REGISTRATION_TOKEN} \
        --name ${RUNNER_NAME_UNIQUE} \
        --work ${RUNNER_WORKDIR} \
        --labels ${RUNNER_LABELS} \
        --unattended \
        --replace

    echo "Starting GitHub Actions runner..."
    ./run.sh
fi