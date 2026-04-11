#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ZaloClaw Local Setup (macOS)"
APP_VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/scripts/macos-bootstrap.js"

log() {
  printf "%s\n" "$1"
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_homebrew() {
  if has_cmd brew; then
    return
  fi

  log "Homebrew is required but not installed."
  read -r -p "Install Homebrew now? [y/N]: " install_brew
  case "${install_brew,,}" in
    y|yes)
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      ;;
    *)
      log "Please install Homebrew manually: https://brew.sh"
      exit 1
      ;;
  esac
}

ensure_formula() {
  local command_name="$1"
  local formula_name="$2"

  if has_cmd "$command_name"; then
    return
  fi

  log "Installing $formula_name via Homebrew..."
  brew install "$formula_name"
}

ensure_docker_desktop() {
  if has_cmd docker; then
    return
  fi

  log "Installing Docker Desktop via Homebrew cask..."
  brew install --cask docker
  log "Docker Desktop installed. Launch Docker Desktop once if docker command remains unavailable."
}

ensure_node_runtime() {
  ensure_homebrew
  ensure_formula git git
  ensure_formula node node
  ensure_formula npm node
  ensure_docker_desktop

  if ! has_cmd node; then
    log "Node.js is required but still unavailable after install attempt."
    exit 1
  fi
}

main() {
  log "== $APP_NAME v$APP_VERSION =="
  ensure_node_runtime

  if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
    log "Bootstrap script not found: $BOOTSTRAP_SCRIPT"
    exit 1
  fi

  cd "$ROOT_DIR"
  node "$BOOTSTRAP_SCRIPT" --source-root "$ROOT_DIR" "$@"
}

main "$@"
