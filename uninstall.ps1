#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs\DaiBan'
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) '待办.lnk'
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) '待办.lnk'
$configDirectory = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'DaiBan'
$installedScript = Join-Path $installDir 'DaiBan.ps1'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

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
    Write-Host '请先关闭正在运行的“待办”，再重新运行卸载。'
    exit 1
}

$shell = New-Object -ComObject WScript.Shell

foreach ($shortcutPath in @($startMenuShortcut, $desktopShortcut)) {
    if (-not (Test-Path -LiteralPath $shortcutPath)) { continue }

    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $arguments = [string]$shortcut.Arguments
        if ([string]::Equals($shortcut.TargetPath, $powershellPath, [StringComparison]::OrdinalIgnoreCase) -and
            -not [string]::IsNullOrWhiteSpace($arguments) -and
            $arguments.IndexOf($installedScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Remove-Item -LiteralPath $shortcutPath -Force
        }
    }
    catch {
    }
}

[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)

if (Test-Path -LiteralPath $installDir) {
    $resolvedInstall = (Resolve-Path -LiteralPath $installDir).Path
    $programsRoot = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs')
    if ($resolvedInstall.StartsWith($programsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedInstall -Recurse -Force
    }
}

if ($RemoveData -and (Test-Path -LiteralPath $configDirectory)) {
    Remove-Item -LiteralPath $configDirectory -Recurse -Force
}

Write-Host ''
Write-Host '待办已卸载。'
if (-not $RemoveData) {
    Write-Host ('设置和默认位置的数据仍保留在：' + $configDirectory)
    Write-Host '如果使用了自定义保存位置，那里的数据不会被自动删除。'
    Write-Host '如需一并清除默认数据，可重新运行：.\uninstall.ps1 -RemoveData'
}
Write-Host ''
