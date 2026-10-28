#requires -Version 5.1

# 待办 · 极简桌面待办清单
# This host version uses the signed Windows PowerShell runtime so it can start
# in environments where Windows Smart App Control blocks newly built EXEs.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:AppRoot = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($env:DAIBAN_APP_ROOT) {
    $env:DAIBAN_APP_ROOT
} else {
    Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$script:AppVersion = '1.3.0'
$script:TaskFilter = 'all'
$script:ComposerPriorityValue = 'medium'
$script:ComposerReminderDraft = [pscustomobject]@{ Title = '新待办'; RemindAt = $null; IsDraft = $true }
$script:CompletedExpanded = $true
$script:PersistenceState = 'empty'
$script:TasksDirty = $false
$script:ChineseCulture = [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN')
$script:DefaultDataDirectory = if ($env:DAIBAN_DATA_DIR) {
    $env:DAIBAN_DATA_DIR
} else {
    Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'DaiBan'
}
$script:ConfigDirectory = if ($env:DAIBAN_CONFIG_DIR) {
    $env:DAIBAN_CONFIG_DIR
} else {
    Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'DaiBan'
}
$script:SettingsFilePath = Join-Path $script:ConfigDirectory 'settings.json'
$script:DataDirectory = $script:DefaultDataDirectory
$script:DataFilePath = Join-Path $script:DataDirectory 'todos.json'
$script:Settings = @{
    PriorityEnabled = $true
    RemindersEnabled = $true
    Theme = 'system'
    DataDirectory = $null
}
$script:ThemePreference = 'system'
$script:EffectiveTheme = 'light'
$script:ThemeDictionary = $null
$script:ThemeWatchTimer = $null
$script:SuppressThemeEvents = $false
$script:ActiveTasks = New-Object System.Collections.ArrayList
$script:CompletedTasks = New-Object System.Collections.ArrayList
$script:ArchivedTasks = New-Object System.Collections.ArrayList
$script:TrashedTasks = New-Object System.Collections.ArrayList
$script:LoadError = $null
$script:SettingsError = $null
$script:SettingsReadError = $null
$script:LastTasksSaveSucceeded = $false
$script:LastSettingsSaveSucceeded = $false
$script:EditingContext = $null
$script:UndoPayload = $null
$script:ToastTimer = $null
$script:ClockTimer = $null
$script:ToastToken = 0
$script:UiReady = $false
$script:Mutex = $null
$script:Application = $null
$script:HasNativeHelpers = $false
$script:SettingsOpen = $false

$script:RowHoverBrush = $null
$script:EditRowBrush = $null
$script:AccentBrush = $null
$script:SecondaryBrush = $null
$script:TransparentBrush = [System.Windows.Media.Brushes]::Transparent

$script:TaskTitleStyle = $null
$script:TaskCheckStyle = $null
$script:InlineEditStyle = $null
$script:RowIconStyle = $null
$script:DeleteIconStyle = $null

try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DaiBanNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MinMaxInfo {
        public Point Reserved, MaxSize, MaxPosition, MinTrackSize, MaxTrackSize;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MonitorInfo {
        public int Size;
        public Rect Monitor, Work;
        public int Flags;
    }
    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    public static bool ApplyWorkArea(IntPtr window, IntPtr pointer, double minWidth, double minHeight) {
        MonitorInfo monitor = new MonitorInfo();
        monitor.Size = Marshal.SizeOf(typeof(MonitorInfo));
        if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref monitor)) return false;
        MinMaxInfo bounds = (MinMaxInfo)Marshal.PtrToStructure(pointer, typeof(MinMaxInfo));
        bounds.MaxPosition.X = monitor.Work.Left - monitor.Monitor.Left;
        bounds.MaxPosition.Y = monitor.Work.Top - monitor.Monitor.Top;
        bounds.MaxSize.X = monitor.Work.Right - monitor.Work.Left;
        bounds.MaxSize.Y = monitor.Work.Bottom - monitor.Work.Top;
        double scale = GetDpiForWindow(window) / 96.0;
        bounds.MinTrackSize.X = (int)Math.Ceiling(minWidth * scale);
        bounds.MinTrackSize.Y = (int)Math.Ceiling(minHeight * scale);
        Marshal.StructureToPtr(bounds, pointer, false);
        return true;
    }

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);

    // Modern shell folder picker. The owner handle keeps it modal above the WPF window.
    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialog
    {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint count, IntPtr filters);
        void SetFileTypeIndex(uint index);
        void GetFileTypeIndex(out uint index);
        void Advise(IntPtr events, out uint cookie);
        void Unadvise(uint cookie);
        void SetOptions(uint options);
        void GetOptions(out uint options);
        void SetDefaultFolder(IShellItem item);
        void SetFolder(IShellItem item);
        void GetFolder(out IShellItem item);
        void GetCurrentSelection(out IShellItem item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void GetResult(out IShellItem item);
        void AddPlace(IShellItem item, uint place);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
        void Close(int result);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr filter);
    }

    [ComImport, Guid("d57c7288-d4ad-4768-be02-9d969532d960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileOpenDialog : IFileDialog
    {
        void GetResults(out IntPtr results);
        void GetSelectedItems(out IntPtr items);
    }

    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
        void GetParent(out IShellItem parent);
        [PreserveSig] int GetDisplayName(uint nameType, [MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetAttributes(uint mask, out uint attributes);
        void Compare(IShellItem item, uint hint, out int order);
    }

    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    public class FileOpenDialog
    {
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string path,
        IntPtr bindContext,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

    public static string PickFolder(IntPtr owner, string title, string initialPath)
    {
        const uint PickFolders = 0x00000020;
        const uint ForceFileSystem = 0x00000040;
        const uint PathMustExist = 0x00000800;
        const uint FileSystemPath = 0x80058000;

        IFileOpenDialog dialog = null;
        IShellItem initial = null;

        try
        {
            dialog = (IFileOpenDialog)new FileOpenDialog();
            dialog.SetOptions(PickFolders | ForceFileSystem | PathMustExist);

            if (!string.IsNullOrWhiteSpace(title))
            {
                dialog.SetTitle(title);
            }

            if (!string.IsNullOrWhiteSpace(initialPath))
            {
                try
                {
                    Guid iid = typeof(IShellItem).GUID;
                    SHCreateItemFromParsingName(initialPath, IntPtr.Zero, ref iid, out initial);
                    if (initial != null)
                    {
                        dialog.SetFolder(initial);
                    }
                }
                catch
                {
                }
            }

            int result = dialog.Show(owner);
            if (result != 0)
            {
                return null;
            }

            IShellItem selected;
            dialog.GetResult(out selected);
            if (selected == null)
            {
                return null;
            }

            try
            {
                string path;
                if (selected.GetDisplayName(FileSystemPath, out path) == 0)
                {
                    return path;
                }
                return null;
            }
            finally
            {
                Marshal.ReleaseComObject(selected);
            }
        }
        finally
        {
            if (initial != null)
            {
                Marshal.ReleaseComObject(initial);
            }
            if (dialog != null)
            {
                Marshal.ReleaseComObject(dialog);
            }
        }
    }
}
'@ -ErrorAction Stop
    $script:HasNativeHelpers = $true
}
catch {
    $script:HasNativeHelpers = $false
}

# ---------------------------------------------------------------- data store

function Write-AppLog {
    param([string]$Message)

    try {
        [void][System.IO.Directory]::CreateDirectory($script:ConfigDirectory)
        [System.IO.File]::AppendAllText(
            (Join-Path $script:ConfigDirectory 'runtime.log'),
            ('[{0}] {1}{2}' -f (Get-Date).ToString('s'), $Message, [Environment]::NewLine),
            [System.Text.Encoding]::UTF8)
    }
    catch {
    }
}

function ConvertTo-CleanTitle {
    param([string]$Text)

    if ($null -eq $Text) { return '' }

    $clean = ($Text -replace '\s+', ' ').Trim()
    if ($clean.Length -gt 200) {
        $clean = $clean.Substring(0, 200)
    }
    return $clean
}

function ConvertFrom-UnixMilliseconds {
    param([long]$Value)

    try {
        return [DateTimeOffset]::FromUnixTimeMilliseconds($Value).LocalDateTime
    }
    catch {
        return Get-Date
    }
}

function Get-UnixMilliseconds {
    param([datetime]$Value)
    return [DateTimeOffset]::new($Value.ToUniversalTime()).ToUnixTimeMilliseconds()
}

function Load-Tasks {
    $script:LoadError = $null
    $script:PersistenceState = 'empty'
    $script:TasksDirty = $false
    $script:ActiveTasks.Clear()
    $script:CompletedTasks.Clear()
    $script:ArchivedTasks.Clear()
    $script:TrashedTasks.Clear()

    if (-not (Test-Path -LiteralPath $script:DataFilePath)) {
        return
    }

    try {
        $raw = [System.IO.File]::ReadAllText(
            $script:DataFilePath,
            [System.Text.Encoding]::UTF8)
        $state = $raw | ConvertFrom-Json
        # Reject unreadable/unknown shapes rather than silently replacing data with an empty list.
        if ($null -eq $state -or $null -eq $state.PSObject.Properties['items'] -or
            $state.items -isnot [System.Array] -or
            ($null -ne $state.version -and $state.version -ne 1)) {
            throw 'Unsupported todo file format. The original file has been preserved.'
        }
        $tasks = @()

        $groups = @(@{ Name = 'items'; Destination = $tasks }, @{ Name = 'archive' }, @{ Name = 'trash' })
        foreach ($name in @('archive','trash')) {
            if ($null -ne $state.PSObject.Properties[$name] -and $state.$name -isnot [System.Array]) { throw 'Invalid stored collection.' }
        }
        $seenIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($group in $groups) {
        foreach ($saved in @($state.($group.Name))) {
            if ($null -eq $saved -and $group.Name -ne 'items') { continue }
            if ($null -eq $saved -or $saved.title -isnot [string] -or
                $saved.completed -isnot [bool]) {
                throw 'Invalid task record. The original file has been preserved.'
            }

            $title = ConvertTo-CleanTitle -Text ([string]$saved.title)
            if ($title.Length -eq 0) { throw 'Empty task title. The original file has been preserved.' }

            $id = [string]$saved.id
            if ([string]::IsNullOrWhiteSpace($id)) {
                $id = [guid]::NewGuid().ToString('N')
            }

            if (-not $seenIds.Add($id)) { throw 'Duplicate task ID. The original file has been preserved.' }
            $createdAt = Get-Date
            if ($null -ne $saved.createdAt) {
                $createdAt = ConvertFrom-UnixMilliseconds -Value ([long]$saved.createdAt)
            }

            $completedAt = $null
            if ($null -ne $saved.completedAt) {
                $completedAt = ConvertFrom-UnixMilliseconds -Value ([long]$saved.completedAt)
            }

            $task = [pscustomobject][ordered]@{
                Id = $id
                Title = $title
                IsCompleted = [bool]$saved.completed
                CreatedAt = $createdAt
                CompletedAt = $completedAt
                RemindAt = $(if ($null -ne $saved.remindAt) { ConvertFrom-UnixMilliseconds -Value ([long]$saved.remindAt) } else { $null })
                ReminderNotified = [bool]$saved.reminderNotified
                Priority = $(if ($saved.priority -in @('high','medium','low')) { [string]$saved.priority } else { 'medium' })
                IsEditing = $false
            }
            switch ($group.Name) {
                'archive' { [void]$script:ArchivedTasks.Add($task) }
                'trash' { [void]$script:TrashedTasks.Add($task) }
                default { $tasks += $task }
            }
        }
        }

        $active = @($tasks | Where-Object { -not $_.IsCompleted } |
            Sort-Object -Property CreatedAt -Descending)
        $completed = @($tasks | Where-Object { $_.IsCompleted } |
            Sort-Object -Property CompletedAt -Descending)

        foreach ($task in $active) {
            [void]$script:ActiveTasks.Add($task)
        }
        foreach ($task in $completed) {
            [void]$script:CompletedTasks.Add($task)
        }
        $script:PersistenceState = 'saved'
    }
    catch {
        $script:PersistenceState = 'readError'
        $script:LoadError = $_.Exception.Message
        $script:ActiveTasks.Clear()
        $script:CompletedTasks.Clear()
        $script:ArchivedTasks.Clear()
        $script:TrashedTasks.Clear()
    }
}

function Read-AppLicense {
    $path = Join-Path $script:AppRoot 'LICENSE'
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path (Split-Path -Parent $script:AppRoot) 'LICENSE' }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Show-LicenseInformation {
    $dialog = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="TodoDesk · 开源许可" Width="520" Height="440" MinWidth="360" MinHeight="300" WindowStartupLocation="CenterOwner" Background="{DynamicResource SettingsCardBrush}" Foreground="{DynamicResource InkBrush}" FontFamily="Segoe UI, Microsoft YaHei UI">
 <Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <TextBlock Text="TodoDesk · MIT 开源许可" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,16"/>
  <TextBox x:Name="LicenseText" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="Transparent" Foreground="{DynamicResource InkBrush}" BorderThickness="0" FontSize="12"/>
  <Button x:Name="CloseLicense" Grid.Row="2" IsCancel="True" Content="关闭" HorizontalAlignment="Right" Margin="0,16,0,0"/>
 </Grid>
</Window>
'@)
    [void]$dialog.Resources.MergedDictionaries.Add($script:ThemeDictionary)
    $dialog.Owner = $script:Window
    $dialog.FindName('LicenseText').Text = Read-AppLicense
    $dialog.FindName('CloseLicense').Style = $script:Window.FindResource('SettingsButtonStyle')
    [void]$dialog.ShowDialog()
}

function Test-InComposer {
    param($Source)
    $node = $Source
    while ($null -ne $node) {
        if ($node -eq $script:Composer) { return $true }
        if ($node -is [System.Windows.Media.Visual]) { $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node) }
        else { $node = [System.Windows.LogicalTreeHelper]::GetParent($node) }
    }
    return $false
}

function Queue-ComposerConfirmation {
    param([bool]$Force = $false)
    if ([string]::IsNullOrWhiteSpace($script:NewTaskInput.Text)) { return }
    if ($Force) { $script:ComposerConfirmForce = $true }
    if ($script:ComposerConfirmQueued) { return }
    $script:ComposerConfirmQueued = $true
    [void]$script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{
        $force = $script:ComposerConfirmForce
        $script:ComposerConfirmForce = $false
        $script:ComposerConfirmQueued = $false
        if (-not $script:ComposerReminderDialogOpen -and -not $script:ComposerPriority.ContextMenu.IsOpen -and
            ($force -or -not $script:Composer.IsKeyboardFocusWithin) -and -not [string]::IsNullOrWhiteSpace($script:NewTaskInput.Text)) {
            Add-TaskFromComposer -ReturnFocus $false
        }
    })
}

