#!/bin/bash
# cache-ports.sh — build MacPorts ports and publish their archives to the cache.
#
# Runs on the build machine itself: on a modern runner directly, on a legacy
# VM over ssh (both from the "Cache ports" workflow). For each port spec it runs `port install` in the background and,
# while that runs, submits every newly finished archive to the cache share
# once a minute, so each dependency is published within about a minute of
# being built. A long run that fails, times out or is cancelled keeps
# everything it finished. After each spec it flushes once more.
#
# Dependencies already in the cache install as binaries, because the script
# first configures this machine as a cache client (setup-client.sh, idempotent).
# Ports in the blakeports tree itself are built but never published (see
# submit-archive.sh): caching a blakeports port only caches its dependencies.
#
# Usage:
#   ./cache-ports.sh "netatalk, curl +ssl -http2, libcbor"
#   (port specs are comma-separated; each may carry variants)
#
# Environment:
#   PACKAGES_SHARE_URL  share to submit to (default: the darkstar packages share,
#                     over SMB on macOS 13 and later, AFP before that)
#   PACKAGES_URL      cache to configure as a client (default http://packages.jibb.tv)
#   PORTS_TREE        local ports tree to portindex first (default: the blakeports
#                     checkout this script lives in)
#   PUBLISH_INTERVAL  seconds between submits during a build (default 60)
#
# Prints one "CACHE-RESULT <status> <minutes> <spec>" line per port at the end,
# and exits non-zero if any port failed. Dependencies: bash 3.2, mount_afp or
# mount_smbfs — Mac OS X 10.5+.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# Newer macOS is dropping the AFP client, and the legacy VMs can't speak the
# SMB that darkstar's Samba does: SMB from macOS 13 (Darwin 22), AFP before.
if [ "$(uname -r | cut -d. -f1)" -ge 22 ]; then
    PACKAGES_SHARE_URL="${PACKAGES_SHARE_URL:-smb://macports:macports@darkstar.jibb.tv/packages}"
else
    PACKAGES_SHARE_URL="${PACKAGES_SHARE_URL:-afp://macports:macports@darkstar.jibb.tv/packages}"
fi
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
    case "$PACKAGES_SHARE_URL" in
        smb://*) mount_smbfs "${PACKAGES_SHARE_URL#smb:}" "$MNT" >/dev/null 2>&1 && return 0 ;;
        *) mount_afp "$PACKAGES_SHARE_URL" "$MNT" >/dev/null 2>&1 && return 0 ;;
    esac
    echo "warning: cannot mount ${PACKAGES_SHARE_URL%%@*}@..." >&2
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
TAIL_PID=""
LOG="$(cd /tmp && pwd -P)/cache-ports.$$.log"
# Archives found on an official mirror, so the minute-by-minute publishes ask
# the mirrors about each one only once (see submit-archive.sh).
export MIRROR_MEMO="$(cd /tmp && pwd -P)/cache-ports.$$.mirrored"
REACTIVATE=""
cleanup() {
    [ -n "$INSTALL_PID" ] && sudo kill "$INSTALL_PID" 2>/dev/null
    [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
    reactivate
    rm -f "$LOG" "$MIRROR_MEMO"
    unmount
}
trap cleanup EXIT

# Reactivate whatever install_spec deactivated to get past a conflict.
reactivate() {
    for p in $REACTIVATE; do
        if ! port -q installed "$p" | grep -q '(active)'; then
            echo "reactivating $p"
            sudo port activate "$p" </dev/null || true
        fi
    done
    REACTIVATE=""
}

# publish [submit-archive.sh args]: submit every installed archive not yet on
# the share (dependencies included), except blakeports' own ports.
publish() {
    ensure_mounted || return 1
    "$HERE/submit-archive.sh" -m "$MNT" -x "$PORTS_TREE/PortIndex" "$@"
}

# install_spec spec: run `port install` in the background, publishing as the
# build goes; returns its exit status. The output goes to $LOG (and is followed
# on stdout) so a failure can be inspected.
install_spec() {
    : > "$LOG"
    tail -f "$LOG" &
    TAIL_PID=$!
    # $1 is unquoted on purpose: "curl +ssl -http2" is a port plus variants.
    sudo port -N install $1 </dev/null >"$LOG" 2>&1 &
    INSTALL_PID=$!
    # Publish as the build goes. ps rather than kill -0: the job runs as root.
    # -a: MacPorts writes a new archive in place (portinstall.tcl create_archive),
    # so skip one modified in the last 2 minutes; it may still be compressing.
    local last rc
    last=$(date +%s)
    while ps -p "$INSTALL_PID" >/dev/null 2>&1; do
        sleep 5
        if [ $(( $(date +%s) - last )) -ge "$PUBLISH_INTERVAL" ]; then
            publish -a 120 -q
            last=$(date +%s)
        fi
    done
    wait "$INSTALL_PID"
    rc=$?
    INSTALL_PID=""
    sleep 1
    kill "$TAIL_PID" 2>/dev/null
    wait "$TAIL_PID" 2>/dev/null
    TAIL_PID=""
    return $rc
}

echo "::group::Configure cache client ($PACKAGES_URL)"
sudo "$HERE/setup-client.sh" "$PACKAGES_URL" </dev/null || die "setup-client.sh failed"
echo "::endgroup::"

echo "::group::Check the cache share"
ensure_mounted || die "cannot mount ${PACKAGES_SHARE_URL%%@*}@... (share down or bad credentials)"
echo "share OK, mounted at $MNT"
echo "::endgroup::"

if [ -d "$PORTS_TREE" ]; then
    echo "::group::portindex $PORTS_TREE"
    (cd "$PORTS_TREE" && portindex) || die "portindex failed in $PORTS_TREE"
    echo "::endgroup::"
fi

if [ -x "$PORTS_TREE/scripts/syncports" ]; then
    echo "::group::Sync the official ports tree"
    "$PORTS_TREE/scripts/syncports"
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
    install_spec "$spec"
    rc=$?
    # gcc ports refuse to build while a conflicts_build port is active
    # (e.g. libunwind-headers, pulled in by cctools on legacy systems).
    # Deactivate it for the retry, as the MacPorts error suggests, and
    # reactivate it once the install finishes (as scripts/install-deps does).
    tries=0
    while [ $rc -ne 0 ] && [ $tries -lt 3 ]; do
        conflict=$(sed -n 's/.*cannot be built while \([^ ]*\) is active.*/\1/p' "$LOG" | head -1)
        [ -n "$conflict" ] || break
        tries=$((tries + 1))
        echo "$conflict blocks a dependency of $spec; deactivating it and retrying"
        sudo port -f deactivate "$conflict" </dev/null
        REACTIVATE="$REACTIVATE $conflict"
        install_spec "$spec"
        rc=$?
    done
    reactivate
    if [ $rc -eq 0 ]; then
        status="built"
    else
        status="FAILED"
        FAILED=$((FAILED + 1))
    fi
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
