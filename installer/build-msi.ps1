$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$wix = Join-Path $env:LOCALAPPDATA 'Programs\WiX'
$candle = Join-Path $wix 'candle.exe'
$light = Join-Path $wix 'light.exe'
$outputDir = Join-Path $root 'dist\installer'
$object = Join-Path $outputDir 'DaiBan.wixobj'
$msi = Join-Path $outputDir 'DaiBan-1.3.0.msi'

if (-not (Test-Path -LiteralPath $candle)) { throw 'WiX candle.exe not found. Install or extract WiX v3.' }
if (-not (Test-Path -LiteralPath $light)) { throw 'WiX light.exe not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dist\native\DaiBan.exe'))) {
    throw 'Native DaiBan.exe has not been built.'
}

[void][System.IO.Directory]::CreateDirectory($outputDir)
Remove-Item $object, $msi -Force -ErrorAction SilentlyContinue

Push-Location $PSScriptRoot
try {
    & $candle -nologo -arch x64 -out $object (Join-Path $PSScriptRoot 'DaiBan.wxs')
    if ($LASTEXITCODE -ne 0) { throw 'candle failed.' }

    & $light -nologo -out $msi $object
    if ($LASTEXITCODE -ne 0) { throw 'light failed.' }
}
finally {
    Pop-Location
}

$info = Get-Item -LiteralPath $msi
Write-Host ('Built: ' + $info.FullName + ' (' + $info.Length + ' bytes)')
