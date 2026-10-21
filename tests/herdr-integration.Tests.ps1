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
    $node.Name -eq "Configure-HerdrIntegration"
}, $true)
if ($null -eq $helper) { throw "Configure-HerdrIntegration was not found" }
. ([scriptblock]::Create($helper.Extent.Text))

function Write-Utf8NoBom($Path, $Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Write-Info($Message) {}
function Write-Warn($Message) { $script:Warnings += $Message }
function herdr {
    $global:LASTEXITCODE = 0
    if ($args[1] -eq "status") { "copilot: not installed" }
    else { $script:Operations += ($args -join " ") }
}

$originalAppData = $env:APPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-herdr-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $env:APPDATA = $testRoot
    $choicePath = Join-Path $testRoot "herdr\dotfiles-copilot-integration"
    New-Item -ItemType Directory -Path (Split-Path $choicePath -Parent) | Out-Null
    foreach ($content in @("", " `r`n")) {
        Write-Utf8NoBom $choicePath $content
        $script:Warnings = @()
        $script:Operations = @()
        $script:Prompts = 0
        Configure-HerdrIntegration -Target copilot -CommandName Get-Item `
            -DisplayName Copilot -PromptReader {
                param($Prompt)
                $script:Prompts++
                "y"
            }
        if ($script:Warnings.Count -ne 1 -or
            $script:Warnings[0] -notlike "Invalid Herdr integration choice*") {
            throw "An invalid choice should emit a warning"
        }
        if ($script:Prompts -ne 1 -or
            ($script:Operations -join ",") -ne "integration install copilot" -or
            (Get-Content -LiteralPath $choicePath -Raw).Trim() -ne "1") {
            throw "An invalid choice should be prompted again, saved, and applied"
        }
    }
    "Herdr empty and whitespace-only choice recovery passed"
} finally {
    $env:APPDATA = $originalAppData
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
