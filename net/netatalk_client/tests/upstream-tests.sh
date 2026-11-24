#!/bin/bash
# Run upstream's installed-client tests, from the commit the Portfile builds,
# against afp-server.sh. Usage: upstream-tests.sh test.t...
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PORT=${AFP_TEST_PORT:-10548}
COMMIT=$(awk '$1 == "github.setup" { print $4 }' "$HERE/../Portfile")
SRC=${AFP_TEST_DIR:?}/upstream
export PATH=/opt/local/bin:$PATH
mkdir -p "$SRC"
curl -fsSL "https://github.com/Netatalk/netatalk-client/archive/$COMMIT.tar.gz" | tar xz -C "$SRC" --strip-components 1
cd "$SRC/test/integration"
# The tests name a local account and the default port; ours is guest on $PORT.
sed -i '' -e "s#afp://test_usr:test_pwd@localhost#afp://127.0.0.1:$PORT#g" \
    -e "s#afp://localhost#afp://127.0.0.1:$PORT#g" \
    -e 's#\${AFP_USER}:\${AFP_PASS}\\@##g' \
    -e "s#= 'localhost';#= '127.0.0.1:$PORT';#" "$@"
grep -n "127.0.0.1:$PORT" "$@"
exec /usr/bin/prove -v "$@"
