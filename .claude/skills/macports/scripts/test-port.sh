#!/bin/bash
# Test a MacPorts port with standard workflow
# Usage: test-port.sh <portname>

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <portname>"
    exit 1
fi

PORTNAME=$1

echo "========================================="
echo "Testing port: $PORTNAME"
echo "========================================="

echo ""
echo "Step 1: Update port index..."
portindex

echo ""
echo "Step 2: Lint check (nitpick mode)..."
port lint --nitpick "$PORTNAME"

echo ""
echo "Step 3: Clean uninstall existing installation..."
sudo port uninstall "$PORTNAME" 2>/dev/null || echo "Port not installed, skipping uninstall"

echo ""
echo "Step 4: Clean distribution files..."
sudo port clean --dist "$PORTNAME"

echo ""
echo "Step 5: Install with verbose output..."
sudo port install -sv "$PORTNAME"

echo ""
echo "========================================="
echo "Port test completed successfully!"
echo "========================================="
