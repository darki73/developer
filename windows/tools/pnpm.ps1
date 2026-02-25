# windows/tools/pnpm.ps1
# Installs pnpm — fast, disk space efficient package manager

function Get-PnpmMetadata {
    return @{
        Name        = "pnpm"
        Description = "Fast, disk space efficient Node.js package manager"
        Url         = "https://pnpm.io/"
    }
}

function Install-Pnpm {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"
    )

    $installDir = Join-Path $BaseDir "pnpm"
    $storeDir   = Join-Path $BaseDir "pnpm\store"

    Ensure-Dir $installDir
    Ensure-Dir $storeDir

    Set-PersistentEnvVar "PNPM_HOME"      $installDir
    Set-PersistentEnvVar "PNPM_STORE_DIR" $storeDir

    # Resolve version
    $versions = Get-GitHubReleaseVersions -Repo "pnpm/pnpm"
    if ($versions.Count -eq 0) {
        $versions = @("10.5.2", "9.15.9", "8.15.9")
    }
    $version = Invoke-VersionPicker -ToolName "pnpm" -RequestedVersion $RequestedVersion -AvailableVersions $versions

    if (-not $version) { return $false }

    # Download specific version binary from GitHub releases
    $pnpmArch = switch ($Arch) { "arm64" { "arm64" } default { "x64" } }
    $exeName     = "pnpm-win-${pnpmArch}.exe"
    $downloadUrl = "https://github.com/pnpm/pnpm/releases/download/v${version}/${exeName}"
    $pnpmExe     = Join-Path $installDir "pnpm.exe"

    Write-Info "Downloading pnpm v$version..."
    try {
        Invoke-Download -Uri $downloadUrl -OutFile $pnpmExe
    }
    catch {
        Write-Err "Failed to download pnpm v${version}: $_"
        return $false
    }

    if (-not (Test-Path $pnpmExe)) {
        Write-Err "pnpm.exe not found at $installDir after download"
        return $false
    }

    # Set in-process for pnpm to find its own home
    $env:PNPM_HOME = $installDir

    Add-ToUserPath @($installDir)

    try {
        $result = & $pnpmExe --version 2>&1
        Write-Success "pnpm: v$result"
        return $true
    }
    catch {
        Write-Info "pnpm installed (restart terminal to verify)"
        return $true
    }
}

function Detect-Pnpm {
    param([string]$BaseDir)
    # Check BaseDir
    $pnpmExe = Join-Path $BaseDir "pnpm\pnpm.exe"
    if (Test-Path $pnpmExe) {
        try {
            $result = (& $pnpmExe --version 2>&1).Trim()
            return @{ Installed = $true; Version = $result }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    # Check PATH
    $onPath = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($onPath) {
        try {
            $result = (& pnpm --version 2>&1).Trim()
            return @{ Installed = $true; Version = $result }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    return @{ Installed = $false; Version = $null }
}

function Test-Pnpm {
    param([string]$BaseDir)
    $pnpmExe = Join-Path $BaseDir "pnpm\pnpm.exe"
    if (Test-Path $pnpmExe) {
        try {
            $result = & $pnpmExe --version 2>&1
            Write-Success "pnpm: v$result"
            return $true
        }
        catch {}
    }
    Write-Err "pnpm: not found"
    return $false
}
