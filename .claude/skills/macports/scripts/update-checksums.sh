#!/bin/bash
# Update checksums in a Portfile after a version change, using `port bump`
# Usage: update-checksums.sh <portname>
#
# Update the version in the Portfile first (keep the old checksums), then run
# this. `port bump` fetches the new distfile, rewrites the checksums line in
# place and resets the revision. It does not touch `version` lines in
# subports/stubs (e.g. netatalk4) - update those by hand.

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

if sudo port checksum "$PORTNAME" >/dev/null 2>&1; then
    echo "Checksums already match! No update needed."
    exit 0
fi

sudo port bump "$PORTNAME"

echo ""
echo "Verifying..."
sudo port checksum "$PORTNAME"

echo ""
echo "========================================="
echo "Next: portindex && port lint --nitpick $PORTNAME"
echo "========================================="
