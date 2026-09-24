[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]+$')][string]$Package,
    [Parameter(Mandatory)][ValidatePattern('^S-1-(5-21|12-1)-\d+-\d+-\d+-\d+$')][string]$TargetUserSid,
    [string]$SourceDirectory,
    [string]$Compiler,
    [string]$SevenZip,
    [string]$SdkDirectory,
    [ValidateRange(0,65535)][int]$Revision = 0
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$packageRoot = Join-Path $root "packages\$Package"
$metadataFile = Join-Path $packageRoot 'package.json'
if (-not (Test-Path -LiteralPath $metadataFile)) { throw "Unknown package: $Package" }
$metadata = Get-Content -LiteralPath $metadataFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($metadata.name -ne $Package -or $metadata.buildScript -ne 'scripts/Build.ps1') { throw 'Invalid package metadata.' }
$parameters = @{ Revision = $Revision; TargetUserSid = $TargetUserSid }
foreach ($key in @('SourceDirectory','Compiler','SevenZip','SdkDirectory')) {
    if ($PSBoundParameters.ContainsKey($key)) { $parameters[$key] = $PSBoundParameters[$key] }
}
& (Join-Path $packageRoot $metadata.buildScript) @parameters
