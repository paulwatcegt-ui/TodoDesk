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
    'tests\statistics-display.ps1',
    'tests\polish.ps1',
    'tests\backup.ps1',
    'tests\tracking.ps1',
    '.github\workflows\release.yml',
    'installer\setup-wix.ps1',
    'tests\installer.ps1',
    'tests\lifecycle.ps1',
    'tests\features.ps1',
    'tests\priorities.ps1',
    'tests\reminder-entry.ps1',
    'tests\reminders.ps1',
    'tests\window.ps1',
    'preview.ps1',
    'tests\smoke.ps1',
    'app\DaiBan.ps1',
    'app\Tracking.ps1',
    'app\ui.xaml',
    'app\app.ico',
    'app\themes\light.xaml',
    'app\themes\dark.xaml',
    'host\DaiBanHost.cs',
    'host\AssemblyInfo.cs',
    'host\app.manifest',
    'host\build.ps1',
    'installer\DaiBan.wxs',
    'installer\build-msi.ps1',
    'README.md',
    'RELEASE_NOTES.md',
    'LICENSE',
    'CHANGELOG.md'
)

foreach ($relative in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relative)) "required file: $relative"
}

$powershellFiles = @(
    'tests\statistics-display.ps1',
    'tests\polish.ps1',
    'tests\backup.ps1',
    'tests\tracking.ps1',
    'app\Tracking.ps1',
    'installer\setup-wix.ps1',
    'tests\installer.ps1',
    'tests\lifecycle.ps1',
    'tests\features.ps1',
    'tests\priorities.ps1',
    'tests\reminder-entry.ps1',
    'tests\reminders.ps1',
    'tests\window.ps1',
    'preview.ps1',
    'tests\smoke.ps1',
    'app\DaiBan.ps1',
    'host\build.ps1',
    'installer\build-msi.ps1',
    'tests\validate.ps1'
)

$csharpFiles = @(
    'host\DaiBanHost.cs',
    'host\AssemblyInfo.cs'
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
        'ImportBackupButton', 'SettingsScroll',
        'ComposerTimer', 'FilterStats', 'TimingFeatureToggle', 'StatisticsFeatureToggle', 'ResetOrderButton',
        'FilterAll', 'FilterActive', 'FilterCompleted', 'TaskProgress', 'ProgressText',
        'EmptyTitle', 'EmptyDescription', 'StorageStatusText', 'StorageStatusDot', 'ListCountText',
        'MaximizeButton', 'MaximizeGlyph', 'CompletedToggleButton',
        'ArchiveCompletedButton', 'TrashSettingsButton', 'ArchiveSettingsButton', 'LicenseInfoButton',
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

function Get-Luminance($color) {
    $values = foreach ($channel in @($color.R, $color.G, $color.B)) {
        $value = $channel / 255.0
        if ($value -le 0.04045) { $value / 12.92 } else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
    }
    return $values[0] * 0.2126 + $values[1] * 0.7152 + $values[2] * 0.0722
}

function Get-Contrast($foreground, $background) {
    $first = Get-Luminance $foreground
    $second = Get-Luminance $background
    return ([Math]::Max($first,$second) + 0.05) / ([Math]::Min($first,$second) + 0.05)
}

foreach ($themeName in @('light', 'dark')) {
    $themePath = Join-Path $root ('app\themes\' + $themeName + '.xaml')
    try {
        $dictionary = Load-Xaml $themePath
        Assert-True ($dictionary -is [System.Windows.ResourceDictionary]) "theme loads: $themeName"
        $keys = @($dictionary.Keys)
        $missing = @($dynamicKeys | Where-Object { $_ -notin $keys })
        Assert-True ($missing.Count -eq 0) "theme keys complete: $themeName"
        foreach ($pair in @(@('PriorityHighBrush','PriorityHighSurfaceBrush'), @('PriorityMediumBrush','PriorityMediumSurfaceBrush'), @('PriorityLowBrush','PriorityLowSurfaceBrush'), @('PriorityHighBrush','CardBrush'), @('PriorityMediumBrush','CardBrush'), @('PriorityLowBrush','CardBrush'), @('InkBrush','CardBrush'), @('SecondaryBrush','CardBrush'), @('TertiaryBrush','CardBrush'),
            @('CompletedTextBrush','CardBrush'), @('AccentBrush','AccentSoftBrush'), @('OnAccentBrush','AccentBrush'))) {
            $ratio = Get-Contrast $dictionary[$pair[0]].Color $dictionary[$pair[1]].Color
            Assert-True ($ratio -ge 4.5) ('text contrast {0}: {1}/{2} = {3:N2}' -f $themeName,$pair[0],$pair[1],$ratio)
        }
        foreach ($stop in $dictionary['WindowBackgroundBrush'].GradientStops) {
            $ratio = Get-Contrast $dictionary['SecondaryBrush'].Color $stop.Color
            Assert-True ($ratio -ge 4.5) ('footer and date contrast {0}: {1:N2}' -f $themeName,$ratio)
        }
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
Assert-True ($appSource -match "\`$script:AppVersion\s*=\s*'1\.3\.1'") 'app version is 1.3.1'
Assert-True ($appSource -notmatch 'D:\\DeepSeekWork') 'no local workspace path in app'

$userFacingSources = @(
    (Join-Path $root 'app\DaiBan.ps1'),
    (Join-Path $root 'host\DaiBanHost.cs'),
    (Join-Path $root 'host\build.ps1'),
    (Join-Path $root 'installer\DaiBan.wxs'),
    (Join-Path $root 'installer\build-msi.ps1')
)
foreach ($path in $userFacingSources) {
    if (Test-Path -LiteralPath $path) {
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        Assert-True ($text -notmatch 'D:\\DeepSeekWork') "no local workspace path: $([IO.Path]::GetFileName($path))"
    }
}

foreach ($relative in $csharpFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True $hasBom "UTF-8 BOM: $relative"
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host ('Validation failed with ' + $failures.Count + ' problem(s).') -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'All validations passed.' -ForegroundColor Green
exit 0
