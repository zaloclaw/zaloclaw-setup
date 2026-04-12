#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLI_INSTALLER="$SCRIPT_DIR/setup-macos-installer.sh"
DESIGN_BG_IMAGE=""

for candidate in "$SCRIPT_DIR/zaloclaw-design.png" "$SCRIPT_DIR/../../zaloclaw-design.png"; do
  if [[ -f "$candidate" ]]; then
    DESIGN_BG_IMAGE="$candidate"
    break
  fi
done

DOCKER_DESKTOP_DOCS_URL="https://docs.docker.com/desktop/setup/install/mac-install/"

if [[ ! -x "$CLI_INSTALLER" ]]; then
  osascript -e 'display alert "Missing installer" message "setup-macos-installer.sh is missing or not executable." as critical'
  exit 1
fi

ask_text() {
  local title="$1"
  local prompt="$2"
  local default_value="$3"

  osascript - "$title" "$prompt" "$default_value" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set promptText to item 2 of argv
  set defaultText to item 3 of argv
  set iconPath to item 4 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    set response to display dialog promptText with title titleText default answer defaultText buttons {"Cancel", "Continue"} default button "Continue"
  else
    set response to display dialog promptText with title titleText default answer defaultText buttons {"Cancel", "Continue"} default button "Continue" with icon iconAlias
  end if
  return text returned of response
end run
OSA
}

ask_path_with_browse() {
  local title="$1"
  local prompt="$2"
  local default_path="$3"

  local expanded_default
  expanded_default="${default_path/\~/$HOME}"

  local current_value="$expanded_default"

  while true; do
    local action_and_value
    action_and_value="$(osascript - "$title" "$prompt" "$current_value" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set promptText to item 2 of argv
  set currentValue to item 3 of argv
  set iconPath to item 4 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    set response to display dialog promptText with title titleText default answer currentValue buttons {"Cancel", "Browse...", "Continue"} default button "Continue"
  else
    set response to display dialog promptText with title titleText default answer currentValue buttons {"Cancel", "Browse...", "Continue"} default button "Continue" with icon iconAlias
  end if
  set clicked to button returned of response
  set typedValue to text returned of response
  return clicked & linefeed & typedValue
end run
OSA
)"

    local action
    action="${action_and_value%%$'\n'*}"
    local value
    value="${action_and_value#*$'\n'}"

    if [[ "$action" == "Continue" ]]; then
      if [[ -z "$value" ]]; then
        osascript -e 'display alert "Missing value" message "Please enter or browse for a folder path." as critical'
        continue
      fi
      echo "$value"
      return 0
    fi

    local chosen_path
    chosen_path="$(osascript - "$title" "$value" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set seedPath to item 2 of argv
  try
    set seedAlias to POSIX file seedPath as alias
    set picked to choose folder with prompt "Select a folder" default location seedAlias
  on error
    set picked to choose folder with prompt "Select a folder"
  end try

  set posixPath to POSIX path of picked
  if posixPath ends with "/" then
    set posixPath to text 1 thru -2 of posixPath
  end if
  return posixPath
end run
OSA
)"

    current_value="$chosen_path"
  done
}

ask_secret() {
  local title="$1"
  local prompt="$2"

  osascript - "$title" "$prompt" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set promptText to item 2 of argv
  set iconPath to item 3 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    set response to display dialog promptText with title titleText default answer "" hidden answer true buttons {"Cancel", "Continue"} default button "Continue"
  else
    set response to display dialog promptText with title titleText default answer "" hidden answer true buttons {"Cancel", "Continue"} default button "Continue" with icon iconAlias
  end if
  return text returned of response
end run
OSA
}

ask_choice() {
  local title="$1"
  local prompt="$2"
  shift 2

  osascript - "$title" "$prompt" "$@" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set promptText to item 2 of argv
  set choices to items 3 thru -1 of argv
  set picked to choose from list choices with title titleText with prompt promptText default items {item 1 of choices} without multiple selections allowed and empty selection allowed
  if picked is false then
    error number -128
  end if
  return item 1 of picked
end run
OSA
}

