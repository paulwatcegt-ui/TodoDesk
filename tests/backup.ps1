#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $root ('.testdata\backup-'+[guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR=Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR=Join-Path $testRoot 'config'
$source=[IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source,'# -+ startup')[0])
$script:AppRoot=Join-Path $root 'app'
function Assert($value,$message){if(-not $value){throw $message};Write-Host ('ok    '+$message)}
function Pump {
    $frame=[Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false}.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame);$window.UpdateLayout()
}
Load-Settings;Load-Tasks
$window=Load-Interface
Initialize-ThemePalette $window 'dark';Initialize-Interface $window;Wire-InterfaceEvents;Update-SettingsUi
$window.Show()
try {
    $script:NewTaskInput.Text='Current task';Add-TaskFromComposer
    $current=$script:ActiveTasks[0]
    $saved=[IO.File]::ReadAllText($script:DataFilePath)|ConvertFrom-Json
    $base=$saved.items[0]
    $base.title='Older conflicting title'
    $saved.items=@($base,[pscustomobject]@{id='import-active';title='Imported active';completed=$false;priority='high'})
    $saved.archive=@([pscustomobject]@{id='import-archive';title='Archived';completed=$true})
    $saved.trash=@([pscustomobject]@{id='trash-one';title='Trash one';completed=$false},[pscustomobject]@{id='trash-two';title='Trash two';completed=$true})
    $now=Get-UnixMilliseconds (Get-Date)
    $saved.timeEntries=@([pscustomobject]@{id='session-one';taskId='trash-one';title='Trash one';start=$now-1000;end=$now},[pscustomobject]@{id='session-two';taskId='trash-two';title='Trash two';start=$now-2000;end=$now})
    $saved.activeOrder=@('import-active')
    $importPath=Join-Path $testRoot 'backup.json'
    [IO.File]::WriteAllText($importPath,($saved|ConvertTo-Json -Depth 6))
    $original=[IO.File]::ReadAllText($script:DataFilePath)
    $result=Import-BackupFile $importPath
    Assert ($result.Added -eq 4 -and $result.Skipped -eq 1 -and $result.TimeEntries -eq 2) 'Import merges every stored collection and timer history'
    Assert ($script:ActiveTasks[0] -eq $current -and $current.Title -eq 'Current task') 'Same-ID task preserves its live object and current content'
    Assert ([IO.File]::ReadAllText($result.BackupPath) -eq $original) 'Import creates an exact durable backup before merging'
    Assert ($script:ActiveOrder.Contains('import-active')) 'Imported manual ordering is retained'
    $again=Import-BackupFile $importPath
    Assert ($again.Added -eq 0 -and $again.TimeEntries -eq 0 -and $script:TrashedTasks.Count -eq 2) 'Repeated import is idempotent'
    $script:TimingFeatureToggle.IsChecked=$true
    Start-TaskTimer $current
    $timer=$script:RunningTimer
    $before=[IO.File]::ReadAllText($script:DataFilePath)
    $bad=Join-Path $testRoot 'invalid.json';[IO.File]::WriteAllText($bad,'{"items":[{"title":"broken"}]}')
    $failed=$false;try{Import-BackupFile $bad}catch{$failed=$true}
    Assert ($failed -and $script:RunningTimer -eq $timer -and $script:ActiveTasks[0] -eq $current -and $null -eq $script:LoadError) 'Invalid import restores live collections, timer and read state'
    Assert ([IO.File]::ReadAllText($script:DataFilePath) -eq $before) 'Invalid backup does not write the current file'
    Stop-TaskTimer
    $trash=$script:TrashedTasks[0]
    $other=$script:TrashedTasks[1]
    $script:UndoPayload=@{Kind='delete';Task=$trash}
    Remove-TrashedTaskPermanently $trash
    Assert ($script:TrashedTasks.Count -eq 1 -and $script:TrashedTasks[0].Id -eq $other.Id) 'Permanent deletion removes only the selected trash task'
    Assert (@($script:TimeEntries|Where-Object TaskId -eq $trash.Id).Count -eq 0 -and @($script:TimeEntries|Where-Object TaskId -eq $other.Id).Count -eq 1) 'Single deletion removes only its own time history'
    Assert ($null -eq $script:UndoPayload) 'Permanent deletion cannot be reversed by an older undo action'
    $dialog=[Windows.Window]::new()
    $dialog.Tag=@{Mode='trash';List=[Windows.Controls.StackPanel]::new();Count=[Windows.Controls.TextBlock]::new();Empty=[Windows.Controls.TextBlock]::new();Error=[Windows.Controls.TextBlock]::new();Clear=[Windows.Controls.Button]::new()}
    Refresh-StoredTasksDialog $dialog
    $buttons=@($dialog.Tag.List.Children[0].Child.Children|Where-Object {$_ -is [Windows.Controls.Button]})
    Assert ('永久删除' -in $buttons.Content -and '恢复' -in $buttons.Content) 'Every recycle-bin row exposes restore and permanent delete'
    $dialog.Tag.Mode='archive';Refresh-StoredTasksDialog $dialog
    $buttons=@($dialog.Tag.List.Children[0].Child.Children|Where-Object {$_ -is [Windows.Controls.Button]})
    Assert ('永久删除' -notin $buttons.Content) 'Archive rows retain their restore-only behavior'
    Load-Tasks
    Assert ($null -eq $script:LoadError -and $script:ActiveTasks.Count -eq 2 -and $script:ArchivedTasks.Count -eq 1 -and $script:TrashedTasks.Count -eq 1) 'Merged data and single deletion survive restart'
    foreach($theme in @('light','dark')) {
        Set-EffectiveTheme $theme;$window.Width=400;$window.Height=400;Open-Settings;Pump
        $scroll=$window.FindName('SettingsScroll')
        $start=$script:SettingsCloseButton.TranslatePoint([Windows.Point]::new(0,0),$script:SettingsCardRoot)
        Assert ($scroll.ScrollableHeight -gt 0) 'Compact settings body can scroll'
        $scroll.ScrollToEnd();Pump
        $end=$script:SettingsCloseButton.TranslatePoint([Windows.Point]::new(0,0),$script:SettingsCardRoot)
        Assert ([Math]::Abs($start.Y-$end.Y) -lt 0.1 -and $script:SettingsCloseButton.IsVisible) ('Close button stays fixed while scrolling in '+$theme+' mode: '+$start.Y+' / '+$end.Y+' visible='+$script:SettingsCloseButton.IsVisible)
        Close-Settings;Pump
    }
    $blocker=Join-Path $testRoot 'not-a-folder';[IO.File]::WriteAllText($blocker,'block')
    $safe=$script:DataDirectory;$script:DataDirectory=$blocker
    $failed=$false;try{Import-BackupFile $importPath}catch{$failed=$true}
    Assert ($failed -and $script:ActiveTasks.Count -eq 2 -and $script:TrashedTasks.Count -eq 1) 'Failure saving existing data aborts import before merging'
    $script:DataDirectory=$safe;Save-Tasks
    Write-Host 'All backup, recycle-bin and fixed settings header checks passed.'
}finally{$window.Close();if($script:TrackingHeartbeat){$script:TrackingHeartbeat.Stop()};if($script:ThemeWatchTimer){$script:ThemeWatchTimer.Stop()}}
