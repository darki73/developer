# windows/lib/prompt.ps1
# Interactive TUI prompt primitives (arrow keys, checkboxes, selectors, text input)

function Test-InteractiveConsole {
    try {
        return -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

# ============================================================================
# Styled text input — title + hint + ">" prompt
# ============================================================================

function Invoke-TextPrompt {
    param(
        [string]$Title,
        [string]$Hint,
        [string]$Default,
        [switch]$Required
    )

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    if ($Hint) {
        Write-Host "  $Hint" -ForegroundColor DarkGray
    }

    if ($Default) {
        Write-Host "  ($Default) " -NoNewline -ForegroundColor DarkGray
    }
    Write-Host "> " -NoNewline -ForegroundColor Cyan
    $raw = Read-Host

    $value = if ($raw -and $raw.Trim() -ne "") { $raw.Trim() } else { $Default }

    if ($Required -and (-not $value -or $value -eq "")) {
        Write-Err "Required. Aborted."
        exit 0
    }

    return $value
}

# ============================================================================
# Confirm prompt — arrow keys to select Yes/No
# ============================================================================

function Invoke-ConfirmPrompt {
    param(
        [string]$Title,
        [bool]$Default = $true
    )

    $items = @(
        @{ Label = "Yes"; Description = "" }
        @{ Label = "No";  Description = "" }
    )
    $defaultIndex = if ($Default) { 0 } else { 1 }

    $selected = Invoke-SelectPrompt -Title $Title -Items $items -Default $defaultIndex
    return ($selected -eq 0)
}

# ============================================================================
# Single-select prompt — arrow keys to move, Enter to confirm
# ============================================================================

function Invoke-SelectPrompt {
    param(
        [string]$Title,
        [array]$Items,         # Each: @{ Label = "..."; Description = "..." }
        [int]$Default = 0
    )

    # Fallback for non-interactive consoles (piped input, ISE, etc.)
    if (-not (Test-InteractiveConsole)) {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $marker = if ($i -eq $Default) { " (default)" } else { "" }
            Write-Host "    [$($i + 1)] $($Items[$i].Label)$marker" -ForegroundColor Gray
        }
        $choice = Read-Host "  Select (1-$($Items.Count))"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Items.Count) {
            return [int]$choice - 1
        }
        return $Default
    }

    $cursor = $Default
    $lineWidth = try { [Console]::BufferWidth } catch { 80 }

    [Console]::CursorVisible = $false
    try {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White

        # Reserve lines for items
        for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host "" }
        # Calculate startY AFTER reserving — immune to console scrolling
        $startY = [Console]::CursorTop - $Items.Count

        while ($true) {
            [Console]::SetCursorPosition(0, $startY)

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]
                $isCurrent = ($i -eq $cursor)

                $pointer = if ($isCurrent) { ">" } else { " " }
                $pointerColor = if ($isCurrent) { "Cyan" } else { "DarkGray" }
                $labelColor = if ($isCurrent) { "Cyan" } else { "White" }

                $desc = if ($item.Description) { "  $($item.Description)" } else { "" }

                Write-Host "  " -NoNewline
                Write-Host $pointer -NoNewline -ForegroundColor $pointerColor
                Write-Host " $($item.Label)" -NoNewline -ForegroundColor $labelColor
                if ($desc) {
                    Write-Host $desc -NoNewline -ForegroundColor DarkGray
                }
                $written = 4 + $item.Label.Length + $desc.Length
                $pad = [Math]::Max(0, $lineWidth - $written - 1)
                Write-Host (" " * $pad)
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" {
                    if ($cursor -gt 0) { $cursor-- }
                }
                "DownArrow" {
                    if ($cursor -lt $Items.Count - 1) { $cursor++ }
                }
                "Enter" {
                    # Clear picker and print compact summary
                    [Console]::SetCursorPosition(0, $startY)
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        Write-Host (" " * ($lineWidth - 1))
                    }
                    [Console]::SetCursorPosition(0, $startY)
                    Write-Success "$Title $($Items[$cursor].Label)"

                    # Reclaim leftover blank lines
                    $leftover = $Items.Count - 1
                    if ($leftover -gt 0) {
                        for ($i = 0; $i -lt $leftover; $i++) {
                            Write-Host (" " * ($lineWidth - 1))
                        }
                        [Console]::SetCursorPosition(0, [Console]::CursorTop - $leftover)
                    }

                    return $cursor
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}

# ============================================================================
# Multi-select checkbox prompt — Space to toggle, A to toggle all, Enter done
# ============================================================================

