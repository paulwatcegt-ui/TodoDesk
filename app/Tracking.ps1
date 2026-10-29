#requires -Version 5.1
# Loaded into the app's script scope by Initialize-Interface.
function script:Get-OrderedTasks {
    param([bool]$Completed = $false)
    $tasks = if ($Completed) { @($script:CompletedTasks) } else { @($script:ActiveTasks) }
    if ($Completed) { $sorted = @($tasks | Sort-Object CompletedAt -Descending) }
    elseif ($script:Settings.PriorityEnabled -ne $false) {
        $sorted = @($tasks | Sort-Object @{ Expression = { switch (Get-TaskPriority $_) { 'high' { 0 }; 'low' { 2 }; default { 1 } } } }, @{ Expression = 'CreatedAt'; Descending = $true })
    } else { $sorted = @($tasks | Sort-Object CreatedAt -Descending) }
    $order = if ($Completed) { @($script:CompletedOrder) } else { @($script:ActiveOrder) }
    $lookup = @{}; foreach ($task in $tasks) { $lookup[$task.Id] = $task }
    foreach ($id in $order) { if ($lookup.ContainsKey($id)) { $lookup[$id]; $lookup.Remove($id) } }
    foreach ($task in $sorted) { if ($lookup.ContainsKey($task.Id)) { $task; $lookup.Remove($task.Id) } }
}

function script:Move-TaskPosition {
    param([string]$SourceId,[string]$TargetId,[bool]$After = $false)
    if ($null -ne $script:LoadError -or $SourceId -eq $TargetId) { return }
    foreach ($completed in @($false,$true)) {
        $items = @(Get-OrderedTasks $completed)
        $ids = [Collections.Generic.List[string]]::new()
        foreach ($task in $items) { $ids.Add($task.Id) }
        if (-not $ids.Contains($SourceId) -or -not $ids.Contains($TargetId)) { continue }
        [void]$ids.Remove($SourceId)
        $index = $ids.IndexOf($TargetId) + $(if ($After) { 1 } else { 0 })
        $ids.Insert($index,$SourceId)
        $order = $script:ActiveOrder
        if ($completed) { $order = $script:CompletedOrder }
        $order.Clear(); foreach ($id in $ids) { [void]$order.Add($id) }
        Save-Tasks; Refresh-TaskList
        return
    }
}

function script:Reset-TaskOrder {
    $script:ActiveOrder.Clear(); $script:CompletedOrder.Clear()
    Save-Tasks; Refresh-TaskList
}

function script:Remove-TaskTimeHistory {
    param([string[]]$Ids)
    foreach ($entry in @($script:TimeEntries)) { if ($entry.TaskId -in $Ids) { $script:TimeEntries.Remove($entry) } }
    foreach ($id in $Ids) { $script:ActiveOrder.Remove($id); $script:CompletedOrder.Remove($id) }
}

