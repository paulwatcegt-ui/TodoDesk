#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$DesktopShortcut
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$source = Join-Path $root 'app'
$installDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\DaiBan'
$startMenu = [Environment]::GetFolderPath('Programs')
$desktop = [Environment]::GetFolderPath('Desktop')
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appScript = Join-Path $installDir 'DaiBan.ps1'
$iconPath = Join-Path $installDir 'app.ico'
$shortcutPath = Join-Path $startMenu '待办.lnk'

$running = $false
try {
    $mutex = [System.Threading.Mutex]::OpenExisting('Local\DaiBan.Todo.Hosted.SingleInstance')
    $mutex.Dispose()
    $running = $true
}
catch [System.Threading.WaitHandleCannotBeOpenedException] {
}
catch {
}

if ($running) {
    Write-Host '请先关闭正在运行的“待办”，再重新运行安装。'
    exit 1
}

foreach ($required in @(
    (Join-Path $source 'DaiBan.ps1'),
    (Join-Path $source 'ui.xaml'),
    (Join-Path $source 'app.ico'),
    (Join-Path $source 'themes\light.xaml'),
    (Join-Path $source 'themes\dark.xaml'))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "安装文件不完整：缺少 $required"
    }
}

if (Test-Path -LiteralPath $installDir) {
    Remove-Item -LiteralPath $installDir -Recurse -Force
}

[void][System.IO.Directory]::CreateDirectory($installDir)
Copy-Item -Path (Join-Path $source '*') -Destination $installDir -Recurse -Force

foreach ($extra in @('LICENSE', 'uninstall.ps1')) {
    $path = Join-Path $root $extra
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination (Join-Path $installDir $extra) -Force
    }
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $appScript + '"'
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = $iconPath + ',0'
$shortcut.Description = '待办 · 极简桌面待办清单'
$shortcut.WindowStyle = 1
$shortcut.Save()
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)

if ($DesktopShortcut) {
    $desktopShortcut = $shell.CreateShortcut((Join-Path $desktop '待办.lnk'))
    $desktopShortcut.TargetPath = $powershellPath
    $desktopShortcut.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $appScript + '"'
    $desktopShortcut.WorkingDirectory = $installDir
    $desktopShortcut.IconLocation = $iconPath + ',0'
    $desktopShortcut.Description = '待办 · 极简桌面待办清单'
    $desktopShortcut.WindowStyle = 1
    $desktopShortcut.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($desktopShortcut)
}

[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)

Write-Host ''
Write-Host '安装完成。'
Write-Host ('程序位置：' + $installDir)
Write-Host ('启动方式：开始菜单搜索“待办”' + $(if ($DesktopShortcut) { '，或双击桌面“待办”快捷方式' } else { '' }))
Write-Host '数据位置：默认 %APPDATA%\DaiBan，可在应用设置中更改。'
Write-Host ''
