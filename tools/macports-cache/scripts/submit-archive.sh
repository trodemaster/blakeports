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
#   ./submit-archive.sh [-m mount_path] [-a seconds] [-q] [portname ...]
#   (no port names: submit every installed port)
#
#   -m  where the share is mounted (default /Volumes/packages)
#   -a  skip archives modified less than this many seconds ago (default 0),
#       for running while a build may still be writing one
#   -q  print nothing when there is nothing to submit
#
# Examples:
#   ./submit-archive.sh                       # seed the cache with everything
#   ./submit-archive.sh netatalk libgcrypt
#   ./submit-archive.sh -m /Volumes/packages -a 60 -q
#
# Archives already on the share (same name and size) are skipped, so it's
# cheap to run after every build, or every minute during one.
#
# Dependencies: bash 3.2, cp, stat — runs on Mac OS X 10.5.
set -e

MOUNT_PATH="${MOUNT:-/Volumes/packages}"
SOFTWARE_DIR="${SOFTWARE_DIR:-/opt/local/var/macports/software}"
MIN_AGE=0
QUIET=0

PORTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        -m) MOUNT_PATH="${2:?-m needs a path}"; shift 2 ;;
        -a) MIN_AGE="${2:?-a needs seconds}"; shift 2 ;;
        -q) QUIET=1; shift ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
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

now=$(date +%s)
copied=0
skipped=0
young=0
for port in $PORTS; do
    found=0
    for tbz in "${SOFTWARE_DIR}/${port}"/*.tbz2; do
        [ -f "$tbz" ] || continue
        found=1
        name=$(basename "$tbz")
        dst="${MOUNT_PATH}/${port}/${name}"
        # Same name + same size is treated as already cached: the name pins
        # port, version, revision, variants and platform, and comparing
        # contents would re-read the whole cache over the share every run.
        if [ -f "$dst" ] && [ "$(stat -f %z "$tbz")" = "$(stat -f %z "$dst")" ]; then
            skipped=$((skipped + 1))
            continue
        fi
        if [ "$MIN_AGE" -gt 0 ] && [ $((now - $(stat -f %m "$tbz"))) -lt "$MIN_AGE" ]; then
            young=$((young + 1))
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

[ "$QUIET" -eq 1 ] && [ "$copied" -eq 0 ] && exit 0
echo ""
msg="Done: ${copied} submitted, ${skipped} already present"
[ "$young" -eq 0 ] || msg="${msg}, ${young} still being written"
echo "${msg}."
[ "$copied" -eq 0 ] || echo "The signer adds the .rmd160 signatures within about 30 seconds."
