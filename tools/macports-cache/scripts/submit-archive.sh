#!/bin/bash
# submit-archive.sh — copy a locally built MacPorts port to the cache server.
#
# The cache server auto-signs archives every 15 seconds, so no crypto tools
# are needed on the build machine.
#
# Prerequisites:
#   1. Mount the cache server's share (AFP/SMB/NFS) to a local path.
#   2. The port must already be installed (sudo port install <portname>).
#
# Usage:
#   ./submit-archive.sh <portname> [mount_path]
#
# Examples:
#   ./submit-archive.sh netatalk /Volumes/macports-cache
#   MOUNT=/Volumes/macports-cache ./submit-archive.sh libcbor
#
# On very old MacPorts (pre-2.0, where images are .tbz2 files):
#   The script also looks for .tbz2 files in the software directory.
#
# Dependencies: cp, tar, basename — all standard UNIX, no extras needed.
set -e

PORTNAME="${1:?Usage: $0 <portname> [mount_path]}"
MOUNT_PATH="${2:-${MOUNT:-/Volumes/macports-cache}}"
SOFTWARE_DIR="${SOFTWARE_DIR:-/opt/local/var/macports/software}"

# ── validate mount ──────────────────────────────────────────────────────────
if [ ! -d "$MOUNT_PATH" ]; then
    echo "error: cache mount not found at $MOUNT_PATH" >&2
    echo "       mount the cache server share first, or set MOUNT=/your/path" >&2
    exit 1
fi

PORT_IMG_DIR="${SOFTWARE_DIR}/${PORTNAME}"
if [ ! -d "$PORT_IMG_DIR" ]; then
    echo "error: no installed image for '${PORTNAME}' at ${PORT_IMG_DIR}" >&2
    echo "       run: sudo port install ${PORTNAME}" >&2
    exit 1
fi

# ── destination directory ───────────────────────────────────────────────────
DST_DIR="${MOUNT_PATH}/${PORTNAME}"
mkdir -p "$DST_DIR"

count=0

# ── case 1: pre-built .tbz2 files in the software dir (old MacPorts) ────────
for tbz in "${PORT_IMG_DIR}"/*.tbz2; do
    [ -f "$tbz" ] || continue
    filename=$(basename "$tbz")
    echo "Copying pre-built archive: ${filename}"
    cp "$tbz" "${DST_DIR}/${filename}"
    count=$((count + 1))
done

# ── case 2: directory images (modern MacPorts 2.x) ──────────────────────────
# Each subdirectory is a port image; pack it into a .tbz2 on the fly.
for img_dir in "${PORT_IMG_DIR}"/*/; do
    [ -d "$img_dir" ] || continue
    imagename=$(basename "$img_dir")

    # Skip if we already handled a matching .tbz2 above
    if ls "${DST_DIR}/${imagename}.tbz2" 2>/dev/null | grep -q .; then
        continue
    fi

    archive="${imagename}.tbz2"
    tmp_archive="${TMPDIR:-/tmp}/${archive}"

    echo "Archiving image: ${imagename}"
    # Pack exactly as MacPorts expects: top-level dir = imagename
    tar -cjf "$tmp_archive" -C "$PORT_IMG_DIR" "$imagename"

    echo "Copying: ${archive}"
    cp "$tmp_archive" "${DST_DIR}/${archive}"
    rm -f "$tmp_archive"
    count=$((count + 1))
done

# ── summary ─────────────────────────────────────────────────────────────────
if [ "$count" -eq 0 ]; then
    echo "No archives found for '${PORTNAME}' in ${PORT_IMG_DIR}" >&2
    exit 1
fi

echo ""
echo "Done. Submitted ${count} archive(s) for ${PORTNAME}."
echo "The cache server will sign them within 15 seconds."
