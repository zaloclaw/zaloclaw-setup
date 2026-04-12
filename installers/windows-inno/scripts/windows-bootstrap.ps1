param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OpenClawConfigDir,

    [Parameter(Mandatory = $true)]
    [ValidateSet("openai", "google", "anthropic")]
    [string]$Provider,

    [string]$OpenAIApiKey,
    [string]$GoogleApiKey,
    [string]$AnthropicApiKey,

    [Parameter(Mandatory = $true)]
    [string]$LiteLlmMasterKey,

    [ValidateSet("reuse", "replace", "fail")]
    [string]$CloneMode = "reuse",

    [switch]$InstallMissingPrerequisites,
    [switch]$LaunchUi,

    [string]$InfraScriptPath
)

$ErrorActionPreference = "Stop"

$Repositories = @(
    @{
        Name = "zaloclaw-ui"
        Url = "https://github.com/zaloclaw/zaloclaw-ui.git"
        Folder = "zaloclaw-ui"
    },
    @{
        Name = "zaloclaw-infra"
        Url = "https://github.com/zaloclaw/zaloclaw-infra.git"
        Folder = "zaloclaw-infra"
    }
)

$StepTitles = @(
    @{ Id = "platform"; Title = "Detect OS and permission context" },
    @{ Id = "prerequisites"; Title = "Validate and install prerequisites" },
    @{ Id = "clone"; Title = "Clone or prepare repositories" },
    @{ Id = "env"; Title = "Collect and write infra .env" },
    @{ Id = "infra"; Title = "Run Windows infra setup script" },
    @{ Id = "ui"; Title = "Optional UI launch" }
)

function New-State {
    param(
        [string]$Workspace,
        [bool]$IsAdmin
    )

    $steps = @()
    foreach ($item in $StepTitles) {
        $steps += [ordered]@{
            id = $item.Id
            title = $item.Title
            status = "pending"
            retries = 0
            checkpoints = @()
            lastError = $null
            startedAt = $null
            endedAt = $null
        }
    }

    return [ordered]@{
        startedAt = (Get-Date).ToString("o")
        platform = [ordered]@{
            name = "windows"
            raw = $PSVersionTable.Platform
            isWindows = $true
            isMac = $false
            isAdminLike = $IsAdmin
        }
        workspaceRoot = $Workspace
        logs = @()
        blockedReasons = @()
        steps = $steps
        setupCompletion = [ordered]@{
            status = "pending"
            completedAt = $null
        }
        uiRuntime = [ordered]@{
            status = "not-started"
            pid = $null
            exitCode = $null
            lastMessage = $null
        }
    }
}

function Get-Step {
    param(
        $State,
        [string]$Id
    )

    foreach ($step in $State.steps) {
        if ($step.id -eq $Id) {
            return $step
        }
    }

    return $null
}

function Set-StepStatus {
    param(
        $State,
        [string]$Id,
        [string]$Status,
        [string]$ErrorMessage
    )

    $step = Get-Step -State $State -Id $Id
    if ($null -eq $step) {
        return
    }

    if ($Status -eq "running") {
        $step.startedAt = (Get-Date).ToString("o")
    }

    if ($Status -eq "done" -or $Status -eq "failed" -or $Status -eq "blocked") {
        $step.endedAt = (Get-Date).ToString("o")
    }

    $step.status = $Status

    if ($ErrorMessage) {
        $step.lastError = $ErrorMessage
    }
}

function Add-Checkpoint {
    param(
        $State,
        [string]$StepId,
        [string]$Message
    )

    $step = Get-Step -State $State -Id $StepId
    if ($null -eq $step) {
        return
    }

    $step.checkpoints += "$(Get-Date -Format o) $Message"
}

