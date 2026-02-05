#!/bin/bash
set -e

# Define directories
APP_NAME="PL2303Term"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

echo "Building $APP_NAME..."
swift build -c release

echo "Creating bundle structure if needed..."
mkdir -p "$MACOS_DIR"

echo "Copying executable to bundle..."
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Create Info.plist if it doesn't exist (basic version)
if [ ! -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo "Creating Info.plist..."
    cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
</dict>
</plist>
EOF
fi

echo "Build complete! App located at $APP_BUNDLE"
