# windows/lib/env.ps1
# Shared environment variable and PATH management

function Set-PersistentEnvVar {
    param(
        [string]$Name,
        [string]$Value,
        [switch]$Quiet
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    if (-not $Quiet) {
        Write-Info "$Name = $Value"
    }
}

function Get-PersistentEnvVar {
    param([string]$Name)
    return [Environment]::GetEnvironmentVariable($Name, "User")
}

function Add-ToUserPath {
    param(
        [string[]]$Paths,
        [switch]$Quiet
    )
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = $currentPath -split ";" | Where-Object { $_ -ne "" }
    $added = @()

    foreach ($p in $Paths) {
        if ($p -notin $pathEntries) {
            $pathEntries = @($p) + $pathEntries
            $added += $p
        }
    }

    if ($added.Count -gt 0) {
        $newPath = ($pathEntries | Where-Object { $_ -ne "" }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$($added -join ';');$env:Path"
        if (-not $Quiet) {
            foreach ($a in $added) { Write-Info "Added to PATH: $a" }
        }
    }
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Info "Created: $Path"
    }
}

function Normalize-Path {
    param([string]$RawPath)
    return $RawPath.Trim().Trim('"').Trim("'").Replace('/', '\').TrimEnd('\')
}

function Test-IsAdmin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Resolve-InstalledTool {
    # Standard "is this tool installed?" probe used by Detect-* across tool modules.
    # Checks the BaseDir path first, then falls back to the system PATH.
    # GetVersion (optional) receives the resolved exe path and returns a version string.
    param(
        [string]$BasePath,
        [string]$CommandName,
        [scriptblock]$GetVersion
    )

    $exe = $null
    if ($BasePath -and (Test-Path $BasePath)) {
        $exe = $BasePath
    } elseif ($CommandName -and (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        $exe = $CommandName
    }

    if (-not $exe) {
        return @{ Installed = $false; Version = $null }
    }

    if (-not $GetVersion) {
        return @{ Installed = $true; Version = $null }
    }

    try {
        $ver = & $GetVersion $exe
        if ($null -ne $ver) { $ver = $ver.ToString().Trim() }
        return @{ Installed = $true; Version = $ver }
    } catch {
        return @{ Installed = $true; Version = $null }
    }
}

function Test-WritableDir {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) {
            $parent = Split-Path $Path -Parent
            if ($parent -and -not (Test-Path $parent)) { return $false }
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        $probe = Join-Path $Path ".write-probe-$([Guid]::NewGuid().ToString('N'))"
        Set-Content -Path $probe -Value "" -ErrorAction Stop
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}