function Add-Log {
    param(
        $State,
        [string]$Level,
        [string]$Message
    )

    $entry = "$(Get-Date -Format o) [$Level] $Message"
    $State.logs += $entry

    if ($Level -eq "error") {
        Write-Error $Message
        return
    }

    if ($Level -eq "warn") {
        Write-Warning $Message
        return
    }

    Write-Host $Message
}

function Get-StatePath {
    param([string]$Workspace)
    return (Join-Path $Workspace "setup-state.json")
}

function Save-State {
    param($State)

    $path = Get-StatePath -Workspace $State.workspaceRoot
    $json = $State | ConvertTo-Json -Depth 12
    Set-Content -Path $path -Value $json -Encoding utf8
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command {
    param([string]$CommandName)

    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Ensure-Tool {
    param(
        $State,
        [string]$CommandName,
        [string]$WingetId,
        [string]$DisplayName
    )

    if (Test-Command -CommandName $CommandName) {
        Add-Log -State $State -Level "info" -Message "$DisplayName is available."
        return $true
    }

    Add-Log -State $State -Level "warn" -Message "$DisplayName is missing."

    if (-not $InstallMissingPrerequisites) {
        Add-Log -State $State -Level "warn" -Message "Automatic install disabled. Enable install-missing option to install $DisplayName."
        return $false
    }

    if (-not (Test-Command -CommandName "winget")) {
        Add-Log -State $State -Level "error" -Message "winget is required to install missing prerequisites."
        return $false
    }

    Add-Log -State $State -Level "info" -Message "Installing $DisplayName via winget..."
    $arguments = @(
        "install",
        "--id",
        $WingetId,
        "-e",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )

    $process = Start-Process -FilePath "winget" -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Add-Log -State $State -Level "warn" -Message "$DisplayName install failed with exit code $($process.ExitCode)."
        return $false
    }

    if (-not (Test-Command -CommandName $CommandName)) {
        Add-Log -State $State -Level "warn" -Message "$DisplayName remains unavailable after install attempt."
        return $false
    }

    Add-Log -State $State -Level "info" -Message "$DisplayName is now available."
    return $true
}

function Ensure-Prerequisites {
    param($State)

    $checks = @(
        @{ Command = "git"; WingetId = "Git.Git"; Name = "Git" },
        @{ Command = "node"; WingetId = "OpenJS.NodeJS.LTS"; Name = "Node.js" },
        @{ Command = "npm"; WingetId = "OpenJS.NodeJS.LTS"; Name = "npm" },
        @{ Command = "docker"; WingetId = "Docker.DockerDesktop"; Name = "Docker Desktop" }
    )

    $missing = @()
    foreach ($item in $checks) {
        $ok = Ensure-Tool -State $State -CommandName $item.Command -WingetId $item.WingetId -DisplayName $item.Name
        if (-not $ok) {
            $missing += $item.Name
        }
    }

    return $missing
}

function Ensure-Repository {
    param(
        $State,
        $Repository
    )

    $targetPath = Join-Path $State.workspaceRoot $Repository.Folder

    if (Test-Path $targetPath) {
        if ($CloneMode -eq "reuse") {
            Add-Log -State $State -Level "info" -Message "$($Repository.Folder) exists; reusing as configured."
            return $true
        }

        if ($CloneMode -eq "replace") {
            Add-Log -State $State -Level "warn" -Message "$($Repository.Folder) exists; replacing as configured."
            Remove-Item -Path $targetPath -Recurse -Force
        } else {
            Add-Log -State $State -Level "error" -Message "$($Repository.Folder) exists and clone mode is fail."
            return $false
        }
    }

    Add-Log -State $State -Level "info" -Message "Cloning $($Repository.Url) into $($Repository.Folder)..."
    $process = Start-Process -FilePath "git" -ArgumentList @("clone", $Repository.Url, $Repository.Folder) -WorkingDirectory $State.workspaceRoot -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Add-Log -State $State -Level "error" -Message "Clone failed for $($Repository.Folder) with exit code $($process.ExitCode)."
        return $false
    }

    return $true
}

