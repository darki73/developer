# windows/lib/tui.ps1
# Full-screen TUI dashboard and shared frame rendering primitives

$script:TuiState = $null

$script:SpinnerChars = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")

# ============================================================================
# Helpers
# ============================================================================

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ============================================================================
# Shared dimensions
# ============================================================================

function Get-TuiDimensions {
    $w = try { [Console]::WindowWidth } catch { 80 }
    $w = [Math]::Max($w, 60)
    $boxW    = $w - 4          # box border width (inside the 2-space left margin)
    $innerW  = $boxW - 2       # content area width
    return @{ Width = $w; BoxWidth = $boxW; InnerWidth = $innerW }
}

# ============================================================================
# Rendering primitives — used by both wizard and installation TUI
# ============================================================================

function Write-TuiTopBorder {
    param([int]$BoxWidth)
    Write-Host "  ┌$("─" * $BoxWidth)┐" -ForegroundColor DarkCyan
}

function Write-TuiBottomBorder {
    param([int]$BoxWidth)
    Write-Host "  └$("─" * $BoxWidth)┘" -ForegroundColor DarkCyan
}

function Write-TuiDivider {
    param([int]$BoxWidth, [string]$Label = "")
    if ($Label) {
        $labelPart = "─── $Label "
        $remaining = $BoxWidth - $labelPart.Length
        Write-Host "  ├${labelPart}$("─" * $remaining)┤" -ForegroundColor DarkCyan
    } else {
        Write-Host "  ├$("─" * $BoxWidth)┤" -ForegroundColor DarkCyan
    }
}

function Write-TuiEmptyLine {
    param([int]$InnerWidth)
    Write-Host "  │ $(" " * $InnerWidth) │" -ForegroundColor DarkCyan
}

function Write-TuiTextLine {
    param([string]$Text, [int]$InnerWidth, [string]$Color = "White")
    $padded = $Text.PadRight($InnerWidth).Substring(0, $InnerWidth)
    Write-Host "  │ " -NoNewline -ForegroundColor DarkCyan
    Write-Host $padded -NoNewline -ForegroundColor $Color
    Write-Host " │" -ForegroundColor DarkCyan
}

# Writes left border. Caller writes content with -NoNewline,
# then calls Write-TuiEndLine to pad and close the right border.
function Write-TuiStartLine {
    Write-Host "  │ " -NoNewline -ForegroundColor DarkCyan
}

function Write-TuiEndLine {
    param([int]$Written, [int]$InnerWidth)
    $pad = [Math]::Max(0, $InnerWidth - $Written)
    if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
    Write-Host " │" -ForegroundColor DarkCyan
}

# Key-value line:  "  ✓  Label         Value"  or  "  Label         Value"
function Write-TuiKeyValueLine {
    param(
        [string]$Key,
        [string]$Value,
        [int]$InnerWidth,
        [string]$Icon = "",
        [string]$IconColor = "Green",
        [int]$KeyPad = 14
    )

    Write-TuiStartLine
    $w = 0

    Write-Host "  " -NoNewline; $w += 2
    if ($Icon) {
        Write-Host $Icon -NoNewline -ForegroundColor $IconColor; $w += 1
        Write-Host "  " -NoNewline; $w += 2
    }
    $paddedKey = $Key.PadRight($KeyPad)
    Write-Host $paddedKey -NoNewline -ForegroundColor DarkGray; $w += $paddedKey.Length

    # Truncate value if too long
    $maxVal = $InnerWidth - $w
    $val = if ($Value.Length -gt $maxVal) { $Value.Substring(0, $maxVal - 3) + "..." } else { $Value }
    Write-Host $val -NoNewline -ForegroundColor White; $w += $val.Length

    Write-TuiEndLine -Written $w -InnerWidth $InnerWidth
}

# ============================================================================
# Wizard frame — bordered header for interactive setup screens
# ============================================================================

function Write-WizardFrame {
    param(
        [array]$CompletedSteps = @()   # array of @{ Label; Value }
    )

    Clear-Host

    $dim = Get-TuiDimensions
    $boxW   = $dim.BoxWidth
    $innerW = $dim.InnerWidth

    Write-TuiTopBorder -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiTextLine -Text "  Developer Environment Setup" -InnerWidth $innerW -Color White
    Write-TuiTextLine -Text "  github.com/darki73/developer" -InnerWidth $innerW -Color DarkGray
    Write-TuiEmptyLine -InnerWidth $innerW

    if ($CompletedSteps.Count -gt 0) {
        foreach ($s in $CompletedSteps) {
            Write-TuiKeyValueLine -Key $s.Label -Value $s.Value -InnerWidth $innerW -Icon "✓" -IconColor Green
        }
        Write-TuiEmptyLine -InnerWidth $innerW
    }

    Write-TuiBottomBorder -BoxWidth $boxW
    Write-Host ""
}

