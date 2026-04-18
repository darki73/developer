# windows/tools/git.ps1
# Installs Git for Windows with full shell integration

function Get-GitMetadata {
    return @{
        Name        = "git"
        Description = "Git version control system"
        Url         = "https://git-scm.com/"
        # Git should install after vscode so it can set it as default editor
        DependsOn   = @("vscode")
    }
}

function Install-Git {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64",
        [hashtable]$InstalledTools = @{}
    )

    $installDir = Join-Path $BaseDir "git"
    Ensure-Dir $installDir

    # Resolve version via GitHub releases
    $versions = Get-GitHubReleaseVersions -Repo "git-for-windows/git"
    # git-for-windows tags look like "2.47.1.windows.1" — strip the ".windows.N" suffix
    $cleanVersions = @($versions | ForEach-Object { $_ -replace "\.windows\.\d+$", "" } | Select-Object -Unique)
    if ($cleanVersions.Count -eq 0) {
        $cleanVersions = @("2.49.0", "2.48.1", "2.47.2")
    }
    $version = Invoke-VersionPicker -ToolName "Git" -RequestedVersion $RequestedVersion -AvailableVersions $cleanVersions

    if (-not $version) { return $false }

    # Map architecture to Git installer suffix
    $gitArch = switch ($Arch) { "arm64" { "arm64" } default { "64-bit" } }

    # Find the matching release — the actual tag includes ".windows.N"
    Write-Info "Fetching Git $version release..."
    try {
        $headers = @{ "Accept" = "application/vnd.github.v3+json" }
        $releases = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/git-for-windows/git/releases?per_page=20" `
            -Headers $headers -UseBasicParsing

        $release = $releases | Where-Object {
            ($_.tag_name -replace "^v", "" -replace "\.windows\.\d+$", "") -eq $version
        } | Select-Object -First 1

        if (-not $release) {
            Write-Err "Could not find Git release matching version $version"
            return $false
        }

        $installerAsset = $release.assets |
            Where-Object { $_.name -match "^Git-.*-${gitArch}\.exe$" -and $_.name -notmatch "Portable" } |
            Select-Object -First 1

        if (-not $installerAsset) {
            Write-Err "Could not find Git $gitArch installer in release $($release.tag_name)"
            return $false
        }

        Write-Info "Git version: $version ($gitArch)"
    }
    catch {
        Write-Err "Failed to fetch Git release info: $_"
        return $false
    }

    $installerPath = Join-Path $env:TEMP $installerAsset.name

    try {
        Write-Info "Downloading $($installerAsset.name)..."
        Invoke-Download -Uri $installerAsset.browser_download_url -OutFile $installerPath

        Write-Info "Installing to $installDir..."

        # Build installer arguments
        $gitArgs = @(
            "/VERYSILENT"
            "/NORESTART"
            "/NOCANCEL"
            "/SP-"
            "/DIR=`"$installDir`""
            "/COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`""
            "/o:DefaultBranchOption=main"
            "/o:PathOption=Cmd"
            "/o:SSHOption=ExternalOpenSSH"
            "/o:CRLFOption=CRLFCommitAsIs"
        )

        # Set VS Code as default editor if it was installed
        if ($InstalledTools.ContainsKey("vscode") -and $InstalledTools["vscode"]) {
            $gitArgs += "/o:EditorOption=VisualStudioCode"
            Write-Info "Setting VS Code as default Git editor"
        }

        Start-Process -FilePath $installerPath -ArgumentList $gitArgs -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

        $gitExe = Join-Path $installDir "cmd\git.exe"
        if (Test-Path $gitExe) {
            $result = & $gitExe --version 2>&1
            Write-Success "Git: $result"
            return $true
        }

        Write-Err "git.exe not found at $installDir\cmd"
        return $false
    }
    catch {
        Write-Err "Failed to install Git: $_"
        return $false
    }
}

function Detect-Git {
    param([string]$BaseDir)
    Resolve-InstalledTool `
        -BasePath (Join-Path $BaseDir "git\cmd\git.exe") `
        -CommandName "git" `
        -GetVersion {
            param($exe)
            $out = & $exe --version 2>&1
            if ($out -match "(\d+\.\d+\.\d+)") { $Matches[1] } else { $null }
        }
}

function Test-Git {
    param([string]$BaseDir)
    $gitExe = Join-Path $BaseDir "git\cmd\git.exe"
    if (Test-Path $gitExe) {
        $result = & $gitExe --version 2>&1
        Write-Success "git: $result"
        return $true
    }
    Write-Err "git: not found"
    return $false
}