function ConvertTo-StoredTask {
    param($Task)
    return [pscustomobject][ordered]@{
        id = $Task.Id; title = $Task.Title; completed = [bool]$Task.IsCompleted
        createdAt = Get-UnixMilliseconds $Task.CreatedAt
        completedAt = $(if ($null -ne $Task.CompletedAt) { Get-UnixMilliseconds $Task.CompletedAt } else { $null })
        remindAt = $(if ($null -ne $Task.RemindAt) { Get-UnixMilliseconds $Task.RemindAt } else { $null })
        reminderNotified = [bool]$Task.ReminderNotified; priority = Get-TaskPriority $Task
    }
}

function Remove-StoredTask {
    param($Tasks, [string]$Id)
    $index = Find-TaskIndex $Tasks $Id
    if ($index -ge 0) { $Tasks.RemoveAt($index) }
}

function Update-StoredCounts {
    if (-not $script:UiReady) { return }
    $script:TrashSettingsButton.Content = '回收站  ·  ' + $script:TrashedTasks.Count
    $script:ArchiveSettingsButton.Content = '归档记录  ·  ' + $script:ArchivedTasks.Count
}

function Archive-Completed {
    if ($null -ne $script:LoadError -or $script:CompletedTasks.Count -eq 0) { return }
    Commit-ActiveEdit
    $items = @($script:CompletedTasks)
    foreach ($task in $items) { $script:ArchivedTasks.Insert(0, $task) }
    $script:CompletedTasks.Clear()
    Save-Tasks
    Refresh-TaskList
    $script:UndoPayload = @{ Kind = 'archive'; Items = $items }
    Show-Toast -Message ('已归档 {0} 项，可在设置中查看' -f $items.Count) -CanUndo $true
}

function Restore-StoredTask {
    param($Task, [ValidateSet('trash','archive')][string]$Mode)
    if ($null -ne $script:LoadError) { return }
    $stored = $script:TrashedTasks
    if ($Mode -eq 'archive') { $stored = $script:ArchivedTasks }
    if ((Find-TaskIndex $stored $Task.Id) -lt 0 -or (Test-TaskIdInList $script:ActiveTasks $Task.Id) -or (Test-TaskIdInList $script:CompletedTasks $Task.Id)) { return }
    Remove-StoredTask $stored $Task.Id
    if ($Task.IsCompleted) { $script:CompletedTasks.Insert(0, $Task) } else { $script:ActiveTasks.Insert(0, $Task) }
    Save-Tasks
    Refresh-TaskList
}

function Refresh-StoredTasksDialog {
    param($Dialog)
    $ctx = $Dialog.Tag
    $list = $script:TrashedTasks
    if ($ctx.Mode -eq 'archive') { $list = $script:ArchivedTasks }
    $ctx.List.Children.Clear()
    $ctx.Count.Text = '共 {0} 项' -f $list.Count
    $ctx.Empty.Visibility = if ($list.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    foreach ($task in @($list)) {
        $card = [System.Windows.Controls.Border]::new()
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'CardBrush')
        $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $card.Padding = [System.Windows.Thickness]::new(12)
        $card.Margin = [System.Windows.Thickness]::new(0,0,0,8)
        $dock = [System.Windows.Controls.DockPanel]::new()
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = '恢复'; $button.Style = $script:Window.FindResource('SettingsButtonStyle')
        $button.Margin = [System.Windows.Thickness]::new(12,0,0,0)
        $button.IsEnabled = $null -eq $script:LoadError
        $button.Tag = @{ Dialog = $Dialog; Task = $task; Mode = $ctx.Mode }
        $button.Add_Click({
            param($sender,$eventArgs)
            Restore-StoredTask $sender.Tag.Task $sender.Tag.Mode
            Refresh-StoredTasksDialog $sender.Tag.Dialog
        })
        [System.Windows.Controls.DockPanel]::SetDock($button,'Right')
        [void]$dock.Children.Add($button)
        $text = [System.Windows.Controls.TextBlock]::new()
        $text.Text = $task.Title + [Environment]::NewLine + $(if ($task.IsCompleted) { '已完成' } else { '待办' })
        $text.TextWrapping = 'Wrap'; $text.FontSize = 13
        $text.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'InkBrush')
        [void]$dock.Children.Add($text)
        $card.Child = $dock; [void]$ctx.List.Children.Add($card)
    }
    $ctx.Clear.IsEnabled = $list.Count -gt 0 -and $null -eq $script:LoadError
    $ctx.Error.Text = if ($script:TasksDirty) { '更改尚未保存，请检查保存位置。' } else { '' }
}

function Open-StoredTasksDialog {
    param([ValidateSet('trash','archive')][string]$Mode)
    $dialog = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="420" Height="440" MinWidth="360" MinHeight="320" WindowStartupLocation="CenterOwner" Background="{DynamicResource SettingsCardBrush}" Foreground="{DynamicResource InkBrush}" FontFamily="Microsoft YaHei UI, Segoe UI">
 <Grid Margin="22"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock x:Name="StoredTitle" FontSize="21" FontWeight="SemiBold"/><TextBlock x:Name="StoredDescription" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,16" Foreground="{DynamicResource SecondaryBrush}"/></StackPanel>
  <Grid Grid.Row="1"><ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel x:Name="StoredList"/></ScrollViewer><TextBlock x:Name="StoredEmpty" Text="这里还没有记录" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource SecondaryBrush}"/></Grid>
  <StackPanel Grid.Row="2" Margin="0,12,0,0"><TextBlock x:Name="StoredError" TextWrapping="Wrap" Foreground="{DynamicResource DangerBrush}"/><Grid Margin="0,8,0,0"><TextBlock x:Name="StoredCount" VerticalAlignment="Center" Foreground="{DynamicResource SecondaryBrush}"/><Button x:Name="EmptyTrash" Content="清空回收站" HorizontalAlignment="Right"/></Grid></StackPanel>
 </Grid>
</Window>
'@)
    [void]$dialog.Resources.MergedDictionaries.Add($script:ThemeDictionary)
    $dialog.Owner = $script:Window
    $dialog.Title = if ($Mode -eq 'trash') { '回收站' } else { '归档记录' }
    $dialog.FindName('StoredTitle').Text = $dialog.Title
    $dialog.FindName('StoredDescription').Text = if ($Mode -eq 'trash') { '删除和清除的任务保存在这里，可恢复原来的状态。' } else { '已归档的完成记录，不计入当前清单进度。' }
    $dialog.Tag = @{ Mode = $Mode; List = $dialog.FindName('StoredList'); Count = $dialog.FindName('StoredCount'); Empty = $dialog.FindName('StoredEmpty'); Error = $dialog.FindName('StoredError'); Clear = $dialog.FindName('EmptyTrash') }
    $dialog.Tag.Clear.Style = $script:Window.FindResource('SettingsButtonStyle')
    $dialog.Tag.Clear.Visibility = if ($Mode -eq 'trash') { 'Visible' } else { 'Collapsed' }
    $dialog.Tag.Clear.Tag = $dialog
    $dialog.Tag.Clear.Add_Click({
        param($sender,$eventArgs)
        $dialog = $sender.Tag
        $answer = [System.Windows.MessageBox]::Show($dialog,'永久删除回收站中的所有任务？此操作无法撤销。','清空回收站','YesNo','Warning','No')
        if ($answer -eq 'Yes' -and $null -eq $script:LoadError) {
            $script:TrashedTasks.Clear(); $script:UndoPayload = $null
            Save-Tasks; Refresh-TaskList; Refresh-StoredTasksDialog $dialog
        }
    })
    Refresh-StoredTasksDialog $dialog
    [void]$dialog.ShowDialog()
}

function Get-TaskTitleBrush {
    param($Task)
    if ($script:Settings.PriorityEnabled -ne $false) {
        switch (Get-TaskPriority $Task) { 'high' { return 'PriorityHighBrush' }; 'low' { return 'PriorityLowBrush' } }
        return 'InkBrush'
    }
    if ($Task.IsCompleted) { return 'CompletedTextBrush' }
    return 'InkBrush'
}

function Update-ComposerFeatures {
    if (-not $script:UiReady) { return }
    $script:ComposerPriority.Visibility = if ($script:Settings.PriorityEnabled -ne $false) { 'Visible' } else { 'Collapsed' }
    $script:ComposerReminderButton.Visibility = if ($script:Settings.RemindersEnabled -ne $false) { 'Visible' } else { 'Collapsed' }
    $when = $script:ComposerReminderDraft.RemindAt
    $script:ComposerReminderButton.Content = if ($null -ne $when) { $when.ToString('HH:mm') + ' 提醒' } else { '设置提醒' }
    $script:ComposerReminderButton.ToolTip = if ($null -ne $when) { $when.ToString('yyyy-MM-dd HH:mm') + '，添加任务时一并保存' } else { '为新待办预先设置提醒时间' }
}

function Update-FeaturePreferences {
    if ($script:SuppressFeatureEvents) { return }
    Commit-ActiveEdit
    $script:Settings.PriorityEnabled = [bool]$script:PriorityFeatureToggle.IsChecked
    $script:Settings.RemindersEnabled = [bool]$script:RemindersFeatureToggle.IsChecked
    Save-Settings
    Update-ComposerFeatures
    Refresh-TaskList
}

function Confirm-EditOutside {
    param($Source)
    $ctx = $script:EditingContext
    if ($null -eq $ctx) { return }
    $node = $Source
    while ($null -ne $node) {
        if ($node -eq $ctx.EditHost) { return }
        if ($node -is [System.Windows.Media.Visual]) { $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node) }
        else { $node = [System.Windows.LogicalTreeHelper]::GetParent($node) }
    }
    Commit-ActiveEdit
}

function Get-TaskPriority {
    param($Task)
    if ($null -ne $Task -and $Task.Priority -in @('high','medium','low')) { return [string]$Task.Priority }
    return 'medium'
}

function Get-PriorityInfo {
    param([string]$Priority)
    switch ($Priority) {
        'high' { return @{ Label = '高'; Brush = 'PriorityHighBrush' } }
        'low' { return @{ Label = '低'; Brush = 'PriorityLowBrush' } }
        default { return @{ Label = '中'; Brush = 'PriorityMediumBrush' } }
    }
}

function Set-TaskPriority {
    param($Task, [string]$Priority)
    if ($null -ne $script:LoadError -or $null -eq $Task) { return }
    if ($Priority -notin @('high','medium','low')) { throw 'Invalid priority.' }
    Commit-ActiveEdit
    $oldPriority = Get-TaskPriority $Task
    if ($oldPriority -eq $Priority) { return }
    $Task | Add-Member -NotePropertyName Priority -NotePropertyValue $Priority -Force
    Save-Tasks
    Refresh-TaskList
    $script:UndoPayload = @{ Kind = 'priority'; Task = $Task; Priority = $oldPriority }
    Show-Toast -Message $(if ($script:LastTasksSaveSucceeded) { '优先级已更新' } else { '优先级尚未保存，请保留窗口' }) -CanUndo $true
}

function Initialize-PriorityButton {
    param($Button, $Task)
    $priority = if ($null -eq $Task) { $script:ComposerPriorityValue } else { Get-TaskPriority $Task }
    $info = Get-PriorityInfo $priority
    $Button.Style = $script:Window.FindResource('PriorityBadgeStyle')
    $Button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, $info.Brush.Replace('Brush','SurfaceBrush'))
    $Button.Content = $info.Label
    $Button.FontWeight = 'SemiBold'
    $Button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, $info.Brush)
    $Button.ToolTip = $(if ($null -eq $Task) { '新任务' } else { '任务' }) + '优先级：' + $info.Label + '（点击选择）'
    [System.Windows.Automation.AutomationProperties]::SetName($Button, $Button.ToolTip)
    $menu = [System.Windows.Controls.ContextMenu]::new()
    $menu.Style = $script:Window.FindResource('PriorityMenuStyle')
    $menu.MinWidth = 188
    $menu.Placement = 'Bottom'
    $menu.HorizontalOffset = -8
    $menu.VerticalOffset = 2
    $menu.Padding = [System.Windows.Thickness]::new(4)
    $menu.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, 'HairlineBrush')
    $menu.Tag = @{ Task = $Task; Button = $Button }
    $menu.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'SettingsCardBrush')
    $menu.Add_Opened({
        param($sender,$eventArgs)
        $sender.Resources.MergedDictionaries.Clear()
        [void]$sender.Resources.MergedDictionaries.Add($script:ThemeDictionary)
        foreach ($item in $sender.Items) {
            $tag = $item.Tag.Clone()
            $tag.Color = $script:Window.FindResource((Get-PriorityInfo $tag.Priority).Brush)
            $item.Tag = $tag
        }
    })
    foreach ($value in @('high','medium','low')) {
        $entry = Get-PriorityInfo $value
        $item = [System.Windows.Controls.MenuItem]::new()
        $item.Style = $script:Window.FindResource('PriorityMenuItemStyle')
        $item.Header = $entry.Label + '优先级'
        $item.IsCheckable = $true
        $item.IsChecked = $value -eq $priority
        $item.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'InkBrush')
        $item.Tag = @{ Task = $Task; Priority = $value; Button = $Button; Color = $script:Window.FindResource($entry.Brush) }
        $item.Add_Click({
            param($sender,$eventArgs)
            $selection = $sender.Tag
            if ($null -eq $selection.Task) {
                $script:ComposerPriorityValue = $selection.Priority
                Initialize-PriorityButton -Button $selection.Button -Task $null
            } else { Set-TaskPriority -Task $selection.Task -Priority $selection.Priority }
        })
        [void]$menu.Items.Add($item)
    }
    $Button.ContextMenu = $menu
    if ($Button.Tag -ne 'PriorityPickerInitialized') {
        $Button.Tag = 'PriorityPickerInitialized'
        $Button.Add_Click({
            param($sender,$eventArgs)
            $sender.ContextMenu.PlacementTarget = $sender
            $sender.ContextMenu.IsOpen = $true
        })
    }
}

function Set-TaskReminder {
    param($Task, $At)
    if ($null -eq $Task -or $null -ne $script:LoadError) { return }
    if ($null -ne $At -and ($At -le (Get-Date) -or [TimeZoneInfo]::Local.IsInvalidTime($At))) {
        throw '请选择有效的未来日期和时间。'
    }
    if ($Task.IsDraft) {
        $Task.RemindAt = $At
        Update-ComposerFeatures
        return $true
    }
    $Task | Add-Member -NotePropertyName RemindAt -NotePropertyValue $At -Force
    $Task | Add-Member -NotePropertyName ReminderNotified -NotePropertyValue $false -Force
    Save-Tasks
    Refresh-TaskList
    return $script:LastTasksSaveSucceeded
}

