[CmdletBinding()]
param(
    [switch]$SkipPackages,
    [switch]$SkipPlugins
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

function Write-Info([string]$Message) {
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Warning $Message
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Install-WingetPackage([string]$Id, [string]$Name) {
    & winget list --id $Id --exact --accept-source-agreements --disable-interactivity *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Info "$Name present"
        return
    }

    Write-Info "installing $Name"
    & winget install --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "winget could not install $Name ($Id); continuing so the rest of the setup is usable"
    }
}

function Backup-Path([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        $stamp = Get-Date -Format "yyyyMMddHHmmss"
        $backup = "$Path.backup.$stamp"
        Move-Item -LiteralPath $Path -Destination $backup
        Write-Info "backup: $Path -> $backup"
    }
}

function Install-ManagedFile([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Source file is missing: $Source"
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $isReparsePoint = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint) {
            $hasTarget = $existing.PSObject.Properties.Name -contains "Target"
            if ($hasTarget -and ($existing.Target -contains $Source)) {
                return
            }
        } elseif (-not $existing.PSIsContainer) {
            $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                return
            }
        }
        Backup-Path $Destination
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        Write-Info "link: $Destination -> $Source"
    } catch {
        try {
            New-Item -ItemType HardLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
            Write-Info "hard link: $Destination -> $Source"
        } catch {
            Copy-Item -LiteralPath $Source -Destination $Destination
            Write-Warn "Links are unavailable; copied $Destination instead. Re-run after repo updates."
        }
    }
}

function Test-DirectoryContentEqual([string]$Source, [string]$Destination) {
    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd("\")
    $destinationRoot = (Resolve-Path -LiteralPath $Destination).Path.TrimEnd("\")
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse)
    $destinationFiles = @(Get-ChildItem -LiteralPath $destinationRoot -File -Recurse)
    if ($sourceFiles.Count -ne $destinationFiles.Count) {
        return $false
    }

    foreach ($sourceFile in $sourceFiles) {
        $relative = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart("\")
        $destinationFile = Join-Path $destinationRoot $relative
        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) {
            return $false
        }
        if ((Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash) {
            return $false
        }
    }
    return $true
}

function Install-ManagedDirectory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Source directory is missing: $Source"
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $isReparsePoint = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint) {
            $hasTarget = $existing.PSObject.Properties.Name -contains "Target"
            if ($hasTarget -and ($existing.Target -contains $Source)) {
                return
            }
        } elseif ($existing.PSIsContainer -and (Test-DirectoryContentEqual $Source $Destination)) {
            return
        }
        Backup-Path $Destination
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
        Write-Info "link: $Destination -> $Source"
    } catch {
        try {
            New-Item -ItemType Junction -Path $Destination -Target $Source -ErrorAction Stop | Out-Null
            Write-Info "junction: $Destination -> $Source"
        } catch {
            Copy-Item -LiteralPath $Source -Destination $Destination -Recurse
            Write-Warn "Links are unavailable; copied $Destination instead. Re-run after repo updates."
        }
    }
}

function Set-ClaudeSettings {
    $settingsPath = Join-Path $HOME ".claude\settings.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $settingsPath) | Out-Null

    if (Test-Path -LiteralPath $settingsPath) {
        $settingsText = Get-Content -LiteralPath $settingsPath -Raw
        if ([string]::IsNullOrWhiteSpace($settingsText) -or $settingsText.Trim() -eq "null") {
            $settings = [pscustomobject]@{}
        } else {
            try {
                $settings = $settingsText | ConvertFrom-Json
            } catch {
                throw "Cannot update invalid JSON in $settingsPath`: $($_.Exception.Message)"
            }
        }
    } else {
        $settings = [pscustomobject]@{}
    }

    if ($null -eq $settings -or
        $settings.GetType() -ne [System.Management.Automation.PSCustomObject]) {
        throw "Claude settings must contain a JSON object: $settingsPath"
    }

    $statuslinePath = Join-Path $HOME ".claude\statusline.ps1"
    $statusLine = [pscustomobject]@{
        type = "command"
        command = "pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$statuslinePath`""
    }
    $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine -Force
    Write-Utf8NoBom $settingsPath ($settings | ConvertTo-Json -Depth 100)
    Write-Info "configured Claude Code status line in $settingsPath"
}

