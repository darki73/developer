# developer

A modular developer environment setup tool. Install your entire dev stack to a custom directory with a single command — no more patching on top of patches after every OS reinstall.

## Quick Start

**One-liner** (downloads and runs interactively):

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://raw.githubusercontent.com/darki73/developer/main/install.ps1 | iex"
```

**Or clone and run:**

```powershell
git clone https://github.com/darki73/developer.git
cd developer
.\windows\setup.ps1
```

**With a config file** (unattended):

```powershell
.\windows\setup.ps1 -ConfigFile .\configs\example.json
```

## Features

- **Full TUI experience** — htop-style dashboard with real-time progress bars, spinners, and a scrolling activity log, all in pure PowerShell (no external dependencies)
- **Download progress tracking** — per-file progress bars with percentage and size, powered by HEAD requests and chunked streaming
- **Interactive wizard** — arrow-key navigation, checkbox multi-select, version picker
- **Config file mode** — save your setup once, replay it on any machine
- **Single directory** — no C: drive pollution, pick any drive/folder
- **Dependency-aware** — tools install in the correct order automatically
- **Detects existing installs** — shows installed versions, skips already-installed dependencies
- **Re-runnable** — safe to run again without breaking existing installs

## Available Tools

| Tool | Description | Version Source |
|------|-------------|----------------|
| **uv** | Python package & project manager (Astral) | GitHub Releases |
| **python** | Python runtime (installed via uv) | uv python list |
| **pnpm** | Fast, disk-efficient Node.js package manager | GitHub Releases |
| **node** | Node.js runtime (installed via pnpm) | nodejs.org |
| **go** | Go programming language | go.dev/dl API |
| **vscode** | Visual Studio Code (with context menus & file associations) | Installer |
| **git** | Git for Windows (auto-sets VS Code as editor) | GitHub Releases |
| **claude-code** | Claude Code — AI coding assistant (Anthropic) | GCS binary |
| **jetbrains-toolbox** | JetBrains Toolbox — IDE manager | JetBrains API |

List available tools:

```powershell
.\windows\setup.ps1 -ListTools
```

## How It Works

1. **Choose** — pick an install directory, architecture, and which tools you want
2. **Install** — the TUI dashboard shows live progress as each tool downloads and installs
3. **Done** — restart your terminal and everything is on your PATH

The interactive mode offers to save your choices as a JSON config for future use.

## Config File

```json
{
    "install_directory": "C:\\Dev",
    "architecture": "amd64",
    "tools": {
        "uv":          { "enabled": true, "version": "latest" },
        "python":      { "enabled": true, "version": "3.12" },
        "pnpm":        { "enabled": true, "version": "latest" },
        "node":        { "enabled": true, "version": "24" },
        "go":          { "enabled": true, "version": "latest" },
        "vscode":      { "enabled": true, "version": "latest" },
        "git":         { "enabled": true, "version": "latest" },
        "claude-code": { "enabled": true, "version": "latest" },
        "jetbrains-toolbox": { "enabled": false, "version": "latest" }
    }
}
```

Version values:
- `"latest"` — auto-detect latest stable
- `"pick"` — show a version list, choose interactively
- `"3.12"`, `"24"`, `"1.26.0"` — install a specific version

## Project Structure

```
developer/
├── install.ps1              <- bootstrapper (curl | iex)
├── configs/
│   └── example.json         <- example config
└── windows/
    ├── setup.ps1            <- main orchestrator
    ├── lib/                 <- shared utilities
    │   ├── output.ps1       <- formatting helpers (Write-Info, Write-Success, Write-Err)
    │   ├── env.ps1          <- env vars & PATH management
    │   ├── prompt.ps1       <- interactive prompts (select, checkbox, text, confirm)
    │   ├── tui.ps1          <- full-screen TUI dashboard & download progress
    │   └── versions.ps1     <- version fetching & picker
    └── tools/               <- one module per tool (auto-discovered)
        ├── uv.ps1
        ├── python.ps1
        ├── pnpm.ps1
        ├── node.ps1
        ├── go.ps1
        ├── vscode.ps1
        ├── git.ps1
        ├── claude-code.ps1
        └── jetbrains-toolbox.ps1
```

## Adding a New Tool

Create a file in `windows/tools/` — for example, `rust.ps1`:

```powershell
function Get-RustMetadata {
    return @{
        Name        = "rust"
        Description = "Rust programming language"
        Url         = "https://www.rust-lang.org/"
        DependsOn   = @()  # optional: list tool names this depends on
    }
}

function Detect-Rust {
    param([string]$BaseDir)
    # Check BaseDir, then PATH — return installed status + version
    # Return @{ Installed = $true/$false; Version = "x.y.z" or $null }
}

function Install-Rust {
    param(
        [string]$BaseDir,
        [string]$RequestedVersion = "latest"
    )
    # Your install logic here
    # Return $true on success, $false on failure
}

function Test-Rust {
    param([string]$BaseDir)
    # Verify installation, call Write-Success or Write-Err
    # Return $true/$false
}
```

The orchestrator auto-discovers it. That's it — no other files to edit.

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and available helper functions.

## Requirements

- Windows 10 or later
- PowerShell 5.1+ (ships with Windows)
- Internet connection

## Platforms

- [x] Windows
- [ ] Linux (planned)
- [ ] macOS (planned)

## License

[MIT](LICENSE)
