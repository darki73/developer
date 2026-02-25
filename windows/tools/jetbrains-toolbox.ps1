# windows/tools/jetbrains-toolbox.ps1
# Installs JetBrains Toolbox — a manager for JetBrains IDEs (IntelliJ, Rider, PyCharm, etc.)
#
# Toolbox installs itself to %LOCALAPPDATA%\JetBrains\Toolbox (not customizable at install time).
# However, we pre-seed its .settings.json so that IDEs it manages are downloaded to $BaseDir\jetbrains-apps,
# keeping the bulk of disk usage on the user's chosen drive.

$script:JB_API = "https://data.services.jetbrains.com/products/releases"

function Get-Jetbrains-toolboxMetadata {
    return @{
        Name        = "jetbrains-toolbox"
        Description = "JetBrains Toolbox — IDE manager (JetBrains)"
        Url         = "https://www.jetbrains.com/toolbox-app/"
        DependsOn   = @()
    }
}

function Install-Jetbrains-toolbox {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"
    )

    # ── Fetch available versions from JetBrains API ──────────────────────────
    $apiUrl = "$script:JB_API`?code=TBA&type=release"
    $releases = @()
    $fallbackVersions = @("3.2", "3.1.2", "3.1.1", "3.1", "3.0.1")

    try {
        Write-Info "Fetching JetBrains Toolbox releases..."
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $releases = $response.TBA
    }
    catch {
        Write-Info "Could not fetch releases from API: $_"
    }

    # Build version list from API response
    $availableVersions = @()
    if ($releases -and $releases.Count -gt 0) {
        foreach ($rel in $releases) {
            $availableVersions += $rel.version
        }
    }
    if ($availableVersions.Count -eq 0) {
        Write-Info "Using fallback version list"
        $availableVersions = $fallbackVersions
    }

    # ── Resolve version ──────────────────────────────────────────────────────
    $selected = Invoke-VersionPicker -ToolName "JetBrains Toolbox" `
                                     -RequestedVersion $RequestedVersion `
                                     -AvailableVersions $availableVersions
    if (-not $selected) {
        Write-Err "No version selected"
        return $false
    }

    # ── Find matching release from API data ──────────────────────────────────
    $release = $null
    foreach ($rel in $releases) {
        if ($rel.version -eq $selected) {
            $release = $rel
            break
        }
    }

    if (-not $release) {
        # If using fallback or explicit version not in cache, re-fetch that specific version
        try {
            Write-Info "Fetching release info for version $selected..."
            $response = Invoke-RestMethod -Uri "$script:JB_API`?code=TBA&type=release" -UseBasicParsing
            foreach ($rel in $response.TBA) {
                if ($rel.version -eq $selected) {
                    $release = $rel
                    break
                }
            }
        }
        catch {
            Write-Err "Failed to fetch release info: $_"
        }

        if (-not $release) {
            Write-Err "Could not find release data for version $selected"
            return $false
        }
    }

    # ── Resolve platform download ────────────────────────────────────────────
    $platformKey = if ($Arch -eq "arm64") { "windowsARM64" } else { "windows" }
    $download = $release.downloads.$platformKey

    if (-not $download) {
        Write-Err "No download available for platform: $platformKey"
        return $false
    }

    $downloadUrl   = $download.link
    $expectedSize  = $download.size
    $checksumUrl   = $download.checksumLink

    Write-Info "JetBrains Toolbox $selected ($Arch)"
    Write-Info "URL: $downloadUrl"

    # ── Download installer ───────────────────────────────────────────────────
    $installerPath = Join-Path $env:TEMP "jetbrains-toolbox-setup.exe"

    try {
        Invoke-Download -Uri $downloadUrl -OutFile $installerPath
    }
    catch {
        Write-Err "Download failed: $_"
        return $false
    }

    if (-not (Test-Path $installerPath)) {
        Write-Err "Download produced no file"
        return $false
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Info "Downloaded $(Format-FileSize $fileSize)"

    # ── Verify file size ─────────────────────────────────────────────────────
    if ($expectedSize -and $fileSize -ne [long]$expectedSize) {
        Write-Err "Size mismatch: expected $expectedSize bytes, got $fileSize bytes"
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    # ── Verify SHA256 checksum ───────────────────────────────────────────────
    if ($checksumUrl) {
        try {
            Write-Info "Verifying SHA256 checksum..."
            $checksumData = (Invoke-RestMethod -Uri $checksumUrl -UseBasicParsing).Trim()
            # Format: "hash *filename" — extract just the hash
            $expectedChecksum = ($checksumData -split "\s+")[0]

            $actualChecksum = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()
            if ($actualChecksum -ne $expectedChecksum.ToLower()) {
                Write-Err "Checksum mismatch!"
                Write-Err "  Expected: $expectedChecksum"
                Write-Err "  Actual:   $actualChecksum"
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                return $false
            }
            Write-Success "Checksum verified"
        }
        catch {
            Write-Info "Could not verify checksum (proceeding anyway): $_"
        }
    }

    # ── Run silent installer ─────────────────────────────────────────────────
    Write-Info "Installing JetBrains Toolbox (silent)..."

    # Prevent Toolbox from auto-launching after install
    $env:START_JETBRAINS_TOOLBOX_AFTER_INSTALL = "0"

    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList "/headless" -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Write-Err "Installer exited with code $($process.ExitCode)"
            return $false
        }
    }
    catch {
        Write-Err "Installer failed: $_"
        return $false
    }
    finally {
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        # Clean up environment variable
        Remove-Item Env:\START_JETBRAINS_TOOLBOX_AFTER_INSTALL -ErrorAction SilentlyContinue
    }

    # ── Pre-seed IDE install location ────────────────────────────────────────
    # Toolbox stores settings in %LOCALAPPDATA%\JetBrains\Toolbox\.settings.json
    # Setting "install_location" redirects where IDEs are downloaded to
    $settingsDir = Join-Path $env:LOCALAPPDATA "JetBrains\Toolbox"
    $settingsFile = Join-Path $settingsDir ".settings.json"
    $appsDir = Join-Path $BaseDir "jetbrains-apps"

    Ensure-Dir $settingsDir
    Ensure-Dir $appsDir

    try {
        $settings = @{}
        if (Test-Path $settingsFile) {
            $existing = Get-Content $settingsFile -Raw -ErrorAction SilentlyContinue
            if ($existing) {
                $parsed = $existing | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $settings[$prop.Name] = $prop.Value
                    }
                }
            }
        }
        $settings["install_location"] = $appsDir
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
        Write-Success "IDE install location set to: $appsDir"
    }
    catch {
        Write-Info "Could not pre-seed settings (non-fatal): $_"
        Write-Info "You can set the IDE install location manually in Toolbox settings"
    }

    # ── Done ─────────────────────────────────────────────────────────────────
    Write-Success "JetBrains Toolbox $selected installed"
    Write-Info "IDEs will be installed to: $appsDir"
    Write-Info "Open Toolbox to sign in and install your IDEs"
    return $true
}

function Detect-Jetbrains-toolbox {
    param([string]$BaseDir)
    # Check known install path
    $toolboxExe = Join-Path $env:LOCALAPPDATA "JetBrains\Toolbox\bin\jetbrains-toolbox.exe"
    if (Test-Path $toolboxExe) {
        return @{ Installed = $true; Version = $null }
    }
    # Check PATH
    $onPath = Get-Command jetbrains-toolbox -ErrorAction SilentlyContinue
    if ($onPath) {
        return @{ Installed = $true; Version = $null }
    }
    return @{ Installed = $false; Version = $null }
}

function Test-Jetbrains-toolbox {
    param([string]$BaseDir)

    $toolboxExe = Join-Path $env:LOCALAPPDATA "JetBrains\Toolbox\bin\jetbrains-toolbox.exe"

    if (Test-Path $toolboxExe) {
        Write-Success "jetbrains-toolbox: installed at $toolboxExe"
        return $true
    }

    # Also check if it's on PATH (user might have added it manually)
    $onPath = Get-Command jetbrains-toolbox -ErrorAction SilentlyContinue
    if ($onPath) {
        Write-Success "jetbrains-toolbox: available on PATH"
        return $true
    }

    Write-Err "jetbrains-toolbox: not found"
    return $false
}
