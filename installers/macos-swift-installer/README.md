# ZClaw Installer (macOS/Swift)

Native SwiftUI desktop application to automate setup for ZClaw.

## Features

- **SwiftUI desktop app**: Native shell for setup orchestration.
- **Real-time Output**: Embedded console view with live stdout/stderr streaming.
- **Configuration Form**: Integrated UI for setup inputs (workspace, config dir, provider, keys, clone/options).
- **Donate QR Code**: Integrated donate button/QR code to support the project.
- **Completion Artifacts**: Easy access to crucial setup values:
  - `OPENCLAW_GATEWAY_TOKEN`
  - `OPENCLAW_GATEWAY_CONTAINER`
- **Settings Persistence**: Saves your previous inputs to `~/Library/Application Support/ZClawInstaller/settings.json`.

## Quick Start

```bash
./run-installer-ui.sh
```

## Build Artifact

```bash
./build-swift-installer-artifact.sh
```
This produces a `.tar.gz` bundle containing the `.app` package in `../../dist/macos-swift-installer`.

## Scope

- New native shell lives in `installers/macos-swift-installer/`.
- Fallback existing AppleScript installer in `installers/macos-installer/` remains as reference.

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
