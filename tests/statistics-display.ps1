#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $root ('.testdata\statistics-display-'+[guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR=Join-Path $testRoot 'data';$env:DAIBAN_CONFIG_DIR=Join-Path $testRoot 'config'
$source=[IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source,'# -+ startup')[0])
$script:AppRoot=Join-Path $root 'app'
function Assert($value,$message){if(-not $value){throw $message};Write-Host ('ok    '+$message)}
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false}.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame);$window.UpdateLayout()
}
function Click($button){$event=if($button -is [Windows.Controls.MenuItem]){[Windows.Controls.MenuItem]::ClickEvent}else{[Windows.Controls.Primitives.ButtonBase]::ClickEvent};$button.RaiseEvent([Windows.RoutedEventArgs]::new($event))}
function Enter($control) {
    $key=[Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($window),0,[Windows.Input.Key]::Enter)
    $key.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent;$control.RaiseEvent($key)
    Assert $key.Handled 'Enter is consumed by task creation'
}
Load-Settings;Load-Tasks;$window=Load-Interface
Initialize-ThemePalette $window 'dark';Initialize-Interface $window;Wire-InterfaceEvents;Update-SettingsUi;$window.Show();Pump
try {
    foreach($index in @(0,1,2)) {
        $script:NewTaskInput.Text='Priority test '+$index
        [void]$script:ComposerPriority.Focus();Click $script:ComposerPriority
        $menu=$script:ComposerPriority.ContextMenu
        Assert $menu.IsOpen 'Priority menu opens before selection'
        Click $menu.Items[$index];Pump
        Assert ($script:NewTaskInput.IsKeyboardFocused -and -not $script:ComposerPriority.ContextMenu.IsOpen) 'Choosing priority returns focus to the task input'
        Assert ($script:ActiveTasks.Count -eq $index) 'Choosing priority does not auto-submit the draft'
        Enter $script:NewTaskInput;Pump
        Assert ($script:ActiveTasks.Count -eq $index+1 -and -not $script:ComposerPriority.ContextMenu.IsOpen) 'Enter adds exactly one task instead of reopening the picker'
    }
    $script:NewTaskInput.Text='Fast enter';[void]$script:ComposerPriority.Focus()
    Enter $script:ComposerPriority;Pump
    Assert ($script:ActiveTasks.Count -eq 4) 'Enter from the priority button also safely submits a nonempty draft'
    $tasks=@($script:ActiveTasks)
    Toggle-Task $tasks[2];Archive-Completed
    Remove-Task $tasks[3]
    $start=(Get-Date).Date.AddHours(1)
    $script:TimeEntries.Clear()
    for($i=0;$i -lt 4;$i++) {
        [void]$script:TimeEntries.Add([pscustomobject]@{Id='display-session-'+$i;TaskId=$tasks[$i].Id;Title=$tasks[$i].Title;Start=(Get-UnixMilliseconds $start);End=(Get-UnixMilliseconds $start.AddMinutes($i+1))})
    }
    Save-Tasks
    $script:StatisticsFeatureToggle.IsChecked=$true;$script:FilterStats.IsChecked=$true;Pump
    Assert ($script:StatsTotal.Text -eq '00:10:00' -and $script:StatsPie.Children.Count -eq 4) 'Default statistics include current, archived and recycled tasks'
    $original=[IO.File]::ReadAllText($script:DataFilePath)
    Click $script:StatsLegend.Children[0].Children[3]
    Assert ($script:StatsTotal.Text -eq '00:06:00' -and $script:StatsLegend.Children.Count -eq 3 -and $script:StatsHiddenList.Children.Count -eq 1) 'Hiding a legend item updates the chart, legend and total together'
    Click $script:StatsHiddenList.Children[0]
    Assert ($script:StatsTotal.Text -eq '00:10:00' -and $script:StatsHiddenExpander.Visibility -eq 'Collapsed') 'A hidden task can be restored without losing its time'
    foreach($task in $tasks){Set-StatisticsTaskVisible $task.Id $false}
    Assert ($script:StatsTotal.Text -eq '00:00:00' -and $script:StatsPie.Children.Count -eq 0 -and $script:StatsHiddenList.Children.Count -eq 4) 'Hiding every task gives a recoverable empty view'
    foreach($task in $tasks){Set-StatisticsTaskVisible $task.Id $true}
    $script:StatsIncludeArchive.IsChecked=$false
    Assert ($script:StatsTotal.Text -eq '00:07:00') 'Archive selection excludes only archived time'
    $script:StatsIncludeTrash.IsChecked=$false
    Assert ($script:StatsTotal.Text -eq '00:03:00' -and $script:StatsLegend.Children.Count -eq 2) 'Both optional sources can be excluded independently'
    Set-StatisticsTaskVisible $tasks[0].Id $false
    Assert ($script:StatsTotal.Text -eq '00:02:00') 'Per-task visibility combines with source selection'
    Load-Settings
    Assert (-not $script:Settings.StatsIncludeArchive -and -not $script:Settings.StatsIncludeTrash -and $tasks[0].Id -in $script:Settings.StatsHiddenTaskIds) 'Display selections persist in settings'
    Assert ([IO.File]::ReadAllText($script:DataFilePath) -eq $original -and $script:TimeEntries.Count -eq 4) 'Display preferences never rewrite or remove task time data'
    foreach($period in @('StatsWeek','StatsMonth','StatsCustom')) {
        $script:StatisticsPanel.FindName($period).IsChecked=$true
        Assert ($script:StatsTotal.Text -eq '00:02:00') 'Task and source filters stay active across date modes'
    }
    foreach($theme in @('light','dark')) {
        Set-EffectiveTheme $theme;$window.Width=400;$window.Height=480;Pump
        Assert ($script:StatsError.Text -eq '' -and $script:StatsIncludeTrash.IsVisible) ('Source controls remain usable in compact '+$theme+' mode')
    }
    Write-Host 'All priority keyboard and statistics display checks passed.'
}finally{$window.Close();if($script:ThemeWatchTimer){$script:ThemeWatchTimer.Stop()}}
