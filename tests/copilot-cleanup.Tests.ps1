$ErrorActionPreference = "Stop"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot "..\install.ps1"), [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$helper = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq "Remove-LegacyCopilotShims"
}, $true)
if ($null -eq $helper) { throw "Remove-LegacyCopilotShims was not found" }

# Substitute only the persistent environment API so tests never change the user PATH.
class CopilotCleanupEnvironment {
    static [string]$UserPath
    static [int]$Writes
    static [string] GetEnvironmentVariable([string]$Name, [string]$Target) {
        if ($Name -ne "Path" -or $Target -ne "User") {
            throw "Unexpected environment read"
        }
        return [CopilotCleanupEnvironment]::UserPath
    }
    static [void] SetEnvironmentVariable(
        [string]$Name, [string]$Value, [string]$Target
    ) {
        if ($Name -ne "Path" -or $Target -ne "User") {
            throw "Unexpected environment write"
        }
        [CopilotCleanupEnvironment]::UserPath = $Value
        [CopilotCleanupEnvironment]::Writes++
    }
}
. ([scriptblock]::Create(
    $helper.Extent.Text.Replace("[Environment]", "[CopilotCleanupEnvironment]")
))
function Write-Info($Message) {}

$originalLocalAppData = $env:LOCALAPPDATA
$originalPath = $env:Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-copilot-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $env:LOCALAPPDATA = $testRoot
    $shimDirectory = Join-Path $testRoot "dotfiles\agency-copilot-shims"
    New-Item -ItemType Directory -Path $shimDirectory | Out-Null
    foreach ($name in @("copilot", "copilot.cmd", "copilot.cmd.backup")) {
        Set-Content -LiteralPath (Join-Path $shimDirectory $name) -Value "legacy"
    }
    $unrelatedDirectory = Join-Path $testRoot "dotfiles\powershell"
    New-Item -ItemType Directory -Path $unrelatedDirectory | Out-Null
    $unrelatedFile = Join-Path $unrelatedDirectory "keep.ps1"
    Set-Content -LiteralPath $unrelatedFile -Value "keep"

    $retained = 'C:\VS Code\bin\copilot-shim;;C:\WinGet\Links;C:\Agency;'
    [CopilotCleanupEnvironment]::UserPath =
        "$shimDirectory;$retained;`"C:\OLD\AGENCY-COPILOT-SHIMS\`""
    [CopilotCleanupEnvironment]::Writes = 0
    $env:Path = "C:\session-only;$shimDirectory;$retained"
    Remove-LegacyCopilotShims
    if ((Test-Path -LiteralPath $shimDirectory) -or
        (Get-Content -LiteralPath $unrelatedFile -Raw).Trim() -ne "keep" -or
        [CopilotCleanupEnvironment]::UserPath -cne $retained -or
        $env:Path -cne "C:\session-only;$retained" -or
        [CopilotCleanupEnvironment]::Writes -ne 1) {
        throw "Cleanup must delete only legacy shims and preserve unrelated paths"
    }
    Remove-LegacyCopilotShims
    if ([CopilotCleanupEnvironment]::Writes -ne 1 -or
        [CopilotCleanupEnvironment]::UserPath -cne $retained -or
        $env:Path -cne "C:\session-only;$retained") {
        throw "Repeated cleanup must leave PATH unchanged"
    }

    foreach ($emptyPath in @($null, "", $shimDirectory)) {
        [CopilotCleanupEnvironment]::UserPath = $emptyPath
        $env:Path = $emptyPath
        Remove-LegacyCopilotShims
        if ([CopilotCleanupEnvironment]::UserPath -or $env:Path) {
            throw "Cleanup must handle empty and shim-only paths"
        }
    }
    "Copilot shim cleanup and idempotence passed"
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:Path = $originalPath
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