# Summary frame — shows install plan before confirmation
function Write-SummaryFrame {
    param(
        [string]$BaseDir,
        [string]$Arch,
        [string]$Tools
    )

    Clear-Host

    $dim = Get-TuiDimensions
    $boxW   = $dim.BoxWidth
    $innerW = $dim.InnerWidth

    Write-TuiTopBorder -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiTextLine -Text "  Developer Environment Setup" -InnerWidth $innerW -Color White
    Write-TuiTextLine -Text "  github.com/darki73/developer" -InnerWidth $innerW -Color DarkGray
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiDivider -BoxWidth $boxW -Label "summary"
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Directory" -Value $BaseDir -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Architecture" -Value $Arch -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Tools" -Value $Tools -InnerWidth $innerW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiBottomBorder -BoxWidth $boxW
    Write-Host ""
}

# Config info frame — for config-file mode
function Write-ConfigFrame {
    param(
        [string]$ConfigFile,
        [string]$BaseDir,
        [string]$Arch,
        [string]$Tools
    )

    $dim = Get-TuiDimensions
    $boxW   = $dim.BoxWidth
    $innerW = $dim.InnerWidth

    Write-Host ""
    Write-TuiTopBorder -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiTextLine -Text "  Developer Environment Setup" -InnerWidth $innerW -Color White
    Write-TuiTextLine -Text "  github.com/darki73/developer" -InnerWidth $innerW -Color DarkGray
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiDivider -BoxWidth $boxW -Label "config"
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "File" -Value $ConfigFile -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Directory" -Value $BaseDir -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Architecture" -Value $Arch -InnerWidth $innerW
    Write-TuiKeyValueLine -Key "Tools" -Value $Tools -InnerWidth $innerW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiBottomBorder -BoxWidth $boxW
    Write-Host ""
}

# ============================================================================
# Installation TUI — lifecycle
# ============================================================================

function Initialize-Tui {
    param(
        [string]$BaseDir,
        [string]$Arch,
        [string[]]$ToolNames,
        [int]$Total
    )

    $tools = [ordered]@{}
    foreach ($name in $ToolNames) {
        $tools[$name] = @{
            Status  = "pending"   # pending | installing | done | failed
            Version = ""
        }
    }

    $script:TuiState = @{
        Active       = $false
        BaseDir      = $BaseDir
        Arch         = $Arch
        Tools        = $tools
        Log          = [System.Collections.ArrayList]::new()
        LogCapacity  = 5
        Total        = $Total
        Completed    = 0
        Failed       = 0
        SpinnerIndex = 0
        Completion   = $null   # set by Complete-Tui
        Download     = @{ Active = $false; Total = [long]0; Current = [long]0 }
    }
}

function Start-Tui {
    if (-not $script:TuiState) { return }
    if (-not (Test-InteractiveConsole)) { return }

    $script:TuiState.Active = $true
    [Console]::CursorVisible = $false
    Clear-Host
    Compute-TuiLogCapacity
    Redraw-Tui
}

function Suspend-Tui {
    if (-not $script:TuiState -or -not $script:TuiState.Active) { return }
    $script:TuiState.Active = $false
    [Console]::CursorVisible = $true
    Clear-Host
}

function Resume-Tui {
    if (-not $script:TuiState) { return }
    $script:TuiState.Active = $true
    [Console]::CursorVisible = $false
    Clear-Host
    Compute-TuiLogCapacity
    Redraw-Tui
}

function Complete-Tui {
    param([string]$Message = "Setup complete!")

    if (-not $script:TuiState) { return }

    $script:TuiState.Completion = $Message

    if ($script:TuiState.Active) {
        # Clear-Host to eliminate ghost lines from the taller active frame
        Clear-Host
        Redraw-Tui
        [Console]::CursorVisible = $true
        $script:TuiState.Active = $false
    }
}

# ============================================================================
# Installation TUI — state updates
# ============================================================================

function Update-TuiTool {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Version = ""
    )

    if (-not $script:TuiState) { return }
    $tool = $script:TuiState.Tools[$Name]
    if (-not $tool) { return }

    $tool.Status = $Status
    if ($Version) { $tool.Version = $Version }

    if ($Status -eq "done")   { $script:TuiState.Completed++ }
    if ($Status -eq "failed") { $script:TuiState.Failed++ }

    if ($script:TuiState.Active) { Redraw-Tui }
}