function script:Enable-TaskDragging {
    param($Row)
    $Row.AllowDrop = $true
    $Row.Add_PreviewMouseLeftButtonDown({
        param($sender,$eventArgs)
        $script:DragTaskId = $null
        $node = $eventArgs.OriginalSource
        while ($null -ne $node -and $node -ne $sender) {
            if ($node -is [Windows.Controls.Primitives.ButtonBase] -or $node -is [Windows.Controls.TextBox]) { return }
            if ($node -is [Windows.Media.Visual]) { $node = [Windows.Media.VisualTreeHelper]::GetParent($node) } else { return }
        }
        if ($null -eq $script:EditingContext) {
            $script:DragStart = $eventArgs.GetPosition($script:Window)
            $script:DragTaskId = $sender.Tag.Task.Id
        }
    })
    $Row.Add_MouseMove({
        param($sender,$eventArgs)
        if ($eventArgs.LeftButton -ne 'Pressed' -or $script:DragTaskId -ne $sender.Tag.Task.Id -or $null -ne $script:EditingContext) { return }
        $point = $eventArgs.GetPosition($script:Window)
        if ([Math]::Abs($point.X-$script:DragStart.X) -lt [Windows.SystemParameters]::MinimumHorizontalDragDistance -and
            [Math]::Abs($point.Y-$script:DragStart.Y) -lt [Windows.SystemParameters]::MinimumVerticalDragDistance) { return }
        $data = [Windows.DataObject]::new('TodoDesk.TaskId',[string]$script:DragTaskId)
        try { [void][Windows.DragDrop]::DoDragDrop($sender,$data,[Windows.DragDropEffects]::Move) }
        finally { $script:DragTaskId = $null; $sender.BorderThickness = [Windows.Thickness]::new(0) }
    })
    $Row.Add_DragOver({
        param($sender,$eventArgs)
        $eventArgs.Effects = 'None'; $eventArgs.Handled = $true
        if (-not $eventArgs.Data.GetDataPresent('TodoDesk.TaskId')) { return }
        $id = [string]$eventArgs.Data.GetData('TodoDesk.TaskId')
        $group = if ($sender.Tag.Task.IsCompleted) { @($script:CompletedTasks) } else { @($script:ActiveTasks) }
        if (@($group | Where-Object { $_.Id -eq $id }).Count -eq 0) { return }
        $eventArgs.Effects = 'Move'
        $sender.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty,'AccentBrush')
        $after = $eventArgs.GetPosition($sender).Y -gt $sender.ActualHeight/2
        $sender.BorderThickness = if ($after) { [Windows.Thickness]::new(0,0,0,2) } else { [Windows.Thickness]::new(0,2,0,0) }
        $y = $eventArgs.GetPosition($script:TaskScroll).Y
        if ($y -lt 28) { $script:TaskScroll.LineUp() }
        elseif ($y -gt $script:TaskScroll.ActualHeight-28) { $script:TaskScroll.LineDown() }
    })
    $Row.Add_DragLeave({ param($sender,$eventArgs); $sender.BorderThickness = [Windows.Thickness]::new(0) })
    $Row.Add_Drop({
        param($sender,$eventArgs)
        $sender.BorderThickness = [Windows.Thickness]::new(0)
        if ($eventArgs.Data.GetDataPresent('TodoDesk.TaskId')) {
            Move-TaskPosition ([string]$eventArgs.Data.GetData('TodoDesk.TaskId')) $sender.Tag.Task.Id ($eventArgs.GetPosition($sender).Y -gt $sender.ActualHeight/2)
            $eventArgs.Handled = $true
        }
    })
}

function script:Get-TimerEnd {
    if ($null -eq $script:RunningTimer) { return 0L }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $end = $script:RunningTimer.Start + $script:RunningTimer.Watch.ElapsedMilliseconds
    if ($now - $script:RunningTimer.LastSeen -gt 30000) { $end = [Math]::Min($end,$script:RunningTimer.LastSeen) }
    return [long][Math]::Max($script:RunningTimer.Start,$end)
}