function Get-ReminderSelection {
    param($Dialog)
    $ctx = $Dialog.Tag
    if ($null -eq $ctx.Date.SelectedDate) { throw '请选择提醒日期。' }
    $hour = 0; $minute = 0
    if (-not [int]::TryParse($ctx.Hour.Text.Trim(), [ref]$hour) -or $hour -lt 0 -or $hour -gt 23) { throw '小时请填写 00–23。' }
    if (-not [int]::TryParse($ctx.Minute.Text.Trim(), [ref]$minute) -or $minute -lt 0 -or $minute -gt 59) { throw '分钟请填写 00–59。' }
    return $ctx.Date.SelectedDate.Date.AddHours($hour).AddMinutes($minute)
}

function Update-ReminderSummary {
    param($Dialog)
    if ($null -eq $Dialog -or $null -eq $Dialog.Tag) { return }
    $ctx = $Dialog.Tag
    $ctx.Error.Text = ''
    try {
        $at = Get-ReminderSelection $Dialog
        $dateLabel = if ($at.Date -eq (Get-Date).Date) { '今天' } elseif ($at.Date -eq (Get-Date).Date.AddDays(1)) { '明天' } else { $at.ToString('yyyy年M月d日') }
        $ctx.DateButton.Content = $dateLabel + '  ' + $at.ToString('M月d日') + '  ▾'
        if ($at -le (Get-Date) -or [TimeZoneInfo]::Local.IsInvalidTime($at)) { throw '这个时间已经过去或无效，请选择未来的时间。' }
        $minutes = [Math]::Ceiling(($at - (Get-Date)).TotalMinutes)
        $relative = if ($minutes -lt 60) { '约 {0} 分钟后' -f $minutes } elseif ($minutes -lt 1440) { '约 {0} 小时后' -f [Math]::Round($minutes/60,1) } else { '约 {0} 天后' -f [Math]::Round($minutes/1440,1) }
        $ctx.Summary.Text = '将在{0} {1} 提醒你（{2}）' -f $dateLabel,$at.ToString('HH:mm'),$relative
        $ctx.Save.IsEnabled = $true
    } catch {
        $ctx.Summary.Text = $_.Exception.Message
        $ctx.Save.IsEnabled = $false
    }
}

function Set-ReminderPreset {
    param($Dialog, [int]$Minutes)
    $at = if ($Minutes -eq -1) { (Get-Date).Date.AddDays(1).AddHours(9) } else { (Get-Date).AddMinutes($Minutes) }
    $ctx = $Dialog.Tag
    $ctx.Date.SelectedDate = $at.Date
    $ctx.Hour.Text = $at.ToString('HH')
    $ctx.Minute.Text = $at.ToString('mm')
    Update-ReminderSummary $Dialog
}

function Step-ReminderTime {
    param($Dialog, [string]$Field, [int]$Delta)
    $inputBox = $Dialog.Tag[$Field]
    $value = 0
    [void][int]::TryParse($inputBox.Text, [ref]$value)
    $limit = if ($Field -eq 'Hour') { 24 } else { 60 }
    $inputBox.Text = (($value + $Delta + $limit) % $limit).ToString('00')
    Update-ReminderSummary $Dialog
}

function Open-ReminderDialog {
    param($Task)
    if ($null -ne $script:LoadError) { return }
    Commit-ActiveEdit
    $dialog = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="时间提醒" Width="376" SizeToContent="Height" MaxHeight="620" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
 Background="{DynamicResource SettingsCardBrush}" Foreground="{DynamicResource InkBrush}" FontFamily="Microsoft YaHei UI, Segoe UI" FontSize="13">
 <ScrollViewer Background="{DynamicResource SettingsCardBrush}" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
 <StackPanel Margin="22">
  <TextBlock Text="什么时候提醒你？" FontSize="21" FontWeight="SemiBold"/>
  <TextBlock x:Name="ReminderTaskTitle" Foreground="{DynamicResource SecondaryBrush}" Margin="0,9,0,18" TextWrapping="Wrap" MaxHeight="42" TextTrimming="CharacterEllipsis"/>
  <UniformGrid Columns="2">
   <Button x:Name="Preset10" Content="10 分钟后" Margin="0,0,6,8"/>
   <Button x:Name="Preset30" Content="30 分钟后" Margin="6,0,0,8"/>
   <Button x:Name="Preset60" Content="1 小时后" Margin="0,0,6,0"/>
   <Button x:Name="PresetTomorrow" Content="明天 09:00" Margin="6,0,0,0"/>
  </UniformGrid>
  <TextBlock Text="或自定义日期和时间" Margin="0,20,0,9" Foreground="{DynamicResource SecondaryBrush}" FontSize="12"/>
  <Button x:Name="ReminderDateButton" HorizontalContentAlignment="Left"/>
  <Popup x:Name="ReminderCalendarPopup" Placement="Bottom" StaysOpen="False" AllowsTransparency="True">
   <Border BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1"><Calendar x:Name="ReminderDate"/></Border>
  </Popup>
  <Grid Margin="0,12,0,0">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="26"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
   <Border Background="{DynamicResource SettingsFieldBrush}" BorderBrush="{DynamicResource SettingsFieldBorderBrush}" BorderThickness="1" CornerRadius="8" Padding="8,4">
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="24"/></Grid.ColumnDefinitions>
     <StackPanel><TextBlock Text="时 · 00–23" FontSize="11" Foreground="{DynamicResource SecondaryBrush}"/><TextBox x:Name="ReminderHour" FontSize="22" MaxLength="2" Background="Transparent" BorderThickness="0" Padding="0" Foreground="{DynamicResource InkBrush}" CaretBrush="{DynamicResource AccentBrush}"/></StackPanel>
     <StackPanel Grid.Column="1" VerticalAlignment="Center"><Button x:Name="HourUp" Content="+"/><Button x:Name="HourDown" Content="−"/></StackPanel>
    </Grid>
   </Border>
   <TextBlock Grid.Column="1" Text=":" FontSize="24" HorizontalAlignment="Center" VerticalAlignment="Center"/>
   <Border Grid.Column="2" Background="{DynamicResource SettingsFieldBrush}" BorderBrush="{DynamicResource SettingsFieldBorderBrush}" BorderThickness="1" CornerRadius="8" Padding="8,4">
    <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="24"/></Grid.ColumnDefinitions>
     <StackPanel><TextBlock Text="分 · 00–59" FontSize="11" Foreground="{DynamicResource SecondaryBrush}"/><TextBox x:Name="ReminderMinute" FontSize="22" MaxLength="2" Background="Transparent" BorderThickness="0" Padding="0" Foreground="{DynamicResource InkBrush}" CaretBrush="{DynamicResource AccentBrush}"/></StackPanel>
     <StackPanel Grid.Column="1" VerticalAlignment="Center"><Button x:Name="MinuteUp" Content="+"/><Button x:Name="MinuteDown" Content="−"/></StackPanel>
    </Grid>
   </Border>
  </Grid>
  <Border Background="{DynamicResource AccentSoftBrush}" CornerRadius="8" Padding="10" Margin="0,14,0,0"><TextBlock x:Name="ReminderSummary" Foreground="{DynamicResource AccentBrush}" TextWrapping="Wrap" FontSize="12"/></Border>
  <TextBlock Margin="0,12,0,0" Text="应用打开时提醒，最小化也有效。关闭期间错过的提醒，会在下次打开时补发。" TextWrapping="Wrap" Foreground="{DynamicResource SecondaryBrush}" FontSize="11.5"/>
  <TextBlock x:Name="ReminderError" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource DangerBrush}"/>
  <Grid Margin="0,14,0,0">
   <Button x:Name="RemoveReminder" Content="移除提醒" HorizontalAlignment="Left"/>
   <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="CancelReminder" Content="取消" IsCancel="True" Margin="0,0,8,0"/><Button x:Name="SaveReminder" Content="设定提醒" IsDefault="True"/></StackPanel>
  </Grid>
 </StackPanel>
 </ScrollViewer>
</Window>
'@)
    [void]$dialog.Resources.MergedDictionaries.Add($script:ThemeDictionary)
    $dialog.Owner = $script:Window
    $dialog.MaxHeight = [Math]::Min(620, [System.Windows.SystemParameters]::WorkArea.Height - 32)
    $dialog.FindName('ReminderTaskTitle').Text = $Task.Title
    $ctx = @{ Task = $Task; Date = $dialog.FindName('ReminderDate'); Hour = $dialog.FindName('ReminderHour'); Minute = $dialog.FindName('ReminderMinute');
        DateButton = $dialog.FindName('ReminderDateButton'); Popup = $dialog.FindName('ReminderCalendarPopup'); Summary = $dialog.FindName('ReminderSummary'); Error = $dialog.FindName('ReminderError'); Save = $dialog.FindName('SaveReminder') }
    $dialog.Tag = $ctx
    $ctx.Popup.PlacementTarget = $ctx.DateButton
    $ctx.Date.DisplayDateStart = (Get-Date).Date
    $when = if ($null -ne $Task.RemindAt) { $Task.RemindAt } else { (Get-Date).AddMinutes(30) }
    $ctx.Date.SelectedDate = $when.Date
    $ctx.Date.DisplayDate = $when.Date
    $ctx.Hour.Text = $when.ToString('HH')
    $ctx.Minute.Text = $when.ToString('mm')
    foreach ($name in @('SaveReminder','RemoveReminder','CancelReminder','ReminderDateButton','Preset10','Preset30','Preset60','PresetTomorrow')) {
        $button = $dialog.FindName($name)
        $button.Style = $script:Window.FindResource('SettingsButtonStyle')
        $button.Height = 36
        $button.Tag = $dialog
    }
    $ctx.Save.BorderBrush = $script:Window.FindResource('AccentBrush')
    $dialog.FindName('RemoveReminder').Visibility = if ($null -ne $Task.RemindAt) { 'Visible' } else { 'Collapsed' }
    foreach ($preset in @(@('Preset10',10),@('Preset30',30),@('Preset60',60),@('PresetTomorrow',-1))) {
        $button = $dialog.FindName($preset[0]); $button.Tag = @{ Dialog = $dialog; Minutes = $preset[1] }
        $button.Add_Click({ param($sender,$eventArgs); Set-ReminderPreset -Dialog $sender.Tag.Dialog -Minutes $sender.Tag.Minutes })
    }
    foreach ($step in @(@('HourUp','Hour',1),@('HourDown','Hour',-1),@('MinuteUp','Minute',1),@('MinuteDown','Minute',-1))) {
        $button = $dialog.FindName($step[0]); $button.Style = $script:Window.FindResource('QuietTextButtonStyle'); $button.Height = 21
        [System.Windows.Automation.AutomationProperties]::SetName($button,
            ($(if ($step[1] -eq 'Hour') { '小时' } else { '分钟' }) + $(if ($step[2] -gt 0) { '增加一' } else { '减少一' })))
        $button.Tag = @{ Dialog = $dialog; Field = $step[1]; Delta = $step[2] }
        $button.Add_Click({ param($sender,$eventArgs); Step-ReminderTime $sender.Tag.Dialog $sender.Tag.Field $sender.Tag.Delta })
    }
    foreach ($field in @('Hour','Minute')) {
        $inputBox = $ctx[$field]; $inputBox.Tag = @{ Dialog = $dialog; Field = $field }
        $inputBox.Add_TextChanged({ param($sender,$eventArgs); Update-ReminderSummary $sender.Tag.Dialog })
        $inputBox.Add_PreviewKeyDown({
            param($sender,$eventArgs)
            if ($eventArgs.Key -in @('Up','Down')) { Step-ReminderTime $sender.Tag.Dialog $sender.Tag.Field $(if ($eventArgs.Key -eq 'Up') { 1 } else { -1 }); $eventArgs.Handled = $true }
        })
    }
    $ctx.DateButton.Add_Click({ param($sender,$eventArgs); $sender.Tag.Tag.Popup.IsOpen = $true })
    $ctx.Date.Tag = $dialog
    $ctx.Date.Add_SelectedDatesChanged({ param($sender,$eventArgs); $sender.Tag.Tag.Popup.IsOpen = $false; Update-ReminderSummary $sender.Tag })
    # Keep event handlers in the application's session state. GetNewClosure creates a
    # dynamic module that cannot resolve script-local commands when launched normally.
    $ctx.Save.Add_Click({
        param($sender,$eventArgs)
        $dialog = $sender.Tag; $ctx = $dialog.Tag
        try {
            $at = Get-ReminderSelection $dialog
            if (Set-TaskReminder -Task $ctx.Task -At $at) { $dialog.Close() } else { $ctx.Error.Text = '提醒尚未保存，请检查保存位置后重试。' }
        } catch { $ctx.Error.Text = '无法设定提醒，请检查日期和时间后重试。' }
    })
    $dialog.FindName('RemoveReminder').Add_Click({
        param($sender,$eventArgs)
        $dialog = $sender.Tag
        if (Set-TaskReminder -Task $dialog.Tag.Task -At $null) { $dialog.Close() } else { $dialog.Tag.Error.Text = '移除提醒尚未保存，请重试。' }
    })
    $dialog.Add_PreviewKeyDown({ param($sender,$eventArgs); if ($eventArgs.Key -eq 'Escape') { $sender.Close() } })
    Update-ReminderSummary $dialog
    [void]$dialog.ShowDialog()
}

function Get-DueReminders {
    param([datetime]$Now = (Get-Date))
    if ($script:Settings.RemindersEnabled -eq $false) { return @() }
    return @($script:ActiveTasks | Where-Object { $null -ne $_.RemindAt -and -not $_.ReminderNotified -and $_.RemindAt -le $Now })
}

function Show-ReminderNotification {
    param($Tasks)
    # A separate modeless window remains visible even when the main window is minimized.
    $notice = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="TodoDesk · 待办提醒" Width="360" SizeToContent="Height" MaxHeight="480" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Topmost="True"
 Background="{DynamicResource SettingsCardBrush}" Foreground="{DynamicResource InkBrush}" FontFamily="Microsoft YaHei UI, Segoe UI">
 <StackPanel Margin="22"><TextBlock Text="到时间了" FontSize="22" FontWeight="SemiBold"/><ScrollViewer MaxHeight="300" VerticalScrollBarVisibility="Auto" Margin="0,16"><TextBlock x:Name="NoticeText" TextWrapping="Wrap" FontSize="15"/></ScrollViewer><Button x:Name="DismissNotice" Content="知道了" HorizontalAlignment="Right"/></StackPanel>
</Window>
'@)
    [void]$notice.Resources.MergedDictionaries.Add($script:ThemeDictionary)
    $notice.FindName('NoticeText').Text = (@($Tasks | ForEach-Object { $_.Title }) -join ([Environment]::NewLine + [Environment]::NewLine))
    $notice.FindName('DismissNotice').Style = $script:Window.FindResource('SettingsButtonStyle')
    $notice.FindName('DismissNotice').Add_Click({ $notice.Close() }.GetNewClosure())
    $notice.Show()
    [System.Media.SystemSounds]::Exclamation.Play()
}

