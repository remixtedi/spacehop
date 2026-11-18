#!/bin/bash
# Builds spacehop from this folder, turns off the system's animated Ctrl+arrow
# shortcuts, and starts spacehop at login with a user LaunchAgent.
# Layout follows noswoosh scripts/install.sh (see AUDIT.md, "Install and uninstall").
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_DIR="$HOME/.local/bin"
LABEL="com.remixtedi.spacehop"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/spacehop.log"

command -v swiftc >/dev/null || { echo "swiftc not found. Install the Xcode Command Line Tools: xcode-select --install"; exit 1; }

echo "==> Signing identity (one time)"
scripts/setup-signing.sh

echo "==> Building and scanning"
scripts/build.sh

echo "==> Installing to $BIN_DIR"
mkdir -p "$BIN_DIR"
# Stop the running copy and remove the old file before copying: overwriting a
# running signed binary in place makes the kernel kill later launches of it.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$BIN_DIR/spacehop"
cp build/spacehop "$BIN_DIR/spacehop"

echo "==> Turning off the system's animated Ctrl+arrow shortcuts"
"$BIN_DIR/spacehop" setup

echo "==> Installing LaunchAgent $LABEL"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/spacehop</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"

cat <<EOF

Installed. One step left, and only you can do it:

  System Settings > Privacy & Security > Accessibility: turn on "spacehop".
  (macOS asks just now. If it isn't listed: "+", Cmd+Shift+G, $BIN_DIR/spacehop)

spacehop restarts itself once it's allowed. Then Ctrl+Left/Right and a
three-finger swipe switch desktops instantly.

Log:       $LOG
Uninstall: scripts/uninstall.sh
EOF
