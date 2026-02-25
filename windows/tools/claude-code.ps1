# windows/tools/claude-code.ps1
# Installs Claude Code — AI-powered coding assistant by Anthropic
#
# Reverse-engineered from the official install.ps1 / install.sh
#
# The official installer's flow:
#   1. Fetch version string from  $GCS_BUCKET/{channel}  (e.g. "stable" → "2.1.29")
#   2. Download binary from        $GCS_BUCKET/{version}/{platform}/claude.exe
#   3. Run   & $binary install {channel}    ← THIS IS BROKEN on Windows
#      - Reports "✔ Claude Code successfully installed!" but creates a 0-byte file
#        or no file at all in  $env:USERPROFILE\.local\bin\
#   4. Deletes the temp download in its finally block, so you lose the binary entirely
#
# Our approach: skip step 3 entirely. Just download the binary, verify it,
# copy it to the target location, and set up PATH ourselves.
#
# References:
#   https://github.com/anthropics/claude-code/issues/14942  (root cause analysis)
#   https://github.com/anthropics/claude-code/issues/16041  (binary not copied)
#   https://github.com/anthropics/claude-code/issues/9281   (0-byte file)

$script:GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

function Get-Claude-codeMetadata {
    return @{
        Name        = "claude-code"
        Description = "Claude Code — AI coding assistant (Anthropic)"
        Url         = "https://code.claude.com/"
        DependsOn   = @("git")  # Claude Code uses Git Bash internally
    }
}

