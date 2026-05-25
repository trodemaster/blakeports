#!/bin/bash
# Bump a go-portgroup port to the latest upstream commit on a given branch.
#
# Usage: bump-go-port.sh <portdir> <github-org/repo> [branch]
#
# Updates go.setup with the latest SHA, sets a date-based version label,
# and recomputes checksums. Reports which feature branches need rebasing.
#
# Examples:
#   bump-go-port.sh sysutils/lima-devl lima-vm/lima
#   bump-go-port.sh sysutils/lima-devl lima-vm/lima master
#
# Requires: git, curl, jq, port (MacPorts)

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <portdir> <github-org/repo> [branch]"
    echo "Example: $0 sysutils/lima-devl lima-vm/lima"
    exit 1
fi

PORTDIR="$1"
REPO="$2"
BRANCH="${3:-master}"
PORTFILE="$PORTDIR/Portfile"

if [[ ! -f "$PORTFILE" ]]; then
    echo "Error: Portfile not found at $PORTFILE"
    exit 1
fi

# ── Fetch latest commit SHA from GitHub API ────────────────────────────────────

echo "Fetching latest commit on $REPO@$BRANCH..."
API_URL="https://api.github.com/repos/$REPO/commits/$BRANCH"
RESPONSE=$(curl -sSf "$API_URL")
NEW_SHA=$(echo "$RESPONSE" | jq -r '.sha')
COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.commit.committer.date' | cut -c1-10 | tr -d '-')

if [[ -z "$NEW_SHA" || "$NEW_SHA" == "null" ]]; then
    echo "Error: could not fetch SHA from $API_URL"
    exit 1
fi

echo "  SHA:  $NEW_SHA"
echo "  Date: $COMMIT_DATE"

# ── Extract current SHA from Portfile ─────────────────────────────────────────

CURRENT_SHA=$(grep -E '^go\.setup\s' "$PORTFILE" | awk '{print $3}')

if [[ "$CURRENT_SHA" == "$NEW_SHA" ]]; then
    echo "Already at latest commit $NEW_SHA — nothing to do."
    exit 0
fi

echo ""
echo "Updating $PORTFILE"
echo "  from: $CURRENT_SHA"
echo "  to:   $NEW_SHA"

# ── Update go.setup SHA ───────────────────────────────────────────────────────

# Replace the SHA on the go.setup line; preserves tag prefix if present
sed -i '' -E "s|^(go\.setup[[:space:]]+[^[:space:]]+)[[:space:]]+[^[:space:]]+(.*)|\\1 $NEW_SHA|" "$PORTFILE"

# ── Update version label ──────────────────────────────────────────────────────

# Determine current version prefix from existing version line or go.setup
CURRENT_VERSION=$(grep -E '^version\s' "$PORTFILE" | awk '{print $2}' || true)
if [[ -n "$CURRENT_VERSION" ]]; then
    # Extract the X.Y.Z prefix before -dev
    VER_PREFIX=$(echo "$CURRENT_VERSION" | sed -E 's/(-dev\..*)$//')
    NEW_VERSION="${VER_PREFIX}-dev.${COMMIT_DATE}"
    sed -i '' -E "s|^(version[[:space:]]+)[^[:space:]]+|\\1$NEW_VERSION|" "$PORTFILE"
else
    # No version line — insert one after go.setup
    sed -i '' "/^go\.setup/a\\
version             2.1.0-dev.${COMMIT_DATE}" "$PORTFILE"
    NEW_VERSION="2.1.0-dev.${COMMIT_DATE}"
fi

echo "  version: $NEW_VERSION"

# ── Reset revision to 0 ───────────────────────────────────────────────────────

sed -i '' -E 's/^(revision[[:space:]]+)[0-9]+/\10/' "$PORTFILE"

# ── Recompute checksums ───────────────────────────────────────────────────────

PORTNAME=$(basename "$PORTDIR")

echo ""
echo "Computing new checksums for $PORTNAME..."

