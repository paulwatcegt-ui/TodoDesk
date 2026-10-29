#requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $root ('.testdata\polish-'+[guid]::NewGuid().ToString('N'))
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
Load-Settings;Load-Tasks;$window=Load-Interface
Initialize-ThemePalette $window 'dark';Initialize-Interface $window;Wire-InterfaceEvents;Update-SettingsUi;$window.Show()
try {
    foreach($entry in @(@('medium','Medium one'),@('high','High one'),@('medium','Medium two'),@('high','High two'),@('low','Low one'))) {
        $script:ComposerPriorityValue=$entry[0];$script:NewTaskInput.Text=$entry[1];Add-TaskFromComposer
    }
    Assert ((@(Get-OrderedTasks).Title -join ',') -eq 'High one,High two,Medium one,Medium two,Low one') 'New tasks append after same-priority peers'
    Load-Tasks;Refresh-TaskList
    Assert ((@(Get-OrderedTasks).Title -join ',') -eq 'High one,High two,Medium one,Medium two,Low one') 'Peer order survives restart'
    $low=@($script:ActiveTasks|Where-Object Title -eq 'Low one')[0]
    $high=@($script:ActiveTasks|Where-Object Title -eq 'High one')[0]
    Move-TaskPosition $low.Id $high.Id
    $script:ComposerPriorityValue='high';$script:NewTaskInput.Text='High three';Add-TaskFromComposer
    Assert ((@(Get-OrderedTasks).Title -join ',') -eq 'Low one,High one,High two,High three,Medium one,Medium two') 'New task follows its last peer while preserving every manual relationship'
    Load-Tasks;Refresh-TaskList;Pump
    $row=$script:ActiveList.Children[1];$before=$row.Child.ActualHeight
    Show-TaskDropHint $row $true;Pump
    Assert ($null -ne $script:DropHint -and -not $script:DropHint.IsHitTestVisible) 'Drop indicator is drawn in a noninteractive adorner'
    Assert ($row.BorderThickness.Top -eq 0 -and $row.BorderThickness.Bottom -eq 0 -and $row.Child.ActualHeight -eq $before) 'Drop indicator never squeezes the task layout'
    $hint=$script:DropHint
    Show-TaskDropHint $row $true
    Assert ($hint -eq $script:DropHint) 'Repeated drag events reuse the current indicator'
    Show-TaskDropHint $row $false
    Assert (-not $script:DropHint.After) 'Indicator switches between before and after positions'
    Clear-TaskDropHint
    Assert ($null -eq $script:DropHint -and $null -eq $script:DropHintRow) 'Cancellation removes all insertion feedback'
    foreach($theme in @('light','dark')) {
        Set-EffectiveTheme $theme
        foreach($priority in @('high','medium','low')) {
            $script:ComposerPriorityValue=$priority;Initialize-PriorityButton $script:ComposerPriority $null
            $expected=if($priority -eq 'medium'){'ComposerPriorityForegroundBrush'}else{(Get-PriorityInfo $priority).Brush}
            Assert ($script:ComposerPriority.Foreground.Color -eq $script:ThemeDictionary[$expected].Color) ('Composer '+$priority+' priority uses its intended color in '+$theme+' mode')
            $surface=if($priority -eq 'medium'){'ComposerPrioritySurfaceBrush'}else{(Get-PriorityInfo $priority).Brush.Replace('Brush','SurfaceBrush')}
            Assert ($script:ComposerPriority.Background.Color -eq $script:ThemeDictionary[$surface].Color) ('Composer '+$priority+' background matches its themed text')
        }
    }
    $script:Settings.PriorityEnabled=$false
    $script:ActiveOrder.Clear()
    Assert (@(Get-OrderedTasks)[0].Title -eq 'High three') 'Priority-disabled mode keeps the existing newest-first behavior'
    Write-Host 'All ordering and drag presentation checks passed.'
}finally{Clear-TaskDropHint;$window.Close();if($script:ThemeWatchTimer){$script:ThemeWatchTimer.Stop()}}
