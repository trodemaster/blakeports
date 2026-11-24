#!/bin/bash
# Live tests of netatalk_client +fuse over macFUSE's FSKit backend (macOS 27).
#
# Usage: fskit-test.sh [group...]        (default: every group)
#
# Prints TAP and exits non-zero if a test fails. Needs the server from
# afp-server.sh and macFUSE with its FSKit module enabled and no kernel
# extension; without the latter it skips, as a refused mount only leaves
# dialogs on the desktop. Meant for CI runners, not for a workstation.
#
# Each group maps to one worklist issue (see WORKLIST.md). Results are read
# from the server's side where possible; a mount can answer from its cache.

AFPC=${AFPC:-/opt/local/bin/afpc}
PORT=${AFP_TEST_PORT:-10548}
DIR=${AFP_TEST_DIR:?set AFP_TEST_DIR, as for afp-server.sh}
V=$DIR/vol1
HELPER=/Library/PrivilegedHelperTools/io.macfuse.app.launchservice.daemon
HOST=127.0.0.1
M=/Volumes/afpfs_test
M2=/Volumes/afpfs_test2
PATH=$(dirname "$AFPC"):/opt/local/bin:$PATH; export PATH   # afpc runs afpfsd from PATH
CRASHES=$HOME/Library/Logs/DiagnosticReports
N=0 FAILS=0 OUT= TODO=

