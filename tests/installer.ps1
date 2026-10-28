#requires -Version 5.1
[CmdletBinding()]
param([string]$MsiPath, [switch]$AllowApplicationControlBlock)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($MsiPath)) { $MsiPath = Join-Path $root 'dist\installer\TodoDesk-1.3.0-x64.msi' }
$MsiPath = [IO.Path]::GetFullPath($MsiPath)
$testRoot = Join-Path $root ('.testdata\installer-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $testRoot '自定义 安装路径'
[void][IO.Directory]::CreateDirectory($testRoot)
function Assert($value,$message) { if (-not $value) { throw $message }; Write-Host ('ok    ' + $message) }
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($MsiPath,0)
function Query-Value([string]$Query) {
    $view = $database.OpenView($Query); [void]$view.Execute()
    try { $record = $view.Fetch(); if ($record) { return ([string]$record.StringData(1)).Trim() } }
    finally { [void]$view.Close() }
}
$productCode = Query-Value 'SELECT `Value` FROM `Property` WHERE `Property` = ''ProductCode'''
Assert ((Query-Value 'SELECT `Value` FROM `Property` WHERE `Property` = ''ProductName''') -eq 'TodoDesk') 'MSI uses the TodoDesk product name'
Assert ((Query-Value 'SELECT `Value` FROM `Property` WHERE `Property` = ''WIXUI_INSTALLDIR''') -eq 'INSTALLFOLDER') 'Install wizard exposes the installation directory'
Assert ((Query-Value 'SELECT `Dialog` FROM `Dialog` WHERE `Dialog` = ''InstallDirDlg''') -eq 'InstallDirDlg') 'Installer contains the folder selection dialog'
Assert ((Query-Value 'SELECT `Dialog` FROM `Dialog` WHERE `Dialog` = ''BrowseDlg''') -eq 'BrowseDlg') 'Installer contains the folder browser'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $productCode
$related = @($installer.RelatedProducts('{B4C0A0A6-5A65-4D56-9C9B-1E3C2F5D7A11}') | ForEach-Object { [string]$_ })
Assert ($related.Count -eq 0) 'No existing TodoDesk installation will be changed by this test'
$shortcuts = @((Join-Path ([Environment]::GetFolderPath('Programs')) 'TodoDesk.lnk'), (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'TodoDesk.lnk'))
foreach ($shortcut in $shortcuts) { Assert (-not (Test-Path -LiteralPath $shortcut)) 'No existing TodoDesk shortcut will be replaced' }
function Run-Msi([string[]]$Arguments) {
    $process = Start-Process -FilePath msiexec.exe -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -notin @(0,3010)) { throw ('Windows Installer failed with code ' + $process.ExitCode + '. Logs: ' + $testRoot) }
}
$installed = $false
$appProcess = $null
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class InstallerShortcutReader {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int size, IntPtr data, uint flags);
        void GetIDList(out IntPtr list);
    }
    [DllImport("shell32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    private static extern bool SHGetPathFromIDListW(IntPtr list, [Out] StringBuilder path);
    public static string Target(string shortcut) {
        object instance = new ShellLink();
        IntPtr list = IntPtr.Zero;
        try {
            ((IPersistFile)instance).Load(shortcut, 0);
            ((IShellLinkW)instance).GetIDList(out list);
            StringBuilder path = new StringBuilder(32768);
            if (list != IntPtr.Zero && SHGetPathFromIDListW(list,path)) return path.ToString();
            ((IShellLinkW)instance).GetPath(path,path.Capacity,IntPtr.Zero,0);
            return path.ToString();
        } finally {
            if (list != IntPtr.Zero) Marshal.FreeCoTaskMem(list);
            Marshal.ReleaseComObject(instance);
        }
    }
}
'@
try {
    Run-Msi @('/i', ('"' + $MsiPath + '"'), '/qn', '/norestart', ('INSTALLFOLDER="' + $installRoot + '"'), '/L*V', ('"' + (Join-Path $testRoot 'install.log') + '"'))
    $installed = $true
    $exe = Join-Path $installRoot 'TodoDesk.exe'
    Assert (Test-Path -LiteralPath $exe) 'Application installs into a custom path containing spaces and Chinese characters'
    Assert ((Get-FileHash -LiteralPath $exe).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'dist\native\DaiBan.exe')).Hash) 'Installed executable matches the verified build'
    Assert (([IO.File]::ReadAllText((Join-Path $installRoot 'LICENSE'))) -eq ([IO.File]::ReadAllText((Join-Path $root 'LICENSE')))) 'Full MIT license is installed alongside the app'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcut in $shortcuts) {
        Assert (Test-Path -LiteralPath $shortcut) 'Installer creates the current-user shortcut'
        $shortcutTarget = [InstallerShortcutReader]::Target($shortcut)
        # Read the Unicode shell item ID list; WScript.Shell can expose a lossy
        # ANSI path on an English system even when the actual shell link is valid.
        Assert (Test-Path -LiteralPath $shortcutTarget) ('Shortcut target exists: ' + $shortcutTarget + '; expected ' + $exe)
        $targetItem = Get-Item -LiteralPath $shortcutTarget
        Assert ($targetItem.Name -eq 'TodoDesk.exe' -and (Get-FileHash -LiteralPath $shortcutTarget).Hash -eq (Get-FileHash -LiteralPath $exe).Hash) ('Shortcut resolves to the verified installed executable: ' + $shortcutTarget)
    }
    Assert ($installer.ProductInfo($productCode,'ProductName') -eq 'TodoDesk' -and $installer.ProductInfo($productCode,'Publisher') -eq '宋培恩') 'Windows Installer registers the correct product and maintainer'
    $env:DAIBAN_DATA_DIR = Join-Path $testRoot 'app-data'
    $env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'app-config'
    $env:DAIBAN_PREVIEW = '1'
    [void][IO.Directory]::CreateDirectory($env:DAIBAN_DATA_DIR)
    $dataFile = Join-Path $env:DAIBAN_DATA_DIR 'todos.json'
    [IO.File]::WriteAllText($dataFile,'{"version":1,"items":[{"id":"installer-check","title":"安装验证任务","completed":false}],"archive":[],"trash":[]}',[Text.UTF8Encoding]::new($false))
    $before = (Get-FileHash -LiteralPath $dataFile).Hash
    try { $appProcess = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru }
    catch {
        $nativeError = $_.Exception
        while ($nativeError.InnerException) { $nativeError = $nativeError.InnerException }
        if ($AllowApplicationControlBlock -and ($nativeError.NativeErrorCode -in @(577,1260,4551) -or $_.Exception.Message -match 'Application Control policy')) {
            Write-Warning 'This host blocks unsigned apps by enterprise policy; runtime launch is not verified here. CI must verify launch without this override.'
        } else { throw }
    }
    if ($appProcess) {
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        $appProcess.Refresh()
        if ($appProcess.HasExited -or $appProcess.MainWindowTitle -eq 'TodoDesk · 本地预览') { break }
    }
    Assert (-not $appProcess.HasExited -and $appProcess.MainWindowTitle -eq 'TodoDesk · 本地预览' -and $appProcess.Responding) 'Installed app launches successfully from the custom path'
    Assert ($appProcess.CloseMainWindow()) 'Installed app accepts a normal close request'
    Assert ($appProcess.WaitForExit(5000)) 'Installed app exits cleanly'
    }
    Assert ((Get-FileHash -LiteralPath $dataFile).Hash -eq $before) 'Launching and closing preserve existing task data'
    $sentinel = Join-Path $installRoot 'user-file.txt'
    [IO.File]::WriteAllText($sentinel,'User-owned files must be preserved.')
} finally {
    if ($appProcess -and -not $appProcess.HasExited) { $appProcess.CloseMainWindow() | Out-Null; if (-not $appProcess.WaitForExit(3000)) { Stop-Process -Id $appProcess.Id } }
    if ($installed) {
        Run-Msi @('/x', $productCode, '/qn', '/norestart', '/L*V', ('"' + (Join-Path $testRoot 'uninstall.log') + '"'))
        Assert (-not (Test-Path -LiteralPath (Join-Path $installRoot 'TodoDesk.exe'))) 'Uninstall removes the application executable'
        foreach ($shortcut in $shortcuts) { Assert (-not (Test-Path -LiteralPath $shortcut)) 'Uninstall removes its shortcut' }
        Assert ($installer.ProductState($productCode) -eq -1) 'Uninstall removes its Windows app registration'
    }
}
Assert ((Get-FileHash -LiteralPath $dataFile).Hash -eq $before) 'Uninstall preserves the todo data'
Assert (Test-Path -LiteralPath $sentinel) 'Uninstall preserves unrelated files in the chosen directory'
Write-Host 'Installation, custom directory, data retention and uninstall checks passed. Launch status is reported above.'
