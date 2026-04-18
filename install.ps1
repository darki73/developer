#Requires -Version 5.1
<#
.SYNOPSIS
    Developer environment bootstrapper.
    Downloads and runs the setup script for your platform.

.DESCRIPTION
    Quick-start:
        irm https://raw.githubusercontent.com/darki73/developer/main/install.ps1 | iex

    Or clone the repo and run directly:
        git clone https://github.com/darki73/developer.git
        .\developer\windows\setup.ps1
#>

$ErrorActionPreference = "Stop"

# Determine platform
if ($env:OS -eq "Windows_NT") {
    $platform = "windows"
} else {
    Write-Host "This bootstrapper currently supports Windows only." -ForegroundColor Red
    Write-Host "Linux and macOS support coming soon." -ForegroundColor Yellow
    Write-Host "See: https://github.com/darki73/developer" -ForegroundColor Gray
    exit 1
}

# Check if we're already in the repo
$localSetup = Join-Path $PSScriptRoot "$platform\setup.ps1"
if (Test-Path $localSetup) {
    Write-Host "Running local setup script..." -ForegroundColor Cyan
    & $localSetup @args
    exit $LASTEXITCODE
}

# Otherwise, clone to temp and run
$tempDir = Join-Path $env:TEMP "developer-setup-$(Get-Random)"
$cleanupDir = $tempDir

try {
    Write-Host "Downloading developer setup..." -ForegroundColor Cyan

    # Try git clone first
    $gitAvailable = Get-Command git -ErrorAction SilentlyContinue
    if ($gitAvailable) {
        $cloneOutput = git clone --depth 1 https://github.com/darki73/developer.git $tempDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git clone failed: $cloneOutput" -ForegroundColor Yellow
            Write-Host "Falling back to zip download..." -ForegroundColor Yellow
            $gitAvailable = $null
        }
    }

    if (-not $gitAvailable) {
        # Fallback: download zip
        $zipUrl = "https://github.com/darki73/developer/archive/refs/heads/main.zip"
        $zipPath = Join-Path $env:TEMP "developer-setup.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

        # Sanity check — a real zip is well over 10 KB; smaller probably means
        # an HTML error page from GitHub got saved with a .zip extension.
        $zipSize = (Get-Item $zipPath).Length
        if ($zipSize -lt 10KB) {
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Write-Host "Downloaded zip is only $zipSize bytes — likely an error page, not the repo." -ForegroundColor Red
            exit 1
        }

        Expand-Archive $zipPath -DestinationPath $tempDir -Force
        Remove-Item $zipPath -Force

        # The zip extracts to developer-main/
        $innerDir = Get-ChildItem $tempDir -Directory | Select-Object -First 1
        if ($innerDir) {
            $tempDir = $innerDir.FullName
        }
    }

    # Layout sanity check — confirms what we got actually looks like this repo
    # before executing setup.ps1 from it.
    $expectedPaths = @(
        (Join-Path $tempDir "$platform\setup.ps1"),
        (Join-Path $tempDir "$platform\lib"),
        (Join-Path $tempDir "$platform\tools")
    )
    $missing = $expectedPaths | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Host "Downloaded archive is missing expected paths:" -ForegroundColor Red
        foreach ($m in $missing) { Write-Host "  $m" -ForegroundColor Red }
        Write-Host "Refusing to execute — the archive does not look like darki73/developer." -ForegroundColor Red
        exit 1
    }

    $setupScript = Join-Path $tempDir "$platform\setup.ps1"
    & $setupScript @args
} finally {
    # Cleanup — always remove the original temp dir (not the reassigned inner path)
    if (Test-Path $cleanupDir) {
        Remove-Item $cleanupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}