#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="${1:-$DEFAULT_WORKSPACE_ROOT}"
INFRA_DIR="$WORKSPACE_ROOT/zaloclaw-infra"
UI_DIR="$WORKSPACE_ROOT/zaloclaw-ui"

log() {
  printf "%s\n" "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

compose_down() {
  local service_dir="$1"
  shift
  local compose_files=("$@")

  if [[ ! -d "$service_dir" ]]; then
    log "Skip: missing directory $service_dir"
    return
  fi

  local args=()
  local found=0
  local compose_file
  for compose_file in "${compose_files[@]}"; do
    if [[ -f "$service_dir/$compose_file" ]]; then
      args+=("-f" "$service_dir/$compose_file")
      found=1
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    log "Skip: no compose file found in $service_dir"
    return
  fi

  log "Cleaning compose stack in $service_dir"
  docker compose "${args[@]}" down --remove-orphans --volumes --rmi local || {
    log "Warning: compose cleanup failed in $service_dir"
    return
  }

  log "Done: compose stack cleaned in $service_dir"
}

main() {
  log "== ZaloClaw Docker Cleanup =="
  log "Workspace root: $WORKSPACE_ROOT"

  if ! has_cmd docker; then
    log "Error: docker command not found."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    log "Error: Docker daemon is not running. Start Docker Desktop first."
    exit 1
  fi

  compose_down "$INFRA_DIR" "docker-compose.yml" "docker-compose.extra.yml"
  compose_down "$UI_DIR" "docker-compose.yml"

  log "Pruning dangling images and unused networks..."
  docker image prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true

  log "Cleanup completed."
}

main "$@"
