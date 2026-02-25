# Contributing

Thanks for wanting to contribute! Here's how to get started.

## Adding a New Tool

The easiest way to contribute is by adding support for a new tool. Each tool is a self-contained PowerShell module in `windows/tools/`.

### 1. Create the module

Create `windows/tools/<toolname>.ps1` with three functions:

```powershell
# Metadata — tells the orchestrator about this tool
function Get-<Toolname>Metadata {
    return @{
        Name        = "<toolname>"
        Description = "Short description"
        Url         = "https://..."
        DependsOn   = @()  # tools that must install first
    }
}

# Detect — checks if already installed (shown on selection screen)
function Detect-<Toolname> {
    param([string]$BaseDir)
    # Check $BaseDir path first, then system PATH
    # Return @{ Installed = $true/$false; Version = "x.y.z" or $null }
}

# Install — does the actual work
function Install-<Toolname> {
    param(
        [string]$BaseDir,            # base install directory
        [string]$RequestedVersion = "latest"  # "latest", "pick", or specific
    )
    # ... install logic ...
    # Return $true on success, $false on failure
}

# Test — verifies the installation
function Test-<Toolname> {
    param([string]$BaseDir)
    # Call Write-Success or Write-Err
    # Return $true/$false
}
```

### 2. That's it

The orchestrator auto-discovers modules in the `tools/` directory. No other files need editing.

### Conventions

- **Function naming**: `Get-<Name>Metadata`, `Detect-<Name>`, `Install-<Name>`, `Test-<Name>` — capitalize the first letter
- **Return booleans**: install functions return `$true` / `$false`
- **Be idempotent**: running twice should not break anything
- **Custom directory**: install under `$BaseDir\<toolname>`, not a hardcoded path
- **PowerShell 5.1**: avoid syntax that requires PS 7+ (no ternary `?:`, no null-coalescing `??`)

### Shared Helpers

These are available to all tool modules:

**Output** (`lib/output.ps1`):
- `Write-Info $Message` — info line (yellow arrow, or TUI log entry)
- `Write-Success $Message` — success line (green check)
- `Write-Err $Message` — error line (red cross)

**Environment** (`lib/env.ps1`):
- `Set-PersistentEnvVar $Name $Value` — set a user-level environment variable
- `Add-ToUserPath @($path1, $path2)` — prepend paths to user PATH
- `Ensure-Dir $Path` — create directory if it doesn't exist
- `Normalize-Path $Path` — standardize path format

**Versions** (`lib/versions.ps1`):
- `Get-GitHubReleaseVersions -Repo "owner/name"` — fetch version list from GitHub Releases
- `Invoke-VersionPicker -ToolName "Go" -RequestedVersion $ver -AvailableVersions $list` — handles "latest", "pick", or explicit version

**Prompts** (`lib/prompt.ps1`):
- `Invoke-SelectPrompt -Title "Pick one:" -Items @(...)` — arrow-key single-select
- `Invoke-CheckboxPrompt -Title "Pick many:" -Items @(...)` — space-to-toggle multi-select
- `Invoke-TextPrompt -Title "Enter value"` — free-text input
- `Invoke-ConfirmPrompt -Title "Continue?"` — yes/no

**Downloads** (`lib/tui.ps1`):
- `Invoke-Download -Uri $url -OutFile $path` — download a file with TUI progress bar (falls back to `Invoke-WebRequest` outside TUI mode)
- `Format-FileSize $bytes` — human-readable size string (e.g., "150.2 MB")

### Dependencies

If your tool depends on another (e.g., `node` depends on `pnpm`), add it to `DependsOn`:

```powershell
DependsOn = @("pnpm")
```

The orchestrator resolves the dependency graph and installs in the correct order. Missing dependencies are auto-enabled with a notice, unless they are already installed on the system (detected via `Detect-*` functions).

If your tool needs to know about other tools that were installed (like `git` checking for `vscode`), add an `$InstalledTools` hashtable parameter to your install function.

### Architecture Parameter

If your tool has platform-specific downloads, add an `$Arch` parameter:

```powershell
function Install-<Toolname> {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest",
        [string]$Arch = "amd64"   # "amd64" or "arm64"
    )
    # ...
}
```

The orchestrator passes this automatically for tools listed in its arch-aware set. To register your tool, add its name to the `$toolName -in @("go", "pnpm", "vscode", "git", "jetbrains-toolbox")` check in `setup.ps1`.

### Detection Function

Every tool should include a `Detect-<Name>` function that checks if the tool is already installed. The selection screen uses this to show installed versions and default installed tools to unchecked.

```powershell
function Detect-<Toolname> {
    param([string]$BaseDir)
    # 1. Check the managed install path ($BaseDir\<toolname>\...)
    # 2. Fall back to system PATH (Get-Command <toolname>)
    # 3. Extract version via --version flag
    return @{ Installed = $true; Version = "1.2.3" }
    # or: @{ Installed = $false; Version = $null }
}
```

Guidelines:
- Check `$BaseDir` paths first, then fall back to `Get-Command` for system-wide installs
- Keep version strings clean — strip build metadata, tool name prefixes, etc.
- Wrap version extraction in `try/catch` — return `$null` for version if it can't be determined
- The function is called before the tool selection screen, so it should be fast (no network calls)

## Adding a New Platform

Platform support lives in top-level directories (`windows/`, `linux/`, `macos/`). Each platform has its own `setup.ps1` (or `setup.sh`), `lib/`, and `tools/`.

If you want to add Linux or macOS support:

1. Create the directory structure mirroring `windows/`
2. Implement equivalent lib helpers for bash
3. Port (or rewrite) each tool module
4. Update `install.ps1` to detect and route to the new platform

## Reporting Issues

- Include the full script output
- Mention your Windows version and PowerShell version (`$PSVersionTable`)
- If a specific tool failed, note which one and at what step

## Pull Requests

- One tool per PR if adding new tools
- Test on a clean Windows install if possible
- Keep modules self-contained — don't modify the orchestrator unless necessary
