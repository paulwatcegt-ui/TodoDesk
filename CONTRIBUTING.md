# Contributing

Thanks for considering a contribution to DaiBan. The project intentionally stays small: one local todo list, no accounts, no cloud sync, no extra modules.

## Requirements

- Windows 11
- Windows PowerShell 5.1 (built in)
- No build tools or package manager required

## Run from a checkout

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\DaiBan.ps1
```

The app uses `%APPDATA%\DaiBan` by default. For isolated manual testing you can point the config and default data folders elsewhere:

```powershell
$env:DAIBAN_CONFIG_DIR = Join-Path $PWD '.testdata'
$env:DAIBAN_DATA_DIR = Join-Path $PWD '.testdata'
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\DaiBan.ps1
```

These environment variables are development aids, not part of the user-facing settings.

## Validation

Run validation before opening a pull request:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\validate.ps1
```

It checks:

- UTF-8 BOM and parse validity for every PowerShell file.
- XAML parse validity.
- Required named UI controls.
- Complete theme resource keys for both light and dark dictionaries.
- No contributor-specific local paths in shipped code.

## Code guidelines

- Keep the feature set intentionally narrow.
- Use 4 spaces for indentation in PowerShell and XAML.
- Keep Chinese user-facing strings in the `.ps1`/`.xaml` sources; PowerShell files with Chinese strings must be UTF-8 with BOM for Windows PowerShell 5.1.
- New visual colors belong in both `app/themes/light.xaml` and `app/themes/dark.xaml`, referenced through `DynamicResource`.
- Prefer native Windows behavior for system dialogs and window chrome.
- Do not add background services, auto-start entries, telemetry, or network calls without a separate design discussion.
- Update `CHANGELOG.md` for user-visible changes.

## Packaging and signing

- Package with `scripts/package.ps1`.
- Signing is optional and requires a code-signing certificate. See [docs/SIGNING.md](docs/SIGNING.md).
- Never commit private keys, PFX files, or passwords. The `.gitignore` already excludes common signing files.

## Pull requests

A useful pull request includes:

- What changed and why.
- A short manual test note (theme switched, data folder changed, etc.).
- Screenshots for visible UI changes, including both light and dark appearance when relevant.
- Confirmation that `tests/validate.ps1` passes.
