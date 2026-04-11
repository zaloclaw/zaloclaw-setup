# zaloclaw-setup

Local setup package for OpenClaw and Zalo ecosystem.

## What this does

- Detects OS and permission context.
- Checks and guides installation for Docker Desktop, Git, Node.js, and npm.
- Clones:
	- `https://github.com/zaloclaw/zaloclaw-ui.git` to `zaloclaw-ui`
	- `https://github.com/zaloclaw/zaloclaw-infra.git` to `zaloclaw-infra`
- Collects required values and writes `zaloclaw-infra/.env`.
- Runs OS-specific infra setup script:
	- macOS: `zaloclaw-docker-setup.sh`
	- Windows: `zaloclaw-docker-setup.ps1`
- Offers optional `npm run dev` launch in `zaloclaw-ui`.

## Quick start

Use native bootstrap installers if you do not have Node.js yet.

macOS:

```bash
bash installers/setup-macos.sh
```

Windows (Command Prompt):

```bat
installers\setup-windows.cmd
```

Windows (PowerShell):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\installers\setup-windows.ps1
```

These launchers install prerequisites (including Node.js when missing), then run the interactive setup workflow.

If Node.js is already installed, you can run directly:

```bash
npm run setup
```

The setup workflow writes progress and diagnostics to `setup-state.json`.

## Development commands

```bash
npm run check
```

## Key docs

- State model: `docs/setup-state-model.md`
- Infra script contract: `scripts/infra-script-contract.json`
- Infra script parity checklist: `scripts/infra-script-checklist.md`
- End-to-end validation checklist: `docs/e2e-validation-checklist.md`
- Manual fallback steps: `docs/manual-fallback.md`
