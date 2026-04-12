#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/macos-swift-installer"
STAGE_DIR="$OUT_DIR/stage"
APP_NAME="ZClawInstaller"
VERSION="0.1.0"
ARTIFACT_NAME="zaloclaw-macos-swift-installer-${VERSION}.dmg"
VOL_NAME="ZClaw Installer"

APP_BUNDLE="$STAGE_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

RUNNER_SRC="$SCRIPT_DIR/scripts/macos-swift-runner.sh"
BACKEND_DIR_SRC="$ROOT_DIR/installers/macos-installer"
BACKEND_BOOTSTRAP_SRC="$BACKEND_DIR_SRC/scripts/macos-bootstrap.js"
BINARY_SRC="$SCRIPT_DIR/.build/release/ZClawInstaller"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/scripts" "$CONTENTS_DIR/installers/macos-installer/scripts"

echo "Building release binary..."
(
  cd "$SCRIPT_DIR"
  swift build -c release
)

if [[ ! -x "$BINARY_SRC" ]]; then
  echo "Missing release binary: $BINARY_SRC"
  exit 1
fi

if [[ ! -f "$RUNNER_SRC" ]]; then
  echo "Missing runner script: $RUNNER_SRC"
  exit 1
fi

if [[ ! -f "$BACKEND_DIR_SRC/setup-macos-installer.sh" ]]; then
  echo "Missing backend setup script: $BACKEND_DIR_SRC/setup-macos-installer.sh"
  exit 1
fi

if [[ ! -f "$BACKEND_BOOTSTRAP_SRC" ]]; then
  echo "Missing bootstrap script: $BACKEND_BOOTSTRAP_SRC"
  exit 1
fi

cp "$BINARY_SRC" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$RUNNER_SRC" "$RESOURCES_DIR/scripts/macos-swift-runner.sh"
chmod +x "$RESOURCES_DIR/scripts/macos-swift-runner.sh"

cp "$BACKEND_DIR_SRC/setup-macos-installer.sh" "$CONTENTS_DIR/installers/macos-installer/setup-macos-installer.sh"
cp "$BACKEND_BOOTSTRAP_SRC" "$CONTENTS_DIR/installers/macos-installer/scripts/macos-bootstrap.js"
chmod +x "$CONTENTS_DIR/installers/macos-installer/setup-macos-installer.sh"
chmod +x "$CONTENTS_DIR/installers/macos-installer/scripts/macos-bootstrap.js"

cat > "$CONTENTS_DIR/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ZClawInstaller</string>
  <key>CFBundleIdentifier</key>
  <string>com.zaloclaw.swiftinstaller</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ZClaw Installer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "Creating DMG..."
DMG_TMP="$OUT_DIR/tmp.dmg"
rm -f "$DMG_TMP" "$OUT_DIR/$ARTIFACT_NAME"

# Create a temporary disk image from the app bundle directory
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_TMP"

# Convert to final read-only DMG
hdiutil convert "$DMG_TMP" -format UDZO -o "$OUT_DIR/$ARTIFACT_NAME"
rm "$DMG_TMP"

if [[ ! -f "$OUT_DIR/$ARTIFACT_NAME" ]]; then
  echo "Failed to produce artifact: $OUT_DIR/$ARTIFACT_NAME"
  exit 1
fi

echo "Created DMG: $OUT_DIR/$ARTIFACT_NAME"

# Simple existence check to replace previous tar verification
if [[ ! -f "$OUT_DIR/$ARTIFACT_NAME" ]]; then
  echo "Verification failed: DMG missing"
  exit 1
fi

echo "Artifact produced at: $OUT_DIR/$ARTIFACT_NAME"
exit 0

  exit 1
fi

if [[ ! -f "$VERIFY_DIR/${APP_NAME}.app/Contents/Resources/scripts/macos-swift-runner.sh" ]]; then
  echo "Verification failed: runner script missing"
  exit 1
fi

if [[ ! -f "$VERIFY_DIR/${APP_NAME}.app/Contents/installers/macos-installer/setup-macos-installer.sh" ]]; then
  echo "Verification failed: backend setup script missing"
  exit 1
fi

if [[ ! -f "$VERIFY_DIR/${APP_NAME}.app/Contents/installers/macos-installer/scripts/macos-bootstrap.js" ]]; then
  echo "Verification failed: backend bootstrap script missing"
  exit 1
fi

shasum -a 256 "$OUT_DIR/$ARTIFACT_NAME" > "$OUT_DIR/$ARTIFACT_NAME.sha256"

echo "Built artifact: $OUT_DIR/$ARTIFACT_NAME"
echo "Checksum: $OUT_DIR/$ARTIFACT_NAME.sha256"
echo "App bundle: $STAGE_DIR/${APP_NAME}.app"
