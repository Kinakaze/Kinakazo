[CmdletBinding()]
param([string]$ConfigText)
$ErrorActionPreference = 'Stop'
$metadata = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $ConfigText) { $ConfigText = (Invoke-WebRequest -UseBasicParsing -Uri $metadata.configUrl -TimeoutSec 60).Content }
# Extract only the JSON object; never execute JavaScript from the download site.
$match = [regex]::Match($ConfigText, '(?s)\bvar\s+params\s*=\s*(\{.*?\})\s*;')
if (-not $match.Success) { throw 'The official QQ download configuration format has changed.' }
$config = $match.Groups[1].Value | ConvertFrom-Json
if ($config.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid QQ version in official configuration.' }
$uri = [uri]$config.ntDownloadX64Url
$allowed = @('qqdl.gtimg.cn','dldir1.qq.com','dldir1v6.qq.com')
if ($uri.Scheme -ne 'https' -or $uri.Host -notin $allowed -or $uri.UserInfo -or -not $uri.IsDefaultPort -or $uri.AbsolutePath -notmatch '(?i)/QQ[^/]*_x64[^/]*\.exe$') {
    throw 'The official configuration did not provide an allowed HTTPS x64 QQ installer URL.'
}
if (-not $uri.AbsolutePath.Contains($config.version)) { throw 'QQ URL/version mismatch.' }
[pscustomobject]@{ Version=$config.version; UpdateDate=$config.updateDate; Url=$uri.AbsoluteUri; ConfigUrl=$metadata.configUrl; Homepage=$metadata.homepage }
