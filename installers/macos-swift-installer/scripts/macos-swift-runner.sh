#!/usr/bin/env bash
set -euo pipefail

EVENT_PREFIX="__ZALOC_EVENT__"

emit_event() {
  local event_type="$1"
  local key="$2"
  local value="$3"
  printf '%s|%s|%s|%s\n' "$EVENT_PREFIX" "$event_type" "$key" "$value"
}

is_buildkit_run_echo_line() {
  local line="$1"
  [[ "$line" =~ ^#[0-9]+[[:space:]]+\[[^]]+\][[:space:]]+RUN[[:space:]] ]]
}

is_real_error_line() {
  local line="$1"

  if is_buildkit_run_echo_line "$line"; then
    return 1
  fi

  [[ "$line" =~ ^(ERROR:|Error:|error:) ]] && return 0
  [[ "$line" =~ ^(failed:|Failed:|failed[[:space:]]+to[[:space:]]|Failed[[:space:]]+to[[:space:]]) ]] && return 0
  [[ "$line" =~ [[:space:]](ERROR:|Error:|failed|Failed)[[:space:]] ]] && return 0

  return 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTENTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$SWIFT_DIR/../.." && pwd)"

BUNDLED_BACKEND_SCRIPT="$CONTENTS_DIR/installers/macos-installer/setup-macos-installer.sh"
SOURCE_BACKEND_SCRIPT="$REPO_ROOT/installers/macos-installer/setup-macos-installer.sh"

if [[ -x "$BUNDLED_BACKEND_SCRIPT" ]]; then
  BACKEND_SCRIPT="$BUNDLED_BACKEND_SCRIPT"
  BACKEND_ROOT="$CONTENTS_DIR"
else
  BACKEND_SCRIPT="$SOURCE_BACKEND_SCRIPT"
  BACKEND_ROOT="$REPO_ROOT"
fi

resolve_workspace_root_arg() {
  local previous=""
  local value
  for value in "$@"; do
    if [[ "$previous" == "--workspace-root" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    previous="$value"
  done
  return 1
}

WORKSPACE_ROOT_ARG="$(resolve_workspace_root_arg "$@" || true)"
if [[ -n "$WORKSPACE_ROOT_ARG" ]]; then
  STATE_FILE="$WORKSPACE_ROOT_ARG/setup-state.json"
else
  STATE_FILE="$BACKEND_ROOT/setup-state.json"
fi

LOG_FILE="/tmp/zaloclaw-swift-installer-$(date +%Y%m%d-%H%M%S).log"

if [[ ! -x "$BACKEND_SCRIPT" ]]; then
  emit_event "lifecycle" "status" "failed"
  emit_event "lifecycle" "error" "Missing backend script: $BACKEND_SCRIPT"
  exit 1
fi

emit_event "artifact" "log_file" "$LOG_FILE"
emit_event "artifact" "state_file" "$STATE_FILE"
emit_event "lifecycle" "status" "running"
emit_event "step" "name" "bootstrap"
emit_event "step" "name" "prerequisites"

set +e
while IFS= read -r line; do
  printf '%s\n' "$line" | tee -a "$LOG_FILE"

  if [[ "$line" == *"All prerequisites available"* ]]; then
    emit_event "step" "name" "clone"
  fi

  if [[ "$line" == *"Wrote"*".env"* ]]; then
    emit_event "step" "name" "env"
  fi

  if [[ "$line" == *"==>"* ]]; then
    emit_event "step" "name" "infra"
  fi

  if [[ "$line" == *"OpenClaw Gateway Token:"* ]]; then
    token_value="${line#*OpenClaw Gateway Token:}"
    token_value="${token_value## }"
    emit_event "artifact" "gateway_token" "$token_value"
  fi

  if [[ "$line" == *"OPENCLAW_GATEWAY_CONTAINER="* ]]; then
    container_value="${line#*OPENCLAW_GATEWAY_CONTAINER=}"
    emit_event "artifact" "gateway_container" "$container_value"
  fi

  if is_real_error_line "$line"; then
    emit_event "lifecycle" "error" "$line"
  fi
done < <("$BACKEND_SCRIPT" "$@" 2>&1)
exit_code=$?
set -e

if [[ "$exit_code" -eq 0 ]]; then
  emit_event "step" "name" "done"
  emit_event "lifecycle" "status" "completed"
else
  emit_event "step" "name" "failed"
  emit_event "lifecycle" "status" "failed"
fi

emit_event "lifecycle" "exit_code" "$exit_code"
exit "$exit_code"
