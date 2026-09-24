[CmdletBinding()]
param(
    [Parameter(Mandatory)][uri]$Url,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$Sha256,
    [string]$Referer
)
$ErrorActionPreference = 'Stop'
if ($Url.Scheme -ne 'https') { throw 'Downloads must use HTTPS.' }
$output = [IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $output) -and (Get-FileHash -LiteralPath $output).Hash -eq $Sha256) { return }
$root = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $root '.cache\aria2'
$aria2 = Join-Path $cache 'aria2-1.37.0-win-64bit-build1\aria2c.exe'
if (-not (Test-Path -LiteralPath $aria2)) {
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $archive = Join-Path $cache 'aria2.zip'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip' -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive).Hash -ne '67D015301EEF0B612191212D564C5BB0A14B5B9C4796B76454276A4D28D9B288') { throw 'aria2 bootstrap SHA-256 mismatch.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $cache -Force
}
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
$arguments = @('--no-conf','--split=16','--max-connection-per-server=16','--min-split-size=1M',
    '--max-concurrent-downloads=1','--file-allocation=none','--continue=true','--max-tries=3',
    '--retry-wait=3','--connect-timeout=30','--timeout=60','--auto-file-renaming=false',
    '--allow-overwrite=true','--check-integrity=true','--console-log-level=warn',
    '--summary-interval=0','--show-console-readout=false','--download-result=hide','--user-agent=Mozilla/5.0',
    ('--checksum=sha-256=' + $Sha256),('--dir=' + (Split-Path $output -Parent)),
    ('--out=' + [IO.Path]::GetFileName($output)))
if ($Referer) { $arguments += '--referer=' + $Referer }
$arguments += $Url.AbsoluteUri
& $aria2 @arguments | Out-Host
if ($LASTEXITCODE -ne 0) { throw "aria2 download failed with code $LASTEXITCODE for $Url" }
if ((Get-FileHash -LiteralPath $output).Hash -ne $Sha256) { throw "Download SHA-256 mismatch: $output" }
