#Requires -Version 5.1
<#
.SYNOPSIS
    Developer environment setup for Windows.

.DESCRIPTION
    Modular tool installer that sets up a complete dev environment.
    Each tool is a self-contained module in the tools/ directory.
    Supports interactive mode and config file mode.

.PARAMETER ConfigFile
    Path to a JSON configuration file. See configs/example.json.

.PARAMETER ListTools
    List all available tools and exit.

.EXAMPLE
    # Interactive mode — prompts for everything
    .\setup.ps1

    # Config file mode — unattended install
    .\setup.ps1 -ConfigFile .\configs\example.json

    # List available tools
    .\setup.ps1 -ListTools
#>

param(
    [string]$ConfigFile,
    [switch]$ListTools
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot

# ============================================================================
# Load libraries
# ============================================================================

. (Join-Path $ScriptRoot "lib\output.ps1")
. (Join-Path $ScriptRoot "lib\env.ps1")
. (Join-Path $ScriptRoot "lib\prompt.ps1")
. (Join-Path $ScriptRoot "lib\tui.ps1")
. (Join-Path $ScriptRoot "lib\versions.ps1")

# ============================================================================
# Tool registry — discovers all tool modules
# ============================================================================

# Dot-source all tool modules at script scope so Install-*/Test-* functions
# remain available throughout the script lifetime (not trapped inside a function).
$toolsDir = Join-Path $ScriptRoot "tools"
foreach ($file in Get-ChildItem $toolsDir -Filter "*.ps1" | Sort-Object Name) {
    . $file.FullName
}

function Get-AvailableTools {
    $tools = [ordered]@{}

    foreach ($file in Get-ChildItem (Join-Path $ScriptRoot "tools") -Filter "*.ps1" | Sort-Object Name) {
        $toolName = $file.BaseName
        $metadataFn = "Get-$($toolName.Substring(0,1).ToUpper() + $toolName.Substring(1))Metadata"

        if (Get-Command $metadataFn -ErrorAction SilentlyContinue) {
            $meta = & $metadataFn
            $tools[$toolName] = @{
                Name        = $meta.Name
                Description = $meta.Description
                Url         = $meta.Url
                DependsOn   = if ($meta.DependsOn) { $meta.DependsOn } else { @() }
                ScriptPath  = $file.FullName
            }
        }
    }

    return $tools
}

function Resolve-InstallOrder {
    param([System.Collections.Specialized.OrderedDictionary]$AllTools, [string[]]$SelectedTools)

    $ordered = [System.Collections.ArrayList]::new()
    $visited = @{}

    function Add-WithDeps {
        param([string]$ToolName)
        if ($visited.ContainsKey($ToolName)) { return }
        $visited[$ToolName] = $true

        $tool = $AllTools[$ToolName]
        if ($tool -and $tool.DependsOn) {
            foreach ($dep in $tool.DependsOn) {
                if ($AllTools.Contains($dep)) {
                    if ($dep -notin $SelectedTools) {
                        Write-Info "Auto-enabling $dep (required by $ToolName)"
                    }
                    Add-WithDeps $dep
                }
            }
        }
        [void]$ordered.Add($ToolName)
    }

    foreach ($t in $SelectedTools) {
        Add-WithDeps $t
    }

    return $ordered.ToArray()
}

# ============================================================================
# Config loading
# ============================================================================

function Read-ConfigFile {
    param([string]$Path)
    try {
        $json = Get-Content $Path -Raw | ConvertFrom-Json
        $config = @{
            BaseDir  = $json.install_directory
            Arch     = if ($json.architecture) { $json.architecture } else { "amd64" }
            Tools    = @{}
        }

        if ($json.tools) {
            foreach ($prop in $json.tools.PSObject.Properties) {
                $config.Tools[$prop.Name] = @{
                    Enabled = $prop.Value.enabled
                    Version = if ($prop.Value.version) { $prop.Value.version } else { "latest" }
                }
            }
        }

        return $config
    }
    catch {
        Write-Err "Failed to read config file: $_"
        exit 1
    }
}

function Save-ConfigFile {
    param([string]$Path, [string]$BaseDir, [string]$Arch, [hashtable]$ToolSelections)

    $toolsObj = [ordered]@{}
    foreach ($kv in $ToolSelections.GetEnumerator() | Sort-Object Key) {
        $toolsObj[$kv.Key] = [ordered]@{
            enabled = $kv.Value.Enabled
            version = $kv.Value.Version
        }
    }

    $config = [ordered]@{
        install_directory = $BaseDir
        architecture      = $Arch
        tools             = $toolsObj
    }

    $config | ConvertTo-Json -Depth 4 | Set-Content $Path -Encoding UTF8
    Write-Info "Config saved to $Path"
}

# ============================================================================
# Interactive prompts
# ============================================================================

function Invoke-InteractiveSetup {
    param([System.Collections.Specialized.OrderedDictionary]$AvailableTools)

    $steps = [System.Collections.ArrayList]::new()

    # ── Step 1: Install directory ────────────────────────────────────────────
    Write-WizardFrame -CompletedSteps $steps
    $baseInput = Invoke-TextPrompt `
        -Title "Install directory" `
        -Hint "All tools will be installed under this path." `
        -Required

    $baseDir = Normalize-Path $baseInput
    [void]$steps.Add(@{ Label = "Directory"; Value = $baseDir })

    # ── Step 2: Architecture ─────────────────────────────────────────────────
    Write-WizardFrame -CompletedSteps $steps
    $archItems = @(
        @{ Label = "amd64"; Description = "x86_64 (Intel/AMD)" }
        @{ Label = "arm64"; Description = "ARM64 (Snapdragon/Apple Silicon)" }
    )
    $archIndex = Invoke-SelectPrompt -Title "Architecture:" -Items $archItems -Default 0
    $arch = $archItems[$archIndex].Label
    [void]$steps.Add(@{ Label = "Architecture"; Value = $arch })

    # ── Step 3: Tool selection ───────────────────────────────────────────────
    Write-WizardFrame -CompletedSteps $steps
    $checkboxItems = @()
    foreach ($name in @($AvailableTools.Keys)) {
        $tool = $AvailableTools[$name]
        $checkboxItems += @{
            Key         = $name
            Label       = $name
            Description = $tool.Description
            DependsOn   = $tool.DependsOn
            Checked     = $true
        }
    }

    $checkboxItems = Invoke-CheckboxPrompt -Title "Select tools to install:" -Items $checkboxItems
    $selectedNames = @($checkboxItems | Where-Object { $_.Checked } | ForEach-Object { $_.Key })
    [void]$steps.Add(@{ Label = "Tools"; Value = "$($selectedNames.Count) selected: $($selectedNames -join ', ')" })

    # Build tool selections — interactive mode uses "pick" for version pickers
    $toolSelections = @{}
    foreach ($item in $checkboxItems) {
        $toolSelections[$item.Key] = @{
            Enabled = [bool]$item.Checked
            Version = if ($item.Checked) { "pick" } else { "latest" }
        }
    }

    # ── Step 4: Save config? ─────────────────────────────────────────────────
    Write-WizardFrame -CompletedSteps $steps
    $wantSave = Invoke-ConfirmPrompt -Title "Save configuration for later?" -Default $false
    if ($wantSave) {
        $savePath = Invoke-TextPrompt `
            -Title "Save path" `
            -Default ".\developer-config.json"

        Save-ConfigFile -Path $savePath -BaseDir $baseDir -Arch $arch -ToolSelections $toolSelections
    }

    return @{
        BaseDir = $baseDir
        Arch    = $arch
        Tools   = $toolSelections
    }
}

# ============================================================================
# Main
# ============================================================================

# Discover available tools
$availableTools = Get-AvailableTools

# --ListTools: just show what's available and exit
if ($ListTools) {
    $dim = Get-TuiDimensions
    $boxW = $dim.BoxWidth
    $innerW = $dim.InnerWidth

    Write-Host ""
    Write-TuiTopBorder -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiTextLine -Text "  Available Tools" -InnerWidth $innerW -Color White
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiDivider -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW

    foreach ($kv in $availableTools.GetEnumerator()) {
        $tool = $kv.Value
        $deps = if ($tool.DependsOn.Count -gt 0) { " (requires: $($tool.DependsOn -join ', '))" } else { "" }
        $line = "  $($tool.Name.PadRight(14))$($tool.Description)$deps"
        Write-TuiTextLine -Text $line -InnerWidth $innerW -Color Gray
    }

    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiBottomBorder -BoxWidth $boxW
    Write-Host ""
    exit 0
}

# Load config: from file or interactively
if ($ConfigFile) {
    if (-not (Test-Path $ConfigFile)) {
        Write-Err "Config file not found: $ConfigFile"
        exit 1
    }
    $config = Read-ConfigFile $ConfigFile
} else {
    $config = Invoke-InteractiveSetup -AvailableTools $availableTools
}

$baseDir = Normalize-Path $config.BaseDir
$arch    = $config.Arch

# Determine which tools are enabled
$enabledTools = @()
foreach ($kv in $config.Tools.GetEnumerator()) {
    if ($kv.Value.Enabled) {
        $enabledTools += $kv.Key
    }
}

if ($enabledTools.Count -eq 0) {
    Write-Err "No tools selected. Nothing to do."
    exit 0
}

# Resolve install order (respects dependencies)
$installOrder = Resolve-InstallOrder -AllTools $availableTools -SelectedTools $enabledTools

# Show summary and ask for confirmation
if (-not $ConfigFile) {
    # Interactive mode — bordered summary
    Write-SummaryFrame -BaseDir $baseDir -Arch $arch -Tools ($installOrder -join ", ")

    $proceed = Invoke-ConfirmPrompt -Title "Proceed with installation?" -Default $true
    if (-not $proceed) {
        Write-Err "Aborted."
        exit 0
    }
} else {
    # Config-file mode — bordered config info
    Write-ConfigFrame -ConfigFile $ConfigFile -BaseDir $baseDir -Arch $arch -Tools ($installOrder -join ", ")
}

# Track results
$totalSteps = $installOrder.Count
$currentStep = 0
$installedTools = @{}

# ============================================================================
# Installation — TUI dashboard or fallback scrolling output
# ============================================================================

$useTui = Test-InteractiveConsole

if ($useTui) {
    # TUI dashboard mode — suppress PowerShell progress bars (they corrupt TUI display)
    $savedProgressPref = $Global:ProgressPreference
    $Global:ProgressPreference = 'SilentlyContinue'

    Initialize-Tui -BaseDir $baseDir -Arch $arch -ToolNames $installOrder -Total $totalSteps
    Start-Tui

    foreach ($toolName in $installOrder) {
        $currentStep++
        $toolConfig = $config.Tools[$toolName]
        $version = if ($toolConfig.Version) { $toolConfig.Version } else { "latest" }

        Update-TuiTool -Name $toolName -Status "installing"

        # Determine install function name (handle hyphens: claude-code → Claude-code)
        $fnSuffix = $toolName.Substring(0,1).ToUpper() + $toolName.Substring(1)
        $installFn = "Install-$fnSuffix"

        if (-not (Get-Command $installFn -ErrorAction SilentlyContinue)) {
            Write-Err "Install function '$installFn' not found for tool '$toolName'"
            $installedTools[$toolName] = $false
            Update-TuiTool -Name $toolName -Status "failed"
            continue
        }

        # Build params — all install functions take BaseDir and RequestedVersion
        $params = @{
            BaseDir          = $baseDir
            RequestedVersion = $version
        }

        # Some tools accept extra params
        if ($toolName -in @("go", "pnpm", "vscode", "git")) {
            $params["Arch"] = $arch
        }
        if ($toolName -eq "git") {
            $params["InstalledTools"] = $installedTools
        }

        try {
            $result = & $installFn @params
            $installedTools[$toolName] = $result
            if ($result) {
                Update-TuiTool -Name $toolName -Status "done"
            } else {
                Update-TuiTool -Name $toolName -Status "failed"
            }
        }
        catch {
            Write-Err "Error installing $toolName`: $_"
            $installedTools[$toolName] = $false
            Update-TuiTool -Name $toolName -Status "failed"
        }
    }

    # Verification
    Add-TuiLog -Type "info" -Message "Verifying installations..."
    foreach ($toolName in $installOrder) {
        $testFn = "Test-$($toolName.Substring(0,1).ToUpper() + $toolName.Substring(1))"
        if (Get-Command $testFn -ErrorAction SilentlyContinue) {
            & $testFn -BaseDir $baseDir | Out-Null
        }
    }

    # Completion
    $succeeded = ($installedTools.Values | Where-Object { $_ }).Count
    $failed    = $totalSteps - $succeeded

    if ($failed -eq 0) {
        Complete-Tui -Message "Setup complete! ($succeeded/$totalSteps tools) Restart your terminal to begin."
    } else {
        Complete-Tui -Message "Setup finished with errors. ($succeeded/$totalSteps succeeded) Check log for details."
    }

    # Restore progress preference
    $Global:ProgressPreference = $savedProgressPref
} else {
    # Fallback: scrolling output for non-interactive consoles
    Write-Banner @(
        "Installing $($installOrder.Count) tools"
        "$baseDir"
    )

    foreach ($toolName in $installOrder) {
        $currentStep++
        $toolConfig = $config.Tools[$toolName]
        $version = if ($toolConfig.Version) { $toolConfig.Version } else { "latest" }

        Write-Step -StepNumber $currentStep -TotalSteps $totalSteps -Message "Installing $toolName"

        $fnSuffix = $toolName.Substring(0,1).ToUpper() + $toolName.Substring(1)
        $installFn = "Install-$fnSuffix"

        if (-not (Get-Command $installFn -ErrorAction SilentlyContinue)) {
            Write-Err "Install function '$installFn' not found for tool '$toolName'"
            $installedTools[$toolName] = $false
            continue
        }

        $params = @{
            BaseDir          = $baseDir
            RequestedVersion = $version
        }
        if ($toolName -in @("go", "pnpm", "vscode", "git")) {
            $params["Arch"] = $arch
        }
        if ($toolName -eq "git") {
            $params["InstalledTools"] = $installedTools
        }

        try {
            $result = & $installFn @params
            $installedTools[$toolName] = $result
        }
        catch {
            Write-Err "Error installing $toolName`: $_"
            $installedTools[$toolName] = $false
        }
    }

    Write-Step -Message "Verification"
    foreach ($toolName in $installOrder) {
        $testFn = "Test-$($toolName.Substring(0,1).ToUpper() + $toolName.Substring(1))"
        if (Get-Command $testFn -ErrorAction SilentlyContinue) {
            & $testFn -BaseDir $baseDir | Out-Null
        }
    }

    $succeeded = ($installedTools.Values | Where-Object { $_ }).Count
    $failed    = $totalSteps - $succeeded

    Write-Host ""
    if ($failed -eq 0) {
        Write-Banner @(
            "Setup complete! ($succeeded/$totalSteps tools)"
            "Restart your terminal to begin."
        )
    } else {
        Write-Banner @(
            "Setup finished with errors ($succeeded/$totalSteps succeeded)"
            "Check the output above for details."
            "Restart your terminal to begin."
        )
    }
}

# Print install paths
Write-Host ""
Write-Host "  Installed to:" -ForegroundColor White
foreach ($toolName in $installOrder) {
    if ($installedTools[$toolName]) {
        $path = switch ($toolName) {
            "uv"     { Join-Path $baseDir "uv" }
            "python" { "managed by uv (uv run python)" }
            "pnpm"   { Join-Path $baseDir "pnpm" }
            "node"   { Join-Path $baseDir "pnpm\nodejs" }
            "go"     { Join-Path $baseDir "go\root" }
            "vscode" { Join-Path $baseDir "vscode" }
            "git"    { Join-Path $baseDir "git" }
            "claude-code" { "$env:USERPROFILE\.local\bin" }
            default  { $baseDir }
        }
        Write-Host "    $($toolName.PadRight(12)) → $path" -ForegroundColor Gray
    }
}
Write-Host ""