function Invoke-CheckboxPrompt {
    param(
        [string]$Title,
        [array]$Items          # Each: @{ Key = "..."; Label = "..."; Description = "..."; Checked = $true }
    )

    # Fallback for non-interactive consoles
    if (-not (Test-InteractiveConsole)) {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White
        foreach ($item in $Items) {
            $answer = Read-Host "    $($item.Label)? (Y/n)"
            $item.Checked = (-not $answer) -or ($answer -in @("Y", "y", "yes", ""))
        }
        return $Items
    }

    $cursor = 0
    $lineWidth = try { [Console]::BufferWidth } catch { 80 }

    [Console]::CursorVisible = $false
    try {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor White
        Write-Host "  Space " -NoNewline -ForegroundColor DarkCyan
        Write-Host "toggle  " -NoNewline -ForegroundColor DarkGray
        Write-Host "A " -NoNewline -ForegroundColor DarkCyan
        Write-Host "toggle all  " -NoNewline -ForegroundColor DarkGray
        Write-Host "Enter " -NoNewline -ForegroundColor DarkCyan
        Write-Host "confirm" -ForegroundColor DarkGray

        # Reserve lines for items
        for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host "" }
        # Calculate startY AFTER reserving — immune to console scrolling
        $startY = [Console]::CursorTop - $Items.Count

        while ($true) {
            [Console]::SetCursorPosition(0, $startY)

            for ($i = 0; $i -lt $Items.Count; $i++) {
                $item = $Items[$i]
                $isCurrent = ($i -eq $cursor)
                $isChecked = $item.Checked

                $pointer = if ($isCurrent) { ">" } else { " " }
                $check = if ($isChecked) { "x" } else { " " }

                $pointerColor = if ($isCurrent) { "Cyan" } else { "DarkGray" }
                $checkColor = if ($isChecked) { "Green" } else { "DarkGray" }
                $labelColor = if ($isCurrent) { "Cyan" } else { "White" }

                $desc = $item.Description
                $depText = ""
                if ($item.DependsOn -and $item.DependsOn.Count -gt 0) {
                    $depText = " (requires: $($item.DependsOn -join ', '))"
                }

                Write-Host "  " -NoNewline
                Write-Host $pointer -NoNewline -ForegroundColor $pointerColor
                Write-Host " [" -NoNewline -ForegroundColor DarkGray
                Write-Host $check -NoNewline -ForegroundColor $checkColor
                Write-Host "] " -NoNewline -ForegroundColor DarkGray
                Write-Host "$($item.Label.PadRight(14))" -NoNewline -ForegroundColor $labelColor
                Write-Host $desc -NoNewline -ForegroundColor DarkGray
                if ($depText) {
                    Write-Host $depText -NoNewline -ForegroundColor DarkYellow
                }
                $written = 8 + $item.Label.PadRight(14).Length + $desc.Length + $depText.Length
                $pad = [Math]::Max(0, $lineWidth - $written - 1)
                Write-Host (" " * $pad)
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" {
                    if ($cursor -gt 0) { $cursor-- }
                }
                "DownArrow" {
                    if ($cursor -lt $Items.Count - 1) { $cursor++ }
                }
                "Spacebar" {
                    $Items[$cursor].Checked = -not $Items[$cursor].Checked
                }
                "A" {
                    $allChecked = ($Items | Where-Object { $_.Checked }).Count -eq $Items.Count
                    foreach ($item in $Items) { $item.Checked = -not $allChecked }
                }
                "Enter" {
                    # Clear picker
                    [Console]::SetCursorPosition(0, $startY)
                    for ($i = 0; $i -lt $Items.Count; $i++) {
                        Write-Host (" " * ($lineWidth - 1))
                    }
                    [Console]::SetCursorPosition(0, $startY)

                    # Print compact summary
                    $selected = @($Items | Where-Object { $_.Checked } | ForEach-Object { $_.Key })
                    if ($selected.Count -gt 0) {
                        Write-Host "  $([char]0x2713) $($selected.Count) tools selected: $($selected -join ', ')" -ForegroundColor Green
                    } else {
                        Write-Host "  No tools selected" -ForegroundColor DarkGray
                    }

                    # Reclaim leftover blank lines
                    $leftover = $Items.Count - 1
                    if ($leftover -gt 0) {
                        for ($i = 0; $i -lt $leftover; $i++) {
                            Write-Host (" " * ($lineWidth - 1))
                        }
                        [Console]::SetCursorPosition(0, [Console]::CursorTop - $leftover)
                    }

                    return $Items
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
    }
}
