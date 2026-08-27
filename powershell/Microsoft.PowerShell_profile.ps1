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

if (Import-Module PSReadLine -PassThru -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -EditMode Emacs -HistoryNoDuplicates
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious
    Set-PSReadLineKeyHandler -Key Ctrl+r `
        -BriefDescription "FzfHistory" `
        -Description "Search persistent PowerShell history with fzf" `
        -ScriptBlock {
            $module = Get-Module -Name PSFzf
            if (-not $module) {
                $available = Get-Module -ListAvailable -Name PSFzf |
                    Sort-Object Version -Descending |
                    Select-Object -First 1
                if (-not $available) {
                    throw "PSFzf is not installed. Re-run install.ps1 without -SkipPackages."
                }

                Import-Module $available.Path -ArgumentList "", "", "", "" -ErrorAction Stop
                $module = Get-Module -Name PSFzf
            }

            & $module { Invoke-FzfPsReadlineHandlerHistory }
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
function global:rezsh { . $PROFILE }

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
