$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package) { return }
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($package.InstallLocation + '\', [StringComparison]::OrdinalIgnoreCase)
} | Stop-Process
