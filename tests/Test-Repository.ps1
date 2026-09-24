$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$checked = 0
foreach ($directory in @('scripts','packages','tests')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $directory) -Recurse -File -Filter '*.ps1' | Where-Object FullName -NotMatch '[\\/](build|payload|\.cache)[\\/]') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "$($file.FullName): $($errors.Message -join '; ')" }
        $checked++
    }
}
$resolve = Join-Path $root 'packages\QQNT.Isolated\scripts\Resolve-QQ.ps1'
function Config([string]$url, [string]$version='9.9.99') {
    'var params=' + (@{version=$version;updateDate='2026-01-01';ntDownloadX64Url=$url} | ConvertTo-Json -Compress) + '; this.define && define(function(){return params});'
}
$valid = Config 'https://qqdl.gtimg.cn/qqfile/QQNTV2/9.9.99/release/test/QQ_9.9.99_260101_x64_01.exe'
$resolved = & $resolve -ConfigText $valid
if ($resolved.Version -ne '9.9.99' -or $resolved.Url -notlike '*x64_01.exe') { throw 'Official QQ metadata resolution failed.' }
$invalidCases = @(
    'not JavaScript configuration',
    (Config 'http://qqdl.gtimg.cn/QQ_9.9.99_x64.exe'),
    (Config 'https://qqdl.gtimg.cn.evil.example/QQ_9.9.99_x64.exe'),
    (Config 'https://qqdl.gtimg.cn@evil.example/QQ_9.9.99_x64.exe'),
    (Config 'https://qqdl.gtimg.cn/QQ_9.9.99_x86.exe'),
    (Config 'https://qqdl.gtimg.cn/QQ_9.9.98_x64.exe'),
    (Config 'https://qqdl.gtimg.cn/QQ_9.9.99_x64.exe' 'bad-version')
)
foreach ($text in $invalidCases) {
    $rejected = $false
    try { & $resolve -ConfigText $text | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Resolver accepted invalid upstream metadata: $text" }
}
# The resolver treats trailing JavaScript as data and does not execute it.
$global:KinakazoUnexpectedExecution = $false
& $resolve -ConfigText ($valid + '; $global:KinakazoUnexpectedExecution = $true') | Out-Null
if ($global:KinakazoUnexpectedExecution) { throw 'Resolver executed configuration code.' }
Remove-Variable KinakazoUnexpectedExecution -Scope Global
$rejected = $false
try { & (Join-Path $root 'scripts\Build-Package.ps1') -Package '..\escape' | Out-Null } catch { $rejected = $true }
if (-not $rejected) { throw 'Package selector accepted path traversal.' }
[xml]$manifest = Get-Content -LiteralPath (Join-Path $root 'packages\QQNT.Isolated\layout\AppxManifest.xml') -Raw -Encoding UTF8
$caps = @($manifest.Package.Capabilities.ChildNodes | ForEach-Object { $_.GetAttribute('Name') })
if ('isolatedWin32-promptForAccess' -in $caps -or 'broadFileSystemAccess' -in $caps -or 'runFullTrust' -in $caps) { throw 'Forbidden isolation capability.' }
$app = $manifest.Package.Applications.Application
if ($app.GetAttribute('RuntimeBehavior','http://schemas.microsoft.com/appx/manifest/preview/windows10/security/2') -ne 'appSilo') { throw 'AppSilo runtime is required.' }
$workflow = Get-Content -LiteralPath (Join-Path $root '.github\workflows\build.yml') -Raw
if ($workflow -match '(?m)^  (push|pull_request|schedule|release):') { throw 'Builds must only run on demand.' }
Write-Host "PASS: $checked PowerShell files parse; resolver positive/negative cases; selector boundaries; AppSilo capabilities; manual trigger."
