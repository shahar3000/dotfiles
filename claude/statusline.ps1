$rawInput = $input | Out-String
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    exit 0
}

$data = $rawInput | ConvertFrom-Json
$cwd = if ($data.workspace.current_dir) {
    $data.workspace.current_dir
} elseif ($data.cwd) {
    $data.cwd
} else {
    (Get-Location).Path
}

$model = $data.model.display_name
$context = $data.context_window.used_percentage
$branch = & git --no-optional-locks -C $cwd symbolic-ref --short HEAD 2>$null

Write-Host -NoNewline "`e[01;34m$cwd`e[00m"
if ($branch) {
    Write-Host -NoNewline " | `e[01;32m$branch`e[00m"
}
if ($model) {
    Write-Host -NoNewline " | `e[01;33m$model`e[00m"
}
if ($null -ne $context) {
    Write-Host -NoNewline (" | `e[01;36mctx:{0:N0}%`e[00m" -f [double]$context)
}
