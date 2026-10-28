# Architecture

DaiBan is delivered as a Windows Installer package containing a single `DaiBan.exe`. This page explains the build structure, the runtime host, and the data model.

## Stack

- **WPF** provides the window, controls, styles and theme resources.
- **A native .NET Framework WinExe host** (`host/DaiBanHost.cs`) starts the app, extracts embedded resources, and hosts the UI engine in-process.
- **The existing WPF app logic** (`app/DaiBan.ps1`) is embedded as a resource at build time. It is not installed as a visible `.ps1` file.
- **WiX Toolset v3** builds the standard per-user MSI (`installer/DaiBan.wxs`).
- A small C# helper compiled at runtime wraps Win32/COM calls for native title-bar movement, DWM theme attributes and the modern folder picker.

This hybrid structure was chosen to keep the already-tested WPF interface and local data behavior while presenting a normal Windows app experience: one `DaiBan.exe`, one MSI installer, no console, no visible scripts.

## Build flow

```text
app/DaiBan.ps1, app/ui.xaml, themes, app.ico
                  │
                  ▼
host/build.ps1 ── csc ──► dist/native/DaiBan.exe
                  │           (resources embedded)
                  ▼
installer/build-msi.ps1 ── candle/light ──► dist/installer/DaiBan-1.3.0.msi
```

The native host is compiled against the Windows PowerShell engine that ships with Windows 11. No PowerShell installation or extra runtime is required.

## Startup

1. `DaiBan.exe` starts as a normal GUI process and sets its taskbar identity.
2. It extracts `ui.xaml`, light/dark theme dictionaries and the icon into `%LOCALAPPDATA%\DaiBan\host\1.3.0`.
3. It extracts the embedded application logic into memory and runs it in an STA runspace.
4. The app loads settings and tasks, loads `ui.xaml`, merges the effective theme, and shows the WPF window.
5. Each task mutation saves immediately. Closing retries only pending changes; if that save fails, closing is cancelled. Unchanged or unreadable files are not rewritten when closing.

## Installation

`DaiBan-1.3.0.msi` is a per-user Windows Installer package:

- Installs `DaiBan.exe` to `%LOCALAPPDATA%\Programs\DaiBan`.
- Creates Start menu and desktop shortcuts.
- Registers an entry in Windows “Installed apps”.
- Removes the previous script-based install files if present.
- Does not require administrator elevation.
- Uninstalls through Windows Installer; task data under `%APPDATA%\DaiBan` is preserved.

The portable `DaiBan.exe` is the same application without the MSI wrapper.

## Data

```text
%APPDATA%\DaiBan\settings.json   appearance and custom data folder
%APPDATA%\DaiBan\todos.json      default task list
<custom folder>\todos.json       optional task list location
```

Settings and tasks are separate so changing the task folder never moves the settings file. Writes use a temporary file plus `File.Replace`/`File.Move`. When switching into a directory that already has `todos.json`, the app backs it up before overwriting, and it leaves the old source file in place.

Task loading validates the existing version-1 structure before enabling edits. Read errors or unknown formats preserve the original file and backup, disable mutations, and never trigger an empty close-time save. Invalid settings are preserved rather than overwritten by theme changes. Persistence status distinguishes a new empty list, confirmed disk data, an in-progress write, a write error, and a read error.

## Themes

`app/themes/light.xaml` and `app/themes/dark.xaml` define the same resource key set. UI controls use `DynamicResource`; switching swaps the merged theme dictionary. The native DWM dark-mode and border attributes are updated at the same time. “Follow system” reads the current user's app theme and polls it while the window is open.

## Privacy

No network requests, telemetry, accounts, auto-updates or registry writes at runtime. The MSI creates the standard Installer registration; the application itself only reads/writes its local data folder.

See [SIGNING.md](SIGNING.md) for the unsigned-release caveat and signing steps.