function Parse-KeyValueDefaults {
    param([string[]]$Lines)

    $defaults = [ordered]@{}

    foreach ($line in $Lines) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $defaults[$matches[1]] = $matches[2]
        }
    }

    return $defaults
}

function Read-EnvValue {
    param(
        [string]$FilePath,
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $null
    }

    $content = Get-Content -Path $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        return $null
    }

    if ($content -match "(?m)^\s*$Key\s*=(.*)$") {
        $value = $matches[1].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        return $value
    }

    return $null
}

function Serialize-EnvLines {
    param(
        [string[]]$SourceLines,
        $Overrides
    )

    $result = @()
    $seen = @{}

    foreach ($line in $SourceLines) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $key = $matches[1]
            if ($Overrides.ContainsKey($key)) {
                $value = [string]$Overrides[$key]
                if ($value.Contains(' ')) {
                    $value = '"' + $value.Replace('"', '\"') + '"'
                }
                $result += "$key=$value"
                $seen[$key] = $true
                continue
            }
        }
        $result += $line
    }

    foreach ($key in $Overrides.Keys) {
        if (-not $seen.ContainsKey($key)) {
            $value = [string]$Overrides[$key]
            if ($value.Contains(' ')) {
                $value = '"' + $value.Replace('"', '\"') + '"'
            }
            $result += "$key=$value"
        }
    }

    return $result
}

function New-RequiredOverrides {
    $workspaceDir = Join-Path $OpenClawConfigDir "workspace"
    $providerKeyName = ""
    $providerKeyValue = ""

    if ($Provider -eq "openai") {
        $providerKeyName = "OPENAI_API_KEY"
        $providerKeyValue = $OpenAIApiKey
    } elseif ($Provider -eq "google") {
        $providerKeyName = "GOOGLE_API_KEY"
        $providerKeyValue = $GoogleApiKey
    } else {
        $providerKeyName = "ANTHROPIC_API_KEY"
        $providerKeyValue = $AnthropicApiKey
    }

    if ([string]::IsNullOrWhiteSpace($providerKeyValue)) {
        throw "Selected provider API key value is empty."
    }

    if ([string]::IsNullOrWhiteSpace($LiteLlmMasterKey)) {
        throw "LITELLM_MASTER_KEY is empty."
    }

    $overrides = [ordered]@{
        OPENCLAW_CONFIG_DIR = $OpenClawConfigDir
        OPENCLAW_WORKSPACE_DIR = $workspaceDir
        OPENAI_API_KEY = ""
        GOOGLE_API_KEY = ""
        ANTHROPIC_API_KEY = ""
        LITELLM_MASTER_KEY = $LiteLlmMasterKey
    }

    $overrides[$providerKeyName] = $providerKeyValue
    return $overrides
}

function Write-EnvFile {
    param(
        $State,
        [string]$InfraDirectory
    )

    $envExamplePath = Join-Path $InfraDirectory ".env.example"
    if (-not (Test-Path $envExamplePath)) {
        throw "Cannot find $envExamplePath"
    }

    $sourceLines = Get-Content -Path $envExamplePath
    $defaults = Parse-KeyValueDefaults -Lines $sourceLines
    if ($defaults.Count -eq 0) {
        throw ".env.example did not contain parseable key=value entries."
    }

    $overrides = New-RequiredOverrides
    $finalLines = Serialize-EnvLines -SourceLines $sourceLines -Overrides $overrides

    $envPath = Join-Path $InfraDirectory ".env"
    Set-Content -Path $envPath -Value ($finalLines -join [Environment]::NewLine) -Encoding utf8

    $envContent = Get-Content -Path $envPath -Raw
    foreach ($required in @("OPENCLAW_CONFIG_DIR", "OPENCLAW_WORKSPACE_DIR", "LITELLM_MASTER_KEY")) {
        if ($envContent -notmatch "(?m)^$required=") {
            throw "Missing required key after write: $required"
        }
    }

    if ($Provider -eq "openai" -and $envContent -notmatch "(?m)^OPENAI_API_KEY=") {
        throw "Missing selected provider key OPENAI_API_KEY"
    }

    if ($Provider -eq "google" -and $envContent -notmatch "(?m)^GOOGLE_API_KEY=") {
        throw "Missing selected provider key GOOGLE_API_KEY"
    }

    if ($Provider -eq "anthropic" -and $envContent -notmatch "(?m)^ANTHROPIC_API_KEY=") {
        throw "Missing selected provider key ANTHROPIC_API_KEY"
    }

    Add-Checkpoint -State $State -StepId "env" -Message "Wrote $envPath"
}

