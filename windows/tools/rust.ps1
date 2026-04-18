# windows/tools/rust.ps1
# Installs Rust via rustup, redirected into $BaseDir so the toolchain and
# cargo cache live alongside the rest of the developer environment instead
# of $USERPROFILE\.rustup and $USERPROFILE\.cargo.

function Get-RustMetadata {
    return @{
        Name        = "rust"
        Description = "Rust toolchain (rustup, cargo, rustc)"
        Url         = "https://www.rust-lang.org/"
    }
}

function Install-Rust {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"
    )

    $rustRoot   = Join-Path $BaseDir "rust"
    $rustupHome = Join-Path $rustRoot "rustup"
    $cargoHome  = Join-Path $rustRoot "cargo"
    $cargoBin   = Join-Path $cargoHome "bin"

    Ensure-Dir $rustRoot
    Ensure-Dir $rustupHome
    Ensure-Dir $cargoHome

    Set-PersistentEnvVar "RUSTUP_HOME" $rustupHome
    Set-PersistentEnvVar "CARGO_HOME"  $cargoHome

    # rustup-init reads these at install time
    $env:RUSTUP_HOME = $rustupHome
    $env:CARGO_HOME  = $cargoHome

    # Resolve the rustup-init download for this architecture.
    # The official distribution lives on static.rust-lang.org with a
    # SHA256 sidecar at <url>.sha256.
    $rustArch = if ($Arch -eq "arm64" -or $env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        "aarch64-pc-windows-msvc"
    } else {
        "x86_64-pc-windows-msvc"
    }
    $installerUrl = "https://static.rust-lang.org/rustup/dist/$rustArch/rustup-init.exe"
    $sha256Url    = "$installerUrl.sha256"

    # Resolve toolchain version. "latest"/"pick" → ask the user; otherwise
    # pass the literal version string through to rustup-init.
    $versions = Get-GitHubReleaseVersions -Repo "rust-lang/rust"
    if ($versions.Count -eq 0) {
        $versions = @("1.85.0", "1.84.1", "1.83.0")
    }
    $toolchain = Invoke-VersionPicker `
        -ToolName "Rust" `
        -RequestedVersion $RequestedVersion `
        -AvailableVersions $versions

    if (-not $toolchain) { return $false }

    $tempDir       = Join-Path $env:TEMP "rust-install-$([Guid]::NewGuid().ToString('N'))"
    Ensure-Dir $tempDir
    $installerPath = Join-Path $tempDir "rustup-init.exe"

    try {
        Write-Info "Downloading rustup-init ($rustArch)..."
        try {
            Invoke-Download -Uri $installerUrl -OutFile $installerPath
        }
        catch {
            Write-Err "Failed to download rustup-init: $_"
            return $false
        }

        # SHA256 verification — required, not best-effort
        $expectedSha = $null
        try {
            $shaContent  = (Invoke-RestMethod -Uri $sha256Url -UseBasicParsing).ToString().Trim()
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

        $actualSha = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()
        if ($actualSha -ne $expectedSha) {
            Write-Err "Checksum mismatch for rustup-init.exe"
            Write-Err "  Expected: $expectedSha"
            Write-Err "  Actual:   $actualSha"
            return $false
        }
        Write-Success "SHA256 verified"

        # Run rustup-init unattended:
        #   -y                       no prompts
        #   --default-toolchain X    pin the version (or "stable" when latest)
        #   --profile minimal        rustc + cargo + rust-std, skip docs/rust-analyzer
        #   --no-modify-path         we manage PATH ourselves via Add-ToUserPath
        $defaultToolchain = if ($RequestedVersion -eq "latest") { "stable" } else { $toolchain }

        Write-Info "Running rustup-init (toolchain: $defaultToolchain)..."
        $proc = Start-Process -FilePath $installerPath `
            -ArgumentList @(
                "-y",
                "--default-toolchain", $defaultToolchain,
                "--profile", "minimal",
                "--no-modify-path"
            ) `
            -NoNewWindow -Wait -PassThru

        if ($proc.ExitCode -ne 0) {
            Write-Err "rustup-init exited with code $($proc.ExitCode)"
            Write-Err "If you see a linker/MSVC error, install 'C++ build tools' from the Visual Studio installer:"
            Write-Err "  https://visualstudio.microsoft.com/visual-cpp-build-tools/"
            return $false
        }
    }
    finally {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Add-ToUserPath @($cargoBin)

    $rustcExe = Join-Path $cargoBin "rustc.exe"
    if (Test-Path $rustcExe) {
        $result = (& $rustcExe --version 2>&1)
        Write-Success "rust: $result"
        return $true
    }

    Write-Err "rustc.exe not found at $cargoBin"
    return $false
}

function Detect-Rust {
    param([string]$BaseDir)
    Resolve-InstalledTool `
        -BasePath (Join-Path $BaseDir "rust\cargo\bin\rustc.exe") `
        -CommandName "rustc" `
        -GetVersion {
            param($exe)
            $out = & $exe --version 2>&1
            if ($out -match "rustc\s+(\d+\.\d+\.\d+)") { $Matches[1] } else { $null }
        }
}

function Test-Rust {
    param([string]$BaseDir)
    $rustcExe = Join-Path $BaseDir "rust\cargo\bin\rustc.exe"
    if (Test-Path $rustcExe) {
        $result = & $rustcExe --version 2>&1
        Write-Success "rust: $result"
        return $true
    }
    $onPath = Get-Command rustc -ErrorAction SilentlyContinue
    if ($onPath) {
        $result = & rustc --version 2>&1
        Write-Success "rust: $result"
        return $true
    }
    Write-Err "rust: not found"
    return $false
}