function Install-MarkdownPreviewBinary([string]$PluginRoot) {
    $packagePath = Join-Path $PluginRoot "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        Write-Warn "markdown-preview.nvim is not cloned; its Windows binary cannot be installed"
        return $false
    }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        Write-Warn "curl.exe is unavailable; markdown-preview.nvim cannot be downloaded"
        return $false
    }

    $archive = $null
    $staging = $null
    try {
        $version = (Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json).version
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "package.json has no version"
        }

        $archive = Join-Path ([IO.Path]::GetTempPath()) `
            "markdown-preview-$([Guid]::NewGuid().ToString('N')).zip"
        $staging = Join-Path ([IO.Path]::GetTempPath()) `
            "markdown-preview-$([Guid]::NewGuid().ToString('N'))"
        $url = "https://github.com/iamcco/markdown-preview.nvim/releases/download/v$version/markdown-preview-win.zip"

        Write-Info "downloading markdown-preview.nvim Windows binary"
        & curl.exe --fail --location --silent --show-error --retry 3 `
            --output $archive $url
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe returned exit code $LASTEXITCODE"
        }

        Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
        $stagedBinary = Join-Path $staging "markdown-preview-win.exe"
        if (-not (Test-Path -LiteralPath $stagedBinary -PathType Leaf)) {
            throw "release archive does not contain markdown-preview-win.exe"
        }

        $binDirectory = Join-Path $PluginRoot "app\bin"
        New-Item -ItemType Directory -Force -Path $binDirectory | Out-Null
        Copy-Item -LiteralPath $stagedBinary `
            -Destination (Join-Path $binDirectory "markdown-preview-win.exe") -Force
        Write-Info "installed markdown-preview.nvim Windows binary"
        return $true
    } catch {
        Write-Warn "markdown-preview.nvim binary installation failed: $($_.Exception.Message)"
        return $false
    } finally {
        if ($archive) {
            Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        }
        if ($staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$platform = [Environment]::OSVersion.Platform
if ($platform -ne [PlatformID]::Win32NT) {
    throw "install.ps1 is for native Windows. Use install.sh on Linux, macOS, or WSL."
}

# Node 22.19+/24.6+ can trust enterprise roots from the Windows certificate
# store. coc.nvim inherits this and can install extensions behind TLS proxies.
$env:NODE_USE_SYSTEM_CA = "1"

if ($PSVersionTable.PSEdition -eq "Desktop") {
    if (-not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        if ($SkipPackages) {
            throw "PowerShell 7 is required. Re-run without -SkipPackages so it can be installed."
        }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "winget is required. Install or update App Installer from the Microsoft Store, then re-run."
        }
        Install-WingetPackage -Id "Microsoft.PowerShell" -Name "PowerShell 7"
        Refresh-ProcessPath
    }

    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($null -eq $pwsh) {
        throw "PowerShell 7 was installed but pwsh.exe is not available. Restart the terminal and re-run."
    }

    $pwshArguments = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($SkipPackages) { $pwshArguments += "-SkipPackages" }
    if ($SkipPlugins) { $pwshArguments += "-SkipPlugins" }
    & $pwsh.Source @pwshArguments
    exit $LASTEXITCODE
}

if (-not $SkipPackages) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required. Install or update App Installer from the Microsoft Store, then re-run."
    }

    $packages = @(
        @("Microsoft.PowerShell", "PowerShell 7"),
        @("Microsoft.WindowsTerminal", "Windows Terminal"),
        @("Git.Git", "Git"),
        @("Neovim.Neovim", "Neovim"),
        @("Starship.Starship", "Starship"),
        @("OpenJS.NodeJS.LTS", "Node.js LTS"),
        @("Python.Python.3.13", "Python"),
        @("GoLang.Go", "Go"),
        @("LLVM.LLVM", "LLVM"),
        @("BurntSushi.ripgrep.MSVC", "ripgrep"),
        @("sharkdp.bat", "bat"),
        @("junegunn.fzf", "fzf"),
        @("ajeetdsouza.zoxide", "zoxide"),
        @("eza-community.eza", "eza"),
        @("jqlang.jq", "jq"),
        @("dandavison.delta", "delta"),
        @("UniversalCtags.Ctags", "Universal Ctags"),
        @("DEVCOM.JetBrainsMonoNerdFont", "JetBrainsMono Nerd Font"),
        @("Anthropic.ClaudeCode", "Claude Code"),
        @("GitHub.Copilot", "GitHub Copilot CLI")
    )
    foreach ($package in $packages) {
        Install-WingetPackage -Id $package[0] -Name $package[1]
    }

    Refresh-ProcessPath

    if (-not (Get-Command herdr -ErrorAction SilentlyContinue)) {
        Write-Info "installing Herdr"
        $herdrInstaller = Join-Path ([IO.Path]::GetTempPath()) "herdr-install.ps1"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://herdr.dev/install.ps1" -OutFile $herdrInstaller
            & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $herdrInstaller
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Herdr installer returned exit code $LASTEXITCODE"
            }
        } catch {
            Write-Warn "Herdr could not be installed: $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $herdrInstaller -Force -ErrorAction SilentlyContinue
        }
        Refresh-ProcessPath
    }
}

