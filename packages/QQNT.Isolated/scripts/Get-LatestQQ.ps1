[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory, [string]$SevenZip)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $SevenZip) {
    $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
    $SevenZip = if ($command) { $command.Source } else { Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
}
if (-not (Test-Path -LiteralPath $SevenZip)) { throw '7-Zip is required. Pass -SevenZip with the path to 7z.exe.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Download directory must be new to prevent mixing QQ versions.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$release = & (Join-Path $PSScriptRoot 'Resolve-QQ.ps1')
Write-Host "Downloading official QQ $($release.Version) x64"
Write-Host "Official installer URL: $($release.Url)"
$installer = Join-Path $output 'QQ-installer.exe'
$downloaded = $false
for ($attempt=1; $attempt -le 3; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $release.Url -OutFile $installer -TimeoutSec 600 -Headers @{ Referer=$release.Homepage } -UserAgent 'Mozilla/5.0'
        $downloaded = $true
        break
    } catch {
        if ($attempt -eq 3) { throw "Latest QQ $($release.Version) could not be downloaded from $($release.Url): $($_.Exception.Message)" }
        Start-Sleep -Seconds (2 * $attempt)
    }
}
if (-not $downloaded) { throw 'QQ download failed.' }
$signature = Get-AuthenticodeSignature -LiteralPath $installer
$diagnostic = [pscustomobject]@{
    Release=$release; Length=(Get-Item -LiteralPath $installer).Length
    SignatureStatus=$signature.Status.ToString(); SignatureMessage=$signature.StatusMessage
    Signer=$signature.SignerCertificate.Subject; Sha256=(Get-FileHash -LiteralPath $installer).Hash
}
$diagnostic | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'download-diagnostic.json') -Encoding UTF8
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)Tencent') {
    $diagnostic | ConvertTo-Json -Depth 5 | Write-Host
    throw 'QQ installer must have a valid Tencent Authenticode signature.'
}
$release | Add-Member -NotePropertyName InstallerSha256 -NotePropertyValue (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$release | Add-Member -NotePropertyName Signer -NotePropertyValue $signature.SignerCertificate.Subject
$extract = Join-Path $output 'extracted'
& $SevenZip x $installer "-o$extract" -y -bso0 -bsp0
if ($LASTEXITCODE -ne 0) { throw 'Unable to extract QQ installer.' }
$archives = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter '*.7z')
foreach ($archive in $archives) {
    $destination = Join-Path $output ('payload-' + [Guid]::NewGuid().ToString('N'))
    & $SevenZip x $archive.FullName "-o$destination" -y -bso0 -bsp0
    if ($LASTEXITCODE -ne 0) { throw "Unable to extract QQ payload $($archive.Name)." }
}
$candidates = @(Get-ChildItem -LiteralPath $output -Recurse -File -Filter QQ.exe | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.DirectoryName 'versions') -PathType Container
})
if ($candidates.Count -ne 1) { throw "Expected one complete QQ application root, found $($candidates.Count). The upstream installer layout may have changed." }
$source = $candidates[0].DirectoryName
$versions = @(Get-ChildItem -LiteralPath (Join-Path $source 'versions') -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+-\d+$')
if ($versions.Count -ne 1 -or -not $versions[0].Name.StartsWith($release.Version + '-')) { throw 'Extracted QQ version does not match official latest metadata.' }
$release | Add-Member -NotePropertyName ApplicationVersion -NotePropertyValue $versions[0].Name
$release | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'upstream.json') -Encoding UTF8
[pscustomobject]@{ SourceDirectory=$source; Metadata=$release }
