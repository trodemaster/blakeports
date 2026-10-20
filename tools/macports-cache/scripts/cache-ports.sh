#!/bin/bash
# cache-ports.sh — build MacPorts ports and publish their archives to the cache.
#
# Runs on the build machine itself (a legacy VM, over ssh from the "Cache ports"
# workflow). For each port spec it runs `port install` in the background and,
# while that runs, submits every newly finished archive to the cache share
# once a minute, so each dependency is published within about a minute of
# being built. A long run that fails, times out or is cancelled keeps
# everything it finished. After each spec it flushes once more.
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
#   PUBLISH_INTERVAL  seconds between submits during a build (default 60)
#
# Prints one "CACHE-RESULT <status> <minutes> <spec>" line per port at the end,
# and exits non-zero if any port failed. Dependencies: bash 3.2, mount_afp —
# Mac OS X 10.5+.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PACKAGES_AFP_URL="${PACKAGES_AFP_URL:-afp://macports:macports@darkstar.jibb.tv/packages}"
PACKAGES_URL="${PACKAGES_URL:-http://packages.jibb.tv}"
PORTS_TREE="${PORTS_TREE:-$(cd "$HERE/../../.." && pwd)}"
PUBLISH_INTERVAL="${PUBLISH_INTERVAL:-60}"
PATH="/opt/local/bin:/opt/local/sbin:$PATH"
# Physical path: /tmp is a symlink to /private/tmp, and `mount` lists the
# resolved path, so is_mounted's check would never match "/tmp/...".
MNT="$(cd /tmp && pwd -P)/packages-cache.$$"

die() { echo "error: $*" >&2; exit 1; }

SPECS="$*"
[ -n "$(echo "$SPECS" | tr -d ' ,')" ] || die "usage: $0 \"port [+variants], port ...\""

is_mounted() { mount | grep -q " on $MNT "; }

# The share stays mounted for the whole run; this (re)mounts it if it isn't.
ensure_mounted() {
    is_mounted && return 0
    mkdir -p "$MNT" || return 1
    mount_afp "$PACKAGES_AFP_URL" "$MNT" >/dev/null 2>&1 && return 0
    echo "warning: cannot mount ${PACKAGES_AFP_URL%%@*}@..." >&2
    return 1
}

unmount() {
    if is_mounted; then
        umount "$MNT" || diskutil unmount force "$MNT" >/dev/null 2>&1
    fi
    rmdir "$MNT" 2>/dev/null
    return 0
}

INSTALL_PID=""
cleanup() {
    [ -n "$INSTALL_PID" ] && sudo kill "$INSTALL_PID" 2>/dev/null
    unmount
}
trap cleanup EXIT

# publish [submit-archive.sh args]: submit every installed archive not yet on
# the share (dependencies included).
publish() {
    ensure_mounted || return 1
    "$HERE/submit-archive.sh" -m "$MNT" "$@"
}

echo "::group::Configure cache client ($PACKAGES_URL)"
sudo "$HERE/setup-client.sh" "$PACKAGES_URL" </dev/null || die "setup-client.sh failed"
echo "::endgroup::"

echo "::group::Check the cache share"
ensure_mounted || die "cannot mount ${PACKAGES_AFP_URL%%@*}@... (share down or bad credentials)"
echo "share OK, mounted at $MNT"
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
    sudo port -N install $spec </dev/null &
    INSTALL_PID=$!
    # Publish as the build goes. ps rather than kill -0: the job runs as root.
    # -a: MacPorts writes a new archive in place (portinstall.tcl create_archive),
    # so skip one modified in the last 2 minutes; it may still be compressing.
    last=$(date +%s)
    while ps -p "$INSTALL_PID" >/dev/null 2>&1; do
        sleep 5
        if [ $(( $(date +%s) - last )) -ge "$PUBLISH_INTERVAL" ]; then
            publish -a 120 -q
            last=$(date +%s)
        fi
    done
    if wait "$INSTALL_PID"; then
        status="built"
    else
        status="FAILED"
        FAILED=$((FAILED + 1))
    fi
    INSTALL_PID=""
    mins=$(( ($(date +%s) - start) / 60 ))
    echo "::endgroup::"

    # Flush what's left, even after a failure: the dependencies that did
    # build are useful.
    echo "::group::Submit archives after $spec"
    if publish; then
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
