# windows/tools/node.ps1
# Installs Node.js via pnpm

function Get-NodeMetadata {
    return @{
        Name        = "node"
        Description = "Node.js JavaScript runtime (installed via pnpm)"
        Url         = "https://nodejs.org/"
        DependsOn   = @("pnpm")
    }
}

function Install-Node {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest"
    )

    # Check pnpm is available
    $pnpmExe = Join-Path $BaseDir "pnpm\pnpm.exe"
    if (-not (Test-Path $pnpmExe)) {
        Write-Err "pnpm is required to install Node.js but was not found at $pnpmExe"
        return $false
    }

    # Fetch available major versions
    Write-Info "Fetching Node.js versions from nodejs.org..."
    $versions = @()
    try {
        $releases = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing
        $versions = @($releases |
            ForEach-Object { ($_.version -replace "^v", "") -replace "\.\d+\.\d+$", "" } |
            Select-Object -Unique |
            Where-Object { [int]$_ -ge 18 } |
            Sort-Object { [int]$_ } -Descending |
            Select-Object -First 10)
    }
    catch {
        $versions = @("24", "22", "20", "18")
    }

    $version = Invoke-VersionPicker -ToolName "Node.js" -RequestedVersion $RequestedVersion -AvailableVersions $versions

    if (-not $version) { return $false }

    try {
        & $pnpmExe env use --global $version
        Write-Success "Node.js $version installed"
        return $true
    }
    catch {
        Write-Err "Failed to install Node.js: $_"
        return $false
    }
}

function Detect-Node {
    param([string]$BaseDir)
    # node is managed by pnpm, no fixed BaseDir path — PATH lookup only
    Resolve-InstalledTool `
        -CommandName "node" `
        -GetVersion { param($exe) (& $exe --version 2>&1) -replace "^v", "" }
}

function Test-Node {
    param([string]$BaseDir)
    try {
        $result = & node --version 2>&1
        Write-Success "node: $result"
        return $true
    }
    catch {
        Write-Err "node: not found"
        return $false
    }
}
