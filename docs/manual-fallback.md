# Manual Fallback Path

If the setup package fails or is blocked, use this fallback process.

## 1. Install prerequisites manually

Ensure all are installed and available in terminal:

- Docker Desktop
- Git
- Node.js
- npm

## 2. Clone repositories

From your workspace root:

```bash
git clone https://github.com/zaloclaw/zaloclaw-ui.git
```

```bash
git clone https://github.com/zaloclaw/zaloclaw-infra.git
```

## 3. Configure infra environment

Create `zaloclaw-infra/.env` from project guidance or `.env.example` values.

## 4. Run infra setup script

macOS:

```bash
cd zaloclaw-infra
bash zaloclaw-docker-setup.sh
```

Windows PowerShell:

```powershell
cd zaloclaw-infra
powershell -NoProfile -ExecutionPolicy Bypass -File .\zaloclaw-docker-setup.ps1
```

## 5. Start UI locally

```bash
cd zaloclaw-ui
npm run dev
```

## 6. Troubleshoot using setup state

If you previously ran the setup package, inspect `setup-state.json` in workspace root to see failed steps and retry points.
