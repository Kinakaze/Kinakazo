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
function Manifest([string]$url, [string]$version='9.9.99.100', [string]$hash=('A' * 64)) {
    @"
PackageIdentifier: Tencent.QQ.NT
PackageVersion: $version
Installers:
- Architecture: x86
  InstallerUrl: https://qqdl.gtimg.cn/QQ_9.9.99_x86.exe
  InstallerSha256: $('B' * 64)
- Architecture: x64
  InstallerUrl: $url
  InstallerSha256: $hash
- Architecture: arm64
  InstallerUrl: https://qqdl.gtimg.cn/QQ_9.9.99_arm64.exe
  InstallerSha256: $('C' * 64)
ManifestType: installer
ManifestVersion: 1.12.0
"@
}
$valid = Manifest 'https://qqdl.gtimg.cn/qqfile/QQNT/9.9.99/release/test/QQ_9.9.99_260101_x64_01.exe'
$versions = '[{"name":"9.9.9.999","type":"dir"},{"name":"9.9.99.100","type":"dir"},{"name":"9.9.100-preview","type":"dir"}]'
$resolved = & $resolve -ManifestText $valid -VersionsJson $versions
if ($resolved.WingetVersion -ne '9.9.99.100' -or $resolved.Url -notlike '*x64_01.exe' -or $resolved.InstallerSha256 -ne ('A' * 64)) { throw 'WinGet version ordering or x64/hash resolution failed.' }
$invalidCases = @(
    'not a WinGet manifest',
    (Manifest 'http://qqdl.gtimg.cn/QQ_9.9.99_x64.exe'),
    (Manifest 'https://qqdl.gtimg.cn.evil.example/QQ_9.9.99_x64.exe'),
    (Manifest 'https://qqdl.gtimg.cn@evil.example/QQ_9.9.99_x64.exe'),
    (Manifest 'https://qqdl.gtimg.cn/QQ_9.9.99_x86.exe'),
    (Manifest 'https://qqdl.gtimg.cn/QQ_9.9.98_x64.exe'),
    (Manifest 'https://qqdl.gtimg.cn/QQ_9.9.99_x64.exe' 'bad-version'),
    (Manifest 'https://qqdl.gtimg.cn/QQ_9.9.99_x64.exe' '9.9.99.100' 'invalid-hash'),
    ($valid.Replace('Architecture: x64','Architecture: x86')),
    ($valid.Replace('PackageIdentifier: Tencent.QQ.NT','PackageIdentifier: Wrong.Package'))
)
foreach ($text in $invalidCases) {
    $rejected = $false
    try { & $resolve -ManifestText $text | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Resolver accepted invalid upstream metadata: $text" }
}
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
