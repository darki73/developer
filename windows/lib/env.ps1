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