function Invoke-Infra {
    param(
        $State,
        [string]$InfraDirectory
    )

    $scriptPath = $InfraScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = Join-Path $InfraDirectory "zaloclaw-docker-setup.ps1"
    }

    if (-not (Test-Path $scriptPath)) {
        throw "Windows infra script not found: $scriptPath"
    }

    Add-Log -State $State -Level "info" -Message "Running infra script: $scriptPath"
    $process = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) -WorkingDirectory $InfraDirectory -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Infra script exited with code $($process.ExitCode)"
    }
}

function Cleanup-OpenClawConfigDir {
    param(
        $State
    )

    if ([string]::IsNullOrWhiteSpace($OpenClawConfigDir)) {
        throw "OPENCLAW_CONFIG_DIR is empty."
    }

    $resolved = [System.IO.Path]::GetFullPath($OpenClawConfigDir)
    $rootPath = [System.IO.Path]::GetPathRoot($resolved)
    if ($resolved -eq $rootPath) {
        throw "Refusing to remove root path as OPENCLAW_CONFIG_DIR: $resolved"
    }

    if (Test-Path -LiteralPath $resolved) {
        Add-Log -State $State -Level "info" -Message "Cleaning OpenClaw directory before infra setup: $resolved"
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Add-Checkpoint -State $State -StepId "infra" -Message "Removed existing OpenClaw directory $resolved"
    } else {
        Add-Checkpoint -State $State -StepId "infra" -Message "OpenClaw directory did not exist: $resolved"
    }

    New-Item -Path $resolved -ItemType Directory -Force | Out-Null
    Add-Checkpoint -State $State -StepId "infra" -Message "Prepared clean OpenClaw directory $resolved"
}

function Find-OpenClawGatewayContainer {
    param($State)

    try {
        Add-Log -State $State -Level "info" -Message "Finding OpenClaw gateway container..."
        $output = & docker ps --format "{{.Names}}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Log -State $State -Level "warn" -Message "Failed to list docker containers"
            return $null
        }
        $containers = $output | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $gatewayContainer = $containers | Where-Object { $_ -like "*openclaw-gateway*" } | Select-Object -First 1
        if ($gatewayContainer) {
            Add-Log -State $State -Level "info" -Message "Found OpenClaw gateway container: $gatewayContainer"
            return $gatewayContainer
        }
        Add-Log -State $State -Level "warn" -Message "No container with 'openclaw-gateway' pattern found"
        return $null
    } catch {
        Add-Log -State $State -Level "warn" -Message "Error finding container: $_"
        return $null
    }
}