function Check-Reminders {
    if ($null -ne $script:LoadError) { return }
    $due = @(Get-DueReminders)
    if ($due.Count -eq 0) { return }
    Show-ReminderNotification -Tasks $due
    foreach ($task in $due) { $task.ReminderNotified = $true }
    Save-Tasks
    if ($null -eq $script:EditingContext) { Refresh-TaskList }
}

function Update-StorageStatus {
    if (-not $script:UiReady) { return }
    $script:StorageStatusText.Text = switch ($script:PersistenceState) {
        'saved' { '数据已保存到本机' }
        'saving' { '正在保存到本机…' }
        'error' { '保存失败，更改仍在窗口中' }
        'readError' { '读取失败，已保护原文件' }
        default { '尚无待办，添加后自动保存' }
    }
    $script:StorageStatusText.ToolTip = $script:DataFilePath
    $brush = if ($script:PersistenceState -in @('error', 'readError')) { 'DangerBrush' } else { 'SecondaryBrush' }
    $script:StorageStatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $brush)
    $dotBrush = if ($script:PersistenceState -eq 'saved') { 'AccentBrush' } else { $brush }
    $script:StorageStatusDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $dotBrush)
    $canEdit = $null -eq $script:LoadError
    $script:NewTaskInput.IsEnabled = $canEdit
    $script:ActiveList.IsEnabled = $canEdit
    $script:CompletedList.IsEnabled = $canEdit
    $script:ClearCompletedButton.IsEnabled = $canEdit
    $script:ArchiveCompletedButton.IsEnabled = $canEdit
    $script:ChangeDataFolderButton.IsEnabled = $canEdit -and $null -eq $script:SettingsReadError
    $script:ResetDataFolderButton.IsEnabled = $canEdit -and $null -eq $script:SettingsReadError -and -not (
        Test-SameFolder -First $script:DataDirectory -Second $script:DefaultDataDirectory)
    Update-ComposerState
}

function Save-Tasks {
    $script:LastTasksSaveSucceeded = $false
    if ($null -ne $script:LoadError) {
        $script:PersistenceState = 'readError'
        Update-StorageStatus
        return
    }
    $script:TasksDirty = $true
    $script:PersistenceState = 'saving'
    Update-StorageStatus
    try {
        [void][System.IO.Directory]::CreateDirectory($script:DataDirectory)

        $items = @()
        foreach ($task in @($script:ActiveTasks)) {
            $items += [pscustomobject][ordered]@{
                id = $task.Id
                title = $task.Title
                remindAt = $(if ($null -ne $task.RemindAt) { Get-UnixMilliseconds -Value $task.RemindAt } else { $null })
                reminderNotified = [bool]$task.ReminderNotified
                priority = Get-TaskPriority $task
                completed = $false
                createdAt = Get-UnixMilliseconds -Value $task.CreatedAt
                completedAt = $null
            }
        }
        foreach ($task in @($script:CompletedTasks)) {
            $completedAt = $task.CompletedAt
            if ($null -eq $completedAt) {
                $completedAt = $task.CreatedAt
            }
            $items += [pscustomobject][ordered]@{
                id = $task.Id
                title = $task.Title
                remindAt = $(if ($null -ne $task.RemindAt) { Get-UnixMilliseconds -Value $task.RemindAt } else { $null })
                reminderNotified = [bool]$task.ReminderNotified
                priority = Get-TaskPriority $task
                completed = $true
                createdAt = Get-UnixMilliseconds -Value $task.CreatedAt
                completedAt = Get-UnixMilliseconds -Value $completedAt
            }
        }

        $state = [pscustomobject][ordered]@{
            version = 1
            items = @($items)
            archive = @($script:ArchivedTasks | ForEach-Object { ConvertTo-StoredTask $_ })
            trash = @($script:TrashedTasks | ForEach-Object { ConvertTo-StoredTask $_ })
        }
        $json = ConvertTo-Json -InputObject $state -Depth 5

        $temporaryPath = Join-Path $script:DataDirectory (
            'todos.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText(
            $temporaryPath,
            $json,
            (New-Object System.Text.UTF8Encoding -ArgumentList $false))

        if ([System.IO.File]::Exists($script:DataFilePath)) {
            [System.IO.File]::Replace(
                $temporaryPath,
                $script:DataFilePath,
                $script:DataFilePath + '.bak',
                $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $script:DataFilePath)
        }

        $script:LastTasksSaveSucceeded = $true
        $script:TasksDirty = $false
        $script:PersistenceState = 'saved'
        Update-StorageStatus
    }
    catch {
        $script:LastTasksSaveSucceeded = $false
        $script:PersistenceState = 'error'
        Update-StorageStatus
        if ($script:UiReady) {
            Show-Toast -Message '无法保存到本机，请检查磁盘空间。' -Warning $true -Seconds 6
        }
    }
}

# ------------------------------------------------------------------ ui setup

function Get-NormalizedFolderPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Empty folder path.'
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path.Trim())
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $root.Length) {
        $trimChars = [char[]]@([char]'\', [char]'/')
        $fullPath = $fullPath.TrimEnd($trimChars)
    }
    return $fullPath
}

function Test-SameFolder {
    param([string]$First, [string]$Second)

    if ([string]::IsNullOrWhiteSpace($First) -or
        [string]::IsNullOrWhiteSpace($Second)) {
        return $false
    }

    try {
        $a = Get-NormalizedFolderPath -Path $First
        $b = Get-NormalizedFolderPath -Path $Second
        return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Load-Settings {
    $script:SettingsReadError = $null
    $settings = @{
        PriorityEnabled = $true
        RemindersEnabled = $true
        Theme = 'system'
        DataDirectory = $null
    }

    if (Test-Path -LiteralPath $script:SettingsFilePath) {
        try {
            $raw = [System.IO.File]::ReadAllText(
                $script:SettingsFilePath,
                [System.Text.Encoding]::UTF8)

            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $saved = $raw | ConvertFrom-Json
                if ($saved.priorityEnabled -is [bool]) { $settings.PriorityEnabled = $saved.priorityEnabled }
                if ($saved.remindersEnabled -is [bool]) { $settings.RemindersEnabled = $saved.remindersEnabled }
                $theme = [string]$saved.theme
                if ($theme -in @('system', 'light', 'dark')) {
                    $settings.Theme = $theme
                }

                $dataPath = [string]$saved.dataDirectory
                if (-not [string]::IsNullOrWhiteSpace($dataPath)) {
                    try {
                        $settings.DataDirectory = Get-NormalizedFolderPath -Path $dataPath
                    }
                    catch {
                        $script:SettingsError = '保存位置设置无效，已临时使用默认位置。'
                        $script:SettingsReadError = $script:SettingsError
                    }
                }
            }
        }
        catch {
            $script:SettingsError = '设置文件读取失败，已使用默认设置。'
            $script:SettingsReadError = $script:SettingsError
            Write-AppLog -Message ('Settings load failed: ' + $_.Exception.ToString())
        }
    }

    $script:Settings = $settings
    $script:ThemePreference = $settings.Theme

    if (-not [string]::IsNullOrWhiteSpace($settings.DataDirectory)) {
        $script:DataDirectory = $settings.DataDirectory
    }
    else {
        $script:DataDirectory = $script:DefaultDataDirectory
    }
    $script:DataFilePath = Join-Path $script:DataDirectory 'todos.json'
}

function Save-Settings {
    if ($null -ne $script:SettingsReadError) {
        $script:LastSettingsSaveSucceeded = $false
        if ($script:UiReady) { Show-Toast -Message '原设置读取失败，外观仅本次生效；原文件未改动。' -Warning $true }
        return
    }
    try {
        [void][System.IO.Directory]::CreateDirectory($script:ConfigDirectory)

        $customDataDirectory = $null
        if (-not (Test-SameFolder -First $script:DataDirectory -Second $script:DefaultDataDirectory)) {
            $customDataDirectory = $script:DataDirectory
        }

        $state = [pscustomobject][ordered]@{
            priorityEnabled = [bool]$script:Settings.PriorityEnabled
            remindersEnabled = [bool]$script:Settings.RemindersEnabled
            theme = [string]$script:Settings.Theme
            dataDirectory = $customDataDirectory
        }
        $json = ConvertTo-Json -InputObject $state -Depth 3

        $temporaryPath = Join-Path $script:ConfigDirectory (
            'settings.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText(
            $temporaryPath,
            $json,
            (New-Object System.Text.UTF8Encoding -ArgumentList $false))

        if ([System.IO.File]::Exists($script:SettingsFilePath)) {
            [System.IO.File]::Replace(
                $temporaryPath,
                $script:SettingsFilePath,
                $script:SettingsFilePath + '.bak',
                $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $script:SettingsFilePath)
        }

        $script:SettingsError = $null
        $script:LastSettingsSaveSucceeded = $true
    }
    catch {
        $script:SettingsError = '设置无法保存到本机。'
        $script:LastSettingsSaveSucceeded = $false
        Write-AppLog -Message ('Settings save failed: ' + $_.Exception.ToString())
        if ($script:UiReady) {
            Show-Toast -Message '设置无法保存到本机，请检查磁盘空间。' -Warning $true -Seconds 6
        }
    }
}

function Get-SystemThemeName {
    try {
        $personalize = Get-ItemProperty `
            -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
            -Name 'AppsUseLightTheme' `
            -ErrorAction Stop

        if ([int]$personalize.AppsUseLightTheme -eq 0) {
            return 'dark'
        }
    }
    catch {
    }
    return 'light'
}

function Get-EffectiveThemeName {
    if ($script:Settings.Theme -eq 'light' -or $script:Settings.Theme -eq 'dark') {
        return $script:Settings.Theme
    }
    return Get-SystemThemeName
}

function Load-ThemeDictionary {
    param([string]$Name)

    $themePath = Join-Path (Join-Path $script:AppRoot 'themes') ($Name + '.xaml')
    $reader = [System.Xml.XmlReader]::Create($themePath)
    try {
        return [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }
}

function Update-ThemeBrushCache {
    if ($null -eq $script:Window) { return }

    try {
        $script:RowHoverBrush = $script:Window.FindResource('RowHoverBrush')
        $script:EditRowBrush = $script:Window.FindResource('EditRowBrush')
        $script:AccentBrush = $script:Window.FindResource('AccentBrush')
        $script:SecondaryBrush = $script:Window.FindResource('SecondaryBrush')
    }
    catch {
        Write-AppLog -Message ('Theme brush cache failed: ' + $_.Exception.ToString())
    }
}

function Initialize-ThemePalette {
    param($Window, [string]$ThemeName)

    $dictionary = Load-ThemeDictionary -Name $ThemeName
    [void]$Window.Resources.MergedDictionaries.Add($dictionary)
    $script:Window = $Window
    $script:ThemeDictionary = $dictionary
    $script:EffectiveTheme = $ThemeName
    Update-ThemeBrushCache
}

function Apply-NativeTheme {
    if (-not $script:HasNativeHelpers -or $null -eq $script:Window) { return }

    try {
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($script:Window)
        $handle = $helper.Handle
        if ($handle -eq [IntPtr]::Zero) { return }

        $darkMode = if ($script:EffectiveTheme -eq 'dark') { 1 } else { 0 }
        [void][DaiBanNative]::DwmSetWindowAttribute($handle, 20, [ref]$darkMode, 4)

        $corner = 2
        [void][DaiBanNative]::DwmSetWindowAttribute($handle, 33, [ref]$corner, 4)

        $color = $script:Window.FindResource('HairlineBrush').Color
        $borderColor = [int]$color.R -bor ([int]$color.G -shl 8) -bor ([int]$color.B -shl 16)
        [void][DaiBanNative]::DwmSetWindowAttribute($handle, 34, [ref]$borderColor, 4)
    }
    catch {
    }
}

function Set-EffectiveTheme {
    param([string]$ThemeName)

    if ($ThemeName -notin @('light', 'dark')) {
        $ThemeName = 'light'
    }

    if ($ThemeName -eq $script:EffectiveTheme -and
        $null -ne $script:ThemeDictionary) {
        Apply-NativeTheme
        return
    }

    $dictionary = Load-ThemeDictionary -Name $ThemeName
    if ($null -ne $script:ThemeDictionary) {
        [void]$script:Window.Resources.MergedDictionaries.Remove($script:ThemeDictionary)
    }
    [void]$script:Window.Resources.MergedDictionaries.Add($dictionary)
    $script:ThemeDictionary = $dictionary
    $script:EffectiveTheme = $ThemeName
    Update-ThemeBrushCache
    Apply-NativeTheme
}

function Update-ThemeControls {
    if ($null -eq $script:ThemeSystemButton) { return }

    $script:SuppressThemeEvents = $true
    try {
        $script:ThemeSystemButton.IsChecked = ($script:Settings.Theme -eq 'system')
        $script:ThemeLightButton.IsChecked = ($script:Settings.Theme -eq 'light')
        $script:ThemeDarkButton.IsChecked = ($script:Settings.Theme -eq 'dark')
    }
    finally {
        $script:SuppressThemeEvents = $false
    }
}

function Update-ThemeWatcher {
    if ($null -eq $script:ThemeWatchTimer) {
        $script:ThemeWatchTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:ThemeWatchTimer.Interval = [TimeSpan]::FromSeconds(2)
        $script:ThemeWatchTimer.Add_Tick({
            if ($script:Settings.Theme -ne 'system') { return }

            $effective = Get-SystemThemeName
            if ($effective -ne $script:EffectiveTheme) {
                Set-EffectiveTheme -ThemeName $effective
            }
        })
    }

    if ($script:Settings.Theme -eq 'system') {
        $script:ThemeWatchTimer.Start()
    }
    else {
        $script:ThemeWatchTimer.Stop()
    }
}

function Set-ThemePreference {
    param([string]$Preference)

    if ($Preference -notin @('system', 'light', 'dark')) {
        return
    }

    $script:Settings.Theme = $Preference
    $script:ThemePreference = $Preference

    $effective = if ($Preference -eq 'system') {
        Get-SystemThemeName
    }
    else {
        $Preference
    }

    if ($effective -ne $script:EffectiveTheme) {
        Set-EffectiveTheme -ThemeName $effective
    }

    Update-ThemeControls
    Update-ThemeWatcher
    Save-Settings
}

function Update-SettingsUi {
    if ($null -eq $script:DataPathText) { return }

    $script:DataPathText.Text = $script:DataDirectory
    $script:DataPathText.ToolTip = $script:DataFilePath
    Update-StorageStatus
    $script:SettingsVersionText.Text = 'TodoDesk ' + $script:AppVersion
    Update-ThemeControls
    $script:SuppressFeatureEvents = $true
    $script:PriorityFeatureToggle.IsChecked = $script:Settings.PriorityEnabled -ne $false
    $script:RemindersFeatureToggle.IsChecked = $script:Settings.RemindersEnabled -ne $false
    $script:SuppressFeatureEvents = $false
    Update-ComposerFeatures
}

# ------------------------------------------------------------------ ui setup

function Load-Interface {
    $xamlPath = Join-Path $script:AppRoot 'ui.xaml'
    $reader = [System.Xml.XmlReader]::Create($xamlPath)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }
    return $window
}

function Set-WindowIcon {
    param($Window)

    try {
        $iconPath = Join-Path $script:AppRoot 'app.ico'
        if (Test-Path -LiteralPath $iconPath) {
            $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
                (New-Object System.Uri -ArgumentList $iconPath))
        }
    }
    catch {
        # The taskbar icon is cosmetic.
    }
}

