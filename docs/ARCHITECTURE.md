# Architecture

DaiBan is deliberately small, but it is not a compiled application. This page explains why and how the pieces fit together.

## Stack

- **Windows PowerShell 5.1** is the host process.
- **WPF** provides the native desktop window, controls, animation and layout.
- **XAML** is loaded at runtime with `XamlReader`.
- **PowerShell** owns the state, file persistence, theme switching and event wiring.
- A small in-memory C# helper (compiled with `Add-Type`) wraps a few Win32/COM calls:
  - DWM rounded corners and border tint.
  - Native title-bar move (`WM_NCLBUTTONDOWN` / `HTCAPTION`).
  - The modern Windows folder picker (`IFileOpenDialog` with `FOS_PICKFOLDERS`).

## Why PowerShell instead of a standalone exe?

Windows 11 may enable Smart App Control, which blocks newly built unsiged executables. A locally built WPF exe would be an unsigned local executable and can be rejected before it starts. Windows PowerShell, WPF and the shell folder picker are already signed Microsoft components, so hosting the UI there lets the project run without asking users to weaken application-control settings.

The trade-off is visible in Task Manager: the process is Windows PowerShell. The app is still local and native WPF, but it is not a single executable.

## Startup flow

```text
DaiBan.ps1
  ├─ add WPF assemblies
  ├─ compile native helpers
  ├─ load %APPDATA%\DaiBan\settings.json
  ├─ resolve the data folder (default or custom)
  ├─ load todos.json
  ├─ load ui.xaml
  ├─ merge themes/<effective>.xaml into Window.Resources
  ├─ map named controls and attach events
  ├─ create the Application and show the Window
  └─ autosave on changes and on close
```

The UI is intentionally loaded as runtime XAML. There is no compiled BAML step and no build tool requirement.

## Data

Settings are separate from task storage:

```text
%APPDATA%\DaiBan\settings.json   fixed location
<chosen folder>\todos.json       movable task list
%APPDATA%\DaiBan\todos.json      default task list
```

This separation means changing the task folder cannot cause the app to lose track of which folder it should use next time. Writes use a temporary file and `File.Replace`/`File.Move` to reduce partial-write risk. When changing directories, an existing destination file is copied to a timestamped `.bak-*` file first. The old source file is intentionally left in place.

## Themes

`app/themes/light.xaml` and `app/themes/dark.xaml` define the same resource keys. XAML controls reference them through `DynamicResource`; switching themes swaps the merged theme dictionary. The title bar's native DWM dark-mode and border attributes are updated at the same time.

The “follow system” preference reads the current user's `AppsUseLightTheme` setting and polls it while the app is open. Explicit light/dark preferences are persisted and stop the poll.

## Window behavior

- The window is borderless but resizable through `WindowChrome`.
- DWM provides Windows 11 rounded corners, and the app sets the system border tint.
- The title bar starts a native Windows move loop. This preserves normal movement behavior and avoids the failure mode of WPF `DragMove()` in this hosted process.
- There is intentionally no maximize control; the window is designed to stay at a readable single-column size, with edge resizing.

## Security and privacy

- No network requests, telemetry or update checks.
- No registry writes by the app.
- Installer/uninstaller only copy files and create/remove shortcuts in the current user's profile.
- Signing material is never stored in the repository.

See [SIGNING.md](SIGNING.md) for release signing.
