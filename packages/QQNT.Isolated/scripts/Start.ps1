[CmdletBinding()]
param([int]$TimeoutSeconds = 90)
$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package) { throw 'Run scripts\Install.ps1 first.' }
$launchId = & (Join-Path $PSScriptRoot 'Activate.ps1') -AppId ($package.PackageFamilyName + '!QQ')
Write-Host "Activated isolated QQ, launcher PID: $launchId"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
    $window = Get-Process -Name QQ -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($package.InstallLocation + '\', [StringComparison]::OrdinalIgnoreCase) -and $_.MainWindowHandle -ne 0
    } | Select-Object -First 1
    if ($window) {
        & (Join-Path $PSScriptRoot 'Inspect-Processes.ps1')
        return
    }
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
throw "QQ did not show a window within $TimeoutSeconds seconds. See %LOCALAPPDATA%\Packages\$($package.PackageFamilyName)\AC\QQIsolated\launcher.log"