function Enable-WindowChrome {
    param($Window)

    $chrome = New-Object System.Windows.Shell.WindowChrome
    $chrome.CaptionHeight = 48
    $chrome.ResizeBorderThickness = New-Object System.Windows.Thickness -ArgumentList 6
    $chrome.GlassFrameThickness = New-Object System.Windows.Thickness -ArgumentList 0
    $chrome.CornerRadius = New-Object System.Windows.CornerRadius -ArgumentList 0
    $chrome.UseAeroCaptionButtons = $false
    [System.Windows.Shell.WindowChrome]::SetWindowChrome($Window, $chrome)
    $Window.Add_SourceInitialized({
        if (-not $script:HasNativeHelpers) { return }
        $handle = [System.Windows.Interop.WindowInteropHelper]::new($script:Window).Handle
        $script:BoundsHook = [System.Windows.Interop.HwndSourceHook]{
            param([IntPtr]$hwnd, [int]$message, [IntPtr]$wparam, [IntPtr]$lparam, [ref]$handled)
            if ($message -eq 0x24) {
                $handled.Value = [DaiBanNative]::ApplyWorkArea($hwnd, $lparam,
                    $script:Window.MinWidth, $script:Window.MinHeight)
            }
            return [IntPtr]::Zero
        }
        [System.Windows.Interop.HwndSource]::FromHwnd($handle).AddHook($script:BoundsHook)
    })
}

function Initialize-Interface {
    param($Window)

    $script:Window = $Window
    foreach ($name in @('LicenseInfoButton','ArchiveCompletedButton','TrashSettingsButton','ArchiveSettingsButton','MainContent','ComposerPriority','ComposerReminderButton','PriorityFeatureToggle','RemindersFeatureToggle','ComposerHost','TaskArea','ListCard')) {
        Set-Variable -Scope Script -Name $name -Value $Window.FindName($name)
    }
    foreach ($name in @('FilterAll','FilterActive','FilterCompleted','ListCountText','TaskProgress','ProgressText','EmptyTitle','EmptyDescription','StorageStatusText','StorageStatusDot','MaximizeButton','MaximizeGlyph','CompletedToggleButton')) {
        Set-Variable -Scope Script -Name $name -Value $Window.FindName($name)
    }
    $script:TitleBar = $Window.FindName('TitleBar')
    $script:DateText = $Window.FindName('DateText')
    $script:StatusPanel = $Window.FindName('StatusPanel')
    $script:StatusDot = $Window.FindName('StatusDot')
    $script:StatusText = $Window.FindName('StatusText')
    $script:Composer = $Window.FindName('Composer')
    $script:NewTaskInput = $Window.FindName('NewTaskInput')
    $script:ComposerPlaceholder = $Window.FindName('ComposerPlaceholder')
    $script:AddButton = $Window.FindName('AddButton')
    $script:TaskScroll = $Window.FindName('TaskScroll')
    $script:ActiveList = $Window.FindName('ActiveList')
    $script:CompletedSection = $Window.FindName('CompletedSection')
    $script:CompletedHeaderText = $Window.FindName('CompletedHeaderText')
    $script:CompletedList = $Window.FindName('CompletedList')
    $script:ClearCompletedButton = $Window.FindName('ClearCompletedButton')
    $script:EmptyState = $Window.FindName('EmptyState')
    $script:SettingsButton = $Window.FindName('SettingsButton')
    $script:MinimizeButton = $Window.FindName('MinimizeButton')
    $script:CloseButton = $Window.FindName('CloseButton')
    $script:SettingsOverlay = $Window.FindName('SettingsOverlay')
    $script:SettingsScrim = $Window.FindName('SettingsScrim')
    $script:SettingsCardRoot = $Window.FindName('SettingsCardRoot')
    $script:SettingsCloseButton = $Window.FindName('SettingsCloseButton')
    $script:ThemeSystemButton = $Window.FindName('ThemeSystemButton')
    $script:ThemeLightButton = $Window.FindName('ThemeLightButton')
    $script:ThemeDarkButton = $Window.FindName('ThemeDarkButton')
    $script:DataPathText = $Window.FindName('DataPathText')
    $script:ChangeDataFolderButton = $Window.FindName('ChangeDataFolderButton')
    $script:ResetDataFolderButton = $Window.FindName('ResetDataFolderButton')
    $script:SettingsVersionText = $Window.FindName('SettingsVersionText')
    $script:SettingsCardTransform = $script:SettingsCardRoot.RenderTransform
    $script:Toast = $Window.FindName('Toast')
    $script:ToastText = $Window.FindName('ToastText')
    $script:ToastUndoButton = $Window.FindName('ToastUndoButton')
    $script:ToastTransform = $script:Toast.RenderTransform

    $script:RowHoverBrush = $Window.FindResource('RowHoverBrush')
    $script:EditRowBrush = $Window.FindResource('EditRowBrush')
    $script:AccentBrush = $Window.FindResource('AccentBrush')
    $script:SecondaryBrush = $Window.FindResource('SecondaryBrush')
    $script:TaskTitleStyle = $Window.FindResource('TaskTitleStyle')
    $script:TaskCheckStyle = $Window.FindResource('TaskCheckButtonStyle')
    $script:InlineEditStyle = $Window.FindResource('InlineEditBoxStyle')
    $script:RowIconStyle = $Window.FindResource('RowIconButtonStyle')
    $script:DeleteIconStyle = $Window.FindResource('DeleteRowIconButtonStyle')

    Set-WindowIcon -Window $Window
    Enable-WindowChrome -Window $Window
    if ($env:DAIBAN_PREVIEW -eq '1') {
        $Window.Title = 'TodoDesk · 本地预览'
        $script:StorageStatusText.ToolTip = $script:DataFilePath
    }
    $script:UiReady = $true
    Update-ResponsiveLayout -Width $Window.Width -Height $Window.Height
    Update-StorageStatus
}

function Update-ResponsiveLayout {
    param([double]$Width, [double]$Height)
    if (-not $script:UiReady) { return }
    $script:SettingsCardRoot.MaxHeight = [Math]::Max(200, $Height - 32)
    $compact = $Width -lt 600 -or $Height -lt 560
    $script:MainContent.Margin = if ($compact) { [System.Windows.Thickness]::new(16,12,16,12) } else { [System.Windows.Thickness]::new(30,26,30,24) }
    $script:ComposerHost.Height = if ($compact) { 46 } else { 56 }
    $script:ComposerHost.Margin = [System.Windows.Thickness]::new(0,$(if ($compact) { 14 } else { 26 }),0,0)
    $script:TaskArea.Margin = [System.Windows.Thickness]::new(0,$(if ($compact) { 14 } else { 22 }),0,0)
    $script:TaskArea.RowDefinitions[0].Height = [System.Windows.GridLength]::Auto
    $script:TaskArea.RowDefinitions[2].Height = [System.Windows.GridLength]::new($(if ($compact) { 38 } else { 45 }))
    $script:ListCard.Padding = [System.Windows.Thickness]::new($(if ($compact) { 8 } else { 12 }))
}

