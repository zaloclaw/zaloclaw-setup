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

ensure_brew_path() {
  local -a brew_paths=(
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/local/sbin"
  )

  local brew_path
  for brew_path in "${brew_paths[@]}"; do
    if [[ -d "$brew_path" && ":$PATH:" != *":$brew_path:"* ]]; then
      PATH="$brew_path:$PATH"
    fi
  done

  export PATH
}

resolve_bootstrap_script() {
  local canonical_path="$ROOT_DIR/installers/macos-installer/scripts/macos-bootstrap.js"
  local -a candidates=(
    "$canonical_path"
    "$SCRIPT_DIR/scripts/macos-bootstrap.js"
    "$SCRIPT_DIR/../Resources/scripts/macos-bootstrap.js"
  )

  local -a existing_candidates=()
  local candidate

  # Collect existing files
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      existing_candidates+=("$candidate")
    fi
  done

  # No files found
  if [[ ${#existing_candidates[@]} -eq 0 ]]; then
    log "Bootstrap script not found. Checked:"
    for candidate in "${candidates[@]}"; do
      log " - $candidate"
    done
    return 1
  fi

  # Single file found
  if [[ ${#existing_candidates[@]} -eq 1 ]]; then
    echo "[resolve] Using bootstrap script: ${existing_candidates[0]}" >&2
    echo "${existing_candidates[0]}"
    return 0
  fi

  # Multiple files found - check consistency using md5 (bash 3.x compatible)
  echo "[resolve] Found ${#existing_candidates[@]} bootstrap script copies:" >&2
  local first_checksum=""
  local all_match=true
  local i=0
  
  for candidate in "${existing_candidates[@]}"; do
    local checksum
    checksum=$(md5 -q "$candidate" 2>/dev/null || echo "error")
    echo "[resolve]   - $candidate (md5: ${checksum:0:8}...)" >&2
    
    if [[ $i -eq 0 ]]; then
      first_checksum="$checksum"
    elif [[ "$checksum" != "$first_checksum" ]]; then
      all_match=false
    fi
    i=$((i + 1))
  done

  if [[ "$all_match" == "false" ]]; then
    echo "[resolve] WARNING: Bootstrap script versions differ across locations!" >&2
    echo "[resolve] This indicates inconsistent deployment state." >&2
  else
    echo "[resolve] All ${#existing_candidates[@]} copies are identical." >&2
  fi

  # Prefer canonical path if it exists, otherwise use first match
  if [[ -f "$canonical_path" ]]; then
    echo "[resolve] Using canonical location: $canonical_path" >&2
    echo "$canonical_path"
    return 0
  fi

  echo "[resolve] Canonical path not available, using: ${existing_candidates[0]}" >&2
  echo "${existing_candidates[0]}"
  return 0
}

log() {
  printf "%s\n" "$1"
}

docker_desktop_manual_install_message() {
  log "Docker Desktop is required for ZaloClaw setup."
  log "Download it from: https://www.docker.com/products/docker-desktop/"
  log "After installing:"
  log "  1. Open Docker Desktop"
  log "  2. Complete the first-run setup"
  log "  3. Wait until Docker shows as running"
  log "  4. Re-run this installer"
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
  if ! brew install --cask docker; then
    log "Failed to install Docker Desktop automatically via Homebrew."
    docker_desktop_manual_install_message
    exit 1
  fi
  log "Docker Desktop installed. Launch Docker Desktop once if docker command remains unavailable."

  if ! has_cmd docker; then
    docker_desktop_manual_install_message
  fi
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
  ensure_brew_path
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
