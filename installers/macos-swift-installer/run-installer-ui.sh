#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

swift build

BIN_PATH="$SCRIPT_DIR/.build/debug/ZaloClawSwiftInstaller"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Missing built binary: $BIN_PATH" >&2
  exit 1
fi

echo "Launching ZaloClawSwiftInstaller..."
"$BIN_PATH"
