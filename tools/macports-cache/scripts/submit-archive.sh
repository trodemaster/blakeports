#!/bin/bash
# submit-archive.sh — copy locally built MacPorts archives to the cache share.
#
# MacPorts 2.x keeps every installed port as a ready-made binary archive in
# ${SOFTWARE_DIR}/<port>/<port>-<version>_<rev>+<variants>.darwin_<N>.<arch>.tbz2,
# which is exactly the file archive_sites clients fetch. This script copies
# those files onto the mounted share; the cache's signer adds the .rmd160 once
# each copy has been idle for a scan interval, so no crypto is needed here.
#
# The cache is for dependencies only: ports in the blakeports tree (and their
# subports) are never submitted, so a CI build of one always builds the
# Portfile under test instead of installing a cached binary. The list comes from
# that tree's PortIndex (run portindex first); without one nothing is submitted.
#
# Archives an official mirror already serves (fcix, MIT; see on-mirror.sh) are
# skipped too: clients fetch those from the mirror. If the check can't reach a
# mirror the archive is submitted, and prune-cache.sh removes it later if a
# mirror turns out to have it.
#
# Usage:
#   ./submit-archive.sh [-m mount_path] [-x PortIndex] [-a seconds] [-M] [-q] [portname ...]
#   (no port names: submit every installed port not in blakeports)
#
#   -m  where the share is mounted (default /Volumes/packages)
#   -x  PortIndex of the ports tree whose ports are never submitted (default:
#       the blakeports checkout this script lives in)
#   -a  skip archives modified less than this many seconds ago (default 0),
#       for running while a build may still be writing one
#   -M  submit archives even if an official mirror has them
#   -q  print nothing when there is nothing to submit
#
# Environment:
#   MIRROR_MEMO  file of archives already found on a mirror, read and appended
#                so repeated runs (cache-ports.sh calls this every minute) ask
#                the mirrors about each archive once; unset means no memo
#
# Examples:
#   ./submit-archive.sh                       # seed the cache with every dep
#   ./submit-archive.sh netatalk libgcrypt
#   ./submit-archive.sh -m /Volumes/packages -a 60 -q
#
# Archives already on the share (same name and size) are skipped, so it's
# cheap to run after every build, or every minute during one.
#
# Dependencies: bash 3.2, awk, cp, stat, curl — runs on Mac OS X 10.5.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
DENY_INDEX="$HERE/../../../PortIndex"
MOUNT_PATH="${MOUNT:-/Volumes/packages}"
SOFTWARE_DIR="${SOFTWARE_DIR:-/opt/local/var/macports/software}"
MIN_AGE=0
QUIET=0
CHECK_MIRRORS=1
MIRROR_MEMO="${MIRROR_MEMO:-}"

PORTS=""
while [ $# -gt 0 ]; do
    case "$1" in
        -m) MOUNT_PATH="${2:?-m needs a path}"; shift 2 ;;
        -x) DENY_INDEX="${2:?-x needs a PortIndex path}"; shift 2 ;;
        -a) MIN_AGE="${2:?-a needs seconds}"; shift 2 ;;
        -M) CHECK_MIRRORS=0; shift ;;
        -q) QUIET=1; shift ;;
        -h|--help) sed -n '2,46p' "$0"; exit 0 ;;
        *) PORTS="$PORTS $1"; shift ;;
    esac
done

if [ ! -d "$MOUNT_PATH" ]; then
    echo "error: cache share not mounted at $MOUNT_PATH" >&2
    echo "       mount smb:// (macOS 13+) or afp://darkstar.jibb.tv/packages, or pass -m /your/path" >&2
    exit 1
fi

if [ ! -f "$DENY_INDEX" ]; then
    echo "error: no PortIndex at $DENY_INDEX, so blakeports' own ports can't be" >&2
    echo "       excluded; run portindex in the ports tree, or pass -x /path/PortIndex" >&2
    exit 1
fi
# PortIndex alternates "<name> <length>" lines with one line of port info.
DENY=" $(awk 'NR % 2 == 1 { print $1 }' "$DENY_INDEX" | tr '\n' ' ') "

if [ -z "$PORTS" ]; then
    PORTS=$(cd "$SOFTWARE_DIR" && ls)
fi

now=$(date +%s)
copied=0
skipped=0
young=0
denied=0
mirrored=0
for port in $PORTS; do
    case "$DENY" in
        *" $port "*) denied=$((denied + 1)); continue ;;
    esac
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
        if [ "$CHECK_MIRRORS" -eq 1 ]; then
            if [ -n "$MIRROR_MEMO" ] && grep -qxF "${port}/${name}" "$MIRROR_MEMO" 2>/dev/null; then
                mirrored=$((mirrored + 1))
                continue
            fi
            if "$HERE/on-mirror.sh" "${port}/${name}"; then
                [ -z "$MIRROR_MEMO" ] || echo "${port}/${name}" >> "$MIRROR_MEMO"
                mirrored=$((mirrored + 1))
                continue
            fi
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
msg="Done: ${copied} submitted, ${skipped} already present, ${mirrored} on an official mirror, ${denied} in blakeports (never cached)"
[ "$young" -eq 0 ] || msg="${msg}, ${young} still being written"
echo "${msg}."
[ "$copied" -eq 0 ] || echo "The signer adds the .rmd160 signatures within about 30 seconds."
