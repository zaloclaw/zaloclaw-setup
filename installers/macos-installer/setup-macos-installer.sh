#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ZaloClaw Local Setup (macOS)"
APP_VERSION="0.1.0"
SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE_PATH" ]]; do
  LINK_TARGET="$(readlink "$SOURCE_PATH")"
  if [[ "$LINK_TARGET" == /* ]]; then
    SOURCE_PATH="$LINK_TARGET"
  else
    SOURCE_PATH="$(cd "$(dirname "$SOURCE_PATH")" && cd "$(dirname "$LINK_TARGET")" && pwd)/$(basename "$LINK_TARGET")"
  fi
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

resolve_bootstrap_script() {
  local -a candidates=(
    "$SCRIPT_DIR/scripts/macos-bootstrap.js"
    "$ROOT_DIR/installers/macos-installer/scripts/macos-bootstrap.js"
    "$SCRIPT_DIR/../Resources/scripts/macos-bootstrap.js"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  log "Bootstrap script not found. Checked:"
  for candidate in "${candidates[@]}"; do
    log " - $candidate"
  done
  return 1
}

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

  local bootstrap_script
  if ! bootstrap_script="$(resolve_bootstrap_script)"; then
    exit 1
  fi

  log "Using bootstrap script: $bootstrap_script"

  cd "$ROOT_DIR"
  node "$bootstrap_script" --source-root "$ROOT_DIR" "$@"
}

main "$@"