function Add-TuiLog {
    param(
        [string]$Type,     # info | success | error
        [string]$Message
    )

    if (-not $script:TuiState) { return }

    [void]$script:TuiState.Log.Add(@{ Type = $Type; Message = $Message })

    # Trim old entries
    while ($script:TuiState.Log.Count -gt 50) {
        $script:TuiState.Log.RemoveAt(0)
    }

    $script:TuiState.SpinnerIndex++

    if ($script:TuiState.Active) { Redraw-Tui }
}

# ============================================================================
# Download with TUI progress tracking
# ============================================================================

function Invoke-Download {
    param(
        [string]$Uri,
        [string]$OutFile
    )

    $tuiActive = $script:TuiState -and $script:TuiState.Active

    # Non-TUI mode: fall back to Invoke-WebRequest (has its own progress bar)
    if (-not $tuiActive) {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        return
    }

    # Ensure TLS 1.2 is available
    if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    # Try HEAD request to get file size
    $totalBytes = [long]-1
    try {
        $headReq = [System.Net.HttpWebRequest]::Create($Uri)
        $headReq.Method = "HEAD"
        $headReq.AllowAutoRedirect = $true
        $headReq.UserAgent = "developer-setup/1.0"
        $headResp = $headReq.GetResponse()
        $totalBytes = $headResp.ContentLength
        $headResp.Close()
        $headResp.Dispose()
    }
    catch {
        # HEAD not supported or failed — proceed without size
    }

    # Set up TUI download state
    $script:TuiState.Download = @{
        Active  = $true
        Total   = $totalBytes
        Current = [long]0
    }
    Redraw-Tui

    $fileStream = $null
    $responseStream = $null
    $response = $null

    try {
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = "GET"
        $request.AllowAutoRedirect = $true
        $request.UserAgent = "developer-setup/1.0"

        $response = $request.GetResponse()

        # If HEAD didn't return a size, try from the GET response
        if ($totalBytes -le 0 -and $response.ContentLength -gt 0) {
            $totalBytes = $response.ContentLength
            $script:TuiState.Download.Total = $totalBytes
        }

        $responseStream = $response.GetResponseStream()
        $fileStream = [System.IO.FileStream]::new(
            $OutFile,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write
        )

        $buffer = New-Object byte[] 65536   # 64 KB chunks
        $downloaded = [long]0
        $lastRedrawTime = [DateTime]::UtcNow

        do {
            $read = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $downloaded += $read
                $script:TuiState.Download.Current = $downloaded

                # Redraw at most every 200 ms
                $now = [DateTime]::UtcNow
                if (($now - $lastRedrawTime).TotalMilliseconds -ge 200) {
                    $lastRedrawTime = $now
                    $script:TuiState.SpinnerIndex++
                    Redraw-Tui
                }
            }
        } while ($read -gt 0)

        # Log the final size
        $sizeStr = Format-FileSize $downloaded
        Add-TuiLog -Type "info" -Message "Downloaded $sizeStr"
    }
    catch {
        throw $_
    }
    finally {
        if ($fileStream)     { $fileStream.Close();     $fileStream.Dispose() }
        if ($responseStream) { $responseStream.Close();  $responseStream.Dispose() }
        if ($response)       { $response.Close();        $response.Dispose() }

        # Clear download state
        if ($script:TuiState) {
            $script:TuiState.Download = @{ Active = $false; Total = [long]0; Current = [long]0 }
            if ($script:TuiState.Active) { Redraw-Tui }
        }
    }
}

# ============================================================================
# Installation TUI — layout helpers
# ============================================================================

function Compute-TuiLogCapacity {
    $h = try { [Console]::WindowHeight } catch { 25 }
    $toolCount = $script:TuiState.Tools.Count

    # Fixed lines: top border(1) + empty(1) + title(1) + subtitle(1) + empty(1)
    #   + progress(1) + empty(1) + tools divider(1) + empty(1) + N tools
    #   + empty(1) + log divider(1) + empty(1) + ...log... + empty(1) + bottom(1)
    $fixedLines = 13 + $toolCount
    $available = $h - $fixedLines
    $script:TuiState.LogCapacity = [Math]::Max(3, [Math]::Min($available, 10))
}

# ============================================================================
# Installation TUI — progress bar
# ============================================================================

