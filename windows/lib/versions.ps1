# windows/lib/versions.ps1
# Shared version fetching and interactive selection

function Get-GitHubReleaseVersions {
    param(
        [string]$Repo,
        [int]$Count = 20,
        [switch]$IncludePrerelease
    )
    Write-Info "Fetching versions from github.com/$Repo..."
    try {
        $headers = @{ "Accept" = "application/vnd.github.v3+json" }
        $releases = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/$Repo/releases?per_page=$Count" `
            -Headers $headers -UseBasicParsing

        $filtered = $releases
        if (-not $IncludePrerelease) {
            $filtered = $releases | Where-Object { -not $_.prerelease -and -not $_.draft }
        }

        return @($filtered | ForEach-Object { $_.tag_name -replace "^v", "" })
    }
    catch {
        Write-Err "Failed to fetch versions from $Repo`: $_"
        return @()
    }
}

function Invoke-VersionPicker {
    param(
        [string]$ToolName,
        [string]$RequestedVersion,
        [string[]]$AvailableVersions
    )

    if (-not $AvailableVersions -or $AvailableVersions.Count -eq 0) {
        if ($RequestedVersion -and $RequestedVersion -notin @("latest", "pick")) {
            Write-Info "$ToolName → $RequestedVersion (no version list available)"
            return $RequestedVersion
        }
        Write-Err "No versions available for $ToolName"
        return $null
    }

    # "latest" — return first (newest)
    if ($RequestedVersion -eq "latest") {
        $picked = $AvailableVersions[0]
        Write-Info "$ToolName → latest: $picked"
        return $picked
    }

    # "pick" — interactive selection
    if ($RequestedVersion -eq "pick") {
        $show = [Math]::Min($AvailableVersions.Count, 15)
        $selectItems = @()
        for ($i = 0; $i -lt $show; $i++) {
            $desc = if ($i -eq 0) { "(latest)" } else { "" }
            $selectItems += @{ Label = $AvailableVersions[$i]; Description = $desc }
        }
        $selectItems += @{ Label = "other..."; Description = "type a version manually" }

        # Suspend TUI if active — the picker needs interactive console control
        $wasTui = $script:TuiState -and $script:TuiState.Active
        if ($wasTui) {
            Suspend-Tui
            $dim = Get-TuiDimensions
            Write-Host ""
            Write-TuiTopBorder -BoxWidth $dim.BoxWidth
            Write-TuiEmptyLine -InnerWidth $dim.InnerWidth
            Write-TuiTextLine -Text "  Version Selection" -InnerWidth $dim.InnerWidth -Color White
            Write-TuiTextLine -Text "  $ToolName" -InnerWidth $dim.InnerWidth -Color DarkGray
            Write-TuiEmptyLine -InnerWidth $dim.InnerWidth
            Write-TuiBottomBorder -BoxWidth $dim.BoxWidth
            Write-Host ""
        }

        $selected = Invoke-SelectPrompt -Title "$ToolName versions:" -Items $selectItems -Default 0

        if ($selected -eq $selectItems.Count - 1) {
            # "other" — free-text input
            $custom = Read-Host "  Version"
            if ($wasTui) { Resume-Tui }
            Write-Success "$ToolName → $custom"
            return $custom
        }

        $picked = $AvailableVersions[$selected]
        if ($wasTui) { Resume-Tui }
        Write-Success "$ToolName → $picked"
        return $picked
    }

    # Explicit version passed
    Write-Info "$ToolName → $RequestedVersion"
    return $RequestedVersion
}