# windows/lib/output.ps1
# Shared output formatting helpers

function Write-Step {
    param([string]$StepNumber, [string]$TotalSteps, [string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    if ($StepNumber -and $TotalSteps) {
        Write-Host "  $StepNumber/$TotalSteps  $Message" -ForegroundColor Cyan
    } else {
        Write-Host "  $Message" -ForegroundColor Cyan
    }
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    if ($script:TuiState -and $script:TuiState.Active) {
        # Try to extract version info for the currently installing tool
        # Messages like "uv: 0.5.2", "Go: go version go1.22.5", "pnpm: v9.15.0"
        if ($Message -match '^.+:\s+(.+)$') {
            $raw = $Matches[1]
            # Extract clean version number from verbose output
            # "go version go1.22.5 windows/amd64" → "1.22.5"
            # "git version 2.47.1.windows.1" → "2.47.1"
            # "0.5.2" → "0.5.2", "v9.15.0" → "9.15.0"
            if ($raw -match '(\d+\.\d+[\.\d]*)') {
                $version = $Matches[1]
            } else {
                $version = $raw
            }
            foreach ($kv in $script:TuiState.Tools.GetEnumerator()) {
                if ($kv.Value.Status -eq "installing") {
                    $kv.Value.Version = $version
                    break
                }
            }
        }
        Add-TuiLog -Type "success" -Message $Message
    } else {
        Write-Host "  ✓ $Message" -ForegroundColor Green
    }
}

function Write-Info {
    param([string]$Message)
    if ($script:TuiState -and $script:TuiState.Active) {
        Add-TuiLog -Type "info" -Message $Message
    } else {
        Write-Host "  → $Message" -ForegroundColor Yellow
    }
}

function Write-Err {
    param([string]$Message)
    if ($script:TuiState -and $script:TuiState.Active) {
        Add-TuiLog -Type "error" -Message $Message
    } else {
        Write-Host "  ✗ $Message" -ForegroundColor Red
    }
}

function Write-Banner {
    param([string[]]$Lines)
    $maxLen = ($Lines | Measure-Object -Maximum -Property Length).Maximum
    $border = "─" * ($maxLen + 4)

    Write-Host ""
    Write-Host "  ┌$border┐" -ForegroundColor DarkCyan
    foreach ($line in $Lines) {
        $padded = $line.PadRight($maxLen)
        Write-Host "  │  $padded  │" -ForegroundColor DarkCyan
    }
    Write-Host "  └$border┘" -ForegroundColor DarkCyan
    Write-Host ""
}