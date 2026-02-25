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
        Expand-Archive $zipPath -DestinationPath $tempDir -Force
        Remove-Item $zipPath -Force

        # The zip extracts to developer-main/
        $innerDir = Get-ChildItem $tempDir -Directory | Select-Object -First 1
        if ($innerDir) {
            $tempDir = $innerDir.FullName
        }
    }

    $setupScript = Join-Path $tempDir "$platform\setup.ps1"
    if (Test-Path $setupScript) {
        & $setupScript @args
    } else {
        Write-Host "Setup script not found for platform: $platform" -ForegroundColor Red
        exit 1
    }
} finally {
    # Cleanup — always remove the original temp dir (not the reassigned inner path)
    if (Test-Path $cleanupDir) {
        Remove-Item $cleanupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}