function Update-Date {
    $now = Get-Date
    $script:DateText.Text = '{0} 月 {1} 日 · {2}' -f `
        $now.Month,
        $now.Day,
        $now.ToString('dddd', $script:ChineseCulture)
}

function Update-ComposerState {
    $hasText = -not [string]::IsNullOrWhiteSpace($script:NewTaskInput.Text)
    $script:ComposerPlaceholder.Visibility = if ($hasText) {
        [System.Windows.Visibility]::Collapsed
    } else {
        [System.Windows.Visibility]::Visible
    }
    $script:AddButton.IsEnabled = $hasText -and $null -eq $script:LoadError
    $script:AddButton.Opacity = if ($script:AddButton.IsEnabled) { 1.0 } else { 0.65 }
}

# ------------------------------------------------------------ task list view

function New-IconPath {
    param([string]$Data)

    $path = New-Object System.Windows.Shapes.Path
    $path.Data = [System.Windows.Media.Geometry]::Parse($Data)
    $path.Width = 14
    $path.Height = 14
    $path.Stretch = [System.Windows.Media.Stretch]::Uniform
    $path.Fill = [System.Windows.Media.Brushes]::Transparent
    $path.StrokeThickness = 1.15
    $path.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
    $path.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
    $path.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round
    return $path
}

function Add-IconBinding {
    param($Icon, $Owner)

    $binding = New-Object System.Windows.Data.Binding -ArgumentList 'Foreground'
    $source = New-Object System.Windows.Data.RelativeSource
    $source.Mode = [System.Windows.Data.RelativeSourceMode]::FindAncestor
    $source.AncestorType = [System.Windows.Controls.Button]
    $binding.RelativeSource = $source
    [System.Windows.Data.BindingOperations]::SetBinding(
        $Icon,
        [System.Windows.Shapes.Shape]::StrokeProperty,
        $binding) | Out-Null
}

function New-RowActionButton {
    param(
        [string]$Geometry,
        [string]$ToolTip,
        $Style,
        $Context
    )

    $button = New-Object System.Windows.Controls.Button
    $button.Style = $Style
    $button.Content = New-IconPath -Data $Geometry
    $button.ToolTip = $ToolTip
    $button.Tag = $Context
    Add-IconBinding -Icon $button.Content -Owner $button
    return $button
}

function New-TaskRow {
    param($Task)

    $row = New-Object System.Windows.Controls.Border
    $row.Height = 48
    $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 2)
    $row.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $row.Background = $script:TransparentBrush
    $row.DataContext = $Task

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = [System.Windows.Thickness]::new(10, 0, 6, 0)

    foreach ($width in @(30, '*', 'Auto')) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -eq '*') {
            $column.Width = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
        }
        elseif ($width -eq 'Auto') {
            $column.Width = [System.Windows.GridLength]::Auto
        }
        else {
            $column.Width = New-Object System.Windows.GridLength -ArgumentList ([double]$width)
        }
        [void]$grid.ColumnDefinitions.Add($column)
    }

    $check = New-Object System.Windows.Controls.Button
    $check.Style = $script:TaskCheckStyle
    $check.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $check.DataContext = $Task
    $check.ToolTip = if ($Task.IsCompleted) { '标记为未完成' } else { '标记完成' }
    [System.Windows.Controls.Grid]::SetColumn($check, 0)
    [void]$grid.Children.Add($check)

    $textHost = New-Object System.Windows.Controls.Grid
    $textHost.Margin = [System.Windows.Thickness]::new(2, 0, 10, 0)
    $textColumn = [System.Windows.Controls.ColumnDefinition]::new()
    $textColumn.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    [void]$textHost.ColumnDefinitions.Add($textColumn)
    $priorityColumn = [System.Windows.Controls.ColumnDefinition]::new()
    $priorityColumn.Width = [System.Windows.GridLength]::Auto
    [void]$textHost.ColumnDefinitions.Add($priorityColumn)
    [System.Windows.Controls.Grid]::SetColumn($textHost, 1)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = [string]$Task.Title
    $title.Style = $script:TaskTitleStyle
    $title.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, (Get-TaskTitleBrush $Task))
    $title.DataContext = $Task
    $title.ToolTip = [string]$Task.Title + [Environment]::NewLine + '双击编辑'
    if ($script:Settings.PriorityEnabled -ne $false) {
        $title.ToolTip += [Environment]::NewLine + '优先级：' + (Get-PriorityInfo (Get-TaskPriority $Task)).Label
    }
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($title, 900)
    $title.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if ($eventArgs.ClickCount -eq 2) {
            Start-EditTask -Context $sender.Tag
            $eventArgs.Handled = $true
        }
    })
    [System.Windows.Controls.Grid]::SetColumnSpan($title, 2)
    [void]$textHost.Children.Add($title)
    $reminderLabel = $null
    if ($script:Settings.RemindersEnabled -ne $false -and $null -ne $Task.RemindAt -and -not $Task.IsCompleted) {
        $title.Margin = [System.Windows.Thickness]::new(0,0,0,16)
        $reminderLabel = [System.Windows.Controls.TextBlock]::new()
        $reminderLabel.Text = '提醒 · ' + $Task.RemindAt.ToString('MM-dd HH:mm')
        $reminderLabel.FontSize = 11.5
        $reminderLabel.VerticalAlignment = 'Bottom'
        $reminderLabel.Margin = [System.Windows.Thickness]::new(0,0,0,5)
        $reminderLabel.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryBrush')
        $reminderLabel.IsHitTestVisible = $false
        [System.Windows.Controls.Grid]::SetColumnSpan($reminderLabel, 2)
        [void]$textHost.Children.Add($reminderLabel)
    }

    $editor = New-Object System.Windows.Controls.TextBox
    $editor.Style = $script:InlineEditStyle
    $editor.MaxLength = 200
    $editor.Visibility = [System.Windows.Visibility]::Collapsed
    $editor.Text = [string]$Task.Title
    [void]$textHost.Children.Add($editor)
    [void]$grid.Children.Add($textHost)

    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $actions.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $actions.Opacity = 1
    $actions.IsHitTestVisible = $true
    [System.Windows.Controls.Grid]::SetColumn($actions, 2)

    $editButton = New-RowActionButton `
        -Geometry 'M 2.5,12.7 L 3.4,9.2 L 10.8,1.8 C 11.3,1.3 12.1,1.3 12.6,1.8 L 14.2,3.4 C 14.7,3.9 14.7,4.7 14.2,5.2 L 6.8,12.6 Z M 2.5,12.7 L 6.3,13.5 M 9.8,2.8 L 13.2,6.2' `
        -ToolTip '编辑' `
        -Style $script:RowIconStyle `
        -Context $null
    $editButton.Margin = [System.Windows.Thickness]::new(1, 0, 1, 0)
    $editButton.Style = $script:Window.FindResource('QuietRowActionStyle')

    $deleteButton = New-RowActionButton `
        -Geometry 'M 2,4 L 14,4 M 6,4 L 6,2.3 C 6,1.9 6.3,1.6 6.7,1.6 L 9.3,1.6 C 9.7,1.6 10,1.9 10,2.3 L 10,4 M 3.4,4 L 4.4,13.8 C 4.5,14.4 4.9,14.8 5.5,14.8 L 10.5,14.8 C 11.1,14.8 11.5,14.4 11.6,13.8 L 12.6,4 M 6.1,6.8 L 6.45,12 M 9.9,6.8 L 9.55,12' `
        -ToolTip '删除' `
        -Style $script:DeleteIconStyle `
        -Context $null
    $deleteButton.Margin = [System.Windows.Thickness]::new(1, 0, 0, 0)
    $deleteButton.Style = $script:Window.FindResource('QuietDeleteActionStyle')

    $reminderButton = New-RowActionButton -Geometry 'M 8,1 A 7,7 0 1 1 7.99,1 M 8,4 L 8,8 L 11,10' -ToolTip '设置时间提醒' -Style $script:RowIconStyle -Context $null
    $reminderButton.Style = $script:Window.FindResource('QuietRowActionStyle')
    if ($script:Settings.RemindersEnabled -eq $false) { $reminderButton.Visibility = 'Collapsed' }
    $reminderButton.Tag = $Task
    $reminderButton.Add_Click({ param($sender, $eventArgs); Open-ReminderDialog -Task $sender.Tag })
    [System.Windows.Automation.AutomationProperties]::SetName($reminderButton, '设置时间提醒')
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($reminderButton, 'Reminder_' + [string]$Task.Id)
    if ($null -ne $Task.RemindAt) {
        $reminderButton.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'AccentBrush')
        $reminderButton.ToolTip = '提醒：' + $Task.RemindAt.ToString('yyyy-MM-dd HH:mm')
        $title.ToolTip += [Environment]::NewLine + $reminderButton.ToolTip
    }
    # Keep the clock discoverable without taking width away from the task title.
    # Visibility follows pointer or keyboard focus via QuietRowActionStyle.
    [void]$actions.Children.Add($reminderButton)
    $priorityButton = [System.Windows.Controls.Button]::new()
    $priorityButton.Style = $script:RowIconStyle
    Initialize-PriorityButton -Button $priorityButton -Task $Task
    $priorityButton.Visibility = 'Collapsed'
    [System.Windows.Controls.Grid]::SetColumn($priorityButton, 1)
    [void]$textHost.Children.Add($priorityButton)
    [void]$actions.Children.Add($editButton)
    [void]$actions.Children.Add($deleteButton)
    [void]$grid.Children.Add($actions)

    [System.Windows.Automation.AutomationProperties]::SetName($check, '切换完成状态')
    [System.Windows.Automation.AutomationProperties]::SetHelpText($check, [string]$Task.Title)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($check, 'Check_' + [string]$Task.Id)
    [System.Windows.Automation.AutomationProperties]::SetName($editor, '编辑待办内容')
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($editor, 'Editor_' + [string]$Task.Id)
    [System.Windows.Automation.AutomationProperties]::SetName($editButton, '编辑待办')
    [System.Windows.Automation.AutomationProperties]::SetHelpText($editButton, [string]$Task.Title)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($editButton, 'Edit_' + [string]$Task.Id)
    [System.Windows.Automation.AutomationProperties]::SetName($deleteButton, '删除待办')
    [System.Windows.Automation.AutomationProperties]::SetHelpText($deleteButton, [string]$Task.Title)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($deleteButton, 'Delete_' + [string]$Task.Id)

    $context = @{
        Task = $Task
        Row = $row
        Check = $check
        Title = $title
        Editor = $editor
        EditHost = $textHost
        PriorityButton = $priorityButton
        ReminderLabel = $reminderLabel
        Actions = $actions
        EditButton = $editButton
        DeleteButton = $deleteButton
        IsEditing = $false
    }

    $check.Tag = $context
    $title.Tag = $context
    $editor.Tag = $context
    $editButton.Tag = $context
    $deleteButton.Tag = $context
    $row.Tag = $context

    $check.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx) { return }
        if ($ctx.IsEditing) {
            Complete-Edit -Context $ctx -ReturnFocus $false
        }
        Toggle-Task -Task $ctx.Task
    })

    $editButton.Add_Click({
        param($sender, $eventArgs)
        Start-EditTask -Context $sender.Tag
    })

    $deleteButton.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx) { return }
        Remove-Task -Task $ctx.Task
    })

    $editor.Add_KeyDown({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx) { return }

        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            Complete-Edit -Context $ctx -ReturnFocus $true
            $eventArgs.Handled = $true
        }
        elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            Cancel-Edit -Context $ctx -ReturnFocus $true
            $eventArgs.Handled = $true
        }
    })

    $editor.Add_LostKeyboardFocus({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        [void]$script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ContextIdle, [Action]{
            $ctx = $script:EditingContext
            if ($null -ne $ctx -and $ctx.IsEditing -and -not $ctx.EditHost.IsKeyboardFocusWithin -and -not $ctx.PriorityButton.ContextMenu.IsOpen) {
                Complete-Edit -Context $ctx -ReturnFocus $false
            }
        })
    })

    $showActions = {
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx -or $ctx.IsEditing) { return }
        $ctx.Actions.Opacity = 1
        $ctx.Actions.IsHitTestVisible = $true
    }

    $check.Add_GotKeyboardFocus($showActions)
    $editButton.Add_GotKeyboardFocus($showActions)
    $deleteButton.Add_GotKeyboardFocus($showActions)

    $row.Add_MouseEnter({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx) { return }
        if (-not $ctx.IsEditing) {
            $ctx.Row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'RowHoverBrush')
            $ctx.Actions.Opacity = 1
            $ctx.Actions.IsHitTestVisible = $true
        }
    })

    $row.Add_MouseLeave({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($null -eq $ctx) { return }
        if (-not $ctx.IsEditing -and -not $sender.IsKeyboardFocusWithin) {
            $ctx.Row.Background = $script:TransparentBrush
            $ctx.Actions.Opacity = 1
            $ctx.Actions.IsHitTestVisible = $true
        }
    })

    $row.Child = $grid
    return $row
}

function Refresh-TaskList {
    param([switch]$ResetScroll)

    $previousOffset = 0.0
    if ($null -ne $script:TaskScroll) {
        $previousOffset = $script:TaskScroll.VerticalOffset
    }

    $script:ActiveList.Children.Clear()
    $script:CompletedList.Children.Clear()

    if ($script:TaskFilter -ne 'completed') {
        foreach ($task in @($script:ActiveTasks)) {
            [void]$script:ActiveList.Children.Add((New-TaskRow -Task $task))
        }
    }
    if ($script:TaskFilter -ne 'active' -and ($script:CompletedExpanded -or $script:TaskFilter -eq 'completed')) {
        foreach ($task in @($script:CompletedTasks)) {
            [void]$script:CompletedList.Children.Add((New-TaskRow -Task $task))
        }
    }

    $activeCount = $script:ActiveTasks.Count
    $completedCount = $script:CompletedTasks.Count
    $total = $activeCount + $completedCount

    if ($total -eq 0) {
        $script:StatusPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
    else {
        $script:StatusPanel.Visibility = [System.Windows.Visibility]::Visible
        if ($activeCount -gt 0) {
            $script:StatusText.Text = '{0} 件待办' -f $activeCount
            $script:StatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'SecondaryBrush')
        }
        else {
            $script:StatusText.Text = '全部完成'
            $script:StatusText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        }
        $script:StatusDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, 'AccentBrush')
    }

    $script:CompletedSection.Visibility = if ($completedCount -gt 0 -and $script:TaskFilter -ne 'active') {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }
    $expanded = $script:CompletedExpanded -or $script:TaskFilter -eq 'completed'
    $script:CompletedList.Visibility = if ($expanded) { 'Visible' } else { 'Collapsed' }
    $script:CompletedHeaderText.Text = ('{0}  已完成 · {1}' -f $(if ($expanded) { '⌄' } else { '›' }), $completedCount)
    $script:CompletedToggleButton.IsEnabled = $script:TaskFilter -ne 'completed'
    [System.Windows.Automation.AutomationProperties]::SetName($script:CompletedToggleButton,
        $(if ($expanded) { '折叠已完成任务' } else { '展开已完成任务' }))
    $visibleCount = switch ($script:TaskFilter) { 'active' { $activeCount }; 'completed' { $completedCount }; default { $total } }
    $script:FilterAll.Content = '全部'
    $script:FilterActive.Content = '待办  ' + $activeCount
    $script:FilterCompleted.Content = '已完成  ' + $completedCount
    $script:ListCountText.Text = if ($script:TaskFilter -eq 'all') { '共 {0} 项' -f $total } else { '{0} / {1} 项' -f $visibleCount, $total }
    $script:TaskProgress.Value = if ($total -gt 0) { 100.0 * $completedCount / $total } else { 0 }
    $script:ProgressText.Text = '{0} / {1} 已完成' -f $completedCount, $total
    $script:EmptyTitle.Text = switch ($script:TaskFilter) { 'active' { '眼前的事，都完成了' }; 'completed' { '每一小步，都算数' }; default { '从一件小事开始' } }
    $script:EmptyDescription.Text = switch ($script:TaskFilter) { 'active' { '给自己一点休息，或写下新的想法。' }; 'completed' { '完成的待办会出现在这里。' }; default { '在上方写下待办，按 Enter 就能添加。' } }
    $script:EmptyState.Visibility = if ($visibleCount -eq 0) {
        [System.Windows.Visibility]::Visible
    } else {
        [System.Windows.Visibility]::Collapsed
    }

    if ($null -ne $script:LoadError) {
        $script:EmptyTitle.Text = '暂时无法读取待办'
        $script:EmptyDescription.Text = '原文件保持不变，请检查文件或备份后重新打开。'
    }
    $script:EditingContext = $null
    Update-StoredCounts

    $targetOffset = if ($ResetScroll) { 0.0 } else { $previousOffset }
    $scrollViewer = $script:TaskScroll
    $dispatcher = $script:Window.Dispatcher
    $scrollAction = {
        if ($null -ne $scrollViewer) {
            if ($targetOffset -le 0) {
                $scrollViewer.ScrollToTop()
            }
            else {
                $scrollViewer.ScrollToVerticalOffset($targetOffset)
            }
        }
    }.GetNewClosure()
    [void]$dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Loaded,
        [Action]$scrollAction)
}

# ------------------------------------------------------------------- actions

function Start-EditTask {
    param($Context)
    if ($null -ne $script:LoadError) { return }

    if ($null -eq $Context -or $Context.IsEditing) {
        return
    }

    if ($null -ne $script:EditingContext -and
        $script:EditingContext -ne $Context) {
        Complete-Edit -Context $script:EditingContext -ReturnFocus $false
    }

    $Context.IsEditing = $true
    $Context.PriorityButton.Visibility = if ($script:Settings.PriorityEnabled -ne $false) { 'Visible' } else { 'Collapsed' }
    if ($null -ne $Context.ReminderLabel) { $Context.ReminderLabel.Visibility = 'Collapsed' }
    $Context.Row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'EditRowBrush')
    $Context.Title.Visibility = [System.Windows.Visibility]::Collapsed
    $Context.Editor.Visibility = [System.Windows.Visibility]::Visible
    $Context.Editor.Text = [string]$Context.Task.Title
    $Context.Actions.Visibility = [System.Windows.Visibility]::Collapsed
    $script:EditingContext = $Context

    $Context.Editor.Focus() | Out-Null
    [System.Windows.Input.Keyboard]::Focus($Context.Editor) | Out-Null
    $Context.Editor.SelectAll()
}

function Complete-Edit {
    param(
        $Context,
        [bool]$ReturnFocus = $false
    )

    if ($null -eq $Context -or -not $Context.IsEditing) {
        return
    }

    $text = ConvertTo-CleanTitle -Text ([string]$Context.Editor.Text)
    if ($text.Length -eq 0) {
        $Context.Editor.Text = [string]$Context.Task.Title
    }
    else {
        if ($Context.Task.Title -ne $text) {
            $oldTitle = $Context.Task.Title
            $Context.Task.Title = $text
            $Context.Title.Text = $text
            $Context.Title.ToolTip = $text + [Environment]::NewLine + '双击编辑'
            Save-Tasks
            $script:UndoPayload = @{ Kind = 'edit'; Task = $Context.Task; Title = $oldTitle }
            Show-Toast -Message $(if ($script:LastTasksSaveSucceeded) { '已更新待办' } else { '已更新，尚未保存，请保留窗口' }) -CanUndo $true
        }
    }

    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $Context.Check,
        [string]$Context.Task.Title)
    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $Context.EditButton,
        [string]$Context.Task.Title)
    [System.Windows.Automation.AutomationProperties]::SetHelpText(
        $Context.DeleteButton,
        [string]$Context.Task.Title)

    $Context.IsEditing = $false
    $Context.PriorityButton.Visibility = 'Collapsed'
    if ($null -ne $Context.ReminderLabel) { $Context.ReminderLabel.Visibility = 'Visible' }
    $Context.Editor.Visibility = [System.Windows.Visibility]::Collapsed
    $Context.Title.Visibility = [System.Windows.Visibility]::Visible
    $Context.Actions.Visibility = [System.Windows.Visibility]::Visible

    if ($Context.Row.IsMouseOver) {
        $Context.Row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'RowHoverBrush')
        $Context.Actions.Opacity = 1
        $Context.Actions.IsHitTestVisible = $true
    }
    else {
        $Context.Row.Background = $script:TransparentBrush
        $Context.Actions.Opacity = 1
        $Context.Actions.IsHitTestVisible = $true
    }

    if ($script:EditingContext -eq $Context) {
        $script:EditingContext = $null
    }

    if ($ReturnFocus) {
        $Context.Check.Focus() | Out-Null
    }
}

function Cancel-Edit {
    param(
        $Context,
        [bool]$ReturnFocus = $false
    )

    if ($null -eq $Context -or -not $Context.IsEditing) {
        return
    }

    $Context.Editor.Text = [string]$Context.Task.Title
    $Context.IsEditing = $false
    $Context.PriorityButton.Visibility = 'Collapsed'
    if ($null -ne $Context.ReminderLabel) { $Context.ReminderLabel.Visibility = 'Visible' }
    $Context.Editor.Visibility = [System.Windows.Visibility]::Collapsed
    $Context.Title.Visibility = [System.Windows.Visibility]::Visible
    $Context.Actions.Visibility = [System.Windows.Visibility]::Visible

    if ($Context.Row.IsMouseOver) {
        $Context.Row.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, 'RowHoverBrush')
        $Context.Actions.Opacity = 1
        $Context.Actions.IsHitTestVisible = $true
    }
    else {
        $Context.Row.Background = $script:TransparentBrush
        $Context.Actions.Opacity = 1
        $Context.Actions.IsHitTestVisible = $true
    }

    if ($script:EditingContext -eq $Context) {
        $script:EditingContext = $null
    }

    if ($ReturnFocus) {
        $Context.Check.Focus() | Out-Null
    }
}

function Commit-ActiveEdit {
    if ($null -ne $script:EditingContext) {
        Complete-Edit -Context $script:EditingContext -ReturnFocus $false
    }
}

function Add-TaskFromComposer {
    param([bool]$ReturnFocus = $true)
    if ($null -ne $script:LoadError) { return }
    $resumeEdit = $script:EditingContext
    $resumeText = if ($null -ne $resumeEdit) { $resumeEdit.Editor.Text } else { $null }
    $title = ConvertTo-CleanTitle -Text ([string]$script:NewTaskInput.Text)
    if ($title.Length -eq 0) {
        $script:NewTaskInput.Focus() | Out-Null
        return
    }

    Commit-ActiveEdit

    if ($script:TaskFilter -eq 'completed') { $script:FilterAll.IsChecked = $true }
    $task = [pscustomobject][ordered]@{
        Id = [guid]::NewGuid().ToString('N')
        Title = $title
        IsCompleted = $false
        CreatedAt = Get-Date
        CompletedAt = $null
        RemindAt = $(if ($script:Settings.RemindersEnabled -ne $false) { $script:ComposerReminderDraft.RemindAt } else { $null })
        ReminderNotified = $false
        Priority = $(if ($script:Settings.PriorityEnabled -ne $false) { $script:ComposerPriorityValue } else { 'medium' })
        IsEditing = $false
    }

    $script:ActiveTasks.Insert(0, $task)
    $script:NewTaskInput.Clear()
    $script:ComposerReminderDraft.RemindAt = $null
    Update-ComposerFeatures
    Update-ComposerState
    Save-Tasks
    Refresh-TaskList -ResetScroll
    $script:UndoPayload = @{ Kind = 'add'; Task = $task }
    Show-Toast -Message $(if ($script:LastTasksSaveSucceeded) { '已添加待办' } else { '已添加，尚未保存，请保留窗口' }) -CanUndo $true
    if ($ReturnFocus) {
        $script:NewTaskInput.Focus() | Out-Null
        [System.Windows.Input.Keyboard]::Focus($script:NewTaskInput) | Out-Null
    } elseif ($null -ne $resumeEdit) {
        foreach ($row in @($script:ActiveList.Children) + @($script:CompletedList.Children)) {
            if ($row.Tag.Task.Id -eq $resumeEdit.Task.Id) { Start-EditTask $row.Tag; $row.Tag.Editor.Text = $resumeText; break }
        }
    }
}

function Toggle-Task {
    param($Task)
    if ($null -ne $script:LoadError) { return }

    if ($null -eq $Task) { return }
    Commit-ActiveEdit

    if ($Task.IsCompleted) {
        $index = Find-TaskIndex -Tasks $script:CompletedTasks -Id $Task.Id
        if ($index -ge 0) {
            $script:CompletedTasks.RemoveAt($index)
        }
        $Task.IsCompleted = $false
        $Task.CompletedAt = $null
        $script:ActiveTasks.Insert(0, $Task)
    }
    else {
        $index = Find-TaskIndex -Tasks $script:ActiveTasks -Id $Task.Id
        if ($index -ge 0) {
            $script:ActiveTasks.RemoveAt($index)
        }
        $Task.IsCompleted = $true
        $Task.CompletedAt = Get-Date
        $script:CompletedTasks.Insert(0, $Task)
    }

    Save-Tasks
    Refresh-TaskList
    $script:UndoPayload = @{ Kind = 'toggle'; Task = $Task }
    Show-Toast -Message $(if ($script:LastTasksSaveSucceeded) {
        if ($Task.IsCompleted) { '已完成一项待办' } else { '已恢复为待办' }
    } else { '更改尚未保存，请保留窗口' }) -CanUndo $true
}

function Find-TaskIndex {
    param($Tasks, [string]$Id)

    for ($i = 0; $i -lt $Tasks.Count; $i++) {
        if ($Tasks[$i].Id -eq $Id) {
            return $i
        }
    }
    return -1
}

function Remove-Task {
    param($Task)
    if ($null -ne $script:LoadError) { return }

    if ($null -eq $Task) { return }
    Commit-ActiveEdit

    $wasCompleted = $Task.IsCompleted
    if ($wasCompleted) {
        $index = Find-TaskIndex -Tasks $script:CompletedTasks -Id $Task.Id
        if ($index -lt 0) { return }
        $script:CompletedTasks.RemoveAt($index)
    }
    else {
        $index = Find-TaskIndex -Tasks $script:ActiveTasks -Id $Task.Id
        if ($index -lt 0) { return }
        $script:ActiveTasks.RemoveAt($index)
    }

    $script:TrashedTasks.Insert(0, $Task)
    Save-Tasks
    Refresh-TaskList

    $script:UndoPayload = @{
        Kind = 'delete'
        Task = $Task
        Index = $index
        WasCompleted = $wasCompleted
    }

    Show-Toast -Message '已移入回收站' -CanUndo $true
}

function Clear-Completed {
    if ($null -ne $script:LoadError) { return }
    if ($script:CompletedTasks.Count -eq 0) { return }
    Commit-ActiveEdit

    $removed = @($script:CompletedTasks)
    foreach ($task in $removed) { $script:TrashedTasks.Insert(0, $task) }
    $script:CompletedTasks.Clear()
    Save-Tasks
    Refresh-TaskList

    $script:UndoPayload = @{
        Kind = 'clearCompleted'
        Items = $removed
    }

    Show-Toast -Message ('已将 {0} 项移入回收站' -f $removed.Count) -CanUndo $true
}

function Test-TaskIdInList {
    param($Tasks, [string]$Id)

    for ($i = 0; $i -lt $Tasks.Count; $i++) {
        if ($Tasks[$i].Id -eq $Id) {
            return $true
        }
    }
    return $false
}

function Invoke-UndoPayload {
    param($Payload)
    if ($null -ne $script:LoadError) { return }

    if ($null -eq $Payload) { return }

    switch ($Payload.Kind) {
        'priority' { $Payload.Task | Add-Member -NotePropertyName Priority -NotePropertyValue $Payload.Priority -Force }
        'add' {
            $index = Find-TaskIndex -Tasks $script:ActiveTasks -Id $Payload.Task.Id
            if ($index -ge 0) { $script:ActiveTasks.RemoveAt($index) }
        }
        'edit' { $Payload.Task.Title = $Payload.Title }
        'toggle' { Toggle-Task -Task $Payload.Task; return }
        'delete' {
            $task = $Payload.Task
            Remove-StoredTask -Tasks $script:TrashedTasks -Id $task.Id
            if ($null -eq $task) { return }

            if ($Payload.WasCompleted) {
                if (-not (Test-TaskIdInList -Tasks $script:CompletedTasks -Id $task.Id)) {
                    $safeIndex = [Math]::Min(
                        [Math]::Max([int]$Payload.Index, 0),
                        $script:CompletedTasks.Count)
                    $script:CompletedTasks.Insert($safeIndex, $task)
                }
            }
            else {
                if (-not (Test-TaskIdInList -Tasks $script:ActiveTasks -Id $task.Id)) {
                    $safeIndex = [Math]::Min(
                        [Math]::Max([int]$Payload.Index, 0),
                        $script:ActiveTasks.Count)
                    $script:ActiveTasks.Insert($safeIndex, $task)
                }
            }
        }
        'archive' {
            foreach ($task in $Payload.Items) {
                Remove-StoredTask -Tasks $script:ArchivedTasks -Id $task.Id
                if (-not (Test-TaskIdInList $script:CompletedTasks $task.Id)) { [void]$script:CompletedTasks.Add($task) }
            }
        }
        'clearCompleted' {
            $items = @($Payload.Items)
            for ($i = $items.Count - 1; $i -ge 0; $i--) {
                $task = $items[$i]
                Remove-StoredTask -Tasks $script:TrashedTasks -Id $task.Id
                if ($null -ne $task -and
                    -not (Test-TaskIdInList -Tasks $script:CompletedTasks -Id $task.Id)) {
                    $script:CompletedTasks.Insert(0, $task)
                }
            }
        }
    }

    Save-Tasks
    Refresh-TaskList
}

function Undo-LastTaskAction {
    $payload = $script:UndoPayload
    Hide-Toast
    if ($null -ne $payload) {
        Invoke-UndoPayload -Payload $payload
        $script:UndoPayload = $null
        Show-Toast -Message $(if ($script:LastTasksSaveSucceeded) { '已撤销上一步操作' } else { '已撤销，尚未保存，请保留窗口' })
    }
}

# --------------------------------------------------------------------- toast

function Show-Toast {
    param(
        [string]$Message,
        [bool]$CanUndo = $false,
        [bool]$Warning = $false,
        [int]$Seconds = 6
    )

    if (-not $script:UiReady) { return }

    if (-not $CanUndo) {
        $script:UndoPayload = $null
    }

    $script:ToastToken++
    $script:ToastText.Text = $Message
    $hasUndo = $CanUndo -and $null -ne $script:UndoPayload
    $script:ToastUndoButton.Visibility = if (-not $hasUndo) {
        [System.Windows.Visibility]::Collapsed
    } else {
        [System.Windows.Visibility]::Visible
    }
    $script:Toast.Visibility = [System.Windows.Visibility]::Visible
    $script:Toast.IsHitTestVisible = $true

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 0
    $fade.To = 1
    $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(160))
    $fade.EasingFunction = $ease
    $script:Toast.BeginAnimation(
        [System.Windows.UIElement]::OpacityProperty,
        $fade)

    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slide.From = 8
    $slide.To = 0
    $slide.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(200))
    $slide.EasingFunction = $ease
    $script:ToastTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty,
        $slide)

    if ($null -eq $script:ToastTimer) {
        $script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:ToastTimer.Add_Tick({
            $script:ToastTimer.Stop()
            Hide-Toast
        })
    }

    $script:ToastTimer.Stop()
    $script:ToastTimer.Interval = [TimeSpan]::FromSeconds($Seconds)
    $script:ToastTimer.Start()
}

function Hide-Toast {
    $script:UndoPayload = $null
    if ($null -ne $script:ToastTimer) {
        $script:ToastTimer.Stop()
    }

    if ($null -eq $script:Toast -or
        $script:Toast.Visibility -ne [System.Windows.Visibility]::Visible) {
        return
    }

    $script:Toast.IsHitTestVisible = $false
    $script:ToastToken++
    $token = $script:ToastToken

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn

    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.To = 0
    $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
    $fade.EasingFunction = $ease
    $script:ToastCollapseToken = $script:ToastToken
    $fade.Add_Completed({
        param($sender, $eventArgs)
        if ($script:ToastToken -eq $script:ToastCollapseToken) {
            $script:Toast.Visibility = [System.Windows.Visibility]::Collapsed
        }
    })
    $script:Toast.BeginAnimation(
        [System.Windows.UIElement]::OpacityProperty,
        $fade)

    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slide.To = 5
    $slide.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
    $slide.EasingFunction = $ease
    $script:ToastTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty,
        $slide)
}

# ------------------------------------------------------------ settings sheet

function Show-AppMessage {
    param(
        [string]$Message,
        [string]$Title = '待办',
        [System.Windows.MessageBoxImage]$Image = [System.Windows.MessageBoxImage]::Warning
    )

    if ($null -ne $script:Window) {
        [void][System.Windows.MessageBox]::Show(
            $script:Window,
            $Message,
            $Title,
            [System.Windows.MessageBoxButton]::OK,
            $Image)
    }
}

function Test-DirectoryWritable {
    param([string]$Folder)

    $probe = $null
    try {
        [void][System.IO.Directory]::CreateDirectory($Folder)
        $probe = Join-Path $Folder ('.daiban-write-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($probe, 'probe')
        [System.IO.File]::Delete($probe)
        return $true
    }
    catch {
        if ($null -ne $probe) {
            try { [System.IO.File]::Delete($probe) } catch { }
        }
        return $false
    }
}

function Open-Settings {
    if ($script:SettingsOpen) { return }

    Hide-Toast
    $script:SettingsOpen = $true
    Update-SettingsUi

    $script:SettingsOverlay.Visibility = [System.Windows.Visibility]::Visible
    $script:SettingsOverlay.Opacity = 0
    $script:SettingsCardTransform.Y = 8

    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
    $fade.From = 0
    $fade.To = 1
    $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
    $fade.EasingFunction = $ease
    $script:SettingsOverlay.BeginAnimation(
        [System.Windows.UIElement]::OpacityProperty,
        $fade)

    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation
    $slide.From = 8
    $slide.To = 0
    $slide.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(190))
    $slide.EasingFunction = $ease
    $script:SettingsCardTransform.BeginAnimation(
        [System.Windows.Media.TranslateTransform]::YProperty,
        $slide)

    $selected = switch ($script:Settings.Theme) {
        'light' { $script:ThemeLightButton }
        'dark' { $script:ThemeDarkButton }
        default { $script:ThemeSystemButton }
    }

    if ($null -ne $selected) {
        $selected.Focus() | Out-Null
        [System.Windows.Input.Keyboard]::Focus($selected) | Out-Null
    }
}

function Close-Settings {
    if (-not $script:SettingsOpen) { return }

    $script:SettingsOpen = $false
    $script:SettingsOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $script:SettingsOverlay.Opacity = 0

    if ($null -ne $script:NewTaskInput) {
        $script:NewTaskInput.Focus() | Out-Null
    }
}

function Select-DataDirectory {
    if (-not $script:HasNativeHelpers) {
        Show-AppMessage -Message '当前系统无法打开文件夹选择器，请稍后重试。'
        return
    }

    try {
        $owner = ([System.Windows.Interop.WindowInteropHelper]::new($script:Window)).Handle
        $selected = [DaiBanNative]::PickFolder(
            $owner,
            '选择待办数据的保存文件夹',
            $script:DataDirectory)

        if (-not [string]::IsNullOrWhiteSpace($selected)) {
            Switch-DataDirectory -Folder $selected
        }
    }
    catch {
        Write-AppLog -Message ('Folder picker failed: ' + $_.Exception.ToString())
        Show-AppMessage -Message '无法打开文件夹选择器，请稍后重试。'
    }
    finally {
        if ($null -ne $script:Window) {
            $script:Window.Activate() | Out-Null
            if ($script:SettingsOpen) {
                $script:ChangeDataFolderButton.Focus() | Out-Null
            }
        }
    }
}

function Switch-DataDirectory {
    param([string]$Folder)
    if ($null -ne $script:LoadError -or $null -ne $script:SettingsReadError) { return }

    if ([string]::IsNullOrWhiteSpace($Folder)) { return }

    try {
        $target = Get-NormalizedFolderPath -Path $Folder
    }
    catch {
        Show-AppMessage -Message '这个文件夹路径无效，请重新选择。'
        return
    }

    if (Test-SameFolder -First $target -Second $script:DataDirectory) {
        return
    }

    if (-not (Test-DirectoryWritable -Folder $target)) {
        Show-AppMessage -Message '这个文件夹当前无法写入，请选择其他位置。'
        return
    }

    $targetFile = Join-Path $target 'todos.json'
    if ([System.IO.File]::Exists($targetFile)) {
        $answer = [System.Windows.MessageBox]::Show(
            $script:Window,
            ('该文件夹中已有待办数据。' + [Environment]::NewLine + [Environment]::NewLine +
                '继续会用当前清单覆盖该文件，原文件会先自动备份。是否继续？'),
            '待办',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning,
            [System.Windows.MessageBoxResult]::No)

        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
            return
        }

        try {
            $backupPath = $targetFile + '.bak-' + (Get-Date).ToString('yyyyMMdd-HHmmss')
            [System.IO.File]::Copy($targetFile, $backupPath, $true)
        }
        catch {
            Show-AppMessage -Message '原数据文件备份失败，已取消切换保存位置。'
            return
        }
    }

    $oldDirectory = $script:DataDirectory
    $oldFilePath = $script:DataFilePath
    $oldPersistenceState = $script:PersistenceState
    $oldDirty = $script:TasksDirty
    $oldSaveSucceeded = $script:LastTasksSaveSucceeded
    $script:DataDirectory = $target
    $script:DataFilePath = $targetFile

    Save-Tasks
    if (-not $script:LastTasksSaveSucceeded) {
        $script:DataDirectory = $oldDirectory
        $script:DataFilePath = $oldFilePath
        $script:PersistenceState = $oldPersistenceState
        $script:TasksDirty = $oldDirty
        $script:LastTasksSaveSucceeded = $oldSaveSucceeded
        Update-StorageStatus
        Show-AppMessage -Message '无法写入新位置，已保留原来的保存位置。'
        return
    }

    Save-Settings
    if (-not $script:LastSettingsSaveSucceeded) {
        $script:DataDirectory = $oldDirectory
        $script:DataFilePath = $oldFilePath
        $script:PersistenceState = $oldPersistenceState
        $script:TasksDirty = $oldDirty
        $script:LastTasksSaveSucceeded = $oldSaveSucceeded
        Update-StorageStatus
        Show-AppMessage -Message '无法保存设置，已保留原来的保存位置。'
        return
    }

    Update-SettingsUi
    Close-Settings
    Show-Toast -Message '保存位置已更新'
}

$script:ThemeChoiceChangedHandler = {
    param($sender, $eventArgs)

    if ($script:SuppressThemeEvents) { return }
    if ($null -eq $sender -or [string]::IsNullOrWhiteSpace([string]$sender.Tag)) {
        return
    }

    Set-ThemePreference -Preference ([string]$sender.Tag)
}

# --------------------------------------------------------------- interactions

$script:WindowLoadedHandler = {
    param($sender, $eventArgs)

    $sender.Opacity = 1
    if ([System.Windows.SystemParameters]::ClientAreaAnimation) {
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $fade = New-Object System.Windows.Media.Animation.DoubleAnimation
        $fade.From = 0
        $fade.To = 1
        $fade.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(170))
        $fade.EasingFunction = $ease
        $fade.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $sender.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
    }

    Update-Date
    if ($null -ne $script:ClockTimer) {
        $script:ClockTimer.Start()
    }

    Check-Reminders
    $sender.Activate() | Out-Null
    $script:NewTaskInput.Focus() | Out-Null
    [System.Windows.Input.Keyboard]::Focus($script:NewTaskInput) | Out-Null

    if ($null -ne $script:LoadError) {
        $sender.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{
                Show-Toast -Message '无法读取待办，原文件已保护。请检查文件或备份后重新打开。' -Warning $true -Seconds 6
            }) | Out-Null
    }
    elseif ($null -ne $script:SettingsError) {
        $sender.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::ContextIdle,
            [Action]{
                Show-Toast -Message $script:SettingsError -Warning $true -Seconds 6
            }) | Out-Null
    }
}

$script:WindowClosingHandler = {
    param($sender, $eventArgs)
    if (-not [string]::IsNullOrWhiteSpace($script:NewTaskInput.Text)) { Add-TaskFromComposer -ReturnFocus $false }
    Commit-ActiveEdit
    # No unconditional close-time write: unreadable data and unchanged files stay untouched.
    if ($script:TasksDirty -and $null -eq $script:LoadError) {
        Save-Tasks
        if (-not $script:LastTasksSaveSucceeded) {
            $eventArgs.Cancel = $true
            Show-Toast -Message '数据尚未保存，窗口已保留。请检查保存位置后再次关闭。' -Warning $true
            return
        }
    }
    if ($null -ne $script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($null -ne $script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($null -ne $script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
}

$script:TitleBarMouseHandler = {
    param($sender, $eventArgs)
    if ($eventArgs.ChangedButton -ne [System.Windows.Input.MouseButton]::Left) { return }

    $source = $eventArgs.OriginalSource
    $node = $source
    while ($null -ne $node) {
        if ($node -is [System.Windows.Controls.Button]) {
            return
        }
        if ($node -is [System.Windows.Media.Visual] -or
            $node -is [System.Windows.Media.Media3D.Visual3D]) {
            $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
        }
        else {
            $node = $null
        }
    }

    if ($eventArgs.ClickCount -eq 2) {
        Toggle-WindowMaximize
        $eventArgs.Handled = $true
        return
    }
    if ($script:HasNativeHelpers) {
        try {
            $handle = ([System.Windows.Interop.WindowInteropHelper]::new($script:Window)).Handle
            if ($handle -ne [IntPtr]::Zero) {
                [void][DaiBanNative]::ReleaseCapture()
                [void][DaiBanNative]::SendMessage(
                    $handle,
                    0x00A1,
                    [IntPtr]2,
                    [IntPtr]::Zero)
                $eventArgs.Handled = $true
                return
            }
        }
        catch {
        }
    }

    try {
        $script:Window.DragMove()
    }
    catch {
    }
}

$script:NewTaskChangedHandler = {
    param($sender, $eventArgs)
    Update-ComposerState
}

$script:NewTaskKeyHandler = {
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
        Add-TaskFromComposer
        $eventArgs.Handled = $true
    }
}

$script:WindowKeyHandler = {
    param($sender, $eventArgs)

    $isCtrl = [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control

    if ($isCtrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::OemComma) {
        if ($script:SettingsOpen) {
            Close-Settings
        }
        else {
            Open-Settings
        }
        $eventArgs.Handled = $true
        return
    }

    if ($script:SettingsOpen) {
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            Close-Settings
            $eventArgs.Handled = $true
        }
        return
    }

    $focused = [System.Windows.Input.Keyboard]::FocusedElement
    if ($isCtrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Z -and
        $null -ne $script:UndoPayload -and
        -not ($focused -is [System.Windows.Controls.TextBox] -and $focused.CanUndo)) {
        Undo-LastTaskAction
        $eventArgs.Handled = $true
        return
    }
    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape -and $null -ne $script:EditingContext) {
        Cancel-Edit -Context $script:EditingContext -ReturnFocus $true
        $eventArgs.Handled = $true
        return
    }
    if ($isCtrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::N) {
        $script:NewTaskInput.Focus() | Out-Null
        [System.Windows.Input.Keyboard]::Focus($script:NewTaskInput) | Out-Null
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape -and
        $script:Toast.Visibility -eq [System.Windows.Visibility]::Visible) {
        Hide-Toast
        $eventArgs.Handled = $true
    }
}

function Toggle-WindowMaximize {
    $script:Window.WindowState = if ($script:Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }
}

function Update-WindowControls {
    $maximized = $script:Window.WindowState -eq 'Maximized'
    $label = if ($maximized) { '还原' } else { '最大化' }
    $script:MaximizeButton.ToolTip = $label
    [System.Windows.Automation.AutomationProperties]::SetName($script:MaximizeButton, $label)
    $script:MaximizeGlyph.Data = [System.Windows.Media.Geometry]::Parse(
        $(if ($maximized) { 'M 3,0 L 10,0 L 10,7 M 0,3 L 7,3 L 7,10 L 0,10 Z' } else { 'M 0,0 L 10,0 L 10,10 L 0,10 Z' }))
}

function Wire-InterfaceEvents {
    Initialize-PriorityButton -Button $script:ComposerPriority -Task $null
    $script:ComposerReminderButton.Add_Click({
        $script:ComposerReminderDraft.Title = if ([string]::IsNullOrWhiteSpace($script:NewTaskInput.Text)) { '新待办' } else { $script:NewTaskInput.Text }
        $script:ComposerReminderDialogOpen = $true
        try { Open-ReminderDialog $script:ComposerReminderDraft } finally { $script:ComposerReminderDialogOpen = $false }
    })
    foreach ($toggle in @($script:PriorityFeatureToggle, $script:RemindersFeatureToggle)) {
        $toggle.Add_Checked({ Update-FeaturePreferences })
        $toggle.Add_Unchecked({ Update-FeaturePreferences })
    }
    $script:Window.Add_PreviewMouseDown({ param($sender,$eventArgs); Confirm-EditOutside $eventArgs.OriginalSource })
    Update-ComposerFeatures
    $script:Window.Add_SizeChanged({
        param($sender, $eventArgs)
        Update-ResponsiveLayout -Width $eventArgs.NewSize.Width -Height $eventArgs.NewSize.Height
    })
    $script:MaximizeButton.Add_Click({ Toggle-WindowMaximize })
    $script:Window.Add_StateChanged({ Update-WindowControls })
    Update-WindowControls
    $script:CompletedToggleButton.Add_Click({
        Commit-ActiveEdit
        $script:CompletedExpanded = -not $script:CompletedExpanded
        Refresh-TaskList
    })
    foreach ($filter in @($script:FilterAll, $script:FilterActive, $script:FilterCompleted)) {
        $filter.Add_Checked({
            param($sender, $eventArgs)
            Commit-ActiveEdit
            $script:TaskFilter = [string]$sender.Tag
            Refresh-TaskList -ResetScroll
        })
    }
    $script:Window.Add_Loaded($script:WindowLoadedHandler)
    $script:Window.Add_Closing($script:WindowClosingHandler)
    $script:Window.Add_PreviewKeyDown($script:WindowKeyHandler)

    $script:TitleBar.Add_MouseLeftButtonDown($script:TitleBarMouseHandler)
    $script:SettingsButton.Add_Click({ Open-Settings })
    $script:SettingsCloseButton.Add_Click({ Close-Settings })
    $script:SettingsScrim.Add_MouseLeftButtonDown({ Close-Settings })
    $script:ThemeSystemButton.Add_Checked($script:ThemeChoiceChangedHandler)
    $script:ThemeLightButton.Add_Checked($script:ThemeChoiceChangedHandler)
    $script:ThemeDarkButton.Add_Checked($script:ThemeChoiceChangedHandler)
    $script:ChangeDataFolderButton.Add_Click({ Select-DataDirectory })
    $script:ResetDataFolderButton.Add_Click({
        Switch-DataDirectory -Folder $script:DefaultDataDirectory
    })
    $script:MinimizeButton.Add_Click({
        $script:Window.WindowState = [System.Windows.WindowState]::Minimized
    })
    $script:CloseButton.Add_Click({ $script:Window.Close() })

    $script:NewTaskInput.Add_TextChanged($script:NewTaskChangedHandler)
    $script:NewTaskInput.Add_PreviewKeyDown($script:NewTaskKeyHandler)
    $script:AddButton.Add_Click({ Add-TaskFromComposer })
    $script:LicenseInfoButton.Add_Click({ Show-LicenseInformation })
    $script:ArchiveCompletedButton.Add_Click({ Archive-Completed })
    $script:TrashSettingsButton.Add_Click({ Open-StoredTasksDialog 'trash' })
    $script:ArchiveSettingsButton.Add_Click({ Open-StoredTasksDialog 'archive' })
    $script:Window.Add_PreviewMouseUp({
        param($sender,$eventArgs)
        if (-not (Test-InComposer $eventArgs.OriginalSource)) { Queue-ComposerConfirmation -Force $true }
    })
    $script:NewTaskInput.Add_LostKeyboardFocus({ Queue-ComposerConfirmation })
    $script:ClearCompletedButton.Add_Click({ Clear-Completed })
    $script:ToastUndoButton.Add_Click({ Undo-LastTaskAction })
}

# ------------------------------------------------------------------- startup

$createdNew = $false
try {
    $script:Mutex = [System.Threading.Mutex]::new(
        $true,
        ('Local\DaiBan.Todo.' + [BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [Text.Encoding]::UTF8.GetBytes(([IO.Path]::GetFullPath($script:ConfigDirectory)).ToLowerInvariant()))).Replace('-', '')),

        [ref]$createdNew)
}
catch {
    $createdNew = $true
}

if (-not $createdNew) {
    # The first window already owns the app. A duplicate launch quietly
    # returns instead of creating a second window over the same data file.
    return
}

try {
    $script:Application = New-Object System.Windows.Application
    $script:Application.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
    $script:Application.Add_DispatcherUnhandledException({
        param($sender, $eventArgs)

        Write-AppLog -Message ('Unhandled UI exception: ' + $eventArgs.Exception.ToString())
        $eventArgs.Handled = $true

        try {
            if ($script:UiReady) {
                Show-Toast -Message '遇到一个意外问题，请重试刚才的操作。' -Warning $true
            }
        }
        catch {
        }
    })

    Load-Settings
    Load-Tasks

    $initialWindow = Load-Interface
    Initialize-ThemePalette -Window $initialWindow -ThemeName (Get-EffectiveThemeName)
    Initialize-Interface -Window $initialWindow
    Wire-InterfaceEvents

    $script:UpdateDateTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ClockTimer = $script:UpdateDateTimer
    $script:ClockTimer.Interval = [TimeSpan]::FromSeconds(10)
    $script:ClockTimer.Add_Tick({ Update-Date; Check-Reminders })

    Update-Date
    Update-ComposerState
    Update-SettingsUi
    Update-ThemeWatcher
    Refresh-TaskList

    $script:Window.Add_SourceInitialized({
        param($sender, $eventArgs)
        Apply-NativeTheme
    })

    $script:Application.MainWindow = $script:Window
    [void]$script:Application.Run($script:Window)
}
catch {
    $message = $_.Exception.ToString()
    Write-AppLog -Message ('Startup failure: ' + $message)

    try {
        [void][System.Windows.MessageBox]::Show(
            ('待办无法启动。' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message),
            '待办',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error)
    }
    catch {
    }
}
finally {
    if ($null -ne $script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($null -ne $script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($null -ne $script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }

    if ($null -ne $script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch { }
        $script:Mutex.Dispose()
        $script:Mutex = $null
    }
}
