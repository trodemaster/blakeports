#!/bin/bash
# on-mirror.sh — is a binary archive already on an official MacPorts mirror?
#
# Clients list the official archive mirrors (fcix, MIT) in archive_sites.conf
# next to packages.jibb.tv, so an archive a mirror already serves is dead
# weight in our cache. submit-archive.sh asks this before copying an archive,
# and prune-cache.sh before keeping one.
#
# Usage:
#   ./on-mirror.sh <port>/<archive>.tbz2
#
# Exits 0 if any mirror answers 200 for that path, 1 if none does. Any other
# answer (404, timeout, no network) counts as "not mirrored", so a mirror
# outage makes us cache too much, never too little.
#
# Environment:
#   OFFICIAL_MIRRORS  space-separated archive base URLs (default: fcix, then
#                     MIT over plain http, which 10.5's TLS can still reach)
#
# Dependencies: bash 3.2, curl — runs on Mac OS X 10.5.
set -u

OFFICIAL_MIRRORS="${OFFICIAL_MIRRORS:-https://mirror.fcix.net/macports/packages http://bos.us.packages.macports.org}"
# MacPorts' curl first: the system curl on old OS X can't do modern TLS.
CURL=/opt/local/bin/curl
[ -x "$CURL" ] || CURL=curl

path="${1:?usage: $0 <port>/<archive>.tbz2}"
for base in $OFFICIAL_MIRRORS; do
    code=$("$CURL" -s -o /dev/null -I --connect-timeout 5 --max-time 15 \
        -w '%{http_code}' "${base%/}/${path}" 2>/dev/null)
    [ "$code" = "200" ] && exit 0
done
exit 1
