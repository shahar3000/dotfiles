# Native Windows shell profile: PSReadLine + Starship + zoxide.
$env:EDITOR = "nvim"
$env:VISUAL = "nvim"
$env:BAT_THEME = "Visual Studio Dark+"
$env:STARSHIP_CONFIG = Join-Path $HOME ".config\starship.toml"
$env:VIMWIKI_MARKDOWN_EXTENSIONS = '{"toc": {"baselevel": 2 }, "nl2br": {}}'
# Let Node-based tools such as coc.nvim trust enterprise roots installed in
# the Windows certificate store.
$env:NODE_USE_SYSTEM_CA = "1"

$goPath = Join-Path $HOME "go"
$env:GOPATH = $goPath
$env:GOBIN = Join-Path $goPath "bin"
if ($env:Path -notlike "*$($env:GOBIN)*") {
    $env:Path += ";$($env:GOBIN)"
}

$llvmPath = Join-Path $env:ProgramFiles "LLVM\bin"
if ((Test-Path -LiteralPath $llvmPath) -and $env:Path -notlike "*$llvmPath*") {
    $env:Path += ";$llvmPath"
}

# Resolves and imports PSFzf on first use, returning the loaded module (or
# $null if it isn't installed). PSFzf's own Import-Module is unusually slow
# (~1-2s, a known upstream issue: github.com/kelleyma49/PSFzf#365, an internal
# Get-Module -ListAvailable call), so every key handler below loads it lazily
# on first press instead of importing it eagerly at shell startup, which
# would pay that cost on every single shell launch.
function Import-LazyPSFzf {
    $module = Get-Module -Name PSFzf
    if (-not $module) {
        $available = Get-Module -ListAvailable -Name PSFzf |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($available) {
            Import-Module $available.Path -ArgumentList "", "", "", "" -ErrorAction SilentlyContinue
            $module = Get-Module -Name PSFzf
        }
    }
    return $module
}

if (Import-Module PSReadLine -PassThru -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -EditMode Emacs -HistoryNoDuplicates

    # PowerShell's own completion engine (CommandCompletion.CompleteInput,
    # which both PSFzf's Tab handler and PowerShell's native completion call
    # internally) has an expensive one-time cold start per process -- measured
    # on a real machine at ~110ms cold vs ~18ms warm for the same call.
    # Without this, the FIRST real Tab press of a session pays that cost live
    # and looks like nothing happened, so you reach for a second press; the
    # second press is already warm and looks like "the one that worked" --
    # it isn't, it's just no longer paying the one-time cost. Pay that cost
    # once here instead, so a single Tab already works the first time.
    [void][System.Reflection.Assembly]::LoadWithPartialName("System.Management.Automation")
    $dotfilesCompletionWarmup = [System.Management.Automation.PowerShell]::Create('CurrentRunspace')
    try {
        [void][System.Management.Automation.CommandCompletion]::CompleteInput("cd ", 3, @{}, $dotfilesCompletionWarmup)
    } finally {
        $dotfilesCompletionWarmup.Dispose()
    }
    Remove-Variable dotfilesCompletionWarmup

    # Fzf-based Tab completion: the equivalent of zsh's fzf-tab, an actual
    # fuzzy-searchable picker instead of a plain cycling menu.
    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
        param($key, $arg)
        $module = Import-LazyPSFzf
        if ($module) {
            & $module { Invoke-FzfTabCompletion }
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete($key, $arg)
        }
    }
    Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious

    Set-PSReadLineKeyHandler -Key Ctrl+r `
        -BriefDescription "FzfHistory" `
        -Description "Search persistent PowerShell history with fzf" `
        -ScriptBlock {
            $module = Import-LazyPSFzf
            if (-not $module) {
                throw "PSFzf is not installed. Re-run install.ps1 without -SkipPackages."
            }
            & $module { Invoke-FzfPsReadlineHandlerHistory }
        }

    # Fuzzy-find a file/path anywhere under the cwd (recursively) and insert
    # it at the cursor -- the equivalent of zsh's Ctrl-t. Plain Tab, on both
    # zsh's fzf-tab and PSFzf, only completes one path segment at a time by
    # design; this is the actual tool for "search subdirectories too".
    Set-PSReadLineKeyHandler -Key Ctrl+t `
        -BriefDescription "FzfProvider" `
        -Description "Fuzzy-find a file/path with fzf and insert it at the cursor" `
        -ScriptBlock {
            $module = Import-LazyPSFzf
            if (-not $module) {
                throw "PSFzf is not installed. Re-run install.ps1 without -SkipPackages."
            }
            & $module { Invoke-FzfPsReadlineHandlerProvider }
        }

    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

$nativeInitCache = Join-Path $env:LOCALAPPDATA "dotfiles\powershell"
$importNativeInit = {
    param(
        [System.Management.Automation.ApplicationInfo]$Command,
        [string]$Name,
        [string[]]$Arguments
    )

    $executable = Get-Item -LiteralPath $Command.Source
    if ($executable.LinkType -and $executable.Target) {
        $target = $executable.Target
        if (-not [IO.Path]::IsPathRooted($target)) {
            $target = Join-Path $executable.DirectoryName $target
        }
        $executable = Get-Item -LiteralPath $target
    }

    $cacheKey = "$($executable.Length)-$($executable.LastWriteTimeUtc.Ticks)"
    $cacheFile = Join-Path $nativeInitCache "$Name-$cacheKey.ps1"
    if (-not (Test-Path -LiteralPath $cacheFile)) {
        New-Item -ItemType Directory -Force -Path $nativeInitCache | Out-Null
        $generated = & $Command.Source @Arguments | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "$Name initialization failed with exit code $LASTEXITCODE"
        }

        $tempFile = "$cacheFile.$PID.tmp"
        [IO.File]::WriteAllText($tempFile, $generated, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempFile -Destination $cacheFile -Force
    }

    . $cacheFile
}

$starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
if ($starship) {
    & $importNativeInit $starship "starship" @("init", "powershell", "--print-full-init")
}

$zoxide = Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue
if ($zoxide) {
    & $importNativeInit $zoxide "zoxide" @("init", "powershell")
}

Remove-Variable nativeInitCache, importNativeInit, starship, zoxide -ErrorAction SilentlyContinue

Register-ArgumentCompleter -Native -CommandName git, git.exe -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if (-not (Get-Module -Name posh-git)) {
        if (-not (Get-Module -ListAvailable -Name posh-git)) {
            return
        }
        Import-Module posh-git -ErrorAction Stop
    }

    $length = $cursorPosition - $commandAst.Extent.StartOffset
    $command = $commandAst.ToString().PadRight($length, " ").Substring(0, $length)
    Expand-GitCommand $command
}

$env:FZF_DEFAULT_OPTS = "--bind=ctrl-d:preview-page-down,ctrl-u:preview-page-up"

function global:vim { nvim @args }
function global:reprofile { . $PROFILE }

# PowerShell's built-in `ls` is an ALIAS to Get-ChildItem, and aliases take
# precedence over functions of the same name -- defining `function ls` alone
# would be silently shadowed by that alias. Remove it first so the function
# below actually runs.
Remove-Item -Path Alias:ls -Force -ErrorAction SilentlyContinue
function global:ls {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --color=always --git --icons=always --group-directories-first @args
    } else {
        Get-ChildItem @args
    }
}

function global:ll {
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        eza --color=always --long --git --icons=always --group-directories-first @args
    } else {
        Get-ChildItem -Force @args
    }
}

$localProfile = Join-Path $HOME ".powershell.local.ps1"
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}
