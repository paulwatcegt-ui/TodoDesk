#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\lifecycle-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
function Assert($value,$message) { if (-not $value) { throw $message }; Write-Host ('ok    ' + $message) }
function Pump {
    $frame = [Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{ $frame.Continue = $false }.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $window.UpdateLayout()
}
function OutsideClick {
    $event = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left)
    $event.RoutedEvent = [Windows.UIElement]::PreviewMouseUpEvent
    $script:DateText.RaiseEvent($event)
    Pump
}
Load-Settings
Load-Tasks
$window = Load-Interface
Initialize-ThemePalette $window 'dark'
Initialize-Interface $window
Wire-InterfaceEvents
Update-SettingsUi
$window.Show()
try {
    $script:NewTaskInput.Text = '点击外部添加'
    $script:ComposerPriority.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $menu = $script:ComposerPriority.ContextMenu
    Pump
    Assert ($script:ActiveTasks.Count -eq 0 -and $script:NewTaskInput.Text -eq '点击外部添加') 'Opening composer options does not prematurely add the task'
    $menu.Items[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
    $menu.IsOpen = $false
    Pump
    Assert ($script:ActiveTasks.Count -eq 0) 'Selecting composer priority keeps the draft for confirmation'
    OutsideClick
    Assert ($script:ActiveTasks.Count -eq 1 -and $script:NewTaskInput.Text -eq '') 'Clicking outside the composer adds the draft once'
    OutsideClick
    Assert ($script:ActiveTasks.Count -eq 1) 'Repeated outside clicks do not add duplicates'
    $task = $script:ActiveTasks[0]
    Set-TaskPriority $task 'high'
    $reminder = (Get-Date).AddHours(2)
    Set-TaskReminder $task $reminder | Out-Null
    Remove-Task $task
    Assert ($script:ActiveTasks.Count -eq 0 -and $script:TrashedTasks.Count -eq 1) 'Delete moves a task into the recycle bin'
    Assert (@(Get-DueReminders -Now (Get-Date).AddYears(1)).Count -eq 0) 'Recycled tasks do not trigger reminders'
    Load-Tasks
    Assert ($script:TrashedTasks.Count -eq 1 -and $script:TrashedTasks[0].Priority -eq 'high') 'Recycle bin survives reload with priority metadata'
    Restore-StoredTask $script:TrashedTasks[0] 'trash'
    Assert ($script:ActiveTasks.Count -eq 1 -and $script:TrashedTasks.Count -eq 0 -and [Math]::Abs(($script:ActiveTasks[0].RemindAt-$reminder).TotalSeconds) -lt 1) 'Restore recovers state, priority and reminder time'
    $task = $script:ActiveTasks[0]
    Remove-Task $task
    Undo-LastTaskAction
    Assert ($script:ActiveTasks.Count -eq 1 -and $script:TrashedTasks.Count -eq 0) 'Delete undo removes the matching recycled copy'
    Toggle-Task $task
    Archive-Completed
    Assert ($script:CompletedTasks.Count -eq 0 -and $script:ArchivedTasks.Count -eq 1 -and $script:TaskProgress.Value -eq 0) 'Archive removes completed tasks from current progress'
    Undo-LastTaskAction
    Assert ($script:CompletedTasks.Count -eq 1 -and $script:ArchivedTasks.Count -eq 0) 'Archive can be undone'
    Archive-Completed
    Load-Tasks
    Assert ($script:ArchivedTasks.Count -eq 1 -and $script:ArchivedTasks[0].IsCompleted) 'Archived records survive reload'
    Restore-StoredTask $script:ArchivedTasks[0] 'archive'
    Clear-Completed
    Assert ($script:TrashedTasks.Count -eq 1 -and $script:CompletedTasks.Count -eq 0) 'Clear completed moves records into the recycle bin'
    Undo-LastTaskAction
    Assert ($script:TrashedTasks.Count -eq 0 -and $script:CompletedTasks.Count -eq 1) 'Clear undo restores without duplicate recycled records'
    Clear-Completed
    $script:StoredDialogFailure = $null
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $timer.Stop()
        try {
            $dialog = [Windows.Application]::Current
            # The modal window is owned by the main window, including without Application.Current.
            $dialog = @($script:Window.OwnedWindows | Where-Object { $_.Title -eq '回收站' })[0]
            Assert ($dialog.Tag.List.Children.Count -eq 1) 'Recycle bin dialog displays its stored task'
            $restore = $dialog.Tag.List.Children[0].Child.Children[0]
            $restore.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            Assert ($dialog.Tag.List.Children.Count -eq 0 -and $script:CompletedTasks.Count -eq 1) 'Restore button updates the bin and main list together'
            $dialog.Close()
        } catch { $script:StoredDialogFailure = $_; if ($dialog) { $dialog.Close() } }
    })
    $timer.Start()
    Open-StoredTasksDialog 'trash'
    if ($script:StoredDialogFailure) { throw $script:StoredDialogFailure }
    Assert ($script:SettingsVersionText.Text -like 'TodoDesk *') 'Settings use the TodoDesk product name'
    Assert ((Read-AppLicense) -match 'MIT License' -and (Read-AppLicense) -match 'DaiBan contributors') 'Open-source information retains the complete original license and attribution'
    $licenseTimer = [Windows.Threading.DispatcherTimer]::new()
    $licenseTimer.Interval = [TimeSpan]::FromMilliseconds(150)
    $licenseTimer.Add_Tick({
        $licenseTimer.Stop()
        $licenseDialog = @($script:Window.OwnedWindows | Where-Object { $_.Title -eq 'TodoDesk · 开源许可' })[0]
        try { Assert ($licenseDialog.FindName('LicenseText').Text -match 'MIT License') 'License dialog displays the full text' }
        catch { $script:StoredDialogFailure = $_ }
        finally { $licenseDialog.Close() }
    })
    $licenseTimer.Start()
    Show-LicenseInformation
    if ($script:StoredDialogFailure) { throw $script:StoredDialogFailure }
    Write-Host 'All lifecycle and auto-add checks passed.'
} finally {
    if ($timer) { $timer.Stop() }
    if ($licenseTimer) { $licenseTimer.Stop() }
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
}
