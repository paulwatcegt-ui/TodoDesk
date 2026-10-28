#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\reminders-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
function Assert($condition,$message) { if (-not $condition) { throw $message }; Write-Host ('ok    ' + $message) }
$app = [Windows.Application]::new()
$app.ShutdownMode = 'OnExplicitShutdown'
Load-Settings
Load-Tasks
$window = Load-Interface
Initialize-ThemePalette -Window $window -ThemeName 'dark'
Initialize-Interface -Window $window
Wire-InterfaceEvents
$window.Show()
try {
    $window.Width = 400; $window.Height = 400
    $window.UpdateLayout()
    foreach ($filter in @($script:FilterAll,$script:FilterActive,$script:FilterCompleted)) {
        $filter.ApplyTemplate() | Out-Null
        $chrome = $filter.Template.FindName('FilterChrome',$filter)
        Assert ($chrome.ActualHeight - $chrome.Padding.Top - $chrome.Padding.Bottom -ge $chrome.Child.DesiredSize.Height) 'Compact filter label has sufficient height including padding'
    }
    $script:NewTaskInput.Text = '提醒测试'
    Add-TaskFromComposer
    $task = $script:ActiveTasks[0]
    Assert ($null -eq $task.RemindAt) 'Existing tasks default to no reminder'
    $at = (Get-Date).AddMinutes(5)
    Assert (Set-TaskReminder $task $at) 'Reminder is persisted successfully'
    Load-Tasks
    $task = $script:ActiveTasks[0]
    Assert ([Math]::Abs(($task.RemindAt - $at).TotalSeconds) -lt 1) 'Reminder time survives reload'
    Assert (@(Get-DueReminders -Now ($at.AddSeconds(-1))).Count -eq 0) 'Reminder does not fire early'
    Assert (@(Get-DueReminders -Now ($at.AddSeconds(1))).Count -eq 1) 'Reminder becomes due at the selected time'
    Toggle-Task $task
    Assert (@(Get-DueReminders -Now ($at.AddMinutes(1))).Count -eq 0) 'Completed tasks do not alert'
    Toggle-Task $task
    $task.RemindAt = (Get-Date).AddMinutes(-1)
    $window.WindowState = 'Minimized'
    Check-Reminders
    $notices = @($app.Windows | Where-Object { $_.Title -eq 'TodoDesk · 待办提醒' })
    Assert ($notices.Count -eq 1 -and $notices[0].IsVisible) 'Due notification is visible while the app is minimized'
    Check-Reminders
    Assert (@($app.Windows | Where-Object { $_.Title -eq 'TodoDesk · 待办提醒' }).Count -eq 1) 'Repeated checks do not duplicate an alert'
    $notices[0].Close()
    Load-Tasks
    $task = $script:ActiveTasks[0]
    Assert ($task.ReminderNotified -and @(Get-DueReminders).Count -eq 0) 'Delivered state survives reload'
    Set-TaskReminder $task $null | Out-Null
    Load-Tasks
    $task = $script:ActiveTasks[0]
    Assert ($null -eq $task.RemindAt) 'Removing a reminder survives reload'
    $rejected = $false
    try { Set-TaskReminder $task ((Get-Date).AddMinutes(-1)) | Out-Null } catch { $rejected = $true }
    Assert $rejected 'A reminder cannot be set in the past'
    $window.WindowState = 'Normal'
    # Exercise the real modal dialog and its captured click handler.
    $script:DialogFailure = $null
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $timer.Add_Tick({
        $timer.Stop()
        $dialog = @($app.Windows | Where-Object { $_.Title -eq '时间提醒' })[0]
        try {
            $dialog.FindName('ReminderDate').SelectedDate = (Get-Date).AddDays(1).Date
            $dialog.FindName('ReminderHour').Text = '09'
            $dialog.FindName('ReminderMinute').Text = '30'
            $dialog.FindName('SaveReminder').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            Assert (-not $dialog.IsVisible -and $null -ne $task.RemindAt) 'Reminder dialog saves and closes'
        } catch { $script:DialogFailure = $_; if ($dialog) { $dialog.Close() } }
    })
    $timer.Start()
    Open-ReminderDialog $task
    if ($script:DialogFailure) { throw $script:DialogFailure }
    Write-Host 'All reminder and compact text checks passed.'
} finally {
    if ($timer) { $timer.Stop() }
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
    $app.Shutdown()
}
