# ZaloClawSetup - macOS Installer

An elegant, native macOS application for setting up ZaloClaw locally with minimal configuration.

## Quick Start

### Option 1: Native App (Recommended for Non-Technical Users)
1. Extract `zaloclaw-macos-local-setup-0.1.0.tar.gz`
2. Double-click `ZaloClawSetup.app` 
3. Follow the native dialogs (cleaner than Terminal!)
4. Setup completes silently in background
5. See notification when complete

### Option 2: GUI with Terminal (For Reference/Debugging)
1. Extract the archive
2. Double-click `setup-macos-ui.command`
3. Terminal opens showing progress
4. Complete setup dialog prompts

### Option 3: CLI (For Scripting/Automation)
```bash
bash setup-macos-installer.sh
```

## What It Does

- ✅ Checks for required tools (Git, Node.js, Docker)
- ✅ Installs missing tools via Homebrew
- ✅ Prompts for minimal configuration:
  - Workspace location
  - Config directory  
  - LLM provider (OpenAI/Google/Anthropic)
  - Provider API key
  - LiteLLM master key
- ✅ Generates `.env` file automatically
- ✅ Clones ZaloClaw repository (or reuses existing)
- ✅ Launches Docker infrastructure setup
- ✅ Optionally starts UI dashboard

## Entry Points Inside Package

```
macos-installer/
├── ZaloClawSetup.app/           ← Native app (double-click, no Terminal!)
├── setup-macos-ui.command       ← Terminal wrapper (shows progress)
├── setup-macos-installer.sh     ← CLI entry point
├── setup-macos-ui.sh            ← Dialog/wrapper logic
└── scripts/
    └── macos-bootstrap.js       ← Core orchestration engine
```

## Architecture

### ZaloClawSetup.app (Native macOS Application)

The cleanest experience — **recommended for most users**:

- Runs as native macOS app (appears in Dock, Spotlight searchable)
- Shows beautiful native dialog prompts (no ugly Terminal)
- Orchestrates all setup silently in background
- Notifies completion via native notification
- Zero external dependencies (uses macOS native APIs)

**Implementation:**
- Info.plist defines macOS app metadata
- ByteLauncher script (MacOS/launcher) handles execution
- Calls underlying setup-macos-ui.sh for prompts/logic
- All system integration via osascript (native!)

### setup-macos-ui.command (Finder-Compatible Script)

For users who want to see what's happening:

- Executable wrapper for non-CLI users
- Opens Terminal showing live progress
- Same functionality as .app but visible
- Good for debugging/understanding flow

### setup-macos-installer.sh (Shell Entry Point)

Direct shell access:

```bash
bash setup-macos-installer.sh

# Or with arguments for automation:
bash setup-macos-installer.sh \
  --workspace ~/zaloclaw-local \
  --config ~/.openclaw_z \
  --provider openai \
  --api-key sk-xxxx \
  --litellm-key lk-xxxx
```

## Troubleshooting

### "Permission Denied" on ZaloClawSetup.app
```bash
chmod +x ZaloClawSetup.app/Contents/MacOS/launcher
```

### Homebrew Installation Fails
Ensure Homebrew is installed or accessible:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Docker Desktop Not Found
The installer will prompt to install Docker Desktop via Homebrew Cask.  
If manual install needed: https://www.docker.com/products/docker-desktop

### Want to See Setup Logs?
Logs are stored in:
```bash
cat setup-state.json  # Overall state and checkpoints
```

## Distribution

### For End Users
```bash
# Create distributable zip (for sharing/deployment)
ditto -c -k --sequesterRsrc macos-installer zaloclaw-macos-setup.zip

# Or tar for broader compatibility
tar -czf zaloclaw-macos-setup.tar.gz macos-installer
```

### For macOS Notarization (Future Enterprise Distribution)
```bash
# Sign the app (requires Apple Developer certificate)
codesign --deep --force --verify --verbose --sign "Developer ID Application" \
  macos-installer/ZaloClawSetup.app

# Notarize for distribution outside App Store
xcrun notarytool submit zaloclaw-macos-setup.zip \
  --apple-id your-apple-id@icloud.com \
  --team-id XXXXXXXXXX \
  --password your-app-password
```

## Technical Details

### State Model
Setup state persists to `setup-state.json`:
```json
{
  "platform": "darwin",
  "steps": {
    "prerequisites": "done",
    "repository": "done",
    "environment": "done",
    "infrastructure": "done"
  },
  "timestamp": "2026-04-10T15:30:00.000Z",
  "setupCompletion": {
    "status": "success",
    "checkpoints": [...]
  }
}
```

### Environment Configuration
Auto-generated `.env` includes:
- OPENCLAW_CONFIG_DIR (user provides)
- OPENCLAW_WORKSPACE_DIR (auto-derived)
- Provider key (user provides)
- LITELLM_MASTER_KEY (user provides)
- Other defaults from `.env.example`

### Prerequisites
- macOS 10.12 or later
- Internet connection (for tool/dependency download)
- ~5GB disk space (for Docker images)

## Contributing

To modify the installer:

1. Edit relevant script in `scripts/`
2. Update UI dialogs in `setup-macos-ui.sh`
3. Rebuild app: `bash create-automator-app.sh`
4. Package: `bash build-macos-installer-artifact.sh`
5. Test: `./ZaloClawSetup.app` or `bash setup-macos-ui.command`