ask_yes_no() {
  local title="$1"
  local prompt="$2"
  local default_yes="$3"

  local default_button="Yes"
  if [[ "$default_yes" != "yes" ]]; then
    default_button="No"
  fi

  osascript - "$title" "$prompt" "$default_button" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set titleText to item 1 of argv
  set promptText to item 2 of argv
  set defaultButtonName to item 3 of argv
  set iconPath to item 4 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    set response to display dialog promptText with title titleText buttons {"No", "Yes"} default button defaultButtonName
  else
    set response to display dialog promptText with title titleText buttons {"No", "Yes"} default button defaultButtonName with icon iconAlias
  end if
  return button returned of response
end run
OSA
}

ensure_docker_desktop_installed() {
  if [[ -d "/Applications/Docker.app" || -d "$HOME/Applications/Docker.app" ]]; then
    return 0
  fi

  local action
  action="$(osascript - "$DOCKER_DESKTOP_DOCS_URL" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set docsUrl to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if

  set promptText to "Docker Desktop is required before running setup." & return & return & "Install Docker Desktop, then rerun this installer." & return & docsUrl
  if iconAlias is missing value then
    set response to display dialog promptText with title "Docker Desktop Required" buttons {"Cancel", "Open Install Guide"} default button "Open Install Guide"
  else
    set response to display dialog promptText with title "Docker Desktop Required" buttons {"Cancel", "Open Install Guide"} default button "Open Install Guide" with icon iconAlias
  end if
  return button returned of response
end run
OSA
)"

  if [[ "$action" == "Open Install Guide" ]]; then
    open "$DOCKER_DESKTOP_DOCS_URL" >/dev/null 2>&1 || true
  fi

  return 1
}

run_setup_command() {
  local show_terminal="$1"
  shift
  local -a cmd=("$@")

  if [[ "$show_terminal" != "Yes" ]]; then
    "${cmd[@]}"
    return $?
  fi

  # If invoked from setup-macos-ui.command, reuse the current terminal window.
  if [[ -t 1 ]]; then
    "${cmd[@]}"
    return $?
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/zaloclaw-installer.XXXXXX)"
  local run_script="$tmp_dir/run-setup.sh"
  local status_file="$tmp_dir/exit-code"
  local log_file="$tmp_dir/setup.log"

  local cmd_line
  cmd_line="$(printf '%q ' "${cmd[@]}")"

  cat > "$run_script" <<EOF
#!/usr/bin/env bash
set -o pipefail

$cmd_line 2>&1 | tee "${log_file}"
exit_code=\
\${PIPESTATUS[0]}
echo "\${exit_code}" > "${status_file}"

echo ""
echo "Setup finished with exit code \${exit_code}."
echo "Log file: ${log_file}"
echo "Press Enter to close this window..."
read -r _

exit "\${exit_code}"
EOF

  chmod +x "$run_script"

  osascript - "$run_script" <<'OSA'
on run argv
  set scriptPath to item 1 of argv
  tell application "Terminal"
    activate
    do script "bash " & quoted form of scriptPath
  end tell
end run
OSA

  while [[ ! -f "$status_file" ]]; do
    sleep 1
  done

  local exit_code
  exit_code="$(cat "$status_file" 2>/dev/null || echo 1)"

  if [[ "$exit_code" != "0" ]]; then
    osascript - "$log_file" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set logPath to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    set response to display dialog "Setup failed in Terminal. Open log file?" with title "ZaloClaw Local Setup" buttons {"No", "Open Log"} default button "Open Log"
  else
    set response to display dialog "Setup failed in Terminal. Open log file?" with title "ZaloClaw Local Setup" buttons {"No", "Open Log"} default button "Open Log" with icon iconAlias
  end if
  if button returned of response is "Open Log" then
    do shell script "open " & quoted form of logPath
  end if
end run
OSA
  fi

  return "$exit_code"
}