function script:Flush-TaskTimer {
    if ($null -eq $script:RunningTimer) { return }
    $timer = $script:RunningTimer; $end = Get-TimerEnd
    if ($end -gt $timer.Start) {
        $entry = @($script:TimeEntries | Where-Object { $_.Id -eq $timer.Id })
        if ($entry.Count -gt 0) { $entry[0].End = $end }
        else { [void]$script:TimeEntries.Add([pscustomobject]@{ Id=$timer.Id; TaskId=$timer.TaskId; Title=$timer.Title; Start=[long]$timer.Start; End=[long]$end }) }
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($now - $timer.LastSeen -gt 30000) {
        $timer.Id = [guid]::NewGuid().ToString('N'); $timer.Start = $now; $timer.Watch.Restart()
    }
    $timer.LastSeen = $now
}

function script:Stop-TaskTimer {
    param([bool]$Save = $true)
    if ($null -eq $script:RunningTimer) { return }
    Flush-TaskTimer
    $script:RunningTimer.Watch.Stop(); $script:RunningTimer = $null
    if ($Save) { Save-Tasks }
    Update-TimerRows
}

function script:Start-TaskTimer {
    param($Task)
    if (-not $script:Settings.TimingEnabled -or $null -ne $script:LoadError -or $Task.IsCompleted -or -not (Test-TaskIdInList $script:ActiveTasks $Task.Id)) { return }
    Commit-ActiveEdit
    if ($null -ne $script:RunningTimer -and $script:RunningTimer.TaskId -eq $Task.Id) { Stop-TaskTimer; return }
    Stop-TaskTimer -Save $false
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $script:RunningTimer = @{ Id=[guid]::NewGuid().ToString('N'); TaskId=$Task.Id; Title=$Task.Title; Start=$now; LastSeen=$now; Watch=[Diagnostics.Stopwatch]::StartNew() }
    Save-Tasks; Update-TimerRows
}

function script:Get-EffectiveTimeEntries {
    foreach ($entry in $script:TimeEntries) {
        if ($null -ne $script:RunningTimer -and $entry.Id -eq $script:RunningTimer.Id) {
            [pscustomobject]@{ Id=$entry.Id; TaskId=$entry.TaskId; Title=$entry.Title; Start=$entry.Start; End=(Get-TimerEnd) }
        } else { $entry }
    }
    if ($null -ne $script:RunningTimer -and @($script:TimeEntries | Where-Object { $_.Id -eq $script:RunningTimer.Id }).Count -eq 0) {
        [pscustomobject]@{ Id=$script:RunningTimer.Id; TaskId=$script:RunningTimer.TaskId; Title=$script:RunningTimer.Title; Start=$script:RunningTimer.Start; End=(Get-TimerEnd) }
    }
}

function script:Format-TaskDuration {
    param([double]$Milliseconds)
    $seconds = [long][Math]::Floor([Math]::Max(0.0,$Milliseconds)/1000)
    return '{0:00}:{1:00}:{2:00}' -f [long][Math]::Floor($seconds/3600),[long][Math]::Floor(($seconds%3600)/60),[long]($seconds%60)
}

function script:Get-TaskMetadata {
    param($Task)
    $parts = [Collections.Generic.List[string]]::new()
    if ($script:Settings.RemindersEnabled -ne $false -and $null -ne $Task.RemindAt -and -not $Task.IsCompleted) { $parts.Add('提醒 · '+$Task.RemindAt.ToString('MM-dd HH:mm')) }
    if ($script:Settings.TimingEnabled) {
        $total = 0.0; foreach ($entry in @(Get-EffectiveTimeEntries | Where-Object { $_.TaskId -eq $Task.Id })) { $total += $entry.End-$entry.Start }
        $parts.Add($(if ($null -ne $script:RunningTimer -and $script:RunningTimer.TaskId -eq $Task.Id) { '计时中 · ' } else { '用时 · ' }) + (Format-TaskDuration $total))
    }
    return $parts -join '  ·  '
}

function script:Update-TimerRows {
    if (-not $script:UiReady) { return }
    foreach ($row in @($script:ActiveList.Children)+@($script:CompletedList.Children)) {
        $ctx = $row.Tag
        if ($null -ne $ctx.ReminderLabel -and -not $ctx.IsEditing) { $ctx.ReminderLabel.Text = Get-TaskMetadata $ctx.Task }
        $running = $null -ne $script:RunningTimer -and $script:RunningTimer.TaskId -eq $ctx.Task.Id
        if ($ctx.TimerButton.Tag.Running -ne $running) {
            $ctx.TimerButton.Content = New-IconPath $(if ($running) { 'M 5,2 L 5,14 M 11,2 L 11,14' } else { 'M 4,2 L 12,8 L 4,14 Z' })
            Add-IconBinding $ctx.TimerButton.Content $ctx.TimerButton
            $ctx.TimerButton.Tag.Running = $running
        }
        $ctx.TimerButton.ToolTip = if ($running) { '暂停计时' } else { '开始计时' }
        [Windows.Automation.AutomationProperties]::SetName($ctx.TimerButton,$ctx.TimerButton.ToolTip)
    }
}

function script:Get-TimeSummary {
    param([datetime]$StartDate,[datetime]$EndExclusive)
    $start = Get-UnixMilliseconds $StartDate
    $end = Get-UnixMilliseconds $EndExclusive
    if ($end -le $start) { throw '结束日期不能早于开始日期。' }
    $titles = @{}; foreach ($task in @($script:ActiveTasks)+@($script:CompletedTasks)+@($script:ArchivedTasks)+@($script:TrashedTasks)) { $titles[$task.Id]=$task.Title }
    $totals = @{}
    foreach ($entry in @(Get-EffectiveTimeEntries)) {
        $duration = [Math]::Max(0L,[Math]::Min([long]$entry.End,$end)-[Math]::Max([long]$entry.Start,$start))
        if ($duration -le 0) { continue }
        if (-not $totals.ContainsKey($entry.TaskId)) { $totals[$entry.TaskId]=[pscustomobject]@{TaskId=$entry.TaskId;Title=$(if ($titles.ContainsKey($entry.TaskId)) {$titles[$entry.TaskId]}else{$entry.Title});Milliseconds=0.0} }
        $totals[$entry.TaskId].Milliseconds += $duration
    }
    return @($totals.Values | Sort-Object @{Expression='Milliseconds';Descending=$true},Title)
}

function script:Update-StatisticsView {
    if (-not $script:UiReady -or $null -eq $script:StatisticsPanel) { return }
    $script:StatsPie.Children.Clear(); $script:StatsLegend.Children.Clear()
    $script:StatsError.Text = ''
    $custom = $script:StatsPeriod -eq 'custom'
    $script:StatsCustomDates.Visibility = if ($custom) { 'Visible' } else { 'Collapsed' }
    $script:StatsAnchorDate.Visibility = if ($custom) { 'Collapsed' } else { 'Visible' }
    try {
        $date = $script:StatsAnchorDate.SelectedDate
        if ($null -eq $date) { throw '请选择统计日期。' }
        switch ($script:StatsPeriod) {
            'week' { $start=$date.Date.AddDays(-(([int]$date.DayOfWeek+6)%7)); $end=$start.AddDays(7) }
            'month' { $start=[datetime]::new($date.Year,$date.Month,1); $end=$start.AddMonths(1) }
            'custom' {
                if ($null -eq $script:StatsStartDate.SelectedDate -or $null -eq $script:StatsEndDate.SelectedDate) { throw '请选择开始和结束日期。' }
                $start=$script:StatsStartDate.SelectedDate.Date; $end=$script:StatsEndDate.SelectedDate.Date.AddDays(1)
            }
            default { $start=$date.Date; $end=$start.AddDays(1) }
        }
        $summary = @(Get-TimeSummary $start $end)
        $total=0.0; foreach ($item in $summary) { $total += $item.Milliseconds }
        $script:StatsTotal.Text = Format-TaskDuration $total
        $script:StatsRange.Text = $start.ToString('yyyy-MM-dd')+' 至 '+$end.AddDays(-1).ToString('yyyy-MM-dd')
        $script:StatsEmpty.Visibility = if ($total -gt 0) { 'Collapsed' } else { 'Visible' }
        $script:StatsPie.Visibility = if ($total -gt 0) { 'Visible' } else { 'Collapsed' }
        $angle=-90.0; $index=0
        foreach ($item in $summary) {
            $brush=$script:Window.FindResource('StatsColor'+($index%8))
            $fraction=$item.Milliseconds/$total
            if ($summary.Count -eq 1) {
                $shape=[Windows.Shapes.Ellipse]::new(); $shape.Width=160; $shape.Height=160
                [Windows.Controls.Canvas]::SetLeft($shape,10); [Windows.Controls.Canvas]::SetTop($shape,10)
            } else {
                $next=$angle+360*$fraction
                $first=[Windows.Point]::new(90+80*[Math]::Cos($angle*[Math]::PI/180),90+80*[Math]::Sin($angle*[Math]::PI/180))
                $last=[Windows.Point]::new(90+80*[Math]::Cos($next*[Math]::PI/180),90+80*[Math]::Sin($next*[Math]::PI/180))
                $figure=[Windows.Media.PathFigure]::new(); $figure.StartPoint=[Windows.Point]::new(90,90); $figure.IsClosed=$true
                [void]$figure.Segments.Add([Windows.Media.LineSegment]::new($first,$true))
                [void]$figure.Segments.Add([Windows.Media.ArcSegment]::new($last,[Windows.Size]::new(80,80),0,($fraction -gt 0.5),[Windows.Media.SweepDirection]::Clockwise,$true))
                $geometry=[Windows.Media.PathGeometry]::new(); [void]$geometry.Figures.Add($figure)
                $shape=[Windows.Shapes.Path]::new(); $shape.Data=$geometry; $angle=$next
            }
            $shape.Fill=$brush; $shape.Stroke=$script:Window.FindResource('CardBrush'); $shape.StrokeThickness=1.5
            $shape.ToolTip=$item.Title+' · '+(Format-TaskDuration $item.Milliseconds)+(' · {0:0.0}%' -f (100*$fraction))
            [void]$script:StatsPie.Children.Add($shape)
            $row=[Windows.Controls.Grid]::new(); $row.Margin=[Windows.Thickness]::new(0,6,0,6)
            foreach ($width in @(18,'*','Auto')) {
                $column=[Windows.Controls.ColumnDefinition]::new()
                $column.Width = if ($width -eq '*') { [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) } elseif ($width -eq 'Auto') { [Windows.GridLength]::Auto } else { [Windows.GridLength]::new(18) }
                [void]$row.ColumnDefinitions.Add($column)
            }
            $dot=[Windows.Shapes.Ellipse]::new(); $dot.Width=7; $dot.Height=7; $dot.Fill=$brush; $dot.HorizontalAlignment='Left'; $dot.VerticalAlignment='Center'
            [void]$row.Children.Add($dot)
            $title=[Windows.Controls.TextBlock]::new(); $title.Text=$item.Title; $title.TextTrimming='CharacterEllipsis'; $title.ToolTip=$shape.ToolTip; $title.Margin=[Windows.Thickness]::new(0,0,10,0)
            [Windows.Controls.Grid]::SetColumn($title,1); [void]$row.Children.Add($title)
            $value=[Windows.Controls.TextBlock]::new(); $value.Text=(Format-TaskDuration $item.Milliseconds)+('  {0:0.0}%' -f (100*$fraction)); $value.FontSize=12
            $value.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'SecondaryBrush')
            [Windows.Controls.Grid]::SetColumn($value,2); [void]$row.Children.Add($value)
            [void]$script:StatsLegend.Children.Add($row)
            $index++
        }
    } catch { $script:StatsError.Text=$_.Exception.Message; $script:StatsTotal.Text='--'; $script:StatsRange.Text=''; $script:StatsPie.Visibility='Collapsed'; $script:StatsEmpty.Visibility='Collapsed' }
}

