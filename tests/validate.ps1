#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
    Write-Host ('FAIL  ' + $Message) -ForegroundColor Red
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        Add-Failure $Message
    }
    else {
        Write-Host ('ok    ' + $Message) -ForegroundColor DarkGray
    }
}

function Load-Xaml {
    param([string]$Path)

    $reader = [System.Xml.XmlReader]::Create($Path)
    try {
        return [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Error 'Please run this validator with Windows PowerShell -STA.'
    exit 2
}

$required = @(
    'app\DaiBan.ps1',
    'app\ui.xaml',
    'app\app.ico',
    'app\themes\light.xaml',
    'app\themes\dark.xaml',
    'install.ps1',
    'uninstall.ps1',
    'scripts\sign.ps1',
    'scripts\package.ps1',
    'README.md',
    'RELEASE_NOTES.md',
    'LICENSE',
    'CHANGELOG.md'
)

foreach ($relative in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relative)) "required file: $relative"
}

$powershellFiles = @(
    'app\DaiBan.ps1',
    'install.ps1',
    'uninstall.ps1',
    'scripts\sign.ps1',
    'scripts\package.ps1',
    'tests\validate.ps1'
)

foreach ($relative in $powershellFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True $hasBom "UTF-8 BOM: $relative"

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "PowerShell syntax: $relative"
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-Host ('      ' + $error.Message) -ForegroundColor Red
        }
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ui = $null
try {
    $ui = Load-Xaml (Join-Path $root 'app\ui.xaml')
    Assert-True ($ui -is [System.Windows.Window]) 'ui.xaml loads as a Window'
}
catch {
    Add-Failure ('ui.xaml parse failed: ' + $_.Exception.Message)
}

if ($null -ne $ui) {
    $requiredNames = @(
        'TitleBar', 'DateText', 'StatusPanel', 'StatusDot', 'StatusText',
        'Composer', 'NewTaskInput', 'ComposerPlaceholder', 'AddButton',
        'TaskScroll', 'ActiveList', 'CompletedSection', 'CompletedHeaderText',
        'CompletedList', 'ClearCompletedButton', 'EmptyState',
        'SettingsButton', 'MinimizeButton', 'CloseButton',
        'SettingsOverlay', 'SettingsScrim', 'SettingsCardRoot', 'SettingsCloseButton',
        'ThemeSystemButton', 'ThemeLightButton', 'ThemeDarkButton',
        'DataPathText', 'ChangeDataFolderButton', 'ResetDataFolderButton',
        'SettingsVersionText', 'Toast', 'ToastText', 'ToastUndoButton'
    )
    foreach ($name in $requiredNames) {
        Assert-True ($null -ne $ui.FindName($name)) "named UI element: $name"
    }
}

$uiText = [System.IO.File]::ReadAllText(
    (Join-Path $root 'app\ui.xaml'), [System.Text.Encoding]::UTF8)
$dynamicKeys = @(
    [regex]::Matches($uiText, '\{DynamicResource ([A-Za-z0-9_]+)\}') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
)

foreach ($themeName in @('light', 'dark')) {
    $themePath = Join-Path $root ('app\themes\' + $themeName + '.xaml')
    try {
        $dictionary = Load-Xaml $themePath
        Assert-True ($dictionary -is [System.Windows.ResourceDictionary]) "theme loads: $themeName"
        $keys = @($dictionary.Keys)
        $missing = @($dynamicKeys | Where-Object { $_ -notin $keys })
        Assert-True ($missing.Count -eq 0) "theme keys complete: $themeName"
        if ($missing.Count -gt 0) {
            Write-Host ('      missing: ' + ($missing -join ', ')) -ForegroundColor Red
        }
    }
    catch {
        Add-Failure ('theme parse failed: ' + $themeName + ': ' + $_.Exception.Message)
    }
}

$appSource = [System.IO.File]::ReadAllText(
    (Join-Path $root 'app\DaiBan.ps1'), [System.Text.Encoding]::UTF8)
Assert-True ($appSource -match "\`$script:AppVersion\s*=\s*'[^']+'") 'app version is defined'
Assert-True ($appSource -notmatch 'D:\\DeepSeekWork') 'no local workspace path in app'

$userFacingSources = @(
    (Join-Path $root 'app\DaiBan.ps1'),
    (Join-Path $root 'install.ps1'),
    (Join-Path $root 'uninstall.ps1')
)
foreach ($path in $userFacingSources) {
    if (Test-Path -LiteralPath $path) {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        Assert-True ($text -notmatch 'D:\\DeepSeekWork') "no local workspace path: $([IO.Path]::GetFileName($path))"
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('Validation failed with ' + $failures.Count + ' problem(s).') -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'All validations passed.' -ForegroundColor Green
exit 0
