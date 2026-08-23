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

if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Emacs -HistoryNoDuplicates
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
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
