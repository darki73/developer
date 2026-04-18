# windows/tools/vscode.ps1
# Installs Visual Studio Code with full shell integration

function Get-VscodeMetadata {
    return @{
        Name        = "vscode"
        Description = "Visual Studio Code editor"
        Url         = "https://code.visualstudio.com/"
    }
}

function Install-Vscode {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"
    )

    $installDir = Join-Path $BaseDir "vscode"
    Ensure-Dir $installDir

    # Map architecture to VS Code download platform
    $vscodePlatform = switch ($Arch) {
        "arm64" { "win32-arm64" }
        default { "win32-x64" }
    }

    if ($RequestedVersion -eq "pick") {
        Write-Info "VS Code does not support version selection — installing latest"
    }

    # VS Code uses a direct download URL — no version picker needed for "latest"
    # For specific versions: https://update.code.visualstudio.com/{version}/{platform}/stable
    $installerUrl = if ($RequestedVersion -in @("latest", "pick")) {
        "https://update.code.visualstudio.com/latest/$vscodePlatform/stable"
    } else {
        "https://update.code.visualstudio.com/$RequestedVersion/$vscodePlatform/stable"
    }

    $installerPath = Join-Path $env:TEMP "VSCodeSetup.exe"

    try {
        Write-Info "Downloading VS Code installer ($vscodePlatform)..."
        Invoke-Download -Uri $installerUrl -OutFile $installerPath

        Write-Info "Installing to $installDir..."

        # MERGETASKS:
        #   !runcode              — don't launch after install
        #   addcontextmenufiles   — "Open with Code" for files
        #   addcontextmenufolders — "Open with Code" for folders
        #   associatewithfiles    — register as file handler
        #   addtopath             — add 'code' to PATH
        $mergeTasks = "!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath"
        $installerArgs = @(
            "/VERYSILENT"
            "/NORESTART"
            "/SP-"
            "/DIR=`"$installDir`""
            "/MERGETASKS=`"$mergeTasks`""
        )

        Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

        $codeExe = Join-Path $installDir "Code.exe"
        if (Test-Path $codeExe) {
            Write-Success "VS Code installed (context menus, file associations, PATH)"
            return $true
        }

        Write-Err "Code.exe not found at $installDir"
        return $false
    }
    catch {
        Write-Err "Failed to install VS Code: $_"
        return $false
    }
}

function Detect-Vscode {
    param([string]$BaseDir)
    Resolve-InstalledTool `
        -BasePath (Join-Path $BaseDir "vscode\bin\code.cmd") `
        -CommandName "code" `
        -GetVersion { param($exe) (& $exe --version 2>&1 | Select-Object -First 1) }
}

function Test-Vscode {
    param([string]$BaseDir)
    $codeCmd = Join-Path $BaseDir "vscode\bin\code.cmd"
    if (Test-Path $codeCmd) {
        try {
            $result = & $codeCmd --version 2>&1 | Select-Object -First 1
            Write-Success "code: $result"
            return $true
        }
        catch {}
    }
    Write-Err "code: not found"
    return $false
}
