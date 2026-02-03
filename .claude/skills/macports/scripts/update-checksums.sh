#!/bin/bash
# Update checksums in a Portfile after version change
# Usage: update-checksums.sh <portname>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <portname>"
    exit 1
fi

PORTNAME=$1

echo "========================================="
echo "Updating checksums for: $PORTNAME"
echo "========================================="

echo ""
echo "Running port checksum to get new values..."
echo ""

# Run port checksum and capture output
# This will fail if checksums don't match, but that's expected
if sudo port checksum "$PORTNAME" 2>&1 | tee /tmp/checksum_output.txt; then
    echo "Checksums already match! No update needed."
    exit 0
fi

echo ""
echo "========================================="
echo "Extract the checksums line from output above."
echo "It should look like:"
echo "  checksums           rmd160  HASH \\"
echo "                      sha256  HASH \\"
echo "                      size    SIZE"
echo ""
echo "Update your Portfile with these values."
echo "========================================="
