[CmdletBinding()]
param([switch]$Start, [switch]$TrustCertificate, [switch]$PrepareOnly, [string]$CertificateThumbprint, [string]$SdkDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ([Environment]::OSVersion.Version.Build -lt 26100 -or -not [Environment]::Is64BitOperatingSystem) { throw 'Windows 11 24H2 (build 26100) or later, x64, is required.' }
$payload = Join-Path $root 'payload'
if (-not (Test-Path -LiteralPath (Join-Path $payload 'AppxManifest.xml'))) { throw 'Extract the build artifact and run its Install.cmd. The source checkout is not an installation bundle.' }
$checksums = Get-Content -LiteralPath (Join-Path $root 'files.sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($entry in $checksums) {
    $file = [IO.Path]::GetFullPath((Join-Path $root $entry.Path))
    if (-not $file.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file).Hash -ne $entry.Sha256) { throw "Bundle integrity check failed: $($entry.Path)" }
}
# Checksums detect corruption; users must still trust the source of this unsigned bundle.
[xml]$manifest = Get-Content -LiteralPath (Join-Path $payload 'AppxManifest.xml') -Raw -Encoding UTF8
$publisher = $manifest.Package.Identity.Publisher
if (-not $SdkDirectory) { $SdkDirectory = & (Join-Path $PSScriptRoot 'Get-SdkTools.ps1') -CacheDirectory (Join-Path $root '.cache') }
if ($CertificateThumbprint) { $certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" }
else {
    $certificate = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -eq $publisher -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(7) } | Sort-Object NotAfter -Descending | Select-Object -First 1
    if (-not $certificate) {
        $certificate = New-SelfSignedCertificate -Type CodeSigningCert -Subject $publisher -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(2) -FriendlyName 'Kinakazo local package signing'
    }
}
if ($certificate.Subject -ne $publisher -or -not $certificate.HasPrivateKey -or $certificate.NotAfter -le (Get-Date)) { throw 'A valid matching code-signing certificate with a private key is required.' }
$build = Join-Path $root ('build\install-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $build 'payload'
New-Item -ItemType Directory -Path $stage -Force | Out-Null
& robocopy.exe $payload $stage /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'Unable to stage installation files.' }
& (Join-Path $PSScriptRoot 'New-UserHive.ps1') -OutputPath (Join-Path $stage 'Registry.dat') -Machine
$artifact = Join-Path $build 'QQNT.Isolated.msix'
& (Join-Path $SdkDirectory 'makeappx.exe') pack /d $stage /p $artifact /o *> (Join-Path $build 'pack.log')
if ($LASTEXITCODE -ne 0) { throw "MSIX packing failed. See $build\pack.log" }
& (Join-Path $SdkDirectory 'signtool.exe') sign /fd SHA256 /sha1 $certificate.Thumbprint $artifact
if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed.' }
$certificateFile = Join-Path $build 'QQNT.Isolated.cer'
Export-Certificate -Cert $certificate -FilePath $certificateFile | Out-Null
if ($PrepareOnly) { return [pscustomobject]@{ Artifact=$artifact; Certificate=$certificateFile; UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value } }
if ($TrustCertificate -and -not (Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPeople\$($certificate.Thumbprint)")) {
    # Elevate only import of the public certificate, never QQ or its payload.
    $escaped = $certificateFile.Replace("'", "''")
    $trustScript = "`$ErrorActionPreference='Stop'; Import-Certificate -FilePath '$escaped' -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($trustScript))
    $process = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw 'Certificate trust installation failed or was cancelled.' }
}
$signature = Get-AuthenticodeSignature -LiteralPath $artifact
if ($signature.Status -ne 'Valid') { throw "Package certificate is not trusted. Retry with -TrustCertificate. Status: $($signature.Status)" }
Add-AppxPackage -Path $artifact -ErrorAction Stop
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package -or $package.Status -ne 'Ok') { throw 'Package registration verification failed.' }
$shell = New-Object -ComObject WScript.Shell
try {
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'QQ 隔离版.lnk'))
    $shortcut.TargetPath = Join-Path $env:WINDIR 'explorer.exe'
    $shortcut.Arguments = 'shell:AppsFolder\' + $package.PackageFamilyName + '!QQ'
    $shortcut.IconLocation = (Join-Path $package.InstallLocation 'QQ.exe') + ',0'
    $shortcut.Save()
} finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
$package | Select-Object Name,Version,Status,InstallLocation
if ($Start) { & (Join-Path $PSScriptRoot 'Start.ps1') }
