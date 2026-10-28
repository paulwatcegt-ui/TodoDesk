#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\priority-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
function Assert($condition,$message) { if (-not $condition) { throw $message }; Write-Host ('ok    ' + $message) }
Load-Settings
Load-Tasks
$window = Load-Interface
Initialize-ThemePalette $window 'light'
Initialize-Interface $window
Wire-InterfaceEvents
try {
    foreach ($choice in @(@(0,'high'),@(1,'medium'),@(2,'low'))) {
        $script:ComposerPriority.ContextMenu.Items[$choice[0]].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
        $script:NewTaskInput.Text = $choice[1] + ' task'
        Add-TaskFromComposer
        Assert ($script:ActiveTasks[0].Priority -eq $choice[1]) ('Composer applies ' + $choice[1] + ' priority')
    }
    Load-Tasks
    Assert (($script:ActiveTasks.Priority | Sort-Object) -join ',' -eq 'high,low,medium') 'All three priorities survive reload'
    $task = $script:ActiveTasks[0]
    Set-TaskReminder $task ((Get-Date).AddHours(1)) | Out-Null
    $reminder = $task.RemindAt
    Set-TaskPriority $task 'high'
    Set-TaskPriority $task 'low'
    Undo-LastTaskAction
    Assert ($task.Priority -eq 'high' -and $task.RemindAt -eq $reminder) 'Priority undo preserves the task and reminder'
    Toggle-Task $task
    Toggle-Task $task
    Remove-Task $task
    Undo-LastTaskAction
    Load-Tasks
    $restored = @($script:ActiveTasks | Where-Object { $_.Id -eq $task.Id })[0]
    Assert ($restored.Priority -eq 'high' -and [Math]::Abs(($restored.RemindAt-$reminder).TotalSeconds) -lt 1) 'Completion and delete undo retain priority and reminder on disk'
    Refresh-TaskList
    foreach ($theme in @('light','dark')) {
        Set-EffectiveTheme $theme
        $button = $script:ActiveList.Children[0].Tag.PriorityButton
        $expected = (Get-PriorityInfo (Get-TaskPriority $script:ActiveTasks[0])).Brush
        Assert ($button.Foreground.Color -eq $script:ThemeDictionary[$expected].Color) ('Priority badge uses the current ' + $theme + ' theme')
    }
    $invalid = $false
    try { Set-TaskPriority $restored 'urgent' } catch { $invalid = $true }
    Assert $invalid 'Unknown priority choices are rejected'
    [IO.File]::WriteAllText($script:DataFilePath, '{"version":1,"items":[{"id":"legacy","title":"旧任务","completed":false}]}')
    Load-Tasks
    Assert ($script:ActiveTasks.Count -eq 1 -and $script:ActiveTasks[0].Priority -eq 'medium' -and $null -eq $script:LoadError) 'Legacy tasks load with medium priority without migration'
    Write-Host 'All priority checks passed.'
} finally {
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
}
