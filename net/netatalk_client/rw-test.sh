#!/bin/bash
# Read-write test for netatalk_client +fuse (macFUSE FSKit backend).
#
# Usage: rw-test.sh <server> <volume> [afpc mount options...]
#   e.g. rw-test.sh 192.168.234.23 guestshare -a guest
#
# Mounts <server>:<volume> on /Volumes/<volume>, works only inside a new
# netatalk_client-test-<timestamp> directory at the volume root, and removes
# it again before unmounting. Phase 1 writes, then unmounts to drop caches;
# phase 2 remounts and verifies what the server actually stored.
#
# Run it from a Terminal.app window (or `open -a Terminal x.command`):
# macOS Local Network privacy blocks afpfsd started from tmux/SSH sessions.
# Only point it at a share where writing a test directory is allowed, and
# tell whoever runs the server before and after. Set RWLOG to also write
# the output to a file. Exits non-zero if any check fails.

if [ $# -lt 2 ]; then
    sed -n '4,5p' "$0" | sed 's/^# //'
    exit 2
fi

[ -n "$RWLOG" ] && exec > >(tee "$RWLOG") 2>&1

SERVER="$1"; VOL="$2"; shift 2
M="/Volumes/$VOL"
A=/opt/local/bin/afpc
T="netatalk_client-test-$(date +%Y%m%d-%H%M%S)"
W="$M/$T"
SRC="$(mktemp "${TMPDIR:-/tmp}/rw-test.XXXXXX")"
FAILS=0

step() { echo "=== $(date +%T) $*"; }
check() {
    if [ "$1" = "$2" ]; then
        echo "  OK $3"
    else
        echo "  FAIL $3 (got '$1', want '$2')"
        FAILS=$((FAILS + 1))
    fi
}
mnt() {
    "$A" fs mount "$@" "$SERVER:$VOL" "$M" >/dev/null
    sleep 2
    if mount | grep -qF " on $M "; then
        echo "  mounted"
    else
        echo "  MOUNT FAILED"
        rm -f "$SRC"
        exit 1
    fi
}
umnt() {
    "$A" fs unmount "$M" >/dev/null
    sleep 3
    if mount | grep -qF " on $M "; then echo "  STILL MOUNTED"; else echo "  unmounted"; fi
}

step "phase 1: mount and write ($T)"
mnt "$@"
mkdir "$W"; check $? 0 "mkdir"
printf 'hello from netatalk_client\n' > "$W/small.txt"
printf 'line2\n' >> "$W/small.txt"
head -c 16777216 /dev/urandom > "$SRC"
SUM=$(shasum -a 256 < "$SRC" | cut -d' ' -f1)
cp "$SRC" "$W/big.bin"; check $? 0 "cp 16 MB"
printf 'twenty-six bytes of text\n' > "$W/trunc1.txt"; : > "$W/trunc1.txt"
printf 'twenty-six bytes of text\n' > "$W/trunc2.txt"; truncate -s 0 "$W/trunc2.txt"
printf 'twenty-six bytes of text\n' > "$W/over.txt"; printf 'short\n' > "$W/over.txt"
mv "$W/small.txt" "$W/renamed.txt"
mkdir "$W/sub"
xattr -w org.netatalk.test yes "$W/renamed.txt"

step "phase 1: unmount (drop caches)"
umnt

step "phase 2: remount and verify from the server"
mnt "$@"
ls -la "$W"
check "$(shasum -a 256 < "$W/big.bin" | cut -d' ' -f1)" "$SUM" "16 MB checksum"
check "$(stat -f %z "$W/big.bin")" 16777216 "16 MB size"
check "$(cat "$W/renamed.txt")" "$(printf 'hello from netatalk_client\nline2')" "write, append, rename"
check "$([ -e "$W/small.txt" ] && echo present || echo absent)" absent "old name gone"
check "$(stat -f %z "$W/trunc1.txt")" 0 "truncate via O_TRUNC"
check "$(stat -f %z "$W/trunc2.txt")" 0 "truncate via ftruncate"
check "$(cat "$W/over.txt")" short "overwrite with shorter content"
check "$([ -d "$W/sub" ] && echo dir)" dir "subdirectory"
check "$(xattr -p org.netatalk.test "$W/renamed.txt" 2>&1)" yes "xattr"

step "cleanup"
rm -rf "$W"
check "$([ -e "$W" ] && echo present || echo absent)" absent "test directory removed"
rm -f "$SRC"
umnt
"$A" fs exit >/dev/null 2>&1
sleep 4
pgrep -l afpfsd || echo "  no afpfsd"

echo "FAILS=$FAILS"
step DONE
[ "$FAILS" -eq 0 ]