function Update-UiEnvContainerName {
    param(
        $State,
        [string]$UiDirectory,
        [string]$ContainerName
    )

    try {
        $uiEnvPath = Join-Path $UiDirectory ".env"
        if (-not (Test-Path -LiteralPath $UiDirectory)) {
            Add-Log -State $State -Level "info" -Message "Skipping UI container env: zaloclaw-ui directory not found"
            return $false
        }
        if (-not (Test-Path -LiteralPath $uiEnvPath)) {
            Add-Log -State $State -Level "info" -Message "Skipping UI container env: .env not found"
            return $false
        }
        $uiEnvContent = Get-Content -Path $uiEnvPath -Raw
        $lines = $uiEnvContent -split "`r?`n"
        $outputLines = @()
        $found = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*OPENCLAW_GATEWAY_CONTAINER\s*=') {
                $outputLines += "OPENCLAW_GATEWAY_CONTAINER=$ContainerName"
                $found = $true
            } else {
                $outputLines += $line
            }
        }
        if (-not $found) {
            $outputLines += "OPENCLAW_GATEWAY_CONTAINER=$ContainerName"
        }
        Set-Content -Path $uiEnvPath -Value ($outputLines -join [Environment]::NewLine) -Encoding utf8
        Add-Checkpoint -State $State -StepId "infra" -Message "Updated UI .env with OPENCLAW_GATEWAY_CONTAINER=$ContainerName"
        Add-Log -State $State -Level "info" -Message "Updated zaloclaw-ui .env: OPENCLAW_GATEWAY_CONTAINER=$ContainerName"
        return $true
    } catch {
        Add-Log -State $State -Level "warn" -Message "Failed to update UI .env with container name: $_"
        return $false
    }
}

function Maybe-LaunchUi {
    param(
        $State,
        [string]$UiDirectory
    )

    if (-not $LaunchUi) {
        $State.uiRuntime.status = "skipped"
        $State.uiRuntime.lastMessage = "User skipped UI launch"
        return
    }

    $packageJson = Join-Path $UiDirectory "package.json"
    if (-not (Test-Path $packageJson)) {
        $State.uiRuntime.status = "failed"
        $State.uiRuntime.lastMessage = "Cannot start UI: package.json not found"
        return
    }

    $State.uiRuntime.status = "running"
    $process = Start-Process -FilePath "npm.cmd" -ArgumentList @("run", "dev") -WorkingDirectory $UiDirectory -PassThru
    $State.uiRuntime.pid = $process.Id
    $State.uiRuntime.lastMessage = "UI launched in background"
}

function Print-Summary {
    param($State, $GatewayToken = $null)

    Write-Host ""
    Write-Host "=== Setup Summary ==="
    foreach ($step in $State.steps) {
        Write-Host "- $($step.id): $($step.status)"
        if ($step.lastError) {
            Write-Host "  reason: $($step.lastError)"
        }
    }

    Write-Host "setup completion: $($State.setupCompletion.status)"
    Write-Host "ui runtime: $($State.uiRuntime.status)"

    if ($State.blockedReasons.Count -gt 0) {
        Write-Host "blocked reasons:"
        foreach ($reason in $State.blockedReasons) {
            Write-Host "- $reason"
        }
    }

    if ($GatewayToken) {
        Write-Host ""
        Write-Host "=== OpenClaw Gateway Token ==="
        Write-Host "Token: $GatewayToken"
        Write-Host ""
        Write-Host "Use this token to connect to OpenClaw Gateway interface."
    }
}

$admin = Test-IsAdmin
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

if (-not (Test-Path $WorkspaceRoot)) {
    New-Item -Path $WorkspaceRoot -ItemType Directory -Force | Out-Null
}

$state = New-State -Workspace $WorkspaceRoot -IsAdmin $admin

