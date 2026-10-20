#!/bin/bash
# cache-ports.sh — build MacPorts ports and publish their archives to the cache.
#
# Runs on the build machine itself (a legacy VM, over ssh from the "Cache ports"
# workflow). For each port spec it runs `port install`, then mounts the cache
# share, submits every installed archive that isn't there yet (so dependencies
# are published too), and unmounts. Publishing after each port means a long run
# that dies or times out keeps everything it finished.
#
# Dependencies already in the cache install as binaries, because the script
# first configures this machine as a cache client (setup-client.sh, idempotent).
#
# Usage:
#   ./cache-ports.sh "netatalk, curl +ssl -http2, libcbor"
#   (port specs are comma-separated; each may carry variants)
#
# Environment:
#   PACKAGES_AFP_URL  share to submit to (default afp://macports:macports@darkstar.jibb.tv/packages)
#   PACKAGES_URL      cache to configure as a client (default http://packages.jibb.tv)
#   PORTS_TREE        local ports tree to portindex first (default: the blakeports
#                     checkout this script lives in)
#
# Prints one "CACHE-RESULT <status> <spec>" line per port at the end, and exits
# non-zero if any port failed. Dependencies: bash 3.2, mount_afp — Mac OS X 10.5+.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_AFP_URL="${PACKAGES_AFP_URL:-afp://macports:macports@darkstar.jibb.tv/packages}"
PACKAGES_URL="${PACKAGES_URL:-http://packages.jibb.tv}"
PORTS_TREE="${PORTS_TREE:-$(cd "$HERE/../../.." && pwd)}"
PATH="/opt/local/bin:/opt/local/sbin:$PATH"
# Physical path: /tmp is a symlink to /private/tmp, and `mount` lists the
# resolved path, so unmount()'s check would never match "/tmp/...".
MNT="$(cd /tmp && pwd -P)/packages-cache.$$"

die() { echo "error: $*" >&2; exit 1; }

SPECS="$*"
[ -n "$(echo "$SPECS" | tr -d ' ,')" ] || die "usage: $0 \"port [+variants], port ...\""

unmount() {
    if mount | grep -q " on $MNT "; then
        umount "$MNT" || diskutil unmount force "$MNT" >/dev/null 2>&1
    fi
    rmdir "$MNT" 2>/dev/null
    return 0
}
trap unmount EXIT

submit() {
    mkdir -p "$MNT" || return 1
    if ! mount_afp "$PACKAGES_AFP_URL" "$MNT"; then
        rmdir "$MNT" 2>/dev/null
        return 1
    fi
    "$HERE/submit-archive.sh" -m "$MNT"
    local rc=$?
    unmount
    return $rc
}

echo "::group::Configure cache client ($PACKAGES_URL)"
sudo "$HERE/setup-client.sh" "$PACKAGES_URL" </dev/null || die "setup-client.sh failed"
echo "::endgroup::"

echo "::group::Check the cache share"
mkdir -p "$MNT" && mount_afp "$PACKAGES_AFP_URL" "$MNT" || die "cannot mount ${PACKAGES_AFP_URL%%@*}@... (share down or bad credentials)"
unmount
echo "share OK"
echo "::endgroup::"

if [ -d "$PORTS_TREE" ]; then
    echo "::group::portindex $PORTS_TREE"
    (cd "$PORTS_TREE" && portindex) || die "portindex failed in $PORTS_TREE"
    echo "::endgroup::"
fi

RESULTS=""
FAILED=0
OLDIFS=$IFS
IFS=','
for spec in $SPECS; do
    IFS=$OLDIFS
    spec=$(echo "$spec" | sed -e 's/^ *//' -e 's/ *$//')
    [ -n "$spec" ] || continue

    echo "::group::port install $spec"
    start=$(date +%s)
    # $spec is unquoted on purpose: "curl +ssl -http2" is a port plus variants.
    if sudo port -N install $spec </dev/null; then
        status="built"
    else
        status="FAILED"
        FAILED=$((FAILED + 1))
    fi
    mins=$(( ($(date +%s) - start) / 60 ))
    echo "::endgroup::"

    # Publish even after a failure: the dependencies that did build are useful.
    echo "::group::Submit archives after $spec"
    if submit; then
        published="published"
    else
        published="SUBMIT-FAILED"
        FAILED=$((FAILED + 1))
    fi
    echo "::endgroup::"

    RESULTS="${RESULTS}CACHE-RESULT ${status}/${published} ${mins}m ${spec}
"
    IFS=','
done
IFS=$OLDIFS

echo ""
printf '%s' "$RESULTS"
[ "$FAILED" -eq 0 ]
