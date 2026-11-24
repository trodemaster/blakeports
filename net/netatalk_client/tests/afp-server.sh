#!/bin/bash
# Disposable Netatalk server (port:netatalk) for the netatalk_client tests.
# Meant for CI runners; see .github/workflows/build-netatalk_client.yml.
#
# Usage: afp-server.sh up|down|log
#
# Listens on 127.0.0.1:$AFP_TEST_PORT only, with its own configuration, data
# and CNID database under $AFP_TEST_DIR. The installed afp.conf and the
# launchd service are not used. Guests act as the invoking user, so no
# account or password is created. Volumes: afpfs_test, afpfs_test2.

set -eu
DIR=${AFP_TEST_DIR:?set AFP_TEST_DIR to a scratch directory}
PORT=${AFP_TEST_PORT:-10548}
PREFIX=${PREFIX:-/opt/local}

# afpd creates its CNID database as root. The name check keeps a mistaken
# AFP_TEST_DIR from being deleted.
clean() {
    case "$DIR" in /*/afp-test) sudo -n rm -rf "$DIR" ;; *) echo "leaving $DIR" >&2 ;; esac
}
probe() { "$PREFIX/bin/afpgetstatus" "afp://127.0.0.1:$PORT" 2>&1; }

up() {
    if pgrep -x netatalk >/dev/null; then
        echo "a netatalk is already running; not starting another" >&2; return 1
    fi
    clean
    mkdir -p "$DIR/vol1" "$DIR/vol2" "$DIR/vol3" "$DIR/cnid"
    cat > "$DIR/afp.conf" <<CONF
[Global]
afp listen = 127.0.0.1
afp port = $PORT
log file = $DIR/afpd.log
log level = default:info
server name = afpfs_testsrv
uam list = uams_guest.so uams_dhx2.so
guest account = $(id -un)
zeroconf = no
spotlight = no
cnid scheme = sqlite
vol dbpath = $DIR/cnid

[afpfs_test_nounix]
path = $DIR/vol3
volume name = afpfs_test_nounix
unix priv = no

[afpfs_test2]
path = $DIR/vol2
volume name = afpfs_test2

[afpfs_test]
path = $DIR/vol1
volume name = afpfs_test
CONF
    : > "$DIR/afpd.log"
    sudo -n "$PREFIX/sbin/netatalk" -d -F "$DIR/afp.conf" > "$DIR/netatalk.out" 2>&1 &
    for _ in $(seq 1 60); do
        if probe | grep -q afpfs_testsrv; then echo "afpd ready on 127.0.0.1:$PORT"; return 0; fi
        sleep 0.5
    done
    echo "afpd did not come up" >&2; probe >&2 || true
    cat "$DIR/netatalk.out" "$DIR/afpd.log" >&2; return 1
}

down() { stop; clean; }
stop() {
    # Only the server started with this configuration
    sudo -n pkill -TERM -f "netatalk -d -F $DIR/afp.conf" || true
    for _ in $(seq 1 40); do pgrep -f -- "-F $DIR/afp.conf" >/dev/null || break; sleep 0.25; done
    sudo -n pkill -KILL -f -- "-F $DIR/afp.conf" || true
    return 0
}

case "${1:-}" in
up) up ;; down) down ;; log) cat "$DIR/afpd.log" ;;
*) echo "usage: $0 up|down|log" >&2; exit 2 ;;
esac
