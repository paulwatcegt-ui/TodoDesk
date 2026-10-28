$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $root 'app'
$hostDir = Join-Path $root 'host'
$outputDir = Join-Path $root 'dist\native'
$output = Join-Path $outputDir 'DaiBan.exe'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sma = 'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'

if (-not (Test-Path -LiteralPath $csc)) { throw 'csc.exe not found.' }
if (-not (Test-Path -LiteralPath $sma)) { throw 'System.Management.Automation.dll not found.' }

[void][System.IO.Directory]::CreateDirectory($outputDir)

$arguments = @(
    '/nologo',
    '/codepage:65001',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    ('/out:"' + $output + '"'),
    ('/win32icon:"' + (Join-Path $appDir 'app.ico') + '"'),
    ('/win32manifest:"' + (Join-Path $hostDir 'app.manifest') + '"'),
    ('/reference:"' + $sma + '"'),
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Xml.dll',
    ('/resource:"' + (Join-Path $appDir 'DaiBan.ps1') + '",DaiBan.App.ps1'),
    ('/resource:"' + (Join-Path $appDir 'ui.xaml') + '",DaiBan.ui.xaml'),
    ('/resource:"' + (Join-Path $appDir 'themes\light.xaml') + '",DaiBan.theme.light.xaml'),
    ('/resource:"' + (Join-Path $appDir 'themes\dark.xaml') + '",DaiBan.theme.dark.xaml'),
    ('/resource:"' + (Join-Path $appDir 'app.ico') + '",DaiBan.app.ico'),
    ('/resource:"' + (Join-Path $root 'LICENSE') + '",DaiBan.LICENSE'),
    ('"' + (Join-Path $hostDir 'DaiBanHost.cs') + '"'),
    ('"' + (Join-Path $hostDir 'AssemblyInfo.cs') + '"')
)

& $csc $arguments
if ($LASTEXITCODE -ne 0) { throw 'Native host build failed.' }
if (-not (Test-Path -LiteralPath $output)) { throw 'Native host was not produced.' }

$info = Get-Item -LiteralPath $output
Write-Host ('Built: ' + $info.FullName + ' (' + $info.Length + ' bytes)')
