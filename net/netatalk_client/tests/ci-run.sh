#!/bin/bash
# Run a test command in a GitHub Actions step. Passes its output through,
# and on failure (or a skip) repeats the lines that matter as an annotation,
# so a result can be read through the API without downloading the log.
#
# Usage: ci-run.sh <title> command [args...]
title=$1; shift
log=$(mktemp "${TMPDIR:-/tmp}/ci-run.XXXXXX")
"$@" 2>&1 | tee "$log"; rc=${PIPESTATUS[0]}
annotate() {  # annotate <level> <text>
    local t=${2//'%'/'%25'}; t=${t//$'\r'/}; t=${t//$'\n'/'%0A'}
    echo "::$1 title=$title::${t:0:3500}"
}
if [ "$rc" -ne 0 ]; then
    annotate error "$(grep -E -A8 '^(not ok|Bail out|Dubious|[^#]*Failed [0-9]|.*(rror|usage):)' "$log" | grep -v '^ok ' | head -60; echo "[last lines]"; tail -8 "$log")"
else
    annotate notice "$(grep -c '^ok ' "$log") ok; $(grep -E '# SKIP|# skip|# TODO|^# failed|^Result|^Files=' "$log" | head -15)"
fi
rm -f "$log"
exit "$rc"
