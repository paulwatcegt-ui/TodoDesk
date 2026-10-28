#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root ('.testdata\window-' + [guid]::NewGuid().ToString('N'))
$env:DAIBAN_DATA_DIR = Join-Path $testRoot 'data'
$env:DAIBAN_CONFIG_DIR = Join-Path $testRoot 'config'
$source = [IO.File]::ReadAllText((Join-Path $root 'app\DaiBan.ps1'))
Invoke-Expression ([regex]::Split($source, '# -+ startup')[0])
$script:AppRoot = Join-Path $root 'app'
Load-Settings
Load-Tasks
$window = Load-Interface
Initialize-ThemePalette -Window $window -ThemeName 'light'
Initialize-Interface -Window $window
Wire-InterfaceEvents
Refresh-TaskList

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WindowTestNative {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
}
'@
function Assert($condition, $message) {
    if (-not $condition) { throw $message }
    Write-Host ('ok    ' + $message)
}
function Pump {
    $frame = [Windows.Threading.DispatcherFrame]::new()
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,
        [Action]{ $frame.Continue = $false }.GetNewClosure())
    [Windows.Threading.Dispatcher]::PushFrame($frame)
    $window.UpdateLayout()
}
function Position($point) {
    return [IntPtr](([long][Math]::Round($point.X) -band 0xFFFF) -bor (([long][Math]::Round($point.Y) -band 0xFFFF) -shl 16))
}
function Hit($point) {
    return [WindowTestNative]::SendMessage($handle,0x84,[IntPtr]::Zero,(Position $point)).ToInt32()
}
try {
    $window.ShowInTaskbar = $false
    $window.Show()
    Pump
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    Assert ($script:NewTaskInput.IsKeyboardFocused -and $script:Composer.BorderThickness.Left -eq 2) 'The input receives focus and shows its themed focus border'
    $captionPoint = $script:TitleBar.PointToScreen([Windows.Point]::new(220,22))
    Assert ((Hit $captionPoint) -eq 2) 'Title bar uses the Windows native caption for dragging, snapping and system menu'
    Assert ((Hit ($script:MaximizeButton.PointToScreen([Windows.Point]::new(20,15)))) -eq 1) 'Caption buttons remain interactive client controls'
    Assert ((Hit ($window.Content.PointToScreen([Windows.Point]::new(1,200)))) -eq 10) 'Left edge exposes the native resize border'
    [void][WindowTestNative]::SendMessage($handle,0xA3,[IntPtr]2,(Position $captionPoint))
    Pump
    Assert ($window.WindowState -eq 'Maximized' -and $script:MaximizeButton.ToolTip -eq '还原') 'Double-clicking the native caption maximizes and changes the button label'
    $topLeft = $window.Content.PointToScreen([Windows.Point]::new(0,0))
    $bottomRight = $window.Content.PointToScreen([Windows.Point]::new($window.Content.ActualWidth,$window.Content.ActualHeight))
    $work = [Windows.SystemParameters]::WorkArea
    $scale = [Windows.PresentationSource]::FromVisual($window).CompositionTarget.TransformToDevice
    Assert ($topLeft.X -ge $work.Left*$scale.M11-1 -and $topLeft.Y -ge $work.Top*$scale.M22-1 -and
        $bottomRight.X -le $work.Right*$scale.M11+1 -and $bottomRight.Y -le $work.Bottom*$scale.M22+1) ('Maximized content stays within work area: {0}..{1}, work {2}, scale {3}/{4}' -f $topLeft,$bottomRight,$work,$scale.M11,$scale.M22)
    $script:MaximizeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Pump
    Assert ($window.WindowState -eq 'Normal' -and $script:MaximizeButton.ToolTip -eq '最大化') 'Restore button returns the window to normal'
    $window.Width = 400
    $window.Height = 400
    Pump
    Assert ($window.ActualWidth -eq 400 -and $window.ActualHeight -eq 400 -and
        $script:TaskScroll.ViewportHeight -gt 70 -and $script:HeroSubtitle.Visibility -eq 'Collapsed') 'The native window shrinks to 400x400 with a usable task list'
    $script:MinimizeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Pump
    Assert ($window.WindowState -eq 'Minimized') 'Minimize button minimizes the native window'
    [void][WindowTestNative]::SendMessage($handle,0x112,[IntPtr]0xF120,[IntPtr]::Zero)
    Pump
    Assert ($window.WindowState -eq 'Normal') 'Windows system restore restores the minimized window'
    $script:MaximizeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Pump
    Assert ($window.WindowState -eq 'Maximized') 'Maximize button maximizes the native window'
    $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($window)
    Assert ($chrome.CaptionHeight -eq 48 -and $window.ResizeMode -eq 'CanResize') 'Native resize and caption behavior remain enabled'
    $script:CloseButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert (-not $window.IsVisible -and -not (Test-Path $script:DataFilePath)) 'Close button closes without writing an unchanged empty list'
    Write-Host 'All native window checks passed.'
}
finally {
    if ($script:ClockTimer) { $script:ClockTimer.Stop() }
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    if ($script:ThemeWatchTimer) { $script:ThemeWatchTimer.Stop() }
    $window.Close()
}
