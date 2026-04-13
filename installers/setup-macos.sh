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

check_docker_desktop() {
  if has_cmd docker; then
    return 0
  fi
  log "Docker Desktop is not installed."
  return 1
}

show_docker_guidelines() {
  log ""
  log "========================================"
  log "Docker Desktop Installation Required"
  log "========================================"
  log ""
  log "Docker Desktop is required to run ZaloClaw."
  log ""
  log "Please install Docker Desktop manually:"
  log "  1. Download from: https://www.docker.com/products/docker-desktop/"
  log "  2. Install the application"
  log "  3. Launch Docker Desktop from Applications folder"
  log "  4. Complete the first-run setup"
  log "  5. Wait until Docker is fully running"
  log "  6. Run this setup script again"
  log ""
  log "========================================"
  log ""
}

main() {
  log "== ZaloClaw Native Bootstrap (macOS) =="
  ensure_homebrew
  ensure_formula git
  ensure_formula node
  ensure_formula npm

  if ! check_docker_desktop; then
    show_docker_guidelines
    exit 1
  fi

  if ! has_cmd node; then
    log "Node.js is still unavailable after install attempt."
    exit 1
  fi

  log "Handing off to Node setup workflow..."
  node src/setup-cli.js
}

main "$@"