Write-Info "linking Windows configuration"
$nvimConfig = Join-Path $env:LOCALAPPDATA "nvim"
Install-ManagedFile (Join-Path $RepoRoot "nvim\vimrc") (Join-Path $HOME ".vimrc")
Install-ManagedFile (Join-Path $RepoRoot "nvim\init.vim") (Join-Path $nvimConfig "init.vim")
Install-ManagedFile (Join-Path $RepoRoot "nvim\coc-settings.windows.json") (Join-Path $nvimConfig "coc-settings.json")
Install-ManagedDirectory (Join-Path $RepoRoot "nvim\after") (Join-Path $HOME ".vim\after")
Install-ManagedFile (Join-Path $RepoRoot "starship\starship.toml") (Join-Path $HOME ".config\starship.toml")
Install-ManagedFile (Join-Path $RepoRoot "git\gitconfig.windows") (Join-Path $HOME ".gitconfig")
Install-ManagedFile (Join-Path $RepoRoot "git\gitignore_global") (Join-Path $HOME ".gitignore")
Install-ManagedFile (Join-Path $RepoRoot "herdr\config.windows.toml") (Join-Path $env:APPDATA "herdr\config.toml")
Install-ManagedFile (Join-Path $RepoRoot "powershell\Microsoft.PowerShell_profile.ps1") `
    (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1")
Install-ManagedFile (Join-Path $RepoRoot "claude\statusline.ps1") (Join-Path $HOME ".claude\statusline.ps1")

Set-ClaudeSettings

$gitIdentity = Join-Path $HOME ".gitconfig.local"
if (-not (Test-Path -LiteralPath $gitIdentity)) {
    Write-Warn "Git identity is not configured. Set it with:"
    Write-Host '  git config --file "$HOME/.gitconfig.local" user.name "Your Name"'
    Write-Host '  git config --file "$HOME/.gitconfig.local" user.email "you@example.com"'
}

$vimLocal = Join-Path $HOME ".vimrc.local"
if (-not (Test-Path -LiteralPath $vimLocal)) {
    $vimLocalContent = @"
let g:vimwiki_path = '$($HOME.Replace('\', '/'))/vimwiki/src'
let g:copilot_enabled = 0
"@
    Write-Utf8NoBom $vimLocal $vimLocalContent
    Write-Info "created $vimLocal"
}

if (-not $SkipPlugins) {
    $plugPath = Join-Path $HOME ".vim\autoload\plug.vim"
    if (-not (Test-Path -LiteralPath $plugPath)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plugPath) | Out-Null
        try {
            Invoke-WebRequest -UseBasicParsing `
                -Uri "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" `
                -OutFile $plugPath
            Write-Info "installed vim-plug"
        } catch {
            Write-Warn "vim-plug could not be installed: $($_.Exception.Message)"
            Remove-Item -LiteralPath $plugPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        & python -m pip install --user --upgrade pynvim black
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Python provider packages failed to install"
        }
    } else {
        Write-Warn "python is not on PATH; skipping pynvim and black"
    }

    if (Get-Command go -ErrorAction SilentlyContinue) {
        & go install golang.org/x/tools/gopls@latest
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "gopls failed to install"
        }
    } else {
        Write-Warn "go is not on PATH; skipping gopls"
    }

    if (Get-Command nvim -ErrorAction SilentlyContinue) {
        & nvim --headless "+PlugUpdate --sync" "+qall"
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Neovim plugin installation had errors; run nvim +PlugUpdate manually"
        }
        $markdownPreviewRoot = Join-Path $HOME ".vim\plugged\markdown-preview.nvim"
        $markdownPreview = Join-Path $markdownPreviewRoot `
            "app\bin\markdown-preview-win.exe"
        if (-not (Test-Path -LiteralPath $markdownPreview -PathType Leaf)) {
            [void](Install-MarkdownPreviewBinary $markdownPreviewRoot)
        }
        if (-not (Test-Path -LiteralPath $markdownPreview -PathType Leaf)) {
            Write-Warn "markdown-preview.nvim is unavailable; see the preceding download error"
        }
    } else {
        Write-Warn "nvim is not on PATH; skipping plugin installation"
    }
}

if (Get-Command herdr -ErrorAction SilentlyContinue) {
    & herdr integration install claude
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Herdr's Claude integration failed; run 'herdr integration install claude' manually"
    }
} else {
    Write-Warn "herdr is not on PATH; its Claude integration was not installed"
}

Write-Host
Write-Info "Windows setup complete"
Write-Host "Restart Windows Terminal, select PowerShell 7, and set its font face to JetBrainsMono Nerd Font Mono."
Write-Host "Then run: herdr"
