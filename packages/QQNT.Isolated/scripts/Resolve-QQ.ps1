[CmdletBinding()]
param([string]$ManifestText, [string]$VersionsJson)
$ErrorActionPreference = 'Stop'
$metadata = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$headers = @{ Accept='application/vnd.github+json'; 'User-Agent'='Kinakazo'; 'X-GitHub-Api-Version'='2022-11-28' }
# This token is sent only to api.github.com, never to Tencent or the download URL.
if ($env:GH_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GH_TOKEN }
elseif ($env:GITHUB_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GITHUB_TOKEN }
$manifestUrl = $null; $blob = $null; $selected = $null
if ($VersionsJson -or -not $ManifestText) {
    if ($VersionsJson) { $entries = $VersionsJson | ConvertFrom-Json }
    else { $entries = Invoke-RestMethod -Uri ('https://api.github.com/repos/microsoft/winget-pkgs/contents/' + $metadata.wingetPath) -Headers $headers -TimeoutSec 60 }
    $versions = @($entries | Where-Object { $_.type -eq 'dir' -and $_.name -match '^\d+\.\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.name } -Descending)
    if (-not $versions.Count) { throw 'No stable four-part QQ versions were found in WinGet.' }
    $selected = $versions[0].name
    $manifestPath = $metadata.wingetPath + '/' + $selected + '/' + $metadata.wingetId + '.installer.yaml'
    $manifestUrl = 'https://github.com/microsoft/winget-pkgs/blob/master/' + $manifestPath
    if (-not $ManifestText) {
        $file = Invoke-RestMethod -Uri ('https://api.github.com/repos/microsoft/winget-pkgs/contents/' + $manifestPath) -Headers $headers -TimeoutSec 60
        if ($file.encoding -ne 'base64' -or $file.sha -notmatch '^[0-9a-f]{40}$') { throw 'Unexpected WinGet manifest response.' }
        $ManifestText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.content))
        $blob = $file.sha
    }
}
# Read only the scalar fields used by this package; unsupported YAML fails closed.
function Scalar([string]$text, [string]$name) {
    $matches = [regex]::Matches($text, '(?m)^[ \t]*' + [regex]::Escape($name) + ':[ \t]*([^\r\n]+)[ \t]*$')
    if ($matches.Count -ne 1) { throw "Expected exactly one $name in the WinGet manifest section." }
    $value = $matches[0].Groups[1].Value.Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) { $value=$value.Substring(1,$value.Length-2) }
    $value
}
$identifier = Scalar $ManifestText 'PackageIdentifier'
$version = Scalar $ManifestText 'PackageVersion'
if ($identifier -ne $metadata.wingetId -or $version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or ($selected -and $version -ne $selected)) { throw 'WinGet package identity/version mismatch.' }
$blocks = [regex]::Matches($ManifestText, '(?ms)^[ \t]*-[ \t]+Architecture:[ \t]*["'']?x64["'']?[ \t]*\r?\n(.*?)(?=^[ \t]*-[ \t]+Architecture:|^[A-Za-z]|\z)')
if ($blocks.Count -ne 1) { throw 'Expected exactly one x64 installer in the WinGet manifest.' }
$url = Scalar $blocks[0].Groups[1].Value 'InstallerUrl'
$hash = Scalar $blocks[0].Groups[1].Value 'InstallerSha256'
if ($hash -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid WinGet installer SHA-256.' }
$uri = [uri]$url
if ($uri.Scheme -ne 'https' -or $uri.Host -notin @('qqdl.gtimg.cn','dldir1.qq.com','dldir1v6.qq.com') -or $uri.UserInfo -or -not $uri.IsDefaultPort -or $uri.AbsolutePath -notmatch '(?i)/QQ[^/]*_x64[^/]*\.exe$') { throw 'Invalid WinGet QQ x64 HTTPS download URL.' }
$parts = $version.Split('.')
$productVersion = $parts[0..2] -join '.'
if (-not $uri.AbsolutePath.Contains($productVersion)) { throw 'WinGet URL/version mismatch.' }
[pscustomobject]@{
    Source='winget'; WingetId=$identifier; WingetVersion=$version; Version=$productVersion
    Url=$uri.AbsoluteUri; InstallerSha256=$hash.ToUpperInvariant()
    ManifestUrl=$manifestUrl; ManifestBlobSha=$blob; Homepage=$metadata.homepage
}
