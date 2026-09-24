[CmdletBinding()]
param(
    [string]$SourceDirectory, [string]$Compiler = 'cl.exe', [string]$SevenZip,
    [string]$SdkDirectory, [string]$OutputDirectory,
    [ValidateRange(0,65535)][int]$Revision = 0
)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $packageRoot -Parent) -Parent
$publicPath = Join-Path $repoRoot 'certificates\Kinakaze.cer'
$publicCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($publicPath)
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$($publicCertificate.Thumbprint)"
if ($certificate.Subject -ne 'CN=Kinakaze' -or -not $certificate.HasPrivateKey -or $certificate.NotAfter -le (Get-Date)) { throw 'The private key matching the fixed Kinakaze.cer is required.' }
# Use the installed Visual Studio toolchain, including x64 headers and libraries.
if (-not $env:VSCMD_VER) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) { throw 'Visual Studio C++ build tools are required.' }
    & (Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
}
if ($env:VSCMD_ARG_TGT_ARCH -ne 'x64') { throw 'An x64 MSVC developer environment is required.' }
if (-not (Get-Command $Compiler -ErrorAction SilentlyContinue)) { throw 'MSVC cl.exe was not found.' }
if (-not $SdkDirectory) { $SdkDirectory = & (Join-Path $repoRoot 'scripts\Get-SdkTools.ps1') -CacheDirectory (Join-Path $repoRoot '.cache') }
$work = Join-Path $repoRoot ('build\QQNT.Isolated-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
if ($SourceDirectory) {
    $source = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $versions = @(Get-ChildItem -LiteralPath (Join-Path $source 'versions') -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+-\d+$' | Sort-Object { [version]($_.Name -replace '-', '.') } -Descending)
    if (-not $versions.Count) { throw 'SourceDirectory does not contain a complete QQ NT installation.' }
    $metadata = [pscustomobject]@{ Version=($versions[0].Name -split '-')[0]; ApplicationVersion=$versions[0].Name; Source='local' }
} else {
    $download = & (Join-Path $PSScriptRoot 'Get-LatestQQ.ps1') -OutputDirectory (Join-Path $work 'download') -SevenZip $SevenZip
    $source = $download.SourceDirectory
    $metadata = $download.Metadata
}
$payload = Join-Path $work 'payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
# Never reuse packaging metadata or a machine hive from a previous isolated build.
& robocopy.exe $source $payload /E /XF *.zip qqcatch.exe *.log Uninstall.exe Uninstall.xml User.dat Registry.dat QQIsolated.exe AppxManifest.xml AppxBlockMap.xml AppxSignature.p7x /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "QQ copy failed: $LASTEXITCODE" }
Copy-Item -Path (Join-Path $packageRoot 'layout\*') -Destination $payload -Recurse -Force
$manifestPath = Join-Path $payload 'AppxManifest.xml'
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
if ($manifest.Package.Identity.Publisher -ne $certificate.Subject) { throw 'Manifest publisher must match Kinakaze.cer.' }
$packageVersion = "$($metadata.Version).$Revision"
$manifest.Package.Identity.Version = $packageVersion
$manifest.Save($manifestPath)
$compileArguments = @('/nologo','/O2','/MT','/W3','/utf-8','/DUNICODE','/D_UNICODE','/D_WIN32_WINNT=0x0A00',
    (Join-Path $packageRoot 'src\Launcher.c'),('/Fo' + (Join-Path $work 'Launcher.obj')),
    ('/Fe' + (Join-Path $payload 'QQIsolated.exe')),'/link','/SUBSYSTEM:WINDOWS','advapi32.lib','user32.lib','shell32.lib')
& $Compiler @compileArguments | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'MSVC launcher compilation failed.' }
& (Join-Path $PSScriptRoot 'New-UserHive.ps1') -OutputPath (Join-Path $payload 'User.dat')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts\QQNT.Isolated' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$artifact = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "QQNT.Isolated-$packageVersion-x64.msix"
if (Test-Path -LiteralPath $artifact) { throw 'Artifact already exists; choose a new revision or output directory.' }
$packLog = Join-Path $work 'pack.log'
& (Join-Path $SdkDirectory 'makeappx.exe') pack /d $payload /p $artifact /o *> $packLog
if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $packLog -Tail 20; throw 'MSIX validation/packaging failed.' }
& (Join-Path $SdkDirectory 'signtool.exe') sign /fd SHA256 /sha1 $certificate.Thumbprint $artifact | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Kinakaze package signing failed.' }
& (Join-Path $SdkDirectory 'signtool.exe') verify /pa $artifact | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Signed MSIX verification failed. The build environment must trust the fixed Kinakaze.cer for Authenticode verification.' }
Copy-Item -LiteralPath $publicPath -Destination (Join-Path $OutputDirectory 'Kinakaze.cer') -Force
$digest = (Get-FileHash -LiteralPath $artifact).Hash
if ($env:GITHUB_OUTPUT) { "version=$packageVersion" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8 }
if ($env:GITHUB_STEP_SUMMARY) {
    @"
## QQNT.Isolated $packageVersion
- Upstream: $($metadata.ApplicationVersion) ($($metadata.Source))
- Compiler: MSVC x64, static runtime
- Download: aria2, up to 16 connections, WinGet SHA-256 verified
- Publisher: CN=Kinakaze
- Certificate: $($certificate.Thumbprint)
- MSIX SHA-256: $digest
- Trust Kinakaze.cer in Local Machine / Trusted People, then install the MSIX.
- User folders are resolved at launch; the same package supports different Windows users.
- Windows 11 x64 24H2 or later is required.
"@ | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
[pscustomobject]@{ Artifact=$artifact; Version=$packageVersion; Sha256=$digest; Certificate=$certificate.Thumbprint }
