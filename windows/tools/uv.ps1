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

    $env:UV_INSTALL_DIR = $installDir
    $env:UV_NO_MODIFY_PATH = "1"

    # Resolve archive name for this architecture
    $uvArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        "aarch64-pc-windows-msvc"
    } else {
        "x86_64-pc-windows-msvc"
    }
    $archiveName = "uv-$uvArch.zip"
    $baseUrl     = "https://github.com/astral-sh/uv/releases/download/$version"
    $archiveUrl  = "$baseUrl/$archiveName"
    $sha256Url   = "$archiveUrl.sha256"

    $tempDir     = Join-Path $env:TEMP "uv-install-$([Guid]::NewGuid().ToString('N'))"
    Ensure-Dir $tempDir
    $archivePath = Join-Path $tempDir $archiveName

    try {
        Write-Info "Downloading uv $version ($uvArch)..."
        try {
            Invoke-Download -Uri $archiveUrl -OutFile $archivePath
        }
        catch {
            Write-Err "Failed to download uv archive: $_"
            return $false
        }

        # SHA256 verification — required, not best-effort
        $expectedSha = $null
        try {
            $shaContent = (Invoke-RestMethod -Uri $sha256Url -UseBasicParsing).ToString().Trim()
            # Format is "<hash>  <filename>"
            $expectedSha = ($shaContent -split '\s+')[0].ToLower()
        }
        catch {
            Write-Err "Failed to fetch SHA256 from $sha256Url`: $_"
            return $false
        }

        if (-not $expectedSha -or $expectedSha.Length -ne 64) {
            Write-Err "Invalid SHA256 from upstream: '$expectedSha'"
            return $false
        }

        $actualSha = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower()
        if ($actualSha -ne $expectedSha) {
            Write-Err "Checksum mismatch for $archiveName"
            Write-Err "  Expected: $expectedSha"
            Write-Err "  Actual:   $actualSha"
            return $false
        }
        Write-Success "SHA256 verified"

        # Extract to install dir
        try {
            Expand-Archive -Path $archivePath -DestinationPath $installDir -Force
        }
        catch {
            Write-Err "Failed to extract uv archive: $_"
            return $false
        }
    }
    finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
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

function Detect-Uv {
    param([string]$BaseDir)
    Resolve-InstalledTool `
        -BasePath (Join-Path $BaseDir "uv\uv.exe") `
        -CommandName "uv" `
        -GetVersion { param($exe) (& $exe --version 2>&1) -replace "^uv\s+", "" -replace "\s+\(.*$", "" }
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