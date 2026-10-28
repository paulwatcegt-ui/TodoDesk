#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $root 'dist\tools'
$destination = Join-Path $toolRoot 'wix-3.14.1'
$archive = Join-Path $toolRoot 'wix314-binaries.zip'
$expectedHash = '6AC824E1642D6F7277D0ED7EA09411A508F6116BA6FAE0AA5F2C7DAA2FF43D31'
[void][IO.Directory]::CreateDirectory($toolRoot)
if (-not (Test-Path -LiteralPath $archive)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip' -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'WiX archive hash mismatch.' }
if (-not (Test-Path -LiteralPath (Join-Path $destination 'candle.exe'))) { Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force }
Write-Host ('WiX 3.14.1 ready: ' + $destination)