limit() { perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; }  # a hung mount must not hang the suite
ok() {  # ok <status> <name>
    N=$((N + 1))
    if [ "$1" -eq 0 ]; then echo "ok $N - $2"; else
        # A TODO names a known cause outside this port; it is reported, not counted.
        echo "not ok $N - $2${TODO:+ # TODO $TODO}"; [ -n "$TODO" ] || FAILS=$((FAILS + 1))
        [ -n "$OUT" ] && printf '%s\n' "$OUT" | sed 's/^/#   /'
    fi
    OUT=
}
is() { [ "$1" = "$2" ]; ok $? "$3"; [ "$1" = "$2" ] || printf '#   got  %s\n#   want %s\n' "$1" "$2"; }
run() {  # to a file: a daemon that keeps the descriptor must not block us
    local t rc; t=$(mktemp "${TMPDIR:-/tmp}/fskit.XXXXXX"); limit 25 "$@" > "$t" 2>&1 </dev/null; rc=$?
    OUT=$(cat "$t"); rm -f "$t"; return $rc
}
mounted() {  # 2 if mount(8) does not answer: neither mounted nor unmounted
    local t; t=$(limit 10 /sbin/mount) || return 2; grep -qF " on $1 (" <<< "$t"
}
wait_for() {  # wait_for <seconds> <command...>
    local i; for ((i = 0; i < $1 * 5; i++)); do "${@:2}" && return 0; sleep 0.2; done; return 1
}
unmounted() { mounted "$1"; [ $? -eq 1 ]; }
daemons() { pgrep -f "afpfsd --socket-id" | wc -l | tr -d ' '; }
no_daemon() { [ "$(daemons)" = 0 ]; }
mnt() { run "$AFPC" fs mount -a guest -o "$PORT" "${@:3}" "$HOST:$1" "$2" && wait_for 5 mounted "$2"; }
umnt() { run "$AFPC" fs unmount "$1"; }
mark() { MARK=$(wc -l < "$DIR/afpd.log"); touch "${TMPDIR:-/tmp}/fskit-test.mark"; sleep 1; }
logged_out() { tail -n +$((MARK + 1)) "$DIR/afpd.log" | grep -q "AFP logout by"; }
no_crash() { [ -z "$(find "$CRASHES" -name 'afpfsd*' -newer "${TMPDIR:-/tmp}/fskit-test.mark" 2>/dev/null)" ]; }
reset() {
    local m
    for m in "$M" "$M2"; do mounted "$m" && { limit 10 /sbin/umount "$m" || limit 10 /sbin/umount -f "$m"; } >/dev/null 2>&1; done
    limit 20 "$AFPC" fs exit >/dev/null 2>&1; pkill -x afpfsd; wait_for 5 no_daemon
    rm -rf "${DIR:?}"/vol1/* "${DIR:?}"/vol2/*
}

t_backend() {
    [ ! -e /dev/macfuse0 ]; ok $? "backend: no kernel extension is loaded"
    mnt afpfs_test "$M"; ok $? "backend: mounts without /dev/macfuse0"
    limit 10 /sbin/mount | grep -F " on $M (" | grep -q fskit; ok $? "backend: the mount is FSKit's"
    run "$AFPC" fs status; ok $? "backend: status answers"
    umnt "$M"
}
t_mountpoint() {
    [ ! -e "$M" ]; ok $? "mountpoint: absent before the mount"
    mnt afpfs_test "$M"; ok $? "mountpoint: macFUSE creates it under /Volumes"
    umnt "$M"; wait_for 5 test ! -e "$M"; ok $? "mountpoint: the unmount removes it"
    run "$AFPC" fs mount -a guest -o "$PORT" "$HOST:afpfs_test" /Volumes/no/such; [ $? -ne 0 ]
    ok $? "mountpoint: refuses a missing path deeper in /Volumes"
    run "$AFPC" fs mount -a guest -o "$PORT" "$HOST:afpfs_test" "$HOME/no-such-dir"; [ $? -ne 0 ]
    ok $? "mountpoint: refuses a missing path outside /Volumes"
}
t_unmount() {
    mark; mnt afpfs_test "$M"; umnt "$M"; ok $? "unmount: afpc fs unmount succeeds"
    wait_for 5 unmounted "$M"; ok $? "unmount: the volume is gone"
    wait_for 5 no_daemon; ok $? "unmount: the mount's daemon ends"
    wait_for 5 logged_out; ok $? "unmount: the server saw a clean logout"
    no_crash; ok $? "unmount: no crash report"
    mark; mnt afpfs_test "$M"; run /sbin/umount "$M"; ok $? "unmount: umount(8) works"
    wait_for 5 no_daemon; ok $? "unmount: umount(8) ends the daemon"
    wait_for 5 logged_out; ok $? "unmount: umount(8) logs out cleanly"
    no_crash; ok $? "unmount: no crash report after umount(8)"
}
t_busy() {
    mnt afpfs_test "$M"; echo x > "$M/held"; exec 8< "$M/held"
    umnt "$M"; [ $? -ne 0 ]; ok $? "busy: the unmount of a busy volume is refused"
    mounted "$M"; ok $? "busy: the volume stays mounted"
    is "$(limit 10 cat "$M/held")" x "busy: and still works"
    exec 8<&-; sleep 1; umnt "$M"; ok $? "busy: unmounts once free"
}
t_exit() {
    mark; mnt afpfs_test "$M"; run "$AFPC" fs exit; ok $? "exit: afpc fs exit succeeds"
    ! printf '%s' "$OUT" | grep -q 'Broken pipe'; ok $? "exit: no 'Broken pipe'"
    wait_for 12 unmounted "$M"; ok $? "exit: the volume is unmounted"
    wait_for 12 no_daemon; ok $? "exit: the daemon ends"
    wait_for 5 logged_out; ok $? "exit: the server saw a clean logout"
    no_crash; ok $? "exit: no crash report"
    reset; mnt afpfs_test "$M" && mnt afpfs_test2 "$M2"; ok $? "exit: two volumes mount"
    run "$AFPC" fs exit; wait_for 15 unmounted "$M" && wait_for 15 unmounted "$M2"
    ok $? "exit: both are unmounted"
    reset; mark; mnt afpfs_test "$M"; local p; p=$(pgrep -f "afpfsd --socket-id"); kill -TERM $p
    wait_for 12 unmounted "$M"; ok $? "exit: SIGTERM to the daemon unmounts"
    wait_for 5 no_daemon; ok $? "exit: SIGTERM ends the daemon"
    wait_for 5 logged_out; ok $? "exit: SIGTERM logs out cleanly"
    no_crash; ok $? "exit: no crash report after SIGTERM"
    # The loop reads no replies while it ends, so late writes are at risk.
    local how
    for how in exit SIGTERM; do
        reset; mnt afpfs_test "$M"; head -c 1048576 /dev/zero | tr '\0' x > "$M/late"
        if [ $how = exit ]; then run "$AFPC" fs exit; else pkill -TERM -f "afpfsd --socket-id"; fi
        SECONDS=0; wait_for 20 unmounted "$M"; ok $? "exit: $how right after a write unmounts"
        wait_for 5 no_daemon; ok $? "exit: $how right after a write ends the daemon"; echo "# ended after $SECONDS s"
        is "$(stat -f %z "$V/late")" 1048576 "exit: $how right after a write keeps it"
    done
}
t_dead() {
    mnt afpfs_test "$M"; pkill -9 -f "afpfsd --socket-id"; sleep 1
    local t=$SECONDS; run ls "$M"; local rc=$?; [ $rc -ne 142 ]; ok $? "dead daemon: access fails instead of hanging"
    echo "# ls ended with $rc after $((SECONDS - t)) s"
    local e; e=$(limit 10 perl -e 'stat($ARGV[0]) ? print 0 : print $!+0' "$M")   # upstream expects ENOTCONN, 57
    wait_for 15 unmounted "$M"; ok $? "dead daemon: the manager releases the mount"
    echo "# stat(2) of the dead mount: errno ${e:-none, no answer}"
    mounted "$M" && limit 15 /sbin/umount -f "$M"
    mnt afpfs_test "$M"; ok $? "dead daemon: the path mounts again"
    umnt "$M"
}
t_foreground() {
    mark; "$AFPC" fs mount --foreground -a guest -o "$PORT" "$HOST:afpfs_test" "$M" >/dev/null 2>&1 & local p=$!
    wait_for 10 mounted "$M"; ok $? "foreground: mounts"
    # A non-interactive shell starts background jobs with SIGINT ignored.
    kill -TERM $p; wait_for 12 unmounted "$M"; ok $? "foreground: SIGTERM unmounts"
    wait $p; wait_for 5 logged_out; ok $? "foreground: the server saw a clean logout"
}
t_data() {
    local src sum; src=$(mktemp "${TMPDIR:-/tmp}/fskit.XXXXXX"); head -c 16777216 /dev/urandom > "$src"
    sum=$(shasum -a 256 < "$src" | cut -d' ' -f1)
    mnt afpfs_test "$M"; mkdir "$M/d"; ok $? "data: mkdir"
    cp "$src" "$M/d/big"; ok $? "data: cp 16 MB"
    printf 'one\n' > "$M/d/a"; printf 'two\n' >> "$M/d/a"; mv "$M/d/a" "$M/d/b"
    for f in t1 t2 t3 t4; do printf 'twenty-six bytes of text..\n' > "$M/d/$f"; done
    : > "$M/d/t1"; truncate -s 0 "$M/d/t2"; printf 'short\n' > "$M/d/t3"; truncate -s 100 "$M/d/t4"
    ln -s b "$M/d/link"; ok $? "data: symlink"
    chmod 640 "$M/d/b"; touch -t 202001020304.05 "$M/d/b"
    is "$(stat -f %Sm -t %Y%m%d%H%M%S "$V/d/b")" 20200102030405 "data: mtime reached the server"
    xattr -w org.netatalk.test yes "$M/d/b"; ok $? "data: xattr write"
    printf 'rsrc' > "$M/d/b/..namedfork/rsrc"; ok $? "data: resource fork write"
    mkdir "$M/d/empty" && rmdir "$M/d/empty"; ok $? "data: rmdir"
    umnt "$M"; ok $? "data: unmount"
    is "$(shasum -a 256 "$V/d/big" | cut -d' ' -f1)" "$sum" "data: server has the 16 MB file"
    is "$(cat "$V"/d/b)" "$(printf 'one\ntwo')" "data: server has write, append, rename"
    is "$(stat -f %z "$V"/d/t1)" 0 "data: O_TRUNC reached the server"
    is "$(stat -f %z "$V"/d/t2)" 0 "data: ftruncate to 0 reached the server"
    is "$(cat "$V"/d/t3)" short "data: shorter overwrite left no tail"
    is "$(stat -f %z "$V"/d/t4)" 100 "data: ftruncate to longer"
    is "$(stat -f %Lp "$V/d/b")" 640 "data: chmod reached the server"
    mnt afpfs_test "$M"
    is "$(limit 30 shasum -a 256 < "$M/d/big" | cut -d' ' -f1)" "$sum" "data: 16 MB reads back after a remount"
    is "$(limit 10 readlink "$M/d/link")" b "data: symlink reads back"
    is "$(limit 10 xattr -p org.netatalk.test "$M/d/b" 2>&1)" yes "data: xattr reads back"
    is "$(limit 10 cat "$M/d/b/..namedfork/rsrc" 2>&1)" rsrc "data: resource fork reads back"
    # Set again: the xattr and resource fork writes may have changed it.
    touch -t 202001020304.05 "$M/d/b"
    is "$(limit 10 stat -f %Sm -t %Y%m%d%H%M%S "$M/d/b")" 20200102030405 "data: mtime reads back"
    xattr -d org.netatalk.test "$M/d/b"; limit 10 xattr -p org.netatalk.test "$M/d/b" >/dev/null 2>&1; [ $? -ne 0 ]
    ok $? "data: xattr removal"
    limit 30 rm -rf "$M/d"; ok $? "data: rm -rf"
    is "$(ls -A "$V" | grep -v -E '^(\._|\.DS_Store|\.AppleDB)')" "" "data: server directory is empty"
    umnt "$M"; rm -f "$src"
}
t_remote() {
    mnt afpfs_test "$M"; echo first > "$V/r"
    wait_for 10 test -e "$M/r"; ok $? "remote: a file made on the server appears"
    is "$(limit 10 cat "$M/r")" first "remote: and reads"
    TODO="macFUSE issue 1222: FSKit keeps the old size"
    echo a-much-longer-second > "$V/r"; sleep 6
    is "$(limit 10 cat "$M/r")" a-much-longer-second "remote: growth on the server is seen"
    echo x > "$V/r"; sleep 6
    is "$(limit 10 cat "$M/r" | xxd -p)" "$(printf 'x\n' | xxd -p)" "remote: shrinking leaves no padding"
    TODO=
    rm "$V/r"; wait_for 10 test ! -e "$M/r"; ok $? "remote: removal on the server is seen"
    umnt "$M"
}

preflight() {
    # Every mount that macFUSE refuses leaves a dialog on the desktop, so try
    # once and give up, rather than failing (and prompting) in each group.
    local why="no FSKit mount; enable macFUSE's file system extension and helper"
    if mnt afpfs_test "$M"; then
        # A first access can wait for a Network Volumes prompt.
        limit 60 ls "$M" >/dev/null 2>&1 && { umnt "$M"; return 0; }
        why="the volume mounts but cannot be read; a privacy prompt may be waiting"
    fi
    echo "Bail out! $why"
    printf '%s\n' "$OUT" | sed 's/^/# /'
    /usr/bin/log show --last 1m --style compact --predicate 'process == "io.macfuse.app.launchservice.daemon" OR (process == "afpfsd" AND NOT subsystem BEGINSWITH "com.apple")' 2>/dev/null |
        grep -E ' E |not enabled|[Mm]ount|rror' | tail -8 | cut -c1-200 | sed 's/^/# /'
    exit 1
}

if ! pluginkit -m -i io.macfuse.app.fsmodule.macfuse 2>/dev/null | grep -q macfuse || [ ! -e "$HELPER" ]; then
    echo "1..0 # SKIP macFUSE's FSKit module or privileged helper is not set up on this host"
    exit 0
fi
trap reset EXIT
reset >/dev/null 2>&1
preflight
echo "# $(sw_vers -productVersion) $("$AFPC" -V 2>/dev/null | head -1) macfuse $(port -q installed macfuse 2>/dev/null | sed -n 's/.*@\([0-9.]*\).*(active).*/\1/p')"
for g in "${@:-}"; do
    for g in ${g:-backend mountpoint unmount busy exit dead foreground data remote}; do
        reset >/dev/null 2>&1; echo "# --- $g"; "t_$g"
    done
done
echo "1..$N"; echo "# failed: $FAILS"
[ "$FAILS" -eq 0 ]