# Clean old distfile for this port (ignore errors — dist dir may share files)
port clean --dist "$PORTNAME" 2>/dev/null || true

# Run port checksum; on mismatch it exits non-zero but logs the correct values
CHECKSUM_LOG=$(sudo port checksum "$PORTNAME" 2>&1 || true)

# Extract the correct checksum block from the log
RMD=$(echo "$CHECKSUM_LOG" | grep "Distfile checksum:.*rmd160" | awk '{print $NF}')
SHA256=$(echo "$CHECKSUM_LOG" | grep "Distfile checksum:.*sha256" | awk '{print $NF}')
SIZE=$(echo "$CHECKSUM_LOG" | grep "Distfile checksum:.*size" | awk '{print $NF}')

if [[ -z "$RMD" || -z "$SHA256" || -z "$SIZE" ]]; then
    echo ""
    echo "WARNING: could not auto-extract checksums — check manually:"
    echo "$CHECKSUM_LOG"
    exit 1
fi

# Replace checksums block in Portfile (handles multi-line block)
python3 - "$PORTFILE" "$RMD" "$SHA256" "$SIZE" <<'PYEOF'
import sys, re
portfile, rmd, sha256, size = sys.argv[1:]
content = open(portfile).read()
new_block = (
    f"checksums           rmd160  {rmd} \\\n"
    f"                    sha256  {sha256} \\\n"
    f"                    size    {size}"
)
content = re.sub(
    r"checksums\s+rmd160\s+\S+\s*\\\s*\n\s*sha256\s+\S+\s*\\\s*\n\s*size\s+\S+",
    new_block,
    content
)
open(portfile, "w").write(content)
PYEOF

echo "  rmd160  $RMD"
echo "  sha256  $SHA256"
echo "  size    $SIZE"

# Verify
echo ""
echo "Verifying checksums..."
sudo port checksum "$PORTNAME" && echo "Checksums OK" || echo "ERROR: checksum verification failed"

# ── Check which feature branches need rebasing ────────────────────────────────

LIMA_DEVL_DIR="${LIMA_DEVL_DIR:-$HOME/Developer/lima-devl}"

if [[ -d "$LIMA_DEVL_DIR/.git" ]]; then
    echo ""
    echo "Fetching upstream to check feature branch staleness..."
    git -C "$LIMA_DEVL_DIR" fetch origin --quiet

    FILES_CHANGED=$(git -C "$LIMA_DEVL_DIR" diff --name-only "$CURRENT_SHA".."$NEW_SHA" 2>/dev/null || true)

    NEEDS_REBASE=()
    for BRANCH_NAME in $(git -C "$LIMA_DEVL_DIR" branch --list "upstream-pr/*" | sed 's/^[* ]*//'); do
        BRANCH_FILES=$(git -C "$LIMA_DEVL_DIR" diff --name-only "origin/master..${BRANCH_NAME}" 2>/dev/null || true)
        OVERLAP=$(comm -12 <(echo "$BRANCH_FILES" | sort) <(echo "$FILES_CHANGED" | sort))
        if [[ -n "$OVERLAP" ]]; then
            NEEDS_REBASE+=("$BRANCH_NAME")
            echo "  STALE  $BRANCH_NAME (overlapping files: $(echo "$OVERLAP" | tr '\n' ' '))"
        else
            echo "  ok     $BRANCH_NAME"
        fi
    done

    if [[ ${#NEEDS_REBASE[@]} -gt 0 ]]; then
        echo ""
        echo "Branches needing rebase onto origin/master:"
        for B in "${NEEDS_REBASE[@]}"; do echo "  $B"; done
        echo ""
        echo "Rebase command:"
        echo "  git -C $LIMA_DEVL_DIR rebase origin/master <branch> --no-verify"
        echo "Then regenerate patch files:"
        echo "  git -C $LIMA_DEVL_DIR diff --no-prefix origin/master..<branch> > files/<patch>.diff"
    fi
fi

echo ""
echo "Done. Review changes in $PORTFILE, then run: portindex"