function Write-TuiProgressBar {
    param([int]$InnerWidth)

    $tui = $script:TuiState
    $done = $tui.Completed + $tui.Failed

    if ($tui.Completion) {
        $suffix = "  $done/$($tui.Total)  done  "
    } else {
        $pct = if ($tui.Total -gt 0) { [Math]::Floor($done / $tui.Total * 100) } else { 0 }
        $suffix = "  $done/$($tui.Total)   ${pct}%  "
    }

    $barMax = $InnerWidth - 2 - $suffix.Length
    $barMax = [Math]::Max($barMax, 10)
    $filledW = if ($tui.Total -gt 0) { [Math]::Floor($done / $tui.Total * $barMax) } else { 0 }
    $emptyW  = $barMax - $filledW

    Write-TuiStartLine
    $w = 0

    Write-Host "  " -NoNewline; $w += 2
    Write-Host ("█" * $filledW) -NoNewline -ForegroundColor Cyan; $w += $filledW
    Write-Host ("░" * $emptyW)  -NoNewline -ForegroundColor DarkGray; $w += $emptyW
    Write-Host $suffix -NoNewline -ForegroundColor DarkGray; $w += $suffix.Length

    Write-TuiEndLine -Written $w -InnerWidth $InnerWidth
}

# ============================================================================
# Installation TUI — tool status line
# ============================================================================

function Write-TuiToolLine {
    param([string]$Name, [hashtable]$Tool, [int]$InnerWidth)

    $spinner = $script:SpinnerChars[$script:TuiState.SpinnerIndex % $script:SpinnerChars.Count]

    $iconChar  = switch ($Tool.Status) {
        "done"       { "✓" }
        "failed"     { "✗" }
        "installing" { $spinner }
        default      { "·" }
    }
    $iconColor = switch ($Tool.Status) {
        "done"       { "Green" }
        "failed"     { "Red" }
        "installing" { "Cyan" }
        default      { "DarkGray" }
    }
    $nameColor = switch ($Tool.Status) {
        "done"       { "White" }
        "failed"     { "Red" }
        "installing" { "Cyan" }
        default      { "DarkGray" }
    }

    Write-TuiStartLine
    $w = 0

    Write-Host "  " -NoNewline; $w += 2
    Write-Host $iconChar -NoNewline -ForegroundColor $iconColor; $w += 1
    Write-Host "  " -NoNewline; $w += 2

    $paddedName = $Name.PadRight(16)
    Write-Host $paddedName -NoNewline -ForegroundColor $nameColor; $w += $paddedName.Length

    # Check if this tool has an active download
    $dl = $script:TuiState.Download
    if ($Tool.Status -eq "installing" -and $dl -and $dl.Active) {
        $available = $InnerWidth - $w

        if ($dl.Total -gt 0) {
            # Known size — show progress bar with percentage
            $pct = [Math]::Min(100, [Math]::Floor($dl.Current / $dl.Total * 100))
            $currentStr = Format-FileSize $dl.Current
            $totalStr   = Format-FileSize $dl.Total
            $suffix = "  ${pct}%  $currentStr / $totalStr"

            $barWidth = $available - $suffix.Length - 1
            $barWidth = [Math]::Max($barWidth, 10)
            $filledW = [Math]::Floor($dl.Current / $dl.Total * $barWidth)
            $filledW = [Math]::Min($filledW, $barWidth)
            $emptyW  = $barWidth - $filledW

            Write-Host ("█" * $filledW) -NoNewline -ForegroundColor Cyan;    $w += $filledW
            Write-Host ("░" * $emptyW)  -NoNewline -ForegroundColor DarkGray; $w += $emptyW
            Write-Host $suffix -NoNewline -ForegroundColor DarkGray;          $w += $suffix.Length
        }
        else {
            # Unknown size — show downloaded amount with animated dots
            $dots = "." * (($script:TuiState.SpinnerIndex % 3) + 1)
            $currentStr = Format-FileSize $dl.Current
            $text = "downloading$($dots.PadRight(3))  $currentStr"
            Write-Host $text -NoNewline -ForegroundColor DarkGray; $w += $text.Length
        }
    }
    else {
        # Normal status text
        $statusText = switch ($Tool.Status) {
            "done"       { if ($Tool.Version) { $Tool.Version } else { "done" } }
            "failed"     { "failed" }
            "installing" { "installing..." }
            default      { "" }
        }
        $statusColor = switch ($Tool.Status) {
            "done"       { "DarkGray" }
            "failed"     { "Red" }
            "installing" { "DarkGray" }
            default      { "DarkGray" }
        }

        Write-Host $statusText -NoNewline -ForegroundColor $statusColor; $w += $statusText.Length
    }

    Write-TuiEndLine -Written $w -InnerWidth $InnerWidth
}

