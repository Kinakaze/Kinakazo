param([string]$CanaryDirectory)
$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package) { throw 'The isolated package is not installed.' }
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
if (-not $CanaryDirectory) { $CanaryDirectory = Join-Path $root 'build' }
$canary = Join-Path $CanaryDirectory ('host-canary-' + [Guid]::NewGuid().ToString('N') + '.txt')
$content = [Guid]::NewGuid().ToString()
Set-Content -LiteralPath $canary -Value $content -Encoding ASCII
$reportPath = Join-Path $env:LOCALAPPDATA ('Packages\' + $package.PackageFamilyName + '\AC\QQIsolated\isolation-probe.json')
try {
    $start = Get-Date
    $probePid = & (Join-Path $PSScriptRoot 'Activate.ps1') -Arguments ('--probe-file "' + $canary + '" ' + $PID)
    $deadline = (Get-Date).AddSeconds(30)
    do {
        if ((Test-Path -LiteralPath $reportPath) -and (Get-Item -LiteralPath $reportPath).LastWriteTime -ge $start) { break }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    if (-not (Test-Path -LiteralPath $reportPath) -or (Get-Item -LiteralPath $reportPath).LastWriteTime -lt $start) {
        throw 'The sandbox probe did not produce a fresh report. Close isolated QQ before running this test.'
    }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ((Get-Content -LiteralPath $canary -Raw).Trim() -ne $content) { throw 'The host canary was unexpectedly changed.' }
    if (-not $report.appContainer -or $report.hostReadError -ne 5 -or $report.hostWriteError -ne 5 -or $report.hostProcessError -ne 5) {
        $report | Format-List
        throw 'A sandbox boundary probe failed.'
    }
    Copy-Item -LiteralPath $reportPath -Destination (Join-Path $root 'build\isolation-probe.json') -Force
    $report
} finally { Remove-Item -LiteralPath $canary -Force }
