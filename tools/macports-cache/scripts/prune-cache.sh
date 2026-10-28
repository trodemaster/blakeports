#!/bin/bash
# prune-cache.sh — delete archives the packages cache no longer needs.
#
# Runs against the mounted cache share (the "Prune cache" workflow mounts it
# over SMB on a modern runner). An archive is deleted, with its .rmd160, for
# the first of these reasons that applies:
#
#   blakeports  its port is in the blakeports tree (PortIndex). The cache is
#               for dependencies only; submit-archive.sh already refuses these,
#               this catches any that got in another way.
#   mirrored    an official mirror serves the same file (on-mirror.sh), so
#               clients fetch it from there. The buildbots often publish an
#               archive after we cached it.
#   partial     a *.part left by an interrupted copy, older than a day.
#
# Port directories left empty are removed. Nothing else on the share (the
# signer's pubkey.pem and .privkey.pem) is touched.
#
# There is deliberately no "older version" rule: legacy VMs pin older versions,
# so several versions of one archive are in use at once (see CLAUDE.md,
# "Keeping the cache lean").
#
# Usage:
#   ./prune-cache.sh [-m mount_path] [-x PortIndex] [-n]
#
#   -m  where the share is mounted (default /Volumes/packages)
#   -x  PortIndex of the blakeports tree (default: the checkout this script
#       lives in; run portindex first)
#   -n  dry run: print what would be deleted, delete nothing
#
# Prints one "PRUNE <reason> <bytes> <port>/<archive>" line per archive, then a
# summary. Dependencies: bash 3.2, awk, find, stat, curl (macOS).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
DENY_INDEX="$HERE/../../../PortIndex"
MOUNT_PATH="/Volumes/packages"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -m) MOUNT_PATH="${2:?-m needs a path}"; shift 2 ;;
        -x) DENY_INDEX="${2:?-x needs a PortIndex path}"; shift 2 ;;
        -n) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done

# pubkey.pem marks the cache root, so a wrong -m can't delete anything else.
if [ ! -f "$MOUNT_PATH/pubkey.pem" ]; then
    echo "error: $MOUNT_PATH has no pubkey.pem; is the cache share mounted there?" >&2
    exit 1
fi
if [ ! -f "$DENY_INDEX" ]; then
    echo "error: no PortIndex at $DENY_INDEX; run portindex, or pass -x" >&2
    exit 1
fi
# PortIndex alternates "<name> <length>" lines with one line of port info.
DENY=" $(awk 'NR % 2 == 1 { print $1 }' "$DENY_INDEX" | tr '\n' ' ') "

LIST=$(mktemp "${TMPDIR:-/tmp}/prune-cache.XXXXXX")
trap 'rm -f "$LIST"' EXIT

# "<bytes> <port>/<archive>" for every archive on the share.
(cd "$MOUNT_PATH" && find . -mindepth 2 -maxdepth 2 -type f -name '*.tbz2' \
    -exec stat -f '%z %N' {} +) | sed 's| \./| |' > "$LIST"


kept=0
freed=0
n_blakeports=0
n_mirrored=0

prune() {   # prune reason bytes path...
    local reason="$1" bytes="$2" f
    shift 2
    echo "PRUNE $reason $bytes $1"
    eval "n_$reason=\$((n_$reason + 1))"
    freed=$((freed + bytes))
    [ "$DRY_RUN" -eq 1 ] && return 0
    for f in "$@"; do
        rm -f "$MOUNT_PATH/$f"
    done
}

while read -r bytes path; do
    port="${path%%/*}"
    case "$DENY" in
        *" $port "*) prune blakeports "$bytes" "$path" "$path.rmd160"; continue ;;
    esac
    if "$HERE/on-mirror.sh" "$path" </dev/null; then
        prune mirrored "$bytes" "$path" "$path.rmd160"
        continue
    fi
    kept=$((kept + 1))
done < "$LIST"

# Interrupted copies; submit-archive.sh writes <archive>.part, then renames.
(cd "$MOUNT_PATH" && find . -mindepth 2 -maxdepth 2 -type f -name '*.part' -mtime +1 \
    -exec stat -f '%z %N' {} +) | sed 's| \./| |' |
while read -r bytes path; do
    echo "PRUNE partial $bytes $path"
    [ "$DRY_RUN" -eq 1 ] || rm -f "$MOUNT_PATH/$path"
done

if [ "$DRY_RUN" -eq 0 ]; then
    (cd "$MOUNT_PATH" && find . -mindepth 1 -maxdepth 1 -type d -empty -exec rmdir {} +)
fi

echo ""
[ "$DRY_RUN" -eq 1 ] && verb="Would delete" || verb="Deleted"
echo "$verb $((n_blakeports + n_mirrored)) archives, $((freed / 1048576)) MB:" \
    "${n_mirrored} mirrored, ${n_blakeports} blakeports; kept ${kept}."
