$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RootDir

function Write-Info {
    param([string]$Message)
    Write-Host $Message
}

function Test-Cmd {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-Winget {
    if (Test-Cmd "winget") { return }
    throw "winget is required for automatic installation. Install App Installer from Microsoft Store and rerun."
}

function Ensure-Installed {
    param(
        [string]$CommandName,
        [string]$WingetId,
        [string]$DisplayName
    )

    if (Test-Cmd $CommandName) {
        return
    }

    Write-Info "Installing $DisplayName via winget..."
    winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements

    if (-not (Test-Cmd $CommandName)) {
        throw "$DisplayName is still unavailable after install attempt."
    }
}

function Main {
    Write-Info "== ZaloClaw Native Bootstrap (Windows) =="

    Ensure-Winget
    Ensure-Installed -CommandName "git" -WingetId "Git.Git" -DisplayName "Git"
    Ensure-Installed -CommandName "node" -WingetId "OpenJS.NodeJS.LTS" -DisplayName "Node.js"
    Ensure-Installed -CommandName "npm" -WingetId "OpenJS.NodeJS.LTS" -DisplayName "npm"

    if (-not (Test-Cmd "docker")) {
        Write-Info "Installing Docker Desktop via winget..."
        winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
        if (-not (Test-Cmd "docker")) {
            Write-Info "Docker command still unavailable. Start Docker Desktop once, then rerun if needed."
        }
    }

    if (-not (Test-Cmd "node")) {
        throw "Node.js is required to continue but was not found."
    }

    Write-Info "Handing off to Node setup workflow..."
    node src/setup-cli.js
}

Main
