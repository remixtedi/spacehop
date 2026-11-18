#!/bin/bash
# Removes spacehop and everything install.sh made, and turns the system's
# animated Ctrl+arrow shortcuts back on.
set -uo pipefail

BIN_DIR="$HOME/.local/bin"
LABEL="com.remixtedi.spacehop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> Stopping and removing LaunchAgent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

echo "==> Turning the system's Ctrl+arrow shortcuts back on"
if [ -x "$BIN_DIR/spacehop" ]; then
    "$BIN_DIR/spacehop" teardown
else
    echo "    spacehop binary missing. Turn them on in System Settings >"
    echo "    Keyboard > Keyboard Shortcuts > Mission Control."
fi

echo "==> Removing binary and log"
rm -f "$BIN_DIR/spacehop"
rm -f "$HOME/Library/Logs/spacehop.log"

cat <<EOF

spacehop is removed. One manual step: remove "spacehop" from
System Settings > Privacy & Security > Accessibility (select it, then "-").
EOF
