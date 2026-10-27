#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$appScript = Join-Path $root 'app\DaiBan.ps1'

if (-not (Test-Path -LiteralPath $appScript)) {
    throw '找不到 app\DaiBan.ps1。'
}

$source = [System.IO.File]::ReadAllText($appScript, [System.Text.Encoding]::UTF8)
$match = [regex]::Match($source, "\`$script:AppVersion\s*=\s*'([^']+)'")
if (-not $match.Success) {
    throw '无法从 app\DaiBan.ps1 读取版本号。'
}
$version = $match.Groups[1].Value

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist ('DaiBan-v' + $version)
$zip = Join-Path $dist ('DaiBan-v' + $version + '.zip')
$checksum = $zip + '.sha256'

[void][System.IO.Directory]::CreateDirectory($dist)
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}

[void][System.IO.Directory]::CreateDirectory($stage)

Copy-Item -LiteralPath (Join-Path $root 'app') -Destination $stage -Recurse -Force
foreach ($item in @('install.ps1', 'uninstall.ps1', 'README.md', 'LICENSE', 'CHANGELOG.md')) {
    $path = Join-Path $root $item
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination $stage -Force
    }
}
$docs = Join-Path $root 'docs'
if (Test-Path -LiteralPath $docs) {
    Copy-Item -LiteralPath $docs -Destination $stage -Recurse -Force
}

Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal -Force
Remove-Item -LiteralPath $stage -Recurse -Force

$hash = Get-FileHash -LiteralPath $zip -Algorithm SHA256
$checksumLine = $hash.Hash + '  ' + [System.IO.Path]::GetFileName($zip) + "`r`n"
[System.IO.File]::WriteAllText(
    $checksum,
    $checksumLine,
    (New-Object System.Text.ASCIIEncoding))

Write-Host ('Package:  ' + $zip)
Write-Host ('Checksum: ' + $checksum)
Write-Host ('SHA256:   ' + $hash.Hash)
