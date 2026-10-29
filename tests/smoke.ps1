#requires -Version 5.1
[CmdletBinding()]
param([switch]$Screenshots, [switch]$ReadPersistedState)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $ReadPersistedState) {
    $runDirectory = Join-Path $root ('.testdata\' + [guid]::NewGuid().ToString('N'))
    $env:DAIBAN_DATA_DIR = Join-Path $runDirectory 'data'
    $env:DAIBAN_CONFIG_DIR = Join-Path $runDirectory 'config'
}
$env:DAIBAN_PREVIEW = '1'

function Assert($condition, $message) {
    if (-not $condition) { throw $message }
    Write-Host ('ok    ' + $message)
}

# Load the real application functions without starting its blocking event loop.
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
$definitions = [regex]::Split($source, '# -+ startup')[0]
Invoke-Expression $definitions
$script:AppRoot = Join-Path $root 'app'
Load-Settings
Load-Tasks
if ($ReadPersistedState) {
    @{ active = $script:ActiveTasks.Count; completed = $script:CompletedTasks.Count;
        state = $script:PersistenceState; titles = @($script:ActiveTasks.Title) } | ConvertTo-Json -Compress
    return
}
$window = Load-Interface
Initialize-ThemePalette -Window $window -ThemeName 'light'
Initialize-Interface -Window $window
Wire-InterfaceEvents
Update-Date
Refresh-TaskList

function Layout([int]$width = 880, [int]$height = 740) {
    Update-ResponsiveLayout -Width $width -Height $height
    $visual = $window.Content
    $visual.Measure([Windows.Size]::new($width,$height))
    $visual.Arrange([Windows.Rect]::new(0,0,$width,$height))
    $visual.UpdateLayout()
}

function Snapshot([string]$name, [int]$width = 880, [int]$height = 740) {
    if (-not $Screenshots) { return }
    $visual = $window.Content
    Layout $width $height
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Create((Join-Path $root ('docs\' + $name + '.png')))
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

try {
    Assert ($script:EmptyState.Visibility -eq 'Visible') 'Empty state on first launch'
    Assert ($script:StorageStatusText.Text -notmatch '已保存' -and -not (Test-Path $script:DataFilePath)) 'A new empty list never claims to be saved'
    $script:NewTaskInput.Text = '   '
    Add-TaskFromComposer
    Assert ($script:ActiveTasks.Count -eq 0) 'Whitespace is not added'
    Assert (-not $script:AddButton.IsEnabled) 'Whitespace disables the add button'
    foreach ($title in @('打开 TodoDesk，开始新的一天', '写下想法，让脑袋轻一点', '下班后，去散个步', '给新项目留一点专注的时间', '整理今天想做的三件小事')) {
        $script:NewTaskInput.Text = $title
        $script:AddButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    }
    Assert ($script:ActiveTasks.Count -eq 5) 'Add button creates and persists tasks'
    Assert ($script:StorageStatusText.Text -eq '数据已保存到本机') 'Saved status follows a successful disk write'
    $row = $script:ActiveList.Children[0]
    $context = $row.Child.Children[1].Children[0].Tag
    $originalTitle = $context.Task.Title
    Start-EditTask -Context $context
    $context.Editor.Text = '整理今天想做的三件小事（已编辑）'
    Complete-Edit -Context $context -ReturnFocus $false
    Assert ($context.Task.Title -match '已编辑') 'Inline editing commits title'
    $script:ToastUndoButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($context.Task.Title -eq $originalTitle) 'Edit can be undone from its toast'
    $context = $script:ActiveList.Children[0].Tag
    Start-EditTask -Context $context
    $context.Editor.Text = '不应提交的编辑'
    $escape = [pscustomobject]@{ Key = [Windows.Input.Key]::Escape; Handled = $false }
    & $script:WindowKeyHandler $window $escape
    Assert ($escape.Handled -and $null -eq $script:EditingContext -and $context.Task.Title -eq $originalTitle) 'Escape cancels editing even while a toast is visible'
    Toggle-Task -Task $script:ActiveTasks[4]
    Toggle-Task -Task $script:ActiveTasks[3]
    Assert ($script:CompletedTasks.Count -eq 2 -and $script:TaskProgress.Value -eq 40) 'Completion updates groups and progress'
    Layout
    $completedRow = $script:CompletedList.Children[0].Tag
    $completedRow.Check.ApplyTemplate() | Out-Null
    $glyph = $completedRow.Check.Template.FindName('Glyph', $completedRow.Check)
    $ring = $completedRow.Check.Template.FindName('Ring', $completedRow.Check)
    $bounds = $glyph.Data.Bounds
    Assert ([Math]::Abs($bounds.X + $bounds.Width/2 - $ring.ActualWidth/2) -lt 0.1 -and
        [Math]::Abs($bounds.Y + $bounds.Height/2 - $ring.ActualHeight/2) -lt 0.1) 'The checkmark geometry is centered in its circle on both axes'
    Assert ($completedRow.Title.TextDecorations.Count -eq 1 -and
        $completedRow.Title.TextDecorations[0].Location -eq 'Strikethrough') 'Completed task text has a strikethrough'
    Assert ($script:ActiveList.Children[0].Tag.Title.TextDecorations.Count -eq 0) 'Active task text has no completion decoration'
    $indicator = $script:TaskProgress.Template.FindName('PART_Indicator', $script:TaskProgress)
    Assert ([Math]::Abs($indicator.ActualWidth / $script:TaskProgress.ActualWidth - 0.4) -lt 0.02) 'The rendered progress bar matches the completed fraction'
    $script:CompletedToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert ($script:CompletedList.Visibility -eq 'Collapsed' -and $script:CompletedTasks.Count -eq 2 -and $script:TaskProgress.Value -eq 40) 'Collapsing completed tasks preserves totals and progress'
    $script:FilterActive.IsChecked = $true
    Assert ($script:CompletedSection.Visibility -eq 'Collapsed' -and $script:ActiveList.Children.Count -eq 3) 'Active filter hides completed tasks'
    $script:FilterCompleted.IsChecked = $true
    Assert ($script:ActiveList.Children.Count -eq 0 -and $script:CompletedList.Children.Count -eq 2) 'Completed filter hides active tasks'
    Assert ($script:CompletedList.Visibility -eq 'Visible' -and -not $script:CompletedToggleButton.IsEnabled) 'Completed filter always reveals all completed tasks'
    $script:FilterAll.IsChecked = $true
    Assert ($script:CompletedList.Visibility -eq 'Collapsed') 'All filter remembers the completed group collapse state'
    $script:CompletedToggleButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    $script:FilterCompleted.IsChecked = $true
    $script:NewTaskInput.Text = '临时添加'
    Add-TaskFromComposer
    Assert ($script:TaskFilter -eq 'all' -and $script:ActiveList.Children.Count -eq 4) 'Adding in completed view reveals the new task'
    Remove-Task -Task $script:ActiveTasks[0]
    $payload = $script:UndoPayload
    Invoke-UndoPayload -Payload $payload
    Assert ($script:ActiveTasks.Count -eq 4) 'Delete can be undone'
    Remove-Task -Task $script:ActiveTasks[0]
    Clear-Completed
    Assert ($script:CompletedTasks.Count -eq 0) 'Clear completed removes completed group'
    Invoke-UndoPayload -Payload $script:UndoPayload
    Assert ($script:CompletedTasks.Count -eq 2) 'Clear completed can be undone'
    Load-Tasks
    Refresh-TaskList
    Assert ($script:ActiveTasks.Count -eq 3 -and $script:CompletedTasks.Count -eq 2) 'Tasks survive reload from disk'
    Assert ($script:LastTasksSaveSucceeded -and (Test-Path ($script:DataFilePath + '.bak'))) 'Atomic saving retains a backup'
    $probe = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath -ReadPersistedState | ConvertFrom-Json
    Assert ($LASTEXITCODE -eq 0 -and $probe.active -eq 3 -and $probe.completed -eq 2 -and $probe.state -eq 'saved') 'A fresh PowerShell process reads the same persisted list'
    Hide-Toast
    Layout
    Assert ($script:TaskScroll.ScrollableHeight -le 1) 'Five mixed tasks fit without internal scrolling at the default size'
    Snapshot 'preview-light'
    Set-ThemePreference -Preference 'dark'
    Assert ($script:EffectiveTheme -eq 'dark') 'Dark theme applies live'
    Snapshot 'preview-dark'
    Open-Settings
    $script:SettingsOverlay.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $script:SettingsOverlay.Opacity = 1
    Snapshot 'preview-settings'
    Close-Settings
    Set-ThemePreference -Preference 'light'
    $script:FilterActive.IsChecked = $true
    foreach ($task in @($script:ActiveTasks)) { Toggle-Task -Task $task }
    Assert ($script:EmptyState.Visibility -eq 'Visible' -and $script:TaskProgress.Value -eq 100) 'All done state and 100 percent progress'
    Snapshot 'preview-empty'

    # Enter, add undo and completion undo use the same handlers as the native UI.
    $script:NewTaskInput.Text = 'Enter 快捷添加'
    $enter = [pscustomobject]@{ Key = [Windows.Input.Key]::Enter; Handled = $false }
    & $script:NewTaskKeyHandler $script:NewTaskInput $enter
    Assert ($enter.Handled -and $script:ActiveTasks.Count -eq 1) 'Enter adds exactly one task'
    Undo-LastTaskAction
    Assert ($script:ActiveTasks.Count -eq 0) 'Newly added tasks can be undone'
    $completed = $script:CompletedTasks[0]
    Toggle-Task -Task $completed
    Undo-LastTaskAction
    Assert ($script:ActiveTasks.Count -eq 0 -and $completed.IsCompleted) 'Completion state can be undone'
    Clear-Completed
    Assert ($script:TaskProgress.Value -eq 0 -and $script:ProgressText.Text -eq '0 / 0 已完成') 'Clearing the last tasks resets the progress to zero'

    # Stress the list without repeated disk writes; only the final valid state is saved.
    foreach ($i in 1..80) {
        [void]$script:ActiveTasks.Add([pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); Title = ('任务 {0} — 长标题用于检查省略和完整提示' -f $i); IsCompleted = $false; CreatedAt = Get-Date; CompletedAt = $null; IsEditing = $false })
    }
    $script:FilterAll.IsChecked = $true
    Save-Tasks
    Refresh-TaskList -ResetScroll
    foreach ($size in @(@(400,400), @(480,480), @(680,620), @(880,740), @(1280,900))) {
        Layout $size[0] $size[1]
        Assert ($script:TaskScroll.ScrollableHeight -gt 0 -and $script:TaskScroll.ViewportHeight -gt 70) ('Long list scrolls within available space at {0}x{1}' -f $size[0],$size[1])
        $script:TaskScroll.ScrollToBottom()
        Layout $size[0] $size[1]
        Assert ($script:TaskScroll.VerticalOffset -gt 0) 'The last task is reachable by scrolling'
        foreach ($theme in @('light','dark')) {
            Set-EffectiveTheme -ThemeName $theme
            Snapshot ('preview-many-{0}-{1}' -f $theme,$size[0]) $size[0] $size[1]
        }
    }
    $script:ActiveTasks.Clear()
    $script:NewTaskInput.Text = '保存安全检查'
    Add-TaskFromComposer
    Layout 400 400
    Assert ($script:TaskScroll.ScrollableHeight -le 1) 'One task needs no internal scroll at the minimum window size'
    Snapshot 'preview-small' 400 400
    Set-ThemePreference -Preference $script:EffectiveTheme
    Open-Settings
    $script:SettingsOverlay.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $script:SettingsOverlay.Opacity = 1
    Snapshot 'preview-settings-small' 400 400
    $cardPosition = $script:SettingsCardRoot.TranslatePoint([Windows.Point]::new(0,0), $window.Content)
    Assert ($cardPosition.X -ge 0 -and $cardPosition.X + $script:SettingsCardRoot.ActualWidth -le 400 -and
        $cardPosition.Y -ge 0 -and $cardPosition.Y + $script:SettingsCardRoot.ActualHeight -le 400) 'Settings fit inside the smallest window'
    Close-Settings

    # An exclusive file handle produces a real Windows sharing violation.
    $fileBefore = [IO.File]::ReadAllText($script:DataFilePath)
    $lock = [IO.File]::Open($script:DataFilePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $script:ActiveTasks[0].Title = '失败后仍保留在窗口中的更改'
        Save-Tasks
        Assert (-not $script:LastTasksSaveSucceeded -and $script:TasksDirty -and $script:StorageStatusText.Text -match '保存失败') 'A failed write never reports a successful save'
        $closing = [ComponentModel.CancelEventArgs]::new()
        & $script:WindowClosingHandler $window $closing
        Assert ($closing.Cancel) 'Closing is cancelled when pending data cannot be saved'
    }
    finally { $lock.Dispose() }
    Assert ([IO.File]::ReadAllText($script:DataFilePath) -eq $fileBefore) 'Failed replacement leaves the old file untouched'
    Save-Tasks
    Assert ($script:LastTasksSaveSucceeded -and -not $script:TasksDirty -and $script:StorageStatusText.Text -eq '数据已保存到本机') 'Retry persists the in-memory change after the lock is released'
    $goodData = [IO.File]::ReadAllText($script:DataFilePath)
    $goodBackup = [IO.File]::ReadAllText($script:DataFilePath + '.bak')
    foreach ($invalid in @('{broken JSON', 'null', '{"version":1,"items":null}', '{"version":999,"items":[]}', '{"version":1,"items":[{"title":"bad","completed":"false"}]}')) {
        [IO.File]::WriteAllText($script:DataFilePath, $invalid)
        Load-Tasks
        Update-StorageStatus
        Refresh-TaskList
        Save-Tasks
        $closing = [ComponentModel.CancelEventArgs]::new()
        & $script:WindowClosingHandler $window $closing
        $script:NewTaskInput.Text = '不应覆盖原文件'
        Add-TaskFromComposer
        Assert ($null -ne $script:LoadError -and -not $script:NewTaskInput.IsEnabled -and -not $script:ChangeDataFolderButton.IsEnabled) 'Invalid or unknown data makes mutations unavailable'
        Assert ([IO.File]::ReadAllText($script:DataFilePath) -eq $invalid -and [IO.File]::ReadAllText($script:DataFilePath + '.bak') -eq $goodBackup) 'Opening and closing invalid data preserves both original and backup bytes'
    }
    [IO.File]::WriteAllText($script:DataFilePath, $goodData)
    Load-Tasks
    Update-StorageStatus
    Refresh-TaskList
    $script:NewTaskInput.Clear()
    $beforeClose = [IO.File]::GetLastWriteTimeUtc($script:DataFilePath)
    & $script:WindowClosingHandler $window ([ComponentModel.CancelEventArgs]::new())
    Assert ([IO.File]::GetLastWriteTimeUtc($script:DataFilePath) -eq $beforeClose) 'Closing an unchanged list does not rewrite user data'

    $settingsBefore = [IO.File]::ReadAllText($script:SettingsFilePath)
    [IO.File]::WriteAllText($script:SettingsFilePath, '{bad settings')
    Load-Settings
    Set-ThemePreference -Preference 'dark'
    Assert ([IO.File]::ReadAllText($script:SettingsFilePath) -eq '{bad settings' -and -not $script:LastSettingsSaveSucceeded) 'Theme changes preserve an unreadable settings file'
    [IO.File]::WriteAllText($script:SettingsFilePath, $settingsBefore)
    Load-Settings
    Load-Tasks
    Update-StorageStatus
    Write-Host 'All interaction checks passed.'
}
finally {
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
}
