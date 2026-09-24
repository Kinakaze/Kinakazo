[CmdletBinding()]
param([Parameter(Mandatory)][string]$CacheDirectory)
$ErrorActionPreference = 'Stop'
$version = '10.0.26100.4188'
$sha256 = '180DEB372659029864C10A0C04787833234D64AACD1D2C0661D2C00295D8E022'
$cache = [IO.Path]::GetFullPath($CacheDirectory)
$expanded = Join-Path $cache "sdk-$version"
$bin = Join-Path $expanded 'bin\10.0.26100.0\x64'
if (-not (Test-Path -LiteralPath (Join-Path $bin 'signtool.exe'))) {
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $archive = Join-Path $cache "sdk-$version.nupkg"
    if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive).Hash -ne $sha256) {
        & (Join-Path $PSScriptRoot 'Download-File.ps1') -Url "https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/$version/microsoft.windows.sdk.buildtools.$version.nupkg" -OutputPath $archive -Sha256 $sha256
    }
    if ((Get-FileHash -LiteralPath $archive).Hash -ne $sha256) { throw 'Windows SDK archive SHA-256 does not match the pinned version.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $expanded) { throw "Incomplete SDK cache. Rename or remove $expanded and retry." }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $expanded)
}
foreach ($name in @('makeappx.exe','signtool.exe')) {
    $file = Join-Path $bin $name
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Invalid Microsoft SDK tool signature: $name"
    }
}
$bin
