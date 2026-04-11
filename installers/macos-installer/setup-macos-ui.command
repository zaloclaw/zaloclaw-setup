#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UI_SCRIPT="$SCRIPT_DIR/setup-macos-ui.sh"

if [[ ! -x "$UI_SCRIPT" ]]; then
  echo "Missing executable: $UI_SCRIPT"
  echo "Press Enter to close..."
  read -r _
  exit 1
fi

set +e
"$UI_SCRIPT"
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 0 ]]; then
  echo ""
  echo "Setup finished successfully."
else
  echo ""
  echo "Setup failed with exit code $EXIT_CODE."
  echo "Check setup-state.json in the selected workspace for details."
fi

echo ""
echo "Press Enter to close..."
read -r _

exit $EXIT_CODE
