# One-command bootstrap:
#   irm https://raw.githubusercontent.com/shahar3000/dotfiles/main/bootstrap.ps1 | iex
#
# Ensures git is present, clones (or fast-forward updates) the dotfiles
# repo, then invokes install.ps1 BY PATH from that clone -- never by piping
# its text through iex. install.ps1 relaunches itself via $PSCommandPath
# twice (UAC elevation, and the Windows PowerShell 5.1 -> PowerShell 7
# handoff); both break if it's ever run as a string with no backing file.
#
# For advanced usage (e.g. -SkipPackages/-SkipPlugins), clone manually and
# run install.ps1 directly -- see the README.
#
# Usage:
#   irm .../bootstrap.ps1 | iex
#   $env:DOTFILES_DIR = "$HOME\dotfiles"; irm .../bootstrap.ps1 | iex   # custom location

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/shahar3000/dotfiles.git"
$Dest = if ($env:DOTFILES_DIR) {
    $env:DOTFILES_DIR
} else {
    Join-Path (Get-Location) "dotfiles"
}

function Write-Info([string]$Message) {
    Write-Host ">> $Message" -ForegroundColor Cyan
}

# ---- ensure git ----
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Info "git not found -- installing it"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "git is required and winget is unavailable. Install App Installer from the Microsoft Store (for winget), or Git for Windows manually, then re-run."
    }
    & winget install --id Git.Git --exact --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install Git. Install it manually, then re-run."
    }
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git installation finished but git is still not on PATH. Restart the terminal, then re-run."
    }
}

# ---- clone or update ----
if (Test-Path -LiteralPath $Dest) {
    $gitDir = Join-Path $Dest ".git"
    $isDotfilesCheckout = $false
    if (Test-Path -LiteralPath $gitDir) {
        $origin = (& git -C $Dest remote get-url origin 2>$null)
        if ($LASTEXITCODE -eq 0 -and $origin -match "shahar3000/dotfiles") {
            $isDotfilesCheckout = $true
        }
    }
    if (-not $isDotfilesCheckout) {
        throw "$Dest already exists and isn't a dotfiles checkout -- move it aside or set `$env:DOTFILES_DIR, then re-run."
    }

    Write-Info "found existing checkout at $Dest -- updating"
    & git -C $Dest pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "$Dest has local commits that don't fast-forward -- resolve manually, then run $Dest\install.ps1 yourself."
    }
} else {
    Write-Info "cloning into $Dest"
    & git clone $RepoUrl $Dest
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed."
    }
}

# Invoke BY PATH (see header comment) so install.ps1's own UAC-elevation and
# PowerShell 7 relaunch behave correctly.
& (Join-Path $Dest "install.ps1")
exit $LASTEXITCODE
