#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

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
  local formula="$1"
  if has_cmd "$formula"; then
    return
  fi
  log "Installing $formula via Homebrew..."
  brew install "$formula"
}

ensure_docker_desktop() {
  if has_cmd docker; then
    return
  fi
  log "Installing Docker Desktop via Homebrew cask..."
  brew install --cask docker
  log "Docker Desktop installed. Launch Docker Desktop once before continuing if docker command is still unavailable."
}

main() {
  log "== ZaloClaw Native Bootstrap (macOS) =="
  ensure_homebrew
  ensure_formula git
  ensure_formula node
  ensure_formula npm
  ensure_docker_desktop

  if ! has_cmd node; then
    log "Node.js is still unavailable after install attempt."
    exit 1
  fi

  log "Handing off to Node setup workflow..."
  node src/setup-cli.js
}

main "$@"
