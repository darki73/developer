# windows/tools/uv.ps1
# Installs uv — Python package and project manager by Astral

function Get-UvMetadata {
    return @{
        Name        = "uv"
        Description = "Python package and project manager (Astral)"
        Url         = "https://docs.astral.sh/uv/"
    }
}

function Install-Uv {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest"
    )

    $installDir = Join-Path $BaseDir "uv"
    $cacheDir   = Join-Path $BaseDir "uv\cache"
    $pythonDir  = Join-Path $BaseDir "uv\python"

    Ensure-Dir $installDir
    Ensure-Dir $cacheDir
    Ensure-Dir $pythonDir

    # Set persistent env vars
    Set-PersistentEnvVar "UV_INSTALL_DIR"        $installDir
    Set-PersistentEnvVar "UV_CACHE_DIR"          $cacheDir
    Set-PersistentEnvVar "UV_PYTHON_INSTALL_DIR" $pythonDir

    # Resolve version
    $versions = Get-GitHubReleaseVersions -Repo "astral-sh/uv"
    if ($versions.Count -eq 0) {
        $versions = @("0.7.2", "0.6.16", "0.5.30")
    }
    $version = Invoke-VersionPicker -ToolName "uv" -RequestedVersion $RequestedVersion -AvailableVersions $versions

    if (-not $version) { return $false }

    # Must set in-process for the installer to pick it up
    $env:UV_INSTALL_DIR = $installDir
    $env:UV_NO_MODIFY_PATH = "1"

    $installerUrl = "https://astral.sh/uv/$version/install.ps1"
    Write-Info "Downloading uv $version installer..."

    try {
        Invoke-Expression "& { $(Invoke-RestMethod $installerUrl) }"
    }
    catch {
        Write-Err "Failed to download/run uv installer: $_"
        return $false
    }

    Add-ToUserPath @($installDir)

    $uvExe = Join-Path $installDir "uv.exe"
    if (Test-Path $uvExe) {
        $result = & $uvExe --version 2>&1
        Write-Success "uv: $result"
        return $true
    }

    Write-Err "uv.exe not found at $installDir"
    return $false
}

function Test-Uv {
    param([string]$BaseDir)
    $uvExe = Join-Path $BaseDir "uv\uv.exe"
    if (Test-Path $uvExe) {
        $result = & $uvExe --version 2>&1
        Write-Success "uv: $result"
        return $true
    }
    Write-Err "uv: not found"
    return $false
}