#!/bin/bash
set -e

echo "Building Toodoos..."
swift build -c release 2>&1

INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
cp .build/release/Toodoos "$INSTALL_DIR/toodoos"
echo "Installed to $INSTALL_DIR/toodoos"

# Create LaunchAgent for auto-start
PLIST="$HOME/Library/LaunchAgents/com.toodoos.app.plist"
cat > "$PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.toodoos.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>INSTALL_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
sed -i '' "s|INSTALL_PATH|$INSTALL_DIR/toodoos|g" "$PLIST"

echo "LaunchAgent created at $PLIST"
echo ""
echo "To start now:  $INSTALL_DIR/toodoos &"
echo "To auto-start: launchctl load $PLIST"
echo ""
echo "Configure Discord webhook in ~/.toodoos.conf"
echo "Hotkey: Ctrl+Option+T"
