#!/bin/bash
set -e

echo "Building release..."
swift build -c release 2>&1

APP_NAME="Toodoos"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Create .app structure only if it doesn't exist yet (preserves accessibility permissions)
mkdir -p "$MACOS" "$RESOURCES"

# Overwrite binary in-place
cp -f .build/release/Toodoos "$MACOS/$APP_NAME"

# Write Info.plist only if missing
if [ ! -f "$CONTENTS/Info.plist" ]; then
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Toodoos</string>
    <key>CFBundleDisplayName</key>
    <string>Toodoos</string>
    <key>CFBundleIdentifier</key>
    <string>com.toodoos.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Toodoos</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "Updated $APP_DIR"
echo ""
echo "To launch: open $APP_DIR"
echo "To auto-start: add Toodoos to System Settings → General → Login Items"
