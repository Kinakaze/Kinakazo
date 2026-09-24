$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package) { throw 'Install the package first.' }
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
$logPath = Join-Path $env:LOCALAPPDATA ('Packages\' + $package.PackageFamilyName + '\AC\QQIsolated\launcher.log')
$before = if (Test-Path -LiteralPath $logPath) { (Get-Content -LiteralPath $logPath -Raw -Encoding UTF8).Length } else { 0 }
$hostBefore = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' | Select-Object AppData,'Local AppData',Personal | ConvertTo-Json -Compress
$probeId = & (Join-Path $PSScriptRoot 'Activate.ps1') -Arguments '--paths'
$deadline = (Get-Date).AddSeconds(30)
do {
    Start-Sleep -Milliseconds 300
    $content = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
    $fresh = $content.Substring([Math]::Min($before,$content.Length))
    if ($fresh -match 'PATH_VALIDATION_FAILURES=') { break }
} while ((Get-Date) -lt $deadline)
if ($fresh -notmatch 'PATH_VALIDATION_FAILURES=0') { throw "Native folder redirection failed or timed out. Close QQ before testing. $fresh" }
$hostAfter = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' | Select-Object AppData,'Local AppData',Personal | ConvertTo-Json -Compress
if ($hostAfter -ne $hostBefore) { throw 'The host known-folder configuration changed.' }
$fresh | Set-Content -LiteralPath (Join-Path $root 'build\native-paths.txt') -Encoding UTF8
'Native Documents, RoamingAppData, LocalAppData and Profile paths are internal; host configuration is unchanged.'
