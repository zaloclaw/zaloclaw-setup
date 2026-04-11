#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$ROOT_DIR/dist/macos-installer"
VERSION="0.1.0"
ARTIFACT_NAME="zaloclaw-macos-local-setup-${VERSION}.tar.gz"
STAGE_DIR="$OUT_DIR/stage"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/macos-installer/scripts"

# Always regenerate the Automator .app to avoid stale machine-specific symlinks.
bash "$SCRIPT_DIR/create-automator-app.sh" > /dev/null 2>&1

cp "$SCRIPT_DIR/setup-macos-installer.sh" "$STAGE_DIR/macos-installer/"
cp "$SCRIPT_DIR/setup-macos-ui.sh" "$STAGE_DIR/macos-installer/"
cp "$SCRIPT_DIR/setup-macos-ui.command" "$STAGE_DIR/macos-installer/"
cp -r "$SCRIPT_DIR/ZaloClawSetup.app" "$STAGE_DIR/macos-installer/"
cp "$SCRIPT_DIR/scripts/macos-bootstrap.js" "$STAGE_DIR/macos-installer/scripts/"
chmod +x "$STAGE_DIR/macos-installer/setup-macos-installer.sh"
chmod +x "$STAGE_DIR/macos-installer/setup-macos-ui.sh"
chmod +x "$STAGE_DIR/macos-installer/setup-macos-ui.command"
chmod +x "$STAGE_DIR/macos-installer/scripts/macos-bootstrap.js"

(
  cd "$STAGE_DIR"
  tar -czf "$OUT_DIR/$ARTIFACT_NAME" macos-installer
)

if [[ ! -f "$OUT_DIR/$ARTIFACT_NAME" ]]; then
  echo "Failed to produce artifact: $OUT_DIR/$ARTIFACT_NAME"
  exit 1
fi

TMP_VERIFY_DIR="$OUT_DIR/verify"
rm -rf "$TMP_VERIFY_DIR"
mkdir -p "$TMP_VERIFY_DIR"

tar -xzf "$OUT_DIR/$ARTIFACT_NAME" -C "$TMP_VERIFY_DIR"

if [[ ! -f "$TMP_VERIFY_DIR/macos-installer/setup-macos-installer.sh" ]]; then
  echo "Verification failed: missing setup-macos-installer.sh"
  exit 1
fi

if [[ ! -f "$TMP_VERIFY_DIR/macos-installer/setup-macos-ui.sh" ]]; then
  echo "Verification failed: missing setup-macos-ui.sh"
  exit 1
fi

if [[ ! -f "$TMP_VERIFY_DIR/macos-installer/setup-macos-ui.command" ]]; then
  echo "Verification failed: missing setup-macos-ui.command"
  exit 1
fi

if [[ ! -d "$TMP_VERIFY_DIR/macos-installer/ZaloClawSetup.app" ]]; then
  echo "Verification failed: missing ZaloClawSetup.app"
  exit 1
fi

if [[ ! -f "$TMP_VERIFY_DIR/macos-installer/scripts/macos-bootstrap.js" ]]; then
  echo "Verification failed: missing macos-bootstrap.js"
  exit 1
fi

shasum -a 256 "$OUT_DIR/$ARTIFACT_NAME" > "$OUT_DIR/$ARTIFACT_NAME.sha256"

echo "Built artifact: $OUT_DIR/$ARTIFACT_NAME"
echo "Checksum: $OUT_DIR/$ARTIFACT_NAME.sha256"
