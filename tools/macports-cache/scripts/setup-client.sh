#!/bin/bash
# setup-client.sh — configure a MacPorts installation to use the local cache.
#
# Detects the local macOS version and sets cxx_stdlib / delete_la_files to
# match, so MacPorts' filter_sites check passes on any OS version.
#
# Usage (as root or with sudo):
#   sudo ./setup-client.sh <cache-hostname> [port]
#
# Example:
#   sudo ./setup-client.sh mymac.local 8030
set -e

CACHE_HOST="${1:?Usage: $0 <cache-hostname> [port]}"
CACHE_PORT="${2:-8030}"
MACPORTS_ETC="${MACPORTS_ETC:-/opt/local/etc/macports}"
MACPORTS_SHARE="${MACPORTS_SHARE:-/opt/local/share/macports}"
PUBKEY_PATH="${MACPORTS_SHARE}/macports-cache-pubkey.pem"
CACHE_URL="http://${CACHE_HOST}:${CACHE_PORT}"

# ── detect macOS version → cxx_stdlib and delete_la_files ────────────────────
# These must match the local MacPorts installation or filter_sites rejects the
# cache entry entirely. Mirrors the logic in the official archive_sites.tcl.
#   darwin major <= 9  (OS X 10.5 Leopard):       libstdc++, delete_la=no
#   darwin major 10-12 (OS X 10.6–10.8):           libstdc++ on 10.8-, libc++ on 10.9+
#   Wait — os.major is the Darwin kernel version, not the macOS marketing version:
#     Darwin 9  = OS X 10.5   Darwin 10 = OS X 10.6   Darwin 11 = OS X 10.7
#     Darwin 12 = OS X 10.8   Darwin 13 = OS X 10.9   Darwin 14 = OS X 10.10 ...
#   archive_sites.tcl: cxx_stdlib=libc++ when os.major >= 13 (OS X 10.9+)
#                      delete_la_files=no when os.major <= 12 (OS X 10.8 and earlier)
OS_MAJOR=$(uname -r | cut -d. -f1)

if [ "$OS_MAJOR" -ge 13 ] 2>/dev/null; then
    CXX_STDLIB="libc++"
    DELETE_LA="yes"
else
    CXX_STDLIB="libstdc++"
    DELETE_LA="no"
fi
echo "==> Detected Darwin ${OS_MAJOR}: cxx_stdlib=${CXX_STDLIB}, delete_la_files=${DELETE_LA}"

# ── public key ───────────────────────────────────────────────────────────────
echo "==> Fetching public key from ${CACHE_URL}/pubkey.pem"
curl -fsSL "${CACHE_URL}/pubkey.pem" -o "$PUBKEY_PATH"
echo "    Saved to ${PUBKEY_PATH}"

# ── pubkeys.conf ─────────────────────────────────────────────────────────────
PUBKEYS_CONF="${MACPORTS_ETC}/pubkeys.conf"
echo "==> Updating ${PUBKEYS_CONF}"
if grep -qF "$PUBKEY_PATH" "$PUBKEYS_CONF" 2>/dev/null; then
    echo "    Already present."
else
    echo "$PUBKEY_PATH" >> "$PUBKEYS_CONF"
    echo "    Added."
fi

# ── archive_sites.conf ───────────────────────────────────────────────────────
# Each client gets an entry matching its own cxx_stdlib/delete_la_files.
# Multiple clients with different configurations can all point to the same
# cache server URL — the platform-specific archive is selected by filename.
SITES_CONF="${MACPORTS_ETC}/archive_sites.conf"
echo "==> Updating ${SITES_CONF}"
if grep -qF "${CACHE_URL}/" "$SITES_CONF" 2>/dev/null; then
    echo "    Already present."
else
    cat >> "$SITES_CONF" << EOF

name                local_cache
urls                ${CACHE_URL}/
cxx_stdlib          ${CXX_STDLIB}
delete_la_files     ${DELETE_LA}
EOF
    echo "    Added."
fi

echo ""
echo "Done. MacPorts will now try the local cache before building from source."
echo ""
echo "Test with binary-only mode (fails fast if not cached):"
echo "  sudo port -b install <portname>"
echo ""
echo "Test with fallback to source (normal mode):"
echo "  sudo port install <portname>"
