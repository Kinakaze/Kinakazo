[CmdletBinding()]
param(
    [string]$SourceDirectory, [string]$Compiler, [string]$SevenZip,
    [string]$SdkDirectory, [string]$OutputDirectory,
    [ValidateRange(0,65535)][int]$Revision = 0
)
$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $packageRoot -Parent) -Parent
$work = Join-Path $repoRoot ('build\QQNT.Isolated-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
if (-not $Compiler) {
    $command = Get-Command gcc.exe -ErrorAction SilentlyContinue
    if (-not $command) { throw 'MinGW-w64 GCC is required; pass -Compiler or add gcc.exe to PATH.' }
    $Compiler = $command.Source
}
if (-not $SdkDirectory) { $SdkDirectory = & (Join-Path $repoRoot 'scripts\Get-SdkTools.ps1') -CacheDirectory (Join-Path $repoRoot '.cache') }
foreach ($file in @($Compiler, (Join-Path $SdkDirectory 'makeappx.exe'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required build tool missing: $file" }
}
if ($SourceDirectory) {
    $source = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $versions = @(Get-ChildItem -LiteralPath (Join-Path $source 'versions') -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+-\d+$' | Sort-Object { [version]($_.Name -replace '-', '.') } -Descending)
    if (-not $versions.Count) { throw 'SourceDirectory does not contain a QQ NT version directory.' }
    $metadata = [pscustomobject]@{ Version=($versions[0].Name -split '-')[0]; ApplicationVersion=$versions[0].Name; Source='local' }
} else {
    $download = & (Join-Path $PSScriptRoot 'Get-LatestQQ.ps1') -OutputDirectory (Join-Path $work 'download') -SevenZip $SevenZip
    $source = $download.SourceDirectory
    $metadata = $download.Metadata
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'QQ.exe'))) { throw 'The complete QQ application root is required.' }
$bundle = Join-Path $work 'bundle'
$payload = Join-Path $bundle 'payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
& robocopy.exe $source $payload /E /XF *.zip qqcatch.exe *.log Uninstall.exe Uninstall.xml /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "QQ copy failed: $LASTEXITCODE" }
Copy-Item -Path (Join-Path $packageRoot 'layout\*') -Destination $payload -Recurse -Force
$manifestPath = Join-Path $payload 'AppxManifest.xml'
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
$packageVersion = "$($metadata.Version).$Revision"
$manifest.Package.Identity.Version = $packageVersion
$manifest.Save($manifestPath)
$savedPath = $env:PATH
try {
    $env:PATH = (Split-Path $Compiler -Parent) + ';' + $env:PATH
    & $Compiler (Join-Path $packageRoot 'src\Launcher.c') -o (Join-Path $payload 'QQIsolated.exe') -municode -mwindows -static -O2 -Wall -ladvapi32 -luser32 -lshell32
    if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
    & $Compiler (Join-Path $packageRoot 'src\PathProbe.c') -o (Join-Path $payload 'PathProbe.exe') -static -O2 -Wall -lshell32 -ladvapi32
    if ($LASTEXITCODE -ne 0) { throw 'Path probe compilation failed.' }
} finally { $env:PATH = $savedPath }
# User.dat is portable. Registry.dat belongs to the installing user, never the CI runner.
& (Join-Path $PSScriptRoot 'New-UserHive.ps1') -OutputPath (Join-Path $payload 'User.dat')
if (Test-Path -LiteralPath (Join-Path $payload 'Registry.dat')) { throw 'Machine-specific Registry.dat must not be included in the portable bundle.' }
$packLog = Join-Path $work 'pack.log'
& (Join-Path $SdkDirectory 'makeappx.exe') pack /d $payload /p (Join-Path $work 'validation.msix') /o *> $packLog
if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $packLog -Tail 30; throw 'MSIX manifest/packaging validation failed.' }
$bundleScripts = Join-Path $bundle 'scripts'
New-Item -ItemType Directory -Path $bundleScripts -Force | Out-Null
foreach ($script in @('Install.ps1','New-UserHive.ps1','Activate.ps1','Start.ps1','Stop.ps1','Inspect-Processes.ps1','Test-Isolation.ps1','Test-NativePaths.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination $bundleScripts
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\Get-SdkTools.ps1') -Destination $bundleScripts
Copy-Item -LiteralPath (Join-Path $packageRoot 'Install.cmd'),(Join-Path $packageRoot 'Start-QQ.cmd'),(Join-Path $packageRoot 'README.md') -Destination $bundle
$metadata | Add-Member -NotePropertyName PackageVersion -NotePropertyValue $packageVersion
$metadata | Add-Member -NotePropertyName BuiltAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundle 'upstream.json') -Encoding UTF8
$hashes = @(Get-ChildItem -LiteralPath $bundle -Recurse -File | ForEach-Object {
    [pscustomobject]@{ Path=$_.FullName.Substring($bundle.Length+1).Replace('\','/'); Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash }
})
ConvertTo-Json -InputObject $hashes -Depth 3 | Set-Content -LiteralPath (Join-Path $bundle 'files.sha256.json') -Encoding UTF8
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'artifacts\QQNT.Isolated' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$artifact = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "QQNT.Isolated-$packageVersion-x64.zip"
if (Test-Path -LiteralPath $artifact) { throw "Artifact already exists. Use a new -Revision or -OutputDirectory: $artifact" }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($bundle, $artifact, [IO.Compression.CompressionLevel]::Optimal, $false)
$digest = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
"$digest  $([IO.Path]::GetFileName($artifact))" | Set-Content -LiteralPath ($artifact + '.sha256') -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $bundle 'upstream.json') -Destination $OutputDirectory
Write-Host "Built $artifact"
if ($env:GITHUB_OUTPUT) { "version=$packageVersion" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8 }
[pscustomobject]@{ Artifact=$artifact; Version=$packageVersion; Sha256=$digest; BundleDirectory=$bundle }
