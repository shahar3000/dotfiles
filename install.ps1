[CmdletBinding()]
param(
    [switch]$SkipPackages,
    [switch]$SkipPlugins,
    [string]$ExpectedUserProfile
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

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    } finally {
        $identity.Dispose()
    }
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Add-UserPath([string]$Path) {
    $normalized = $Path.TrimEnd("\")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { $_ })
    if ($entries.TrimEnd("\") -notcontains $normalized) {
        $updated = (@($entries) + $normalized) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $updated, "User")
        Write-Info "added to user PATH: $normalized"
    }
    Refresh-ProcessPath
}

function Get-CocExtensionRoot {
    $dataHome = if ($env:COC_DATA_HOME) {
        $env:COC_DATA_HOME
    } else {
        Join-Path $env:LOCALAPPDATA "coc"
    }
    return Join-Path $dataHome "extensions\node_modules"
}

function Get-MissingCocExtensions([string]$ExtensionRoot) {
    return @(
        "coc-clangd", "coc-pyright", "coc-go" |
            Where-Object {
                -not (Test-Path -LiteralPath (Join-Path $ExtensionRoot $_))
            }
    )
}

function Install-CocExtensionsWithNpm(
    [string]$ExtensionRoot,
    [string[]]$Extensions
) {
    if ($Extensions.Count -eq 0) {
        return
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Warn "npm is unavailable; cannot retry coc extension installation"
        return
    }

    $extensionHome = Split-Path -Parent $ExtensionRoot
    New-Item -ItemType Directory -Force -Path $extensionHome | Out-Null
    $packagePath = Join-Path $extensionHome "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        Write-Utf8NoBom $packagePath "{`n  `"dependencies`": {}`n}`n"
    }

    Write-Info "retrying coc extensions with the configured npm client"
    Push-Location $extensionHome
    try {
        & npm install --no-audit --no-fund --package-lock=false @Extensions
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "npm coc extension installation returned exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
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

function Install-PowerShellModule([string]$Name) {
    if (Get-Module -ListAvailable -Name $Name) {
        Write-Info "$Name present"
        return
    }

    Write-Info "installing $Name"
    try {
        Install-PSResource -Name $Name -Scope CurrentUser -Repository PSGallery `
            -TrustRepository -AcceptLicense -Quiet
    } catch {
        Write-Warn "$Name could not be installed: $($_.Exception.Message)"
    }
}

function Assert-WorkingEnvironment([switch]$SkipPluginChecks) {
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($command in @(
        "pwsh", "wt", "git", "nvim", "starship", "node", "npm", "python",
        "go", "clangd", "rg", "bat", "fzf", "zoxide", "eza", "jq", "delta",
        "ctags", "claude", "copilot", "herdr"
    )) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            $missing.Add("command:$command")
        }
    }

    foreach ($module in @("posh-git", "PSFzf")) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missing.Add("PowerShell module:$module")
        }
    }

    if (-not $SkipPluginChecks) {
        foreach ($command in @("black", "gopls")) {
            if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
                $missing.Add("command:$command")
            }
        }

        if (Get-Command python -ErrorAction SilentlyContinue) {
            & python -c "import pynvim" *> $null
            if ($LASTEXITCODE -ne 0) {
                $missing.Add("Python module:pynvim")
            }
        }

        foreach ($plugin in @("coc.nvim", "lualine.nvim", "gruvbox.nvim")) {
            if (-not (Test-Path -LiteralPath (Join-Path $HOME ".vim\plugged\$plugin"))) {
                $missing.Add("Neovim plugin:$plugin")
            }
        }

        $vimLocal = Join-Path $HOME ".vimrc.local"
        if ((Test-Path -LiteralPath $vimLocal) -and
            (Select-String -LiteralPath $vimLocal `
                -Pattern "^\s*let\s+g:copilot_enabled\s*=\s*1\s*$" -Quiet)) {
            foreach ($plugin in @("copilot.vim", "plenary.nvim", "CopilotChat.nvim")) {
                if (-not (Test-Path -LiteralPath (Join-Path $HOME ".vim\plugged\$plugin"))) {
                    $missing.Add("Neovim plugin:$plugin")
                }
            }
        }

        $cocExtensionRoot = Get-CocExtensionRoot
        foreach ($extension in @(Get-MissingCocExtensions $cocExtensionRoot)) {
            $missing.Add("coc extension:$extension")
        }

        $markdownPreview = Join-Path $HOME `
            ".vim\plugged\markdown-preview.nvim\app\bin\markdown-preview-win.exe"
        if (-not (Test-Path -LiteralPath $markdownPreview -PathType Leaf)) {
            $missing.Add("markdown-preview.nvim Windows binary")
        }
    }

    if ($missing.Count -gt 0) {
        throw "Windows setup is incomplete. Missing: $($missing -join ', '). Re-run install.ps1 after resolving the preceding installation errors."
    }

    Write-Info "validated Windows development environment"
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

function Install-GitConfig([string]$Source, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $isReparsePoint = ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint) {
            $hasTarget = $existing.PSObject.Properties.Name -contains "Target"
            if ($hasTarget -and ($existing.Target -contains $Source)) {
                Remove-Item -LiteralPath $Destination -Force
            } else {
                Backup-Path $Destination
            }
            $existing = $null
        } elseif (-not $existing.PSIsContainer) {
            $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            if ($sourceHash -eq $destinationHash) {
                Backup-Path $Destination
                $existing = $null
            }
        }
    }

    if ($null -eq $existing) {
        Write-Utf8NoBom $Destination ""
    }

    $includes = @(& git config --file $Destination --get-all include.path)
    if ($includes -notcontains $Source) {
        & git config --file $Destination --add include.path $Source
        if ($LASTEXITCODE -ne 0) {
            throw "Could not include managed Git config from $Destination"
        }
    }
    Write-Info "configured mutable Git config: $Destination"
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

if ($ExpectedUserProfile -and
    -not $HOME.TrimEnd("\").Equals(
        $ExpectedUserProfile.TrimEnd("\"),
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Setup was elevated as a different Windows user. Run it from an Administrator PowerShell session belonging to the account being configured."
}

if (-not $SkipPackages -and -not (Test-IsAdministrator)) {
    # WinGet 1.28 can fail its per-installer UAC handoff with an Explorer
    # "no app associated" dialog. Elevating once avoids that broken path.
    Write-Info "requesting Administrator access for package installation"
    $hostExecutable = (Get-Process -Id $PID).Path
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass " +
        "-File `"$PSCommandPath`" -ExpectedUserProfile `"$HOME`""
    if ($SkipPlugins) {
        $arguments += " -SkipPlugins"
    }

    try {
        $process = Start-Process -FilePath $hostExecutable -Verb RunAs `
            -ArgumentList $arguments -Wait -PassThru
    } catch {
        throw "Administrator approval is required for package installation: $($_.Exception.Message)"
    }
    exit $process.ExitCode
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

    Install-PowerShellModule -Name "posh-git"
    Install-PowerShellModule -Name "PSFzf"

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

$llvmBin = Join-Path $env:ProgramFiles "LLVM\bin"
if (Test-Path -LiteralPath $llvmBin -PathType Container) {
    Add-UserPath -Path $llvmBin
}

Write-Info "linking Windows configuration"
$nvimConfig = Join-Path $env:LOCALAPPDATA "nvim"
Install-ManagedFile (Join-Path $RepoRoot "nvim\vimrc") (Join-Path $HOME ".vimrc")
Install-ManagedFile (Join-Path $RepoRoot "nvim\init.vim") (Join-Path $nvimConfig "init.vim")
Install-ManagedFile (Join-Path $RepoRoot "nvim\coc-settings.windows.json") (Join-Path $nvimConfig "coc-settings.json")
Install-ManagedDirectory (Join-Path $RepoRoot "nvim\after") (Join-Path $HOME ".vim\after")
Install-ManagedFile (Join-Path $RepoRoot "starship\starship.toml") (Join-Path $HOME ".config\starship.toml")
Install-GitConfig (Join-Path $RepoRoot "git\gitconfig.windows") (Join-Path $HOME ".gitconfig")
Install-ManagedFile (Join-Path $RepoRoot "git\gitignore_global") (Join-Path $HOME ".gitignore")
Install-ManagedFile (Join-Path $RepoRoot "herdr\config.windows.toml") (Join-Path $env:APPDATA "herdr\config.toml")
$powerShellProfile = Join-Path ([Environment]::GetFolderPath("MyDocuments")) `
    "PowerShell\Microsoft.PowerShell_profile.ps1"
Install-ManagedFile (Join-Path $RepoRoot "powershell\Microsoft.PowerShell_profile.ps1") $powerShellProfile
Install-ManagedFile (Join-Path $RepoRoot "claude\statusline.ps1") (Join-Path $HOME ".claude\statusline.ps1")

$powerShellInitCache = Join-Path $env:LOCALAPPDATA "dotfiles\powershell"
foreach ($pattern in @("starship-*.ps1", "zoxide-*.ps1")) {
    Get-ChildItem -LiteralPath $powerShellInitCache -Filter $pattern -File -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
}

Write-Info "warming PowerShell 7 startup cache"
$env:DOTFILES_PROFILE_TO_WARM = $powerShellProfile
try {
    & (Join-Path $PSHOME "pwsh.exe") -NoLogo -NoProfile -NonInteractive `
        -Command '. $env:DOTFILES_PROFILE_TO_WARM'
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell profile cache warm-up failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item Env:DOTFILES_PROFILE_TO_WARM -ErrorAction SilentlyContinue
}

Set-ClaudeSettings

$gitIdentity = Join-Path $HOME ".gitconfig.local"
$existingGitEmail = & git config --global user.email
if ([string]::IsNullOrWhiteSpace($existingGitEmail)) {
    if ([Console]::IsInputRedirected) {
        Write-Warn "Git identity is not configured. Set it with:"
        Write-Host '  git config --file "$HOME/.gitconfig.local" user.name "Your Name"'
        Write-Host '  git config --file "$HOME/.gitconfig.local" user.email "you@example.com"'
    } else {
        $gitName = Read-Host ">> git user.name (blank to skip)"
        $gitEmail = Read-Host ">> git user.email (blank to skip)"
        if (-not [string]::IsNullOrWhiteSpace($gitName)) {
            & git config --file $gitIdentity user.name $gitName
        }
        if (-not [string]::IsNullOrWhiteSpace($gitEmail)) {
            & git config --file $gitIdentity user.email $gitEmail
        }
        if (-not ([string]::IsNullOrWhiteSpace($gitName) -and [string]::IsNullOrWhiteSpace($gitEmail))) {
            Write-Info "wrote git identity to $gitIdentity"
        }
    }
}

$vimLocal = Join-Path $HOME ".vimrc.local"
if (-not (Test-Path -LiteralPath $vimLocal)) {
    Write-Utf8NoBom $vimLocal @"
let g:vimwiki_path = '$($HOME.Replace('\', '/'))/vimwiki/src'
"@
    Write-Info "created $vimLocal"
}

[string]$vimLocalContent = Get-Content -LiteralPath $vimLocal -Raw
if ([string]::IsNullOrEmpty($vimLocalContent) -or
    $vimLocalContent -notmatch "(?m)^\s*let\s+g:copilot_enabled\s*=") {
    $copilotEnabled = 0
    if (-not [Console]::IsInputRedirected) {
        $reply = Read-Host ">> enable Copilot AI completion and chat in nvim? [y/N]"
        if ($reply -match "^[yY]") {
            $copilotEnabled = 1
        }
    }

    $vimLocalContent = $vimLocalContent.TrimEnd() +
        "`r`nlet g:copilot_enabled = $copilotEnabled`r`n"
    Write-Utf8NoBom $vimLocal $vimLocalContent
    if ($copilotEnabled) {
        Write-Info "enabled Copilot in $vimLocal"
        Write-Info "run :Copilot setup once inside nvim to authenticate"
    }
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
        & python -m pip install --upgrade pynvim black
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Python provider packages failed to install"
        } else {
            $pythonScriptPaths = @(& python -c @"
import sysconfig
print(sysconfig.get_path('scripts'))
print(sysconfig.get_path('scripts', scheme='nt_user'))
"@)
            if ($LASTEXITCODE -eq 0 -and
                $pythonScriptPaths.Count -gt 0) {
                $pythonScriptPaths |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_) -and
                        (Test-Path -LiteralPath $_ -PathType Container)
                    } |
                    Sort-Object -Unique |
                    ForEach-Object { Add-UserPath -Path $_.Trim() }
            }
        }
    } else {
        Write-Warn "python is not on PATH; skipping pynvim and black"
    }

    if (Get-Command go -ErrorAction SilentlyContinue) {
        & go install golang.org/x/tools/gopls@latest
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "gopls failed to install"
        } else {
            Add-UserPath -Path (Join-Path $HOME "go\bin")
        }
    } else {
        Write-Warn "go is not on PATH; skipping gopls"
    }

    if (Get-Command nvim -ErrorAction SilentlyContinue) {
        $cocExtensionRoot = Get-CocExtensionRoot
        $previousCocInstalling = $env:DOTFILES_COC_INSTALLING
        $env:DOTFILES_COC_INSTALLING = "1"
        try {
            & nvim --headless "+PlugUpdate --sync" "+qall"
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "Neovim plugin installation had errors; run nvim +PlugUpdate manually"
            }

            $missingCocExtensions = @(Get-MissingCocExtensions $cocExtensionRoot)
            if ($missingCocExtensions.Count -gt 0) {
                $cocInstallCommand = "CocInstall -sync $($missingCocExtensions -join ' ')"
                & nvim --headless "+$cocInstallCommand" "+qall"
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "coc extension installation had errors; run :$cocInstallCommand"
                }
            }
        } finally {
            if ($null -eq $previousCocInstalling) {
                Remove-Item Env:DOTFILES_COC_INSTALLING -ErrorAction SilentlyContinue
            } else {
                $env:DOTFILES_COC_INSTALLING = $previousCocInstalling
            }
        }

        $missingCocExtensions = @(Get-MissingCocExtensions $cocExtensionRoot)
        if ($missingCocExtensions.Count -gt 0) {
            Write-Warn "coc's downloader failed; retrying through npm"
            Install-CocExtensionsWithNpm $cocExtensionRoot $missingCocExtensions
            $missingCocExtensions = @(Get-MissingCocExtensions $cocExtensionRoot)
        }
        if ($missingCocExtensions.Count -gt 0) {
            Write-Warn "coc extensions remain missing: $($missingCocExtensions -join ', ')"
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

Assert-WorkingEnvironment -SkipPluginChecks:$SkipPlugins

Write-Host
Write-Info "Windows setup complete"
Write-Host "Restart Windows Terminal, select PowerShell 7, and set its font face to JetBrainsMono Nerd Font Mono."
Write-Host "Configure Git identity and authenticate Claude/Copilot when first used."
Write-Host "Then run: herdr"