# ============================================================================
# Installation TUI — log entry line
# ============================================================================

function Write-TuiLogLine {
    param([hashtable]$Entry, [int]$InnerWidth)

    $prefixChar = switch ($Entry.Type) {
        "info"    { "→" }
        "success" { "✓" }
        "error"   { "✗" }
        default   { "·" }
    }
    $prefixColor = switch ($Entry.Type) {
        "info"    { "Yellow" }
        "success" { "Green" }
        "error"   { "Red" }
        default   { "DarkGray" }
    }

    Write-TuiStartLine
    $w = 0

    Write-Host "  " -NoNewline; $w += 2
    Write-Host $prefixChar -NoNewline -ForegroundColor $prefixColor; $w += 1
    Write-Host " " -NoNewline; $w += 1

    $maxMsg = $InnerWidth - 4
    $msg = $Entry.Message
    if ($msg.Length -gt $maxMsg) {
        $msg = $msg.Substring(0, $maxMsg - 3) + "..."
    }
    Write-Host $msg -NoNewline -ForegroundColor $prefixColor; $w += $msg.Length

    Write-TuiEndLine -Written $w -InnerWidth $InnerWidth
}

# ============================================================================
# Installation TUI — main renderer
# ============================================================================

function Redraw-Tui {
    $tui = $script:TuiState
    if (-not $tui) { return }

    $dim = Get-TuiDimensions
    $boxW   = $dim.BoxWidth
    $innerW = $dim.InnerWidth

    # Detect if console has scrolled (external command output pushed past frame).
    # If so, Clear-Host to re-anchor. Expected frame is ~13 + tools + log lines.
    $maxExpected = 14 + $tui.Tools.Count + $tui.LogCapacity
    if ([Console]::CursorTop -gt $maxExpected) {
        Clear-Host
    }

    [Console]::SetCursorPosition(0, 0)

    # ── Header ──────────────────────────────────────────────
    Write-TuiTopBorder -BoxWidth $boxW
    Write-TuiEmptyLine -InnerWidth $innerW
    Write-TuiTextLine -Text "  Developer Environment Setup" -InnerWidth $innerW -Color White
    Write-TuiTextLine -Text "  $($tui.BaseDir) · $($tui.Arch)" -InnerWidth $innerW -Color DarkGray
    Write-TuiEmptyLine -InnerWidth $innerW

    # ── Progress bar ────────────────────────────────────────
    Write-TuiProgressBar -InnerWidth $innerW
    Write-TuiEmptyLine -InnerWidth $innerW

    # ── Tools section ───────────────────────────────────────
    $toolsLabel = if ($tui.Completion) { "installed" } else { "tools" }
    Write-TuiDivider -BoxWidth $boxW -Label $toolsLabel
    Write-TuiEmptyLine -InnerWidth $innerW

    foreach ($kv in $tui.Tools.GetEnumerator()) {
        Write-TuiToolLine -Name $kv.Key -Tool $kv.Value -InnerWidth $innerW
    }

    Write-TuiEmptyLine -InnerWidth $innerW

    # ── Log / Completion section ────────────────────────────
    if ($tui.Completion) {
        Write-TuiDivider -BoxWidth $boxW
        Write-TuiEmptyLine -InnerWidth $innerW
        Write-TuiTextLine -Text "  $($tui.Completion)" -InnerWidth $innerW -Color Green
        Write-TuiEmptyLine -InnerWidth $innerW
    } else {
        Write-TuiDivider -BoxWidth $boxW -Label "log"
        Write-TuiEmptyLine -InnerWidth $innerW

        $logStart = [Math]::Max(0, $tui.Log.Count - $tui.LogCapacity)
        $visibleCount = $tui.Log.Count - $logStart

        for ($i = $logStart; $i -lt $tui.Log.Count; $i++) {
            Write-TuiLogLine -Entry $tui.Log[$i] -InnerWidth $innerW
        }

        # Fill remaining log slots with empty lines
        for ($i = $visibleCount; $i -lt $tui.LogCapacity; $i++) {
            Write-TuiEmptyLine -InnerWidth $innerW
        }

        Write-TuiEmptyLine -InnerWidth $innerW
    }

    # ── Bottom border ───────────────────────────────────────
    Write-TuiBottomBorder -BoxWidth $boxW
}
