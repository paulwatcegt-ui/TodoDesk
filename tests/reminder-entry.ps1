#requires -Version 5.1
# Run the real startup path as a child script, rather than importing its functions
# into the test scope. This reproduces script-local callback resolution failures.
param([ValidateSet('light','dark')][string]$Theme = 'dark')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\entry-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$env:DAIBAN_ENTRY_TEST_DIR = $testRoot
$env:DAIBAN_ENTRY_APP_ROOT = Join-Path $root 'app'
$env:DAIBAN_ENTRY_THEME = $Theme
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
$source = $source.Replace("`$script:AppVersion = '1.3.0'", "`$script:AppRoot = `$env:DAIBAN_ENTRY_APP_ROOT`r`n`$script:AppVersion = '1.3.0'")
$automation = @'
function Assert-Entry($value, $message) {
    if (-not $value) { throw $message }
    Write-Host ('ok    ' + $message)
}
function Test-EntryDialog([string]$mode) {
    $script:EntryDialogError = $null
    $script:EntryDialogTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:EntryDialogTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $script:EntryMode = $mode
    $script:EntryDialogTimer.Add_Tick({
        $script:EntryDialogTimer.Stop()
        $dialog = @([Windows.Application]::Current.Windows | Where-Object { $_.Title -eq '时间提醒' })[0]
        try {
            Assert-Entry ($null -ne $dialog) 'Clock button opens the reminder dialog from the real app entry'
            if ($script:EntryMode -in @('save','draft')) {
                $dialog.FindName('Preset10').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $minutes = ((Get-ReminderSelection $dialog) - (Get-Date)).TotalMinutes
                Assert-Entry ($minutes -gt 8 -and $minutes -le 10) '10 minute preset updates the date and time together'
                $dialog.FindName('ReminderHour').Text = '25'
                Assert-Entry (-not $dialog.FindName('SaveReminder').IsEnabled) 'Invalid hours disable saving without showing technical errors'
                $dialog.FindName('PresetTomorrow').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                Assert-Entry ((Get-ReminderSelection $dialog) -eq (Get-Date).Date.AddDays(1).AddHours(9)) 'Tomorrow preset selects tomorrow at 09:00'
                $dialog.FindName('MinuteUp').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                Assert-Entry ($dialog.FindName('ReminderMinute').Text -eq '01') 'Minute step buttons update the selected time'
                $dialog.FindName('ReminderDateButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                Assert-Entry ($dialog.FindName('ReminderCalendarPopup').IsOpen) 'Date button opens the calendar'
                $dialog.FindName('ReminderCalendarPopup').IsOpen = $false
                Assert-Entry ($dialog.FindName('ReminderSummary').Text -match '明天.*09:01') 'Preview describes the selected reminder in plain language'
                $visual = $dialog.Content
                $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($visual)
                $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream = [IO.File]::Create((Join-Path $env:DAIBAN_ENTRY_TEST_DIR 'reminder-dialog.png'))
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
                $dialog.FindName('SaveReminder').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                Assert-Entry (-not $dialog.IsVisible) 'Saving resolves app-local functions and closes the dialog'
            } elseif ($script:EntryMode -eq 'cancel') {
                $dialog.FindName('Preset60').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                $dialog.Close()
            } else {
                $dialog.FindName('RemoveReminder').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
                Assert-Entry (-not $dialog.IsVisible) 'Removing resolves app-local functions and closes the dialog'
            }
        } catch { $script:EntryDialogError = $_; if ($dialog) { $dialog.Close() } }
    })
    $script:EntryDialogTimer.Start()
    $clock = if ($mode -eq 'draft') { $script:ComposerReminderButton } else { $script:ActiveList.Children[0].Tag.Actions.Children[0] }
    $clock.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    if ($script:EntryDialogError) { throw $script:EntryDialogError }
}
$script:EntryTimer = [Windows.Threading.DispatcherTimer]::new()
$script:EntryTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:EntryTimer.Add_Tick({
    $script:EntryTimer.Stop()
    try {
        Set-ThemePreference -Preference $env:DAIBAN_ENTRY_THEME
        $script:NewTaskInput.Text = '休息一下，喝杯水'
        Add-TaskFromComposer
        Start-EditTask $script:ActiveList.Children[0].Tag
        $priority = $script:ActiveList.Children[0].Tag.PriorityButton
        $priority.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        Assert-Entry ($priority.ContextMenu.IsOpen -and $priority.ContextMenu.Items[0].Tag.Color.Color -eq $script:ThemeDictionary['PriorityHighBrush'].Color) 'Priority menu opens with readable themed colors'
        $priority.ContextMenu.UpdateLayout()
        $dot = $priority.ContextMenu.Items[0].Template.FindName('PriorityDot', $priority.ContextMenu.Items[0])
        Assert-Entry ($null -ne $dot.Fill -and $dot.Fill.Color -eq $script:ThemeDictionary['PriorityHighBrush'].Color) 'Priority menu renders its colored dot'
        $menuVisual = $priority.ContextMenu
        $menuBitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$menuVisual.ActualWidth,[int]$menuVisual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $menuBitmap.Render($menuVisual)
        $menuEncoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $menuEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($menuBitmap))
        $menuStream = [IO.File]::Create((Join-Path $env:DAIBAN_ENTRY_TEST_DIR 'priority-menu.png'))
        try { $menuEncoder.Save($menuStream) } finally { $menuStream.Dispose() }
        $priority.ContextMenu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
        $priority.ContextMenu.IsOpen = $false
        Assert-Entry ($script:ActiveTasks[0].Priority -eq 'high') 'Priority menu saves through the production entry point'
        Test-EntryDialog 'draft'
        Assert-Entry ($null -ne $script:ComposerReminderDraft.RemindAt) 'Composer reminder dialog sets a draft before creation'
        $script:NewTaskInput.Text = '新增前设定提醒'
        Add-TaskFromComposer
        Assert-Entry ($null -ne $script:ActiveTasks[0].RemindAt -and $null -eq $script:ComposerReminderDraft.RemindAt) 'Production add action persists the draft reminder and clears it'
        Test-EntryDialog 'save'
        $saved = $script:ActiveTasks[0].RemindAt
        Assert-Entry ($null -ne $saved) 'Reminder exists after the production save handler'
        Test-EntryDialog 'cancel'
        Assert-Entry ($script:ActiveTasks[0].RemindAt -eq $saved) 'Cancel leaves the previous reminder unchanged'
        Test-EntryDialog 'remove'
        Assert-Entry ($null -eq $script:ActiveTasks[0].RemindAt) 'Remove clears the reminder'
        [IO.File]::WriteAllText((Join-Path $env:DAIBAN_ENTRY_TEST_DIR 'result.txt'), 'passed')
    } catch { [IO.File]::WriteAllText((Join-Path $env:DAIBAN_ENTRY_TEST_DIR 'result.txt'), $_.ToString()) }
    finally { $script:Window.Close() }
})
$script:EntryTimer.Start()
[void]$script:Application.Run($script:Window)
'@
$source = $source.Replace('[void]$script:Application.Run($script:Window)', $automation)
$runner = Join-Path $testRoot 'app-entry.ps1'
[IO.File]::WriteAllText($runner,$source,[Text.UTF8Encoding]::new($true))
& $runner
$result = [IO.File]::ReadAllText((Join-Path $testRoot 'result.txt'))
if ($result -ne 'passed') { throw $result }
Write-Host 'Real application entry reminder checks passed.'
Write-Host ('Preview: ' + (Join-Path $testRoot 'reminder-dialog.png'))
