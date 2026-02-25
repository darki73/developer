# windows/tools/python.ps1
# Installs Python via uv

function Get-PythonMetadata {
    return @{
        Name        = "python"
        Description = "Python programming language (installed via uv)"
        Url         = "https://www.python.org/"
        DependsOn   = @("uv")
    }
}

function Install-Python {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest"
    )

    $uvExe = Join-Path $BaseDir "uv\uv.exe"
    if (-not (Test-Path $uvExe)) {
        Write-Err "uv is required to install Python but was not found at $uvExe"
        return $false
    }

    # Fetch available versions from uv
    Write-Info "Fetching Python versions via uv..."
    $versions = @()
    try {
        $output = & $uvExe python list --only-downloads 2>&1 | Out-String
        $versions = @([regex]::Matches($output, "cpython-(\d+\.\d+\.\d+)-windows") |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object { [version]$_ } -Descending -Unique)
    }
    catch {}

    if ($versions.Count -eq 0) {
        $versions = @("3.13.2", "3.12.12", "3.11.14", "3.10.19", "3.9.25")
    }

    $version = Invoke-VersionPicker -ToolName "Python" -RequestedVersion $RequestedVersion -AvailableVersions $versions

    if (-not $version) { return $false }

    try {
        & $uvExe python install $version
        Write-Success "Python $version installed"
        Write-Info "Python is managed by uv — use 'uv run python' or 'uv venv' to access it"

        return $true
    }
    catch {
        Write-Err "Failed to install Python: $_"
        return $false
    }
}

function Detect-Python {
    param([string]$BaseDir)
    # Check via uv first (managed install)
    $uvExe = Join-Path $BaseDir "uv\uv.exe"
    if (Test-Path $uvExe) {
        try {
            $result = (& $uvExe run python --version 2>&1) -replace "^Python\s+", ""
            return @{ Installed = $true; Version = $result.Trim() }
        } catch {}
    }
    # Check PATH
    $onPath = Get-Command python -ErrorAction SilentlyContinue
    if ($onPath) {
        try {
            $result = (& python --version 2>&1) -replace "^Python\s+", ""
            return @{ Installed = $true; Version = $result.Trim() }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    return @{ Installed = $false; Version = $null }
}

function Test-Python {
    param([string]$BaseDir)
    $uvExe = Join-Path $BaseDir "uv\uv.exe"
    if (Test-Path $uvExe) {
        try {
            $result = & $uvExe run python --version 2>&1
            Write-Success "python: $result"
            return $true
        }
        catch {}
    }
    Write-Err "python: not found"
    return $false
}