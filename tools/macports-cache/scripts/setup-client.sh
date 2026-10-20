#!/bin/bash
# setup-client.sh — configure a MacPorts installation to use the local cache.
#
# Detects the local macOS version and sets cxx_stdlib / delete_la_files to
# match, so MacPorts' filter_sites check passes on any OS version.
#
# Usage (as root or with sudo):
#   sudo ./setup-client.sh [base-url | host [port]]
#
# Examples:
#   sudo ./setup-client.sh                          # http://packages.jibb.tv
#   sudo ./setup-client.sh http://packages.jibb.tv
#   sudo ./setup-client.sh mymac.local 8030         # a standalone macports-cache server
set -e

if [ -z "${1:-}" ]; then
    CACHE_URL="http://packages.jibb.tv"
elif echo "$1" | grep -q '://'; then
    CACHE_URL="${1%/}"
else
    CACHE_URL="http://${1}:${2:-8030}"
fi
SITE_NAME="${SITE_NAME:-jibb_archives}"
MACPORTS_ETC="${MACPORTS_ETC:-/opt/local/etc/macports}"
MACPORTS_SHARE="${MACPORTS_SHARE:-/opt/local/share/macports}"
PUBKEY_PATH="${MACPORTS_SHARE}/${SITE_NAME}-pubkey.pem"

# ── detect macOS version → cxx_stdlib and delete_la_files ────────────────────
# These must match the local MacPorts installation or filter_sites rejects the
# cache entry entirely. Same rule as MacPorts' own archive_sites.conf defaults
# (macports.tcl, get_archive_sites_conf_values), keyed on the Darwin major:
#   Darwin <= 12 (OS X 10.8 and earlier): libstdc++, delete_la_files no
#   Darwin >= 13 (OS X 10.9 and later):   libc++,    delete_la_files yes
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
grep -q 'BEGIN PUBLIC KEY' "$PUBKEY_PATH" || { echo "error: ${CACHE_URL}/pubkey.pem is not a PEM public key" >&2; exit 1; }
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
if grep -qE "^name[[:space:]]+${SITE_NAME}\$" "$SITES_CONF" 2>/dev/null; then
    echo "    Already present."
else
    cat >> "$SITES_CONF" << EOF

name                ${SITE_NAME}
urls                ${CACHE_URL}/
cxx_stdlib          ${CXX_STDLIB}
delete_la_files     ${DELETE_LA}
EOF
    echo "    Added."
fi

echo ""
echo "Done. MacPorts will now try ${CACHE_URL} before building from source."
echo ""
echo "Test with binary-only mode (fails fast if not cached):"
echo "  sudo port -b install <portname>"