show_completion_dialog() {
  local workspace_root="$1"
  local launch_ui_choice="$2"
  local state_file="$workspace_root/setup-state.json"
  local summary_text
  summary_text="$(build_setup_summary "$state_file")"

  if [[ "$launch_ui_choice" == "Yes" ]]; then
    local action
    action="$(osascript - "$summary_text" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set summaryText to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  set promptText to "Setup completed. UI launch was requested and is starting in the background. It can take up to a minute before http://localhost:3000 is ready." & return & return & summaryText
  if iconAlias is missing value then
    set response to display dialog promptText with title "ZaloClaw Local Setup" buttons {"Done", "Open setup-state.json", "Open Summary", "Open UI"} default button "Open UI"
  else
    set response to display dialog promptText with title "ZaloClaw Local Setup" buttons {"Done", "Open setup-state.json", "Open Summary", "Open UI"} default button "Open UI" with icon iconAlias
  end if
  return button returned of response
end run
OSA
)"

    case "$action" in
      "Open UI")
        open "http://localhost:3000" >/dev/null 2>&1 || true
        ;;
      "Open setup-state.json")
        if [[ -f "$state_file" ]]; then
          open "$state_file" >/dev/null 2>&1 || true
        else
          osascript -e 'display alert "State file not found" message "setup-state.json was not found in the selected workspace."'
        fi
        ;;
      "Open Summary")
        osascript - "$summary_text" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set summaryText to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    display dialog summaryText with title "Setup Summary" buttons {"OK"} default button "OK"
  else
    display dialog summaryText with title "Setup Summary" buttons {"OK"} default button "OK" with icon iconAlias
  end if
end run
OSA
        ;;
      *)
        ;;
    esac
  else
    local action
    action="$(osascript - "$summary_text" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set summaryText to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  set promptText to "Setup completed successfully." & return & return & summaryText
  if iconAlias is missing value then
    set response to display dialog promptText with title "ZaloClaw Local Setup" buttons {"Done", "Open setup-state.json", "Open Summary"} default button "Done"
  else
    set response to display dialog promptText with title "ZaloClaw Local Setup" buttons {"Done", "Open setup-state.json", "Open Summary"} default button "Done" with icon iconAlias
  end if
  return button returned of response
end run
OSA
)"

    case "$action" in
      "Open setup-state.json")
        if [[ -f "$state_file" ]]; then
          open "$state_file" >/dev/null 2>&1 || true
        else
          osascript -e 'display alert "State file not found" message "setup-state.json was not found in the selected workspace."'
        fi
        ;;
      "Open Summary")
        osascript - "$summary_text" "$DESIGN_BG_IMAGE" <<'OSA'
on run argv
  set summaryText to item 1 of argv
  set iconPath to item 2 of argv
  set iconAlias to missing value
  if iconPath is not "" then
    try
      set iconAlias to POSIX file iconPath as alias
    end try
  end if
  if iconAlias is missing value then
    display dialog summaryText with title "Setup Summary" buttons {"OK"} default button "OK"
  else
    display dialog summaryText with title "Setup Summary" buttons {"OK"} default button "OK" with icon iconAlias
  end if
end run
OSA
        ;;
      *)
        ;;
    esac
  fi
}

build_setup_summary() {
  local state_file="$1"

  if [[ ! -f "$state_file" ]]; then
    echo "Summary unavailable: setup-state.json was not found."
    return 0
  fi

  python3 - "$state_file" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    state = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"Summary unavailable: unable to parse setup-state.json ({exc}).")
    raise SystemExit(0)

setup_status = (state.get("setupCompletion") or {}).get("status", "unknown")
ui_status = (state.get("uiRuntime") or {}).get("status", "unknown")

steps = state.get("steps") or []
step_map = {item.get("id"): item for item in steps if isinstance(item, dict)}
infra_status = (step_map.get("infra") or {}).get("status", "unknown")

compose_hint = "not detected"
infra_checkpoints = (step_map.get("infra") or {}).get("checkpoints") or []
for item in reversed(infra_checkpoints):
    if not isinstance(item, str):
        continue
    if "Started UI compose stack from" in item:
        compose_hint = "started"
        break
    if "No UI repository compose file detected" in item:
        compose_hint = "repo compose file not found"
        break
    if "Started compose UI services:" in item:
        compose_hint = "started from infra compose service"
        break
    if "No UI-related compose service detected" in item:
        compose_hint = "no infra UI service detected"
        break