function script:Initialize-TrackingUI {
    $script:StatisticsPanel=[Windows.Markup.XamlReader]::Parse(@'
<ScrollViewer xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="10,6">
 <ScrollViewer.Resources>
  <Style TargetType="DatePickerTextBox"><Setter Property="Foreground" Value="{DynamicResource InkBrush}"/><Setter Property="Background" Value="{DynamicResource SettingsFieldBrush}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="DatePickerTextBox"><Border Background="{TemplateBinding Background}" CornerRadius="5"><ScrollViewer x:Name="PART_ContentHost" Margin="6,3"/></Border></ControlTemplate></Setter.Value></Setter></Style>
 </ScrollViewer.Resources>
 <StackPanel>
  <TextBlock Text="时间统计" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,14"/>
  <UniformGrid Columns="4" Margin="0,0,0,10">
   <RadioButton x:Name="StatsDay" Content="日" Tag="day" GroupName="StatsPeriod" IsChecked="True"/>
   <RadioButton x:Name="StatsWeek" Content="周" Tag="week" GroupName="StatsPeriod"/>
   <RadioButton x:Name="StatsMonth" Content="月" Tag="month" GroupName="StatsPeriod"/>
   <RadioButton x:Name="StatsCustom" Content="自定义" Tag="custom" GroupName="StatsPeriod"/>
  </UniformGrid>
  <DatePicker x:Name="StatsAnchorDate" Language="zh-CN" Foreground="{DynamicResource InkBrush}" Background="{DynamicResource SettingsFieldBrush}" BorderBrush="{DynamicResource SettingsFieldBorderBrush}"/>
  <Grid x:Name="StatsCustomDates" Visibility="Collapsed"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <DatePicker x:Name="StatsStartDate" Language="zh-CN" Foreground="{DynamicResource InkBrush}" Background="{DynamicResource SettingsFieldBrush}" BorderBrush="{DynamicResource SettingsFieldBorderBrush}"/>
   <TextBlock Grid.Column="1" Text="至" HorizontalAlignment="Center" VerticalAlignment="Center"/>
   <DatePicker x:Name="StatsEndDate" Grid.Column="2" Language="zh-CN" Foreground="{DynamicResource InkBrush}" Background="{DynamicResource SettingsFieldBrush}" BorderBrush="{DynamicResource SettingsFieldBorderBrush}"/>
  </Grid>
  <TextBlock x:Name="StatsRange" Margin="0,12,0,5" FontSize="11.5" Foreground="{DynamicResource SecondaryBrush}"/>
  <TextBlock Text="累计计时" FontSize="12" Foreground="{DynamicResource SecondaryBrush}"/>
  <TextBlock x:Name="StatsTotal" Text="00:00:00" FontSize="28" FontWeight="SemiBold" Margin="0,3,0,4"/>
  <TextBlock x:Name="StatsError" Foreground="{DynamicResource DangerBrush}" TextWrapping="Wrap"/>
  <Canvas x:Name="StatsPie" Width="180" Height="180" HorizontalAlignment="Center"/>
  <TextBlock x:Name="StatsEmpty" Text="选定范围内暂无计时记录" Foreground="{DynamicResource SecondaryBrush}" HorizontalAlignment="Center" Margin="0,0,0,12"/>
  <StackPanel x:Name="StatsLegend"/>
  <TextBlock Text="按实际计时记录统计，含已完成、归档和回收站记录。" TextWrapping="Wrap" FontSize="11" Margin="0,14,0,0" Foreground="{DynamicResource SecondaryBrush}"/>
 </StackPanel>
</ScrollViewer>
'@)
    [void]$script:TaskScroll.Parent.Children.Add($script:StatisticsPanel)
    foreach ($name in @('StatsAnchorDate','StatsCustomDates','StatsStartDate','StatsEndDate','StatsRange','StatsTotal','StatsError','StatsPie','StatsEmpty','StatsLegend')) {
        Set-Variable -Scope Script -Name $name -Value $script:StatisticsPanel.FindName($name)
    }
    $script:StatsPeriod='day'
    foreach ($name in @('StatsDay','StatsWeek','StatsMonth','StatsCustom')) {
        $button=$script:StatisticsPanel.FindName($name); $button.Style=$script:Window.FindResource('FilterStyle')
        $button.Add_Checked({ param($sender,$eventArgs); $script:StatsPeriod=[string]$sender.Tag; Update-StatisticsView })
    }
    foreach ($date in @($script:StatsAnchorDate,$script:StatsStartDate,$script:StatsEndDate)) {
        $date.SelectedDate=(Get-Date).Date
        $date.Add_SelectedDateChanged({ Update-StatisticsView })
        $date.Add_DateValidationError({
            param($sender,$eventArgs)
            $eventArgs.ThrowException=$false
            $sender.SelectedDate=$null
            $script:StatsError.Text='请输入有效日期，例如 2026/10/29。'
        })
    }
    $script:TrackingHeartbeat=[Windows.Threading.DispatcherTimer]::new()
    $script:TrackingHeartbeat.Interval=[TimeSpan]::FromSeconds(1)
    $script:TrackingHeartbeat.Add_Tick({
        if ($null -ne $script:RunningTimer) {
            $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            if ($now-$script:LastTimerSave -ge 10000) { Save-Tasks; $script:LastTimerSave=$now }
            else {
                if ($now-$script:RunningTimer.LastSeen -gt 30000) { Flush-TaskTimer }
                $script:RunningTimer.LastSeen=$now
            }
            Update-TimerRows
            if ($script:TaskFilter -eq 'stats') { Update-StatisticsView }
        }
    })
}

function script:Update-TrackingPreferences {
    if (-not $script:UiReady) { return }
    $script:ComposerTimer.Visibility=if ($script:Settings.TimingEnabled) { 'Visible' } else { 'Collapsed' }
    $script:FilterStats.Visibility=if ($script:Settings.StatisticsEnabled) { 'Visible' } else { 'Collapsed' }
    if (-not $script:Settings.TimingEnabled) { Stop-TaskTimer; $script:ComposerTimer.IsChecked=$false }
    if (-not $script:Settings.StatisticsEnabled -and $script:TaskFilter -eq 'stats') { $script:FilterAll.IsChecked=$true }
    $script:ResetOrderButton.IsEnabled=$script:ActiveOrder.Count+$script:CompletedOrder.Count -gt 0
}
