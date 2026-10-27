# Contributing

Thanks for considering a contribution to DaiBan. The project intentionally stays small: one local todo list, no accounts, no cloud sync, no extra modules.

## Requirements

- Windows 11
- Windows PowerShell 5.1 (built in) and .NET Framework 4.8 (built in)
- WiX Toolset v3 only when building the MSI installer

No Node.js, npm, .NET SDK, or package restore is required.

## Build

Build the native application host:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\host\build.ps1
```

This produces `dist\native\DaiBan.exe`. The host embeds `app\DaiBan.ps1`, `app\ui.xaml`, the themes and the icon, so the installed app does not need external resource files.

Build the MSI (after placing/extracting WiX v3 in `%LOCALAPPDATA%\Programs\WiX`):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\build-msi.ps1
```

This produces `dist\installer\DaiBan-1.2.0.msi`.

## Run from source

The existing development path still runs the WPF interface directly:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\DaiBan.ps1
```

For isolated manual testing:

```powershell
$env:DAIBAN_CONFIG_DIR = Join-Path $PWD '.testdata'
$env:DAIBAN_DATA_DIR = Join-Path $PWD '.testdata'
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\DaiBan.ps1
```

The environment variables are development aids, not part of the installed app.

## Validation

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

The validator checks:

- UTF-8 BOM and syntax for PowerShell files.
- XAML loadability and required named controls.
- Complete theme resource keys for light and dark.
- The native host and MSI build files are present.
- No contributor-specific local paths in shipped source.

## Style

- Keep the feature set intentionally narrow.
- Use 4 spaces in PowerShell/XAML/C#; 2 spaces in YAML/Markdown.
- PowerShell files with Chinese strings must be UTF-8 with BOM for Windows PowerShell 5.1.
- New visual colors belong in both `app/themes/light.xaml` and `app/themes/dark.xaml`, referenced through `DynamicResource`.
- Update `CHANGELOG.md` and `RELEASE_NOTES.md` for user-visible changes.
- Do not commit signing certificates, PFX files, private keys, passwords, or build output (`dist/` is ignored).

## Release

The MSI is intentionally a standard Windows Installer package so it can be installed without the unsigned setup-wrapper issue. Build the app and MSI, verify the MSI by installing and uninstalling it, then upload the MSI and portable EXE with checksum files to a GitHub Release.

See [docs/SIGNING.md](docs/SIGNING.md) for signing.
