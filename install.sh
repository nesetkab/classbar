#!/bin/sh
set -eu

REPO="nesetkab/classbar"
LABEL="local.classbar"
APP="$HOME/Applications/ClassBar.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

stop_agent() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
}

if [ "${1:-}" = "uninstall" ]; then
    stop_agent
    rm -f "$AGENT"
    rm -rf "$APP"
    echo "ClassBar removed. Your settings are still in ~/Library/Application Support/classbar."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ClassBar..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/ClassBar.zip" -o "$tmp/ClassBar.zip"
ditto -x -k "$tmp/ClassBar.zip" "$tmp"

stop_agent
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$APP"
ditto "$tmp/ClassBar.app" "$APP"

cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/ClassBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$AGENT" 2>/dev/null || { sleep 1; launchctl bootstrap "$DOMAIN" "$AGENT"; }
launchctl kickstart -k "$DOMAIN/$LABEL"

echo "ClassBar is running. Look for the cat in your menu bar, then click the gear to set it up."
