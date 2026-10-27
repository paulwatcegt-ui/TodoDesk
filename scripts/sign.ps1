#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PfxPath,

    [string]$Password = $env:DAIBAN_PFX_PASSWORD,

    [string]$TimestampServer = 'http://timestamp.digicert.com',

    [string[]]$Files,

    [switch]$AllowUntrusted
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $PfxPath)) {
    throw "找不到签名证书：$PfxPath"
}

$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
if ([string]::IsNullOrEmpty($Password)) {
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxPath)
}
else {
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
        $PfxPath, $Password, $flags)
}

if (-not $certificate.HasPrivateKey) {
    throw '签名证书没有可用的私钥。'
}

$codeSigningOid = '1.3.6.1.5.5.7.3.3'
$hasCodeSigningEku = $false
$ekuExtension = $certificate.Extensions |
    Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
    Select-Object -First 1
if ($null -ne $ekuExtension) {
    $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
        $ekuExtension, $false)
    foreach ($usage in $eku.EnhancedKeyUsages) {
        if ($usage.Value -eq $codeSigningOid) {
            $hasCodeSigningEku = $true
            break
        }
    }
}
if (-not $hasCodeSigningEku) {
    throw '证书没有 Code Signing (1.3.6.1.5.5.7.3.3) 用途。'
}

$targets = if ($null -ne $Files -and $Files.Count -gt 0) {
    $Files
}
else {
    @(
        (Join-Path $root 'app\DaiBan.ps1'),
        (Join-Path $root 'install.ps1'),
        (Join-Path $root 'uninstall.ps1')
    )
}

Write-Host ('Signing with: ' + $certificate.Subject)
Write-Host ('Thumbprint: ' + $certificate.Thumbprint)
Write-Host ''

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target)) {
        throw "要签名的文件不存在：$target"
    }

    $parameters = @{
        FilePath      = $target
        Certificate   = $certificate
        HashAlgorithm = 'SHA256'
    }
    if (-not [string]::IsNullOrWhiteSpace($TimestampServer)) {
        $parameters.TimestampServer = $TimestampServer
    }

    $signature = Set-AuthenticodeSignature @parameters
    Write-Host ('Signed ' + $target + ' -> ' + $signature.Status)

    if ($signature.Status -ne 'Valid' -and -not $AllowUntrusted) {
        throw "签名校验失败（$($signature.Status)）：$target。若使用自签名证书测试，请添加 -AllowUntrusted。"
    }
}

Remove-Variable Password -ErrorAction SilentlyContinue
Write-Host ''
Write-Host '全部文件已签名。'