function Install-Claude-code {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest"
    )

    # ── Resolve platform ────────────────────────────────────────────────────
    $arch = if ([Environment]::Is64BitOperatingSystem) {
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_IDENTIFIER -match "ARM") {
            "arm64"
        } else {
            "x64"
        }
    } else {
        Write-Err "Claude Code requires a 64-bit operating system"
        return $false
    }
    $platform = "win32-$arch"

    # ── Resolve version ─────────────────────────────────────────────────────
    # Channels: "stable" (one week behind, safer) and "latest" (bleeding edge)
    # The channel endpoint returns a plain version string like "2.1.29"
    $channel = "stable"

    if ($RequestedVersion -eq "latest" -or $RequestedVersion -eq "pick") {
        if ($RequestedVersion -eq "pick") {
            $stableVer = $null
            $latestVer = $null
            try {
                $stableVer = (Invoke-RestMethod -Uri "$script:GCS_BUCKET/stable" -UseBasicParsing).Trim()
                $latestVer = (Invoke-RestMethod -Uri "$script:GCS_BUCKET/latest" -UseBasicParsing).Trim()
            } catch {
                Write-Err "Failed to fetch version info: $_"
                return $false
            }

            # Suspend TUI if active — the picker needs interactive console control
            $wasTui = $script:TuiState -and $script:TuiState.Active
            if ($wasTui) {
                Suspend-Tui
                $dim = Get-TuiDimensions
                Write-Host ""
                Write-TuiTopBorder -BoxWidth $dim.BoxWidth
                Write-TuiEmptyLine -InnerWidth $dim.InnerWidth
                Write-TuiTextLine -Text "  Channel Selection" -InnerWidth $dim.InnerWidth -Color White
                Write-TuiTextLine -Text "  Claude Code" -InnerWidth $dim.InnerWidth -Color DarkGray
                Write-TuiEmptyLine -InnerWidth $dim.InnerWidth
                Write-TuiBottomBorder -BoxWidth $dim.BoxWidth
                Write-Host ""
            }

            $pickItems = @(
                @{ Label = "stable: $stableVer"; Description = "recommended, ~1 week behind" }
                @{ Label = "latest: $latestVer"; Description = "bleeding edge" }
                @{ Label = "other..."; Description = "type a specific version" }
            )
            $selected = Invoke-SelectPrompt -Title "Claude Code channel:" -Items $pickItems -Default 0

            switch ($selected) {
                0 { $RequestedVersion = $stableVer; $channel = "stable" }
                1 { $RequestedVersion = $latestVer; $channel = "latest" }
                2 {
                    $custom = Read-Host "  Version"
                    $RequestedVersion = $custom; $channel = $null
                }
            }

            if ($wasTui) { Resume-Tui }
        }
        else {
            # "latest" → use the latest channel
            $channel = "latest"
        }
    }

    # If we still need to resolve version from a channel
    if ($channel -and $RequestedVersion -in @("latest", "pick")) {
        try {
            Write-Info "Fetching $channel version..."
            $RequestedVersion = (Invoke-RestMethod -Uri "$script:GCS_BUCKET/$channel" -UseBasicParsing).Trim()
        }
        catch {
            Write-Err "Failed to fetch version from $channel channel: $_"
            return $false
        }
    }

    $version = $RequestedVersion
    Write-Info "Claude Code version: $version ($platform)"

    # ── Fetch manifest for checksum verification ────────────────────────────
    $expectedChecksum = $null
    $expectedSize = $null
    try {
        Write-Info "Fetching release manifest..."
        $manifest = Invoke-RestMethod -Uri "$script:GCS_BUCKET/$version/manifest.json" -UseBasicParsing

        # manifest.platforms."win32-x64".checksum / .size
        $platformInfo = $manifest.platforms.$platform
        if ($platformInfo) {
            $expectedChecksum = $platformInfo.checksum
            $expectedSize = $platformInfo.size
            Write-Info "Expected checksum: $($expectedChecksum.Substring(0, 16))..."
        }
        else {
            $availablePlatforms = ($manifest.platforms | Get-Member -MemberType NoteProperty).Name -join ", "
            Write-Err "Platform '$platform' not found in manifest. Available: $availablePlatforms"
            # ARM64 might not be available yet — fall back to x64 under emulation
            if ($platform -eq "win32-arm64") {
                Write-Info "Falling back to win32-x64 (runs under emulation on ARM)"
                $platform = "win32-x64"
                $platformInfo = $manifest.platforms.$platform
                if ($platformInfo) {
                    $expectedChecksum = $platformInfo.checksum
                    $expectedSize = $platformInfo.size
                } else {
                    Write-Err "win32-x64 fallback also not found in manifest"
                    return $false
                }
            }
            else {
                return $false
            }
        }
    }
    catch {
        Write-Info "Could not fetch manifest (proceeding without checksum verification): $_"
    }

    # ── Download binary ─────────────────────────────────────────────────────
    $downloadUrl = "$script:GCS_BUCKET/$version/$platform/claude.exe"
    $tempDir = Join-Path $env:USERPROFILE ".claude\downloads"
    $tempFile = Join-Path $tempDir "claude-$version-$platform.exe"

    Ensure-Dir $tempDir

    Write-Info "Downloading claude.exe..."
    Write-Info "URL: $downloadUrl"

    try {
        Invoke-Download -Uri $downloadUrl -OutFile $tempFile
    }
    catch {
        Write-Err "Download failed: $_"
        return $false
    }

    # ── Verify download ─────────────────────────────────────────────────────
    if (-not (Test-Path $tempFile)) {
        Write-Err "Download produced no file at: $tempFile"
        return $false
    }

    $fileSize = (Get-Item $tempFile).Length
    if ($fileSize -lt 1MB) {
        Write-Err "Downloaded file is suspiciously small ($fileSize bytes) — likely a failed download"
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $false
    }

    Write-Info "Downloaded $([math]::Round($fileSize / 1MB)) MB"

    # Size check
    if ($expectedSize -and $fileSize -ne [long]$expectedSize) {
        Write-Err "Size mismatch: expected $expectedSize bytes, got $fileSize bytes"
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        return $false
    }

    # SHA256 check
    if ($expectedChecksum) {
        Write-Info "Verifying SHA256 checksum..."
        $actualChecksum = (Get-FileHash -Path $tempFile -Algorithm SHA256).Hash.ToLower()
        if ($actualChecksum -ne $expectedChecksum.ToLower()) {
            Write-Err "Checksum mismatch!"
            Write-Err "  Expected: $expectedChecksum"
            Write-Err "  Actual:   $actualChecksum"
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Success "Checksum verified"
    }

    # ── Install binary ──────────────────────────────────────────────────────
    # The official installer tries `& $binary install stable` here, which is broken.
    # We just copy the binary directly to the expected location.
    $installDir = Join-Path $env:USERPROFILE ".local\bin"
    $installPath = Join-Path $installDir "claude.exe"

    Ensure-Dir $installDir

    try {
        # Remove existing if present
        if (Test-Path $installPath) {
            Write-Info "Removing existing claude.exe..."
            Remove-Item $installPath -Force
        }

        Copy-Item -Path $tempFile -Destination $installPath -Force

        # Verify the copy worked and isn't 0-byte
        if (-not (Test-Path $installPath)) {
            Write-Err "Failed to copy binary to $installPath"
            return $false
        }

        $installedSize = (Get-Item $installPath).Length
        if ($installedSize -lt 1MB) {
            Write-Err "Installed binary is $installedSize bytes — copy likely failed"
            return $false
        }

        Write-Success "Binary installed to $installPath ($([math]::Round($installedSize / 1MB)) MB)"
    }
    catch {
        Write-Err "Failed to install binary: $_"
        return $false
    }
    finally {
        # Clean up temp download
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    # ── Add to PATH ─────────────────────────────────────────────────────────
    Add-ToUserPath @($installDir)

    # ── Store channel preference for auto-updates ───────────────────────────
    # The native binary checks  ~/.claude/settings.json  for the update channel
    if ($channel) {
        $settingsDir = Join-Path $env:USERPROFILE ".claude"
        Ensure-Dir $settingsDir
        $settingsFile = Join-Path $settingsDir "settings.json"

        try {
            $settings = @{}
            if (Test-Path $settingsFile) {
                $existing = Get-Content $settingsFile -Raw -ErrorAction SilentlyContinue
                if ($existing) {
                    $parsed = $existing | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($parsed) {
                        # ConvertFrom-Json returns PSCustomObject — convert to hashtable for PS 5.1 compat
                        foreach ($prop in $parsed.PSObject.Properties) {
                            $settings[$prop.Name] = $prop.Value
                        }
                    }
                }
            }
            $settings["releaseChannel"] = $channel
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            Write-Info "Update channel set to: $channel"
        }
        catch {
            Write-Info "Could not write settings (non-fatal): $_"
        }
    }

    # ── Done ────────────────────────────────────────────────────────────────
    Write-Success "Claude Code $version installed"
    Write-Info "Run 'claude' to authenticate (first run opens your browser)"
    Write-Info "Run 'claude doctor' to verify the installation"
    return $true
}

function Detect-Claude-code {
    param([string]$BaseDir)
    # Check known install path
    $installPath = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
    if (Test-Path $installPath) {
        $size = (Get-Item $installPath).Length
        if ($size -ge 1MB) {
            try {
                $result = ((& $installPath --version 2>&1) -replace "\s+\(.*$", "").Trim()
                return @{ Installed = $true; Version = $result }
            } catch {}
            return @{ Installed = $true; Version = $null }
        }
    }
    # Check PATH
    $onPath = Get-Command claude -ErrorAction SilentlyContinue
    if ($onPath) {
        try {
            $result = ((& claude --version 2>&1) -replace "\s+\(.*$", "").Trim()
            return @{ Installed = $true; Version = $result }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    return @{ Installed = $false; Version = $null }
}

function Test-Claude-code {
    param([string]$BaseDir)

    $installPath = Join-Path $env:USERPROFILE ".local\bin\claude.exe"

    # Check if binary exists and isn't 0-byte (the classic broken installer symptom)
    if (Test-Path $installPath) {
        $size = (Get-Item $installPath).Length
        if ($size -lt 1MB) {
            Write-Err "claude-code: binary exists but is only $size bytes (corrupted / 0-byte ghost)"
            Write-Err "  This is the known installer bug — re-run the installer to fix"
            return $false
        }
    }

    # Try running it
    $claudeAvailable = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeAvailable) {
        try {
            $result = & claude --version 2>&1
            Write-Success "claude-code: $result"
            return $true
        }
        catch {
            # Binary exists but crashed — still count as installed
            if (Test-Path $installPath) {
                Write-Success "claude-code: installed at $installPath (could not read version)"
                return $true
            }
        }
    }

    # Not on PATH but file exists
    if (Test-Path $installPath) {
        Write-Success "claude-code: installed at $installPath"
        Write-Info "Not in current PATH — restart your terminal"
        return $true
    }

    Write-Err "claude-code: not found"
    return $false
}