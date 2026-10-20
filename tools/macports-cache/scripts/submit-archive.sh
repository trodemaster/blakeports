#!/bin/bash
# submit-archive.sh — copy locally built MacPorts archives to the cache share.
#
# MacPorts 2.x keeps every installed port as a ready-made binary archive in
# ${SOFTWARE_DIR}/<port>/<port>-<version>_<rev>+<variants>.darwin_<N>.<arch>.tbz2,
# which is exactly the file archive_sites clients fetch. This script copies
# those files onto the mounted share; the cache's signer adds the .rmd160 once
# each copy has been idle for a scan interval, so no crypto is needed here.
#
# Usage:
#   ./submit-archive.sh [portname ...] [-m mount_path]
#   (no port names: submit every installed port)
#
# Examples:
#   ./submit-archive.sh                       # seed the cache with everything
#   ./submit-archive.sh netatalk libgcrypt
#   ./submit-archive.sh -m /Volumes/packages netatalk
#
# Archives already on the share with identical contents are skipped, so it's
# cheap to run after every build.
#
# Dependencies: bash 3.2, cp, cmp — runs on Mac OS X 10.5.
set -e

MOUNT_PATH="${MOUNT:-/Volumes/packages}"
SOFTWARE_DIR="${SOFTWARE_DIR:-/opt/local/var/macports/software}"

PORTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        -m) MOUNT_PATH="${2:?-m needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) PORTS="$PORTS $1"; shift ;;
    esac
done

if [ ! -d "$MOUNT_PATH" ]; then
    echo "error: cache share not mounted at $MOUNT_PATH" >&2
    echo "       mount afp://darkstar.jibb.tv/packages, or pass -m /your/path" >&2
    exit 1
fi

if [ -z "$PORTS" ]; then
    PORTS=$(cd "$SOFTWARE_DIR" && ls)
fi

copied=0
skipped=0
for port in $PORTS; do
    found=0
    for tbz in "${SOFTWARE_DIR}/${port}"/*.tbz2; do
        [ -f "$tbz" ] || continue
        found=1
        name=$(basename "$tbz")
        dst="${MOUNT_PATH}/${port}/${name}"
        if [ -f "$dst" ] && cmp -s "$tbz" "$dst"; then
            skipped=$((skipped + 1))
            continue
        fi
        mkdir -p "${MOUNT_PATH}/${port}"
        echo "submit: ${port}/${name}"
        # Copy to a temp name and rename, so a client never sees a partial file.
        cp "$tbz" "${dst}.part"
        mv -f "${dst}.part" "$dst"
        copied=$((copied + 1))
    done
    [ "$found" -eq 1 ] || echo "warning: no archive for '${port}' in ${SOFTWARE_DIR}" >&2
done

echo ""
echo "Done: ${copied} submitted, ${skipped} already present."
[ "$copied" -eq 0 ] || echo "The signer adds the .rmd160 signatures within about 30 seconds."
