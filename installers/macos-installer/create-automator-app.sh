#!/bin/bash
set -e

# Create macOS Automator-based installer app
# This generates a native .app that wraps the setup process elegantly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ZaloClawSetup"
APP_BUNDLE="$SCRIPT_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "Creating $APP_NAME.app bundle..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create Info.plist
cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>launcher</string>
	<key>CFBundleIdentifier</key>
	<string>com.zaloclaw.setup</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>ZaloClawSetup</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.12</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSBuildVersion</key>
	<string>0.1.0</string>
</dict>
</plist>
EOF

# Create launcher executable
cat > "$MACOS_DIR/launcher" <<'EOF'
#!/bin/bash
set -e

# Get the app bundle directory (two levels up from MacOS)
APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$APP_DIR/.." && pwd)"

# Show welcome notification
osascript <<APPLESCRIPT
display notification "Starting ZaloClawSetup..." with title "ZaloClawSetup"
APPLESCRIPT

# Run the UI wrapper script
if [[ -f "$SCRIPT_DIR/setup-macos-ui.sh" ]]; then
  bash "$SCRIPT_DIR/setup-macos-ui.sh"
  EXIT_CODE=$?
  
  if [[ $EXIT_CODE -eq 0 ]]; then
    osascript <<APPLESCRIPT
display notification "Setup completed successfully!" with title "ZaloClawSetup" subtitle "Check setup-state.json for details"
APPLESCRIPT
  else
    osascript <<APPLESCRIPT
display alert "Setup Failed" message "Exit code: $EXIT_CODE. Check logs for details." buttons {"OK"} default button 1
APPLESCRIPT
    exit $EXIT_CODE
  fi
else
  osascript <<APPLESCRIPT
display alert "Error" message "setup-macos-ui.sh not found in parent directory" buttons {"OK"} default button 1
APPLESCRIPT
  exit 1
fi
EOF

chmod +x "$MACOS_DIR/launcher"

# Create a simple script document for better Finder appearance
cat > "$MACOS_DIR/ZaloClawSetup" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/launcher"
EOF

chmod +x "$MACOS_DIR/ZaloClawSetup"

# Create PkgInfo for proper app identification
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Create a link to setup files in Resources for easy access
ln -sf "$SCRIPT_DIR/setup-macos-ui.sh" "$RESOURCES_DIR/setup-macos-ui.sh"
ln -sf "$SCRIPT_DIR/scripts" "$RESOURCES_DIR/scripts"

# Placeholder icon (will appear as generic document icon until a real .icns is provided)
touch "$RESOURCES_DIR/AppIcon.png"

echo "✓ Created $APP_BUNDLE"
echo ""
echo "To use the installer:"
echo "  1. Move $APP_BUNDLE to /Applications/ (or keep in place)"
echo "  2. Double-click ZaloClawSetup.app to run"
echo "  3. Complete setup dialogs and wait for completion"
echo ""
echo "To package for distribution:"
echo "  open $APP_BUNDLE  # Test it first"
echo "  ditto -c -k --sequesterRsrc $APP_BUNDLE ZaloClawSetup-0.1.0.zip  # Creates distributable zip"
echo ""
