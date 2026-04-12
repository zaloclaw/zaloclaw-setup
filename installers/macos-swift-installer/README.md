# ZaloClaw Swift Installer (macOS)

This directory contains the new native macOS installer shell scaffold.

## Scope

- New native shell lives only in `installers/macos-swift-installer/`.
- Existing AppleScript installer in `installers/macos-installer/` remains unchanged and serves as fallback/reference.

## What This Scaffold Provides

- SwiftUI desktop app shell for setup orchestration.
- Embedded live output panel (console view) with stdout/stderr streaming.
- In-app configuration form for required setup inputs (workspace, config dir, provider, keys, clone/options).
- Basic status timeline mapped from installer logs.
- Completion artifact extraction for:
  - `OPENCLAW_GATEWAY_TOKEN`
  - `OPENCLAW_GATEWAY_CONTAINER`

## Run Locally

```bash
cd installers/macos-swift-installer
swift run
```

If `swift run` does not foreground the window in your terminal environment, use:

```bash
cd installers/macos-swift-installer
bash run-installer-ui.sh
```

Or build first, then run the binary:

```bash
cd installers/macos-swift-installer
swift build
.build/debug/ZaloClawSwiftInstaller
```

The app launches and, when started, runs the existing backend setup script:

- `installers/macos-installer/setup-macos-installer.sh`

through a Swift-runner adapter:

- `installers/macos-swift-installer/scripts/macos-swift-runner.sh`

This keeps migration low-risk while validating native UX.

The runner forwards your form values directly to:

- `installers/macos-installer/setup-macos-installer.sh`

so setup executes with your selected workspace/config/provider/options instead of prompting interactively.

Default options in native UI:
- Clone mode defaults to `reuse`
- Install missing prerequisites is enabled by default
- Launch UI after setup is enabled by default

## Saved Configuration

Installer form values (except secrets) are persisted between launches at:

- `~/Library/Application Support/ZaloClawSwiftInstaller/settings.json`

Notes:
- Provider API key and LiteLLM key are intentionally not persisted.

## Next Steps

- Replace log-line parsing with structured runtime events from the shared installer contract.
- Add feature flag/mode routing for fallback behavior.

## Package For End Users

Build a distributable macOS app artifact:

```bash
cd installers/macos-swift-installer
bash build-swift-installer-artifact.sh
```

Output files:

- `dist/macos-swift-installer/zaloclaw-macos-swift-installer-0.1.0.tar.gz`
- `dist/macos-swift-installer/zaloclaw-macos-swift-installer-0.1.0.tar.gz.sha256`

The artifact contains:

- `ZaloClawSwiftInstaller.app`
- bundled runner script (`Contents/Resources/scripts/macos-swift-runner.sh`)
- bundled backend setup scripts (`Contents/installers/macos-installer/...`)

End-user usage:

1. Extract the `.tar.gz`
2. Double-click `ZaloClawSwiftInstaller.app`
3. Complete setup in the native UI