blocked_reasons = state.get("blockedReasons") or []
blocked = blocked_reasons[0] if blocked_reasons else "none"

lines = [
    f"Setup: {setup_status}",
    f"Infra step: {infra_status}",
    f"UI runtime: {ui_status}",
    f"UI compose: {compose_hint}",
    f"Blocked reason: {blocked}",
]

print("\n".join(lines))
PY
}

provider_to_key_name() {
  case "$1" in
    openai) echo "OPENAI_API_KEY" ;;
    google) echo "GOOGLE_API_KEY" ;;
    anthropic) echo "ANTHROPIC_API_KEY" ;;
    openrouter) echo "OPENROUTER_API_KEY" ;;
    *) echo "OPENAI_API_KEY" ;;
  esac
}

choice_to_provider() {
  case "$1" in
    "OpenAI") echo "openai" ;;
    "Google") echo "google" ;;
    "Anthropic") echo "anthropic" ;;
    "OpenRouter") echo "openrouter" ;;
    *) echo "openai" ;;
  esac
}

choice_to_clone_mode() {
  case "$1" in
    "Reuse existing folder") echo "reuse" ;;
    "Replace existing folder") echo "replace" ;;
    "Fail and stop setup") echo "fail" ;;
    *) echo "reuse" ;;
  esac
}

main() {
  osascript -e 'display notification "Guided setup will collect required values and run bootstrap." with title "ZaloClaw Local Setup"'

  if ! ensure_docker_desktop_installed; then
    exit 1
  fi

  local default_workspace="$HOME/zaloclaw-local"
  local default_config="$HOME/.openclaw_z"

  local workspace_root
  workspace_root="$(ask_path_with_browse "ZaloClaw Local Setup" "Workspace root for repositories:" "$default_workspace")"

  local config_dir
  config_dir="$(ask_path_with_browse "ZaloClaw Local Setup" "OPENCLAW_CONFIG_DIR:" "$default_config")"

  local provider_choice
  provider_choice="$(ask_choice "ZaloClaw Local Setup" "Choose provider" "OpenAI" "Google" "Anthropic" "OpenRouter")"

  local provider
  provider="$(choice_to_provider "$provider_choice")"

  local provider_key_name
  provider_key_name="$(provider_to_key_name "$provider")"

  local provider_api_key
  provider_api_key="$(ask_secret "ZaloClaw Local Setup" "Enter ${provider_key_name}:")"
  if [[ -z "$provider_api_key" ]]; then
    osascript -e 'display alert "Missing value" message "Provider API key is required." as critical'
    exit 1
  fi

  local litellm_key
  litellm_key="$(ask_secret "ZaloClaw Local Setup" "Enter LITELLM_MASTER_KEY:")"
  if [[ -z "$litellm_key" ]]; then
    osascript -e 'display alert "Missing value" message "LITELLM_MASTER_KEY is required." as critical'
    exit 1
  fi

  local clone_choice
  clone_choice="$(ask_choice "ZaloClaw Local Setup" "If repository folder already exists:" "Reuse existing folder" "Replace existing folder" "Fail and stop setup")"

  local clone_mode
  clone_mode="$(choice_to_clone_mode "$clone_choice")"

  local install_missing="Yes"
  local launch_ui="Yes"
  local show_terminal="Yes"

  local -a cmd
  cmd=(
    "$CLI_INSTALLER"
    --workspace-root "$workspace_root"
    --provider "$provider"
    --provider-api-key "$provider_api_key"
    --litellm-master-key "$litellm_key"
    --config-dir "$config_dir"
    --clone-mode "$clone_mode"
  )

  cmd+=(--install-missing-prerequisites)

  cmd+=(--launch-ui)

  if ! run_setup_command "$show_terminal" "$CLI_INSTALLER" "${cmd[@]:1}"; then
    osascript -e 'display alert "Setup failed" message "Bootstrap script exited with an error. Please review terminal logs or setup-state.json for details." as critical'
    exit 1
  fi

  show_completion_dialog "$workspace_root" "$launch_ui"
}

main "$@"
