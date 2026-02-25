# windows/tools/go.ps1
# Installs Go programming language

function Get-GoMetadata {
    return @{
        Name        = "go"
        Description = "Go programming language"
        Url         = "https://go.dev/"
    }
}

function Install-Go {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"
    )

    $goRoot = Join-Path $BaseDir "go\root"
    $goPath = Join-Path $BaseDir "go\gopath"
    $goBin  = Join-Path $BaseDir "go\gopath\bin"

    Ensure-Dir $goRoot
    Ensure-Dir $goPath
    Ensure-Dir $goBin

    Set-PersistentEnvVar "GOROOT" $goRoot
    Set-PersistentEnvVar "GOPATH" $goPath
    Set-PersistentEnvVar "GOBIN"  $goBin

    # Fetch available versions
    Write-Info "Fetching Go versions from go.dev..."
    $versions = @()
    try {
        $releases = Invoke-RestMethod -Uri "https://go.dev/dl/?mode=json" -UseBasicParsing
        $versions = @($releases |
            Where-Object { $_.stable -eq $true } |
            ForEach-Object { $_.version -replace "^go", "" })
    }
    catch {
        Write-Info "Could not fetch versions from go.dev: $_"
    }

    if ($versions.Count -eq 0) {
        $versions = @("1.24.0", "1.23.6", "1.22.12")
    }

    $version = Invoke-VersionPicker -ToolName "Go" -RequestedVersion $RequestedVersion -AvailableVersions $versions

    if (-not $version) { return $false }

    $zipName     = "go${version}.windows-${Arch}.zip"
    $downloadUrl = "https://go.dev/dl/$zipName"
    $zipPath     = Join-Path $env:TEMP $zipName

    try {
        Write-Info "Downloading $downloadUrl..."
        Invoke-Download -Uri $downloadUrl -OutFile $zipPath

        Write-Info "Extracting to $goRoot..."
        Expand-Archive $zipPath -DestinationPath $goRoot -Force

        # Flatten: zip contains a top-level "go" folder
        $nestedGoDir = Join-Path $goRoot "go"
        if (Test-Path $nestedGoDir) {
            Get-ChildItem $nestedGoDir | ForEach-Object {
                $dest = Join-Path $goRoot $_.Name
                if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                Move-Item $_.FullName -Destination $goRoot -Force
            }
            Remove-Item $nestedGoDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        Add-ToUserPath @(
            (Join-Path $goRoot "bin")
            $goBin
        )

        $goExe = Join-Path $goRoot "bin\go.exe"
        if (Test-Path $goExe) {
            $result = & $goExe version 2>&1
            Write-Success "Go: $result"
            return $true
        }

        Write-Err "go.exe not found at $goRoot\bin"
        return $false
    }
    catch {
        Write-Err "Failed to install Go: $_"
        Write-Err "Manual download: https://go.dev/dl/"
        return $false
    }
}

function Detect-Go {
    param([string]$BaseDir)
    # Check BaseDir
    $goExe = Join-Path $BaseDir "go\root\bin\go.exe"
    if (Test-Path $goExe) {
        try {
            $result = & $goExe version 2>&1
            if ($result -match "go(\d+\.\d+[\.\d]*)") { $ver = $Matches[1] } else { $ver = $null }
            return @{ Installed = $true; Version = $ver }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    # Check PATH
    $onPath = Get-Command go -ErrorAction SilentlyContinue
    if ($onPath) {
        try {
            $result = & go version 2>&1
            if ($result -match "go(\d+\.\d+[\.\d]*)") { $ver = $Matches[1] } else { $ver = $null }
            return @{ Installed = $true; Version = $ver }
        } catch {}
        return @{ Installed = $true; Version = $null }
    }
    return @{ Installed = $false; Version = $null }
}

function Test-Go {
    param([string]$BaseDir)
    $goExe = Join-Path $BaseDir "go\root\bin\go.exe"
    if (Test-Path $goExe) {
        $result = & $goExe version 2>&1
        Write-Success "go: $result"
        return $true
    }
    Write-Err "go: not found"
    return $false
}