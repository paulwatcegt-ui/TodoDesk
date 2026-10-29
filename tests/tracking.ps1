#requires -Version 5.1
param([switch]$Screenshots)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\tracking-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
function Assert($value,$message) { if (-not $value) { throw $message }; Write-Host ('ok    '+$message) }
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false}.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame); $window.UpdateLayout()
}
function Add-Time($task,[datetime]$start,[datetime]$end) {
    [void]$script:TimeEntries.Add([pscustomobject]@{Id=[guid]::NewGuid().ToString('N');TaskId=$task.Id;Title=$task.Title;Start=(Get-UnixMilliseconds $start);End=(Get-UnixMilliseconds $end)})
}
Load-Settings; Load-Tasks
$window=Load-Interface
Initialize-ThemePalette $window 'dark'; Initialize-Interface $window; Wire-InterfaceEvents; Update-SettingsUi
$window.Show()
try {
    Assert (-not $script:Settings.TimingEnabled -and -not $script:Settings.StatisticsEnabled) 'Timing and statistics default off'
    Assert ($script:ComposerTimer.Visibility -eq 'Collapsed' -and $script:FilterStats.Visibility -eq 'Collapsed') 'Disabled features add no visible controls'
    foreach ($priority in @('high','low','medium')) {
        $script:ComposerPriorityValue=$priority
        $script:NewTaskInput.Text=switch($priority){'high'{'完成项目收尾'};'medium'{'阅读与练习'};'low'{'整理学习资料'}}
        Add-TaskFromComposer
    }
    Assert ((@(Get-OrderedTasks).Priority -join ',') -eq 'high,medium,low') 'Active tasks automatically sort by priority'
    $high=@($script:ActiveTasks | Where-Object Priority -eq 'high')[0]
    $low=@($script:ActiveTasks | Where-Object Priority -eq 'low')[0]
    Move-TaskPosition $low.Id $high.Id
    Assert (@(Get-OrderedTasks)[0].Id -eq $low.Id) 'Mouse reorder logic overrides automatic priority order'
    Assert ($script:ActiveList.Children[0].AllowDrop) 'Task rows accept drag and drop'
    Save-Tasks; Load-Tasks; Refresh-TaskList
    Assert (@(Get-OrderedTasks)[0].Id -eq $low.Id) 'Manual order survives reload'
    $low=@($script:ActiveTasks | Where-Object Id -eq $low.Id)[0]
    $high=@($script:ActiveTasks | Where-Object Id -eq $high.Id)[0]
    Set-TaskPriority $low 'medium'
    Assert (@(Get-OrderedTasks)[0].Id -eq $low.Id) 'Priority changes preserve a manual order'
    Reset-TaskOrder
    Assert (@(Get-OrderedTasks)[0].Id -eq $high.Id) 'Reset restores automatic order'
    Pump
    $target=$script:ActiveList.Children[0]
    $data=[Windows.DataObject]::new('TodoDesk.TaskId',[string]$low.Id)
    $constructor=[Windows.DragEventArgs].GetConstructors([Reflection.BindingFlags]'Instance,NonPublic')[0]
    $drop=$constructor.Invoke(@($data,[Windows.DragDropKeyStates]::LeftMouseButton,[Windows.DragDropEffects]::Move,$target,[Windows.Point]::new(5,5)))
    $drop.RoutedEvent=[Windows.DragDrop]::DropEvent; $target.RaiseEvent($drop)
    Assert ($drop.Handled -and @(Get-OrderedTasks)[0].Id -eq $low.Id) 'Routed drop event moves the selected task'
    Reset-TaskOrder
    $script:TimingFeatureToggle.IsChecked=$true; $script:StatisticsFeatureToggle.IsChecked=$true
    Assert ($script:ComposerTimer.Visibility -eq 'Visible' -and $script:FilterStats.Visibility -eq 'Visible') 'Settings independently expose timer and statistics'
    $window.Width=400; $window.Height=400
    $script:ComposerReminderDraft.RemindAt=(Get-Date).AddHours(1); Update-ComposerFeatures; Pump
    Assert ($script:NewTaskInput.ActualWidth -gt 50 -and $script:ComposerTimer.ActualWidth -eq 56) 'Compact composer keeps usable input space with every feature enabled'
    $script:ComposerReminderDraft.RemindAt=$null; Update-ComposerFeatures
    if ($Screenshots) {
        Hide-Toast; $script:Toast.Visibility='Collapsed'; Pump
        $visual=$window.Content
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $testRoot 'timer-compact.png'))
        try{$encoder.Save($stream)}finally{$stream.Dispose()}
        Write-Host ('Compact timer preview: '+(Join-Path $testRoot 'timer-compact.png'))
    }
    Start-TaskTimer $high; Start-Sleep -Milliseconds 1100; Stop-TaskTimer
    Assert ($script:TimeEntries.Count -ge 1 -and $script:TimeEntries[0].End-$script:TimeEntries[0].Start -ge 1000) 'Elapsed time is persisted when paused'
    $script:LastTimerSave=0L
    Start-TaskTimer $high; Start-Sleep -Milliseconds 1100; Pump
    $checkpoint=[IO.File]::ReadAllText($script:DataFilePath) | ConvertFrom-Json
    Assert (@($checkpoint.timeEntries | Where-Object { $_.id -eq $script:RunningTimer.Id -and $_.end -gt $_.start }).Count -eq 1) 'Heartbeat checkpoints a running timer without pausing it'
    Stop-TaskTimer
    Start-TaskTimer $high; Start-Sleep -Milliseconds 50; Start-TaskTimer $low
    Assert ($script:RunningTimer.TaskId -eq $low.Id) 'Starting another task pauses the previous timer'
    Toggle-Task $low
    Assert ($null -eq $script:RunningTimer -and $low.IsCompleted) 'Completing a running task pauses it'
    Toggle-Task $low; Start-TaskTimer $low; Remove-Task $low
    Assert ($null -eq $script:RunningTimer) 'Moving a running task to the recycle bin pauses it'
    Undo-LastTaskAction
    $script:ComposerTimer.IsChecked=$true; $script:NewTaskInput.Text='整理明天的计划'; Add-TaskFromComposer
    Assert ($script:RunningTimer.TaskId -eq $script:ActiveTasks[0].Id -and -not $script:ComposerTimer.IsChecked) 'Composer can start a new task immediately and resets its toggle'
    $script:TimingFeatureToggle.IsChecked=$false
    Assert ($null -eq $script:RunningTimer -and $script:TimeEntries.Count -gt 0) 'Disabling timers pauses without erasing history'
    Load-Settings
    Assert (-not $script:Settings.TimingEnabled -and $script:Settings.StatisticsEnabled) 'New feature settings persist'
    Load-Tasks
    Assert ($null -eq $script:RunningTimer -and $script:TimeEntries.Count -gt 0) 'Reload retains recorded time and never accrues offline time'
    Refresh-TaskList
    $high=@($script:ActiveTasks | Where-Object Priority -eq 'high')[0]
    $other=@($script:ActiveTasks | Where-Object Id -ne $high.Id)[0]
    $script:TimeEntries.Clear()
    $today=(Get-Date).Date
    Add-Time $high ($today.AddMinutes(-30)) ($today.AddMinutes(30))
    Add-Time $other ($today.AddHours(2)) ($today.AddHours(3.5))
    $summary=@(Get-TimeSummary $today $today.AddDays(1))
    Assert (($summary | Measure-Object Milliseconds -Sum).Sum -eq 7200000) 'Date boundaries clip cross-midnight sessions correctly'
    Remove-TaskTimeHistory @($other.Id)
    Assert ($script:TimeEntries.Count -eq 1 -and $script:TimeEntries[0].TaskId -eq $high.Id) 'Permanent history removal preserves unrelated task time'
    Add-Time $other ($today.AddHours(2)) ($today.AddHours(3.5))
    $script:FilterStats.IsChecked=$true; Pump
    Assert ($script:StatisticsPanel.Visibility -eq 'Visible' -and $script:TaskScroll.Visibility -eq 'Collapsed') 'Statistics page replaces the task list'
    Assert ($script:StatsTotal.Text -eq '02:00:00' -and $script:StatsPie.Children.Count -eq 2 -and $script:StatsLegend.Children.Count -eq 2) 'Pie sectors, legend and total agree'
    Assert ($script:StatsError.Text -eq '') 'Statistics renders without errors'
    $script:StatisticsPanel.FindName('StatsWeek').IsChecked=$true
    $monday=$today.AddDays(-(([int]$today.DayOfWeek+6)%7))
    Assert ($script:StatsRange.Text.StartsWith($monday.ToString('yyyy-MM-dd'))) 'Week range begins on Monday'
    $script:StatisticsPanel.FindName('StatsMonth').IsChecked=$true
    Assert ($script:StatsRange.Text.StartsWith(([datetime]::new($today.Year,$today.Month,1)).ToString('yyyy-MM-dd'))) 'Month range starts on the first'
    $script:StatisticsPanel.FindName('StatsCustom').IsChecked=$true
    $script:StatsStartDate.SelectedDate=$today; $script:StatsEndDate.SelectedDate=$today
    Update-StatisticsView
    Assert ($script:StatsTotal.Text -eq '02:00:00') 'Custom end date is inclusive'
    $script:StatsEndDate.SelectedDate=$today.AddDays(-1)
    Assert ($script:StatsError.Text.Length -gt 0 -and $script:StatsPie.Children.Count -eq 0) 'Invalid ranges explain the error and clear stale charts'
    $script:StatsEndDate.SelectedDate=$today
    foreach ($theme in @('light','dark')) {
        Set-EffectiveTheme $theme; $window.Width=400; $window.Height=480; Pump
        Assert ($script:StatsError.Text -eq '' -and $script:StatisticsPanel.ActualWidth -gt 250) ('Statistics supports compact '+$theme+' windows')
        if ($Screenshots) {
            $window.Width=560; $window.Height=740
            Hide-Toast; $script:Toast.Visibility='Collapsed'; Pump
            $visual=$window.Content
            $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($visual); $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream=[IO.File]::Create((Join-Path $root ('docs\preview-statistics-'+$theme+'.png')))
            try{$encoder.Save($stream)}finally{$stream.Dispose()}
        }
    }
    $script:StatsStartDate.SelectedDate=$today.AddYears(1); $script:StatsEndDate.SelectedDate=$today.AddYears(1)
    Assert ($script:StatsTotal.Text -eq '00:00:00' -and $script:StatsEmpty.Visibility -eq 'Visible') ('Empty date range shows a clear empty state: '+$script:StatsTotal.Text+' / '+$script:StatsError.Text)
    $script:StatisticsFeatureToggle.IsChecked=$false
    Assert ($script:TaskFilter -eq 'all' -and $script:StatisticsPanel.Visibility -eq 'Collapsed') 'Disabling statistics returns safely to tasks'
    $script:TimeEntries.Clear(); Add-Time $high $today $today.AddHours(1)
    $script:TimingFeatureToggle.IsChecked=$true
    Start-TaskTimer $high; Start-Sleep -Milliseconds 50
    $safeDirectory=$script:DataDirectory
    $blocker=Join-Path $testRoot 'not-a-directory'
    [IO.File]::WriteAllText($blocker,'block')
    $script:DataDirectory=$blocker
    $closing=[ComponentModel.CancelEventArgs]::new()
    & $script:WindowClosingHandler $window $closing
    Assert ($closing.Cancel -and $script:TasksDirty -and $script:TimeEntries.Count -gt 1) 'Failed timer persistence cancels closing and retains time in memory'
    $script:DataDirectory=$safeDirectory; Save-Tasks
    $script:TimeEntries.Clear(); Add-Time $high $today $today.AddHours(1)
    Save-Tasks; Load-Tasks
    Assert ($script:TimeEntries.Count -eq 1 -and $script:TimeEntries[0].End-$script:TimeEntries[0].Start -eq 3600000) 'Time entries round-trip without loss'
    $original=[IO.File]::ReadAllText($script:DataFilePath)
    $invalid=$original | ConvertFrom-Json; $invalid.timeEntries[0].end=-1
    $bad=$invalid | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($script:DataFilePath,$bad)
    Load-Tasks; Save-Tasks
    Assert ($null -ne $script:LoadError -and [IO.File]::ReadAllText($script:DataFilePath) -eq $bad) 'Malformed tracking data cannot be overwritten'
    [IO.File]::WriteAllText($script:DataFilePath,$original); Load-Tasks
    Write-Host 'All ordering, timing and statistics checks passed.'
} finally {
    $window.Close()
    if ($script:TrackingHeartbeat) {$script:TrackingHeartbeat.Stop()}
    if ($script:ClockTimer) {$script:ClockTimer.Stop()}
    if ($script:ThemeWatchTimer) {$script:ThemeWatchTimer.Stop()}
    if ($script:ToastTimer) {$script:ToastTimer.Stop()}
}
