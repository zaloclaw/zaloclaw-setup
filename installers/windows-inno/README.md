# ZaloClaw Windows Inno Installer

This directory contains the [Inno Setup](https://jrsoftware.org/isinfo.php) project to build a native Windows installer (`.exe`).

## Features

- **Standard Installer UI**: Guided setup with standard Windows look and feel.
- **Dependency Check**: Leverages `windows-bootstrap.ps1` to ensure required tools (Git, Node.js, Docker) are present.
- **Configuration Pages**: Interactive forms to collect:
	- Workspace location
	- Config directory
	- Provider (OpenAI, Google, etc.) and API keys
	- LiteLLM master key
	- Clone modes (reuse, replace, fail)
- **Embedded Runner**: Orchestrates the main `setup-cli.js` workflow.

## Build Requirements

1. Install [Inno Setup 6](https://jrsoftware.org/isdl.php).
2. Open `ZaloClawSetup.iss` in the Inno Setup Compiler.
3. Click **Build > Compile** (F9).
4. Find the output `.exe` in this directory.

## Maintenance

- The main logic for setup execution (cloning, env generation) is shared via the [scripts/windows-bootstrap.ps1](scripts/windows-bootstrap.ps1) script which is bundled during compilation.
