#requires -Version 5.1
[CmdletBinding()]
param([string]$WixPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($WixPath)) { $WixPath = Join-Path $root 'dist\tools\wix-3.14.1' }
$candle = Join-Path $WixPath 'candle.exe'
$light = Join-Path $WixPath 'light.exe'
$uiExtension = Join-Path $WixPath 'WixUIExtension.dll'
$outputDir = Join-Path $root 'dist\installer'
$object = Join-Path $outputDir 'TodoDesk.wixobj'
$msi = Join-Path $outputDir 'TodoDesk-1.3.1-x64.msi'
foreach ($tool in @($candle,$light,$uiExtension)) { if (-not (Test-Path -LiteralPath $tool)) { throw 'WiX tools missing. Run installer/setup-wix.ps1 first.' } }
if (-not (Test-Path -LiteralPath (Join-Path $root 'dist\native\DaiBan.exe'))) { throw 'Build the app with host/build.ps1 first.' }
[void][IO.Directory]::CreateDirectory($outputDir)
# RTF is generated from the exact license shipped with the source and binary.
$license = [IO.File]::ReadAllText((Join-Path $root 'LICENSE'))
$rtf = [Text.StringBuilder]::new()
[void]$rtf.Append('{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\viewkind4\uc1\pard\f0\fs18 ')
foreach ($character in $license.ToCharArray()) {
    switch ([int]$character) {
        13 { }
        10 { [void]$rtf.Append('\par ') }
        92 { [void]$rtf.Append('\\') }
        123 { [void]$rtf.Append('\{') }
        125 { [void]$rtf.Append('\}') }
        default {
            if ([int]$character -gt 127) {
                $code = [int]$character
                if ($code -gt 32767) { $code -= 65536 }
                [void]$rtf.Append(('\u{0}?' -f $code))
            } else { [void]$rtf.Append($character) }
        }
    }
}
[void]$rtf.Append('}')
[IO.File]::WriteAllText((Join-Path $outputDir 'license.rtf'), $rtf.ToString(), [Text.Encoding]::ASCII)
Push-Location $PSScriptRoot
try {
    & $candle -nologo -arch x64 -ext $uiExtension -out $object (Join-Path $PSScriptRoot 'DaiBan.wxs')
    if ($LASTEXITCODE -ne 0) { throw 'WiX compilation failed.' }
    & $light -nologo -ext $uiExtension '-cultures:zh-cn' -out $msi $object
    if ($LASTEXITCODE -ne 0) { throw 'WiX linking or MSI validation failed.' }
} finally { Pop-Location }
Write-Host ('Built: ' + $msi)
