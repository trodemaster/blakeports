#!/bin/bash
# Prepare a CI runner for FSKit mounts (approved by the user 2026-11-23 for
# the macOS 27 runner only). Writes outside /opt/local:
#   /Library/Filesystems/macfuse.fs             link to the port's copy
#   /Library/PrivilegedHelperTools, LaunchDaemons   macFUSE's signed helper
# It does not enable the file system extension: that is a System Settings
# approval, made once on the runner's desktop.
#
# Undo: macfuse uninstall --components privileged-helpers, then remove the link.
set -u
[ -n "${GITHUB_ACTIONS:-}" ] || { echo "CI runners only" >&2; exit 2; }
PREFIX=/opt/local
FS=$PREFIX/Library/Filesystems/macfuse.fs
APP=$FS/Contents/Resources/macfuse.app
HELPER=/Library/PrivilegedHelperTools/io.macfuse.app.launchservice.daemon
limit() { perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; }
out=
say() { echo "$*"; out+="$*%0A"; }

[ -d "$APP" ] || { echo "::error title=setup-macfuse::no macfuse.app; is macfuse installed?"; exit 1; }
if [ ! -e /Library/Filesystems/macfuse.fs ] && [ ! -L /Library/Filesystems/macfuse.fs ]; then
    sudo -n ln -s "$FS" /Library/Filesystems/macfuse.fs
fi
say "link: $(readlink /Library/Filesystems/macfuse.fs)"
open -gj "$APP"; sleep 5; pkill -f "$APP/Contents/MacOS/macfuse" || true
msg=$(limit 60 sudo -n "$APP/Contents/MacOS/macfuse" install --components privileged-helpers 2>&1 </dev/null)
say "helper install: rc=$? ${msg//$'\n'/ | }"
say "helper: $([ -e "$HELPER" ] && codesign -dv "$HELPER" 2>&1 | grep Timestamp || echo missing)"
say "daemon: $(sudo -n launchctl print system/io.macfuse.app.launchservice.daemon 2>&1 | grep -m1 -E 'state|Could not')"
say "module: $(pluginkit -m -v -A 2>/dev/null | grep -i fsmodule.macfuse | awk '{print $1}' | tr '\n' ' ')"
say "session: $(launchctl managername), console user $(stat -f %Su /dev/console)"
echo "::notice title=setup-macfuse::$out"