try {
    Save-State -State $state

    Set-StepStatus -State $state -Id "platform" -Status "running"
    Add-Checkpoint -State $state -StepId "platform" -Message "Detected platform windows"
    Add-Checkpoint -State $state -StepId "platform" -Message "Admin-like permissions: $admin"
    Set-StepStatus -State $state -Id "platform" -Status "done"
    Save-State -State $state

    Set-StepStatus -State $state -Id "prerequisites" -Status "running"
    $missing = Ensure-Prerequisites -State $state
    if ($missing.Count -gt 0) {
        $reason = "Missing prerequisites after checks/install attempts: $($missing -join ', ')"
        Set-StepStatus -State $state -Id "prerequisites" -Status "blocked" -ErrorMessage $reason
        $state.blockedReasons += $reason
        Save-State -State $state
        Print-Summary -State $state
        exit 1
    }

    Add-Checkpoint -State $state -StepId "prerequisites" -Message "All prerequisites available"
    Set-StepStatus -State $state -Id "prerequisites" -Status "done"
    Save-State -State $state

    Set-StepStatus -State $state -Id "clone" -Status "running"
    foreach ($repo in $Repositories) {
        $ok = Ensure-Repository -State $state -Repository $repo
        if (-not $ok) {
            $reason = "Repository setup failed for $($repo.Folder)."
            Set-StepStatus -State $state -Id "clone" -Status "blocked" -ErrorMessage $reason
            $state.blockedReasons += $reason
            Save-State -State $state
            Print-Summary -State $state
            exit 1
        }
        Add-Checkpoint -State $state -StepId "clone" -Message "$($repo.Folder) prepared"
    }

    Set-StepStatus -State $state -Id "clone" -Status "done"
    Save-State -State $state

    $infraDir = Join-Path $WorkspaceRoot "zaloclaw-infra"
    if (-not (Test-Path $infraDir)) {
        throw "zaloclaw-infra directory not found after clone step."
    }

    Set-StepStatus -State $state -Id "env" -Status "running"
    Write-EnvFile -State $state -InfraDirectory $infraDir
    Set-StepStatus -State $state -Id "env" -Status "done"
    Save-State -State $state

    Set-StepStatus -State $state -Id "infra" -Status "running"
    Cleanup-OpenClawConfigDir -State $state
    Invoke-Infra -State $state -InfraDirectory $infraDir
    Add-Checkpoint -State $state -StepId "infra" -Message "Infra script completed"
    Set-StepStatus -State $state -Id "infra" -Status "done"
    Save-State -State $state

    $gatewayToken = $null
    try {
        $infraEnvPath = Join-Path $infraDir ".env"
        $gatewayToken = Read-EnvValue -FilePath $infraEnvPath -Key "OPENCLAW_GATEWAY_TOKEN"
        if ($gatewayToken) {
            Add-Log -State $state -Level "info" -Message "OpenClaw Gateway Token: $gatewayToken"
        }
    } catch {
        Add-Log -State $state -Level "warn" -Message "Could not read gateway token: $_"
    }

    try {
        $containerName = Find-OpenClawGatewayContainer -State $state
        if ($containerName) {
            $uiDir = Join-Path $WorkspaceRoot "zaloclaw-ui"
            if (Test-Path -LiteralPath $uiDir) {
                Update-UiEnvContainerName -State $state -UiDirectory $uiDir -ContainerName $containerName
            }
        }
    } catch {
        Add-Log -State $state -Level "warn" -Message "Could not update UI container name: $_"
    }

    Set-StepStatus -State $state -Id "ui" -Status "running"
    $uiDir = Join-Path $WorkspaceRoot "zaloclaw-ui"
    Maybe-LaunchUi -State $state -UiDirectory $uiDir
    Set-StepStatus -State $state -Id "ui" -Status "done"

    $state.setupCompletion.status = "complete"
    $state.setupCompletion.completedAt = (Get-Date).ToString("o")
    Save-State -State $state

    Print-Summary -State $state -GatewayToken $gatewayToken
    exit 0
} catch {
    $message = $_.Exception.Message
    Add-Log -State $state -Level "error" -Message "Unexpected setup error: $message"
    $state.setupCompletion.status = "failed"

    $runningStep = $null
    foreach ($step in $state.steps) {
        if ($step.status -eq "running") {
            $runningStep = $step
            break
        }
    }

    if ($runningStep -ne $null) {
        Set-StepStatus -State $state -Id $runningStep.id -Status "failed" -ErrorMessage $message
    }

    $state.blockedReasons += $message
    Save-State -State $state
    Print-Summary -State $state
    exit 1
}
