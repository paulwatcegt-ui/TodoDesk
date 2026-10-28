#requires -Version 5.1
param([switch]$Screenshots)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\features-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
function Assert($value,$message) { if (-not $value) { throw $message }; Write-Host ('ok    ' + $message) }
Load-Settings
Load-Tasks
$window = Load-Interface
Initialize-ThemePalette $window 'dark'
Initialize-Interface $window
Wire-InterfaceEvents
Update-SettingsUi
$window.Show()
function Pump {
    $frame = [Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{ $frame.Continue = $false }.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $window.UpdateLayout()
}
function Click($control) { $control.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
try {
    Assert ($script:PriorityFeatureToggle.IsChecked -and $script:RemindersFeatureToggle.IsChecked) 'Both optional features default to enabled'
    foreach ($entry in @(@(0,'整理今天的工作计划'),@(1,'给项目补充使用说明'),@(2,'下班后去散步'))) {
        $script:ComposerPriority.ContextMenu.Items[$entry[0]].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
        $script:NewTaskInput.Text = $entry[1]
        Add-TaskFromComposer
    }
    Pump
    if ($Screenshots) {
        Hide-Toast
        $script:Toast.Visibility = 'Collapsed'
        $window.Width = 440; $window.Height = 480
        Pump
        $visual = $window.Content
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create((Join-Path $root 'docs\preview-features.png'))
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    foreach ($row in $script:ActiveList.Children) {
        $ctx = $row.Tag
        Assert ($ctx.PriorityButton.Visibility -eq 'Collapsed') 'Priority selector is hidden outside editing'
        Assert ($ctx.Title.Foreground.Color -eq $script:ThemeDictionary[(Get-TaskTitleBrush $ctx.Task)].Color) 'Title uses its priority color'
    }
    $ctx = $script:ActiveList.Children[0].Tag
    Start-EditTask $ctx
    Assert ($ctx.PriorityButton.Visibility -eq 'Visible') 'Priority selector appears inside the edit field'
    $ctx.Editor.Text = '点击空白处也会保存'
    $args = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
    $args.RoutedEvent = [Windows.UIElement]::PreviewMouseDownEvent
    $script:DateText.RaiseEvent($args)
    Assert ($null -eq $script:EditingContext -and $ctx.Task.Title -eq '点击空白处也会保存') 'Clicking a non-focusable area commits the edit'
    $ctx = $script:ActiveList.Children[0].Tag
    Start-EditTask $ctx
    $ctx.Editor.Text = '编辑文字并修改优先级'
    Click $ctx.PriorityButton
    Pump
    Assert ($null -ne $script:EditingContext -and $ctx.PriorityButton.ContextMenu.IsOpen) 'Moving focus into the priority menu does not prematurely finish editing'
    $ctx.PriorityButton.ContextMenu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
    $ctx.PriorityButton.ContextMenu.IsOpen = $false
    Assert ($script:ActiveTasks[0].Priority -eq 'high' -and $script:ActiveTasks[0].Title -eq '编辑文字并修改优先级') 'Edit and priority changes are both preserved'

    $future = (Get-Date).AddHours(2)
    Set-TaskReminder $script:ComposerReminderDraft $future | Out-Null
    Assert ($script:ComposerReminderButton.Content -match '提醒') 'Composer previews a reminder before task creation'
    $script:NewTaskInput.Text = '带提醒的新任务'
    Add-TaskFromComposer
    $task = $script:ActiveTasks[0]
    Assert ($task.RemindAt -eq $future -and $null -eq $script:ComposerReminderDraft.RemindAt) 'A new task inherits the draft reminder and clears the draft'

    $script:PriorityFeatureToggle.IsChecked = $false
    $script:RemindersFeatureToggle.IsChecked = $false
    Assert ($script:ComposerPriority.Visibility -eq 'Collapsed' -and $script:ComposerReminderButton.Visibility -eq 'Collapsed') 'Feature switches hide the corresponding composer controls'
    Assert (@(Get-DueReminders -Now (Get-Date).AddYears(1)).Count -eq 0 -and $task.RemindAt -eq $future) 'Disabling reminders suspends delivery without deleting their times'
    Assert ($script:ActiveList.Children[0].Tag.Title.Foreground.Color -eq $script:ThemeDictionary['InkBrush'].Color) 'Disabling priorities restores normal title colors'
    Load-Settings
    Assert (-not $script:Settings.PriorityEnabled -and -not $script:Settings.RemindersEnabled) 'Disabled preferences survive settings reload'
    Update-SettingsUi
    $script:PriorityFeatureToggle.IsChecked = $true
    $script:RemindersFeatureToggle.IsChecked = $true
    Assert (@(Get-DueReminders -Now (Get-Date).AddYears(1)).Count -eq 1 -and $task.RemindAt -eq $future) 'Re-enabling reminders restores the retained schedule'
    Load-Tasks
    Assert (@($script:ActiveTasks | Where-Object { $_.Title -eq '带提醒的新任务' -and $null -ne $_.RemindAt }).Count -eq 1) 'Draft reminder and task are persisted together'
    Write-Host 'All feature preference and inline editing checks passed.'
} finally {
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
}
