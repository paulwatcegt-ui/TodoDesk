# Changelog

## 1.3.0 — Unreleased

- Updated the palette to cool slate and periwinkle using the supplied visual reference.
- Centered checkmark geometry, added completed-task strikethrough and enabled a compact 400x400 window with a fitting settings dialog.

- Refined text contrast, input focus, short-list spacing and completed-group folding.
- Added undo for adding, editing and completion, while preserving native text undo.
- Added native maximize/restore controls and monitor work-area bounds for maximized windows.
- Made persistence status explicit; protected unreadable data/settings and kept unsaved changes visible when closing fails.
- Expanded validation to cover contrast, real file locks, corrupt files, fresh-process reload, native window controls and three window sizes.

- Redesigned the native window with a quiet green palette and responsive column.
- Added task filters, progress and contextual empty states.
- Added one-click source preview with isolated sample data and a normal source launcher.
- Fixed title-bar dragging and scoped instance locks to the configuration directory.
- Added interaction checks for editing, filtering, undo, themes and persistence.
- Updated documentation and repository links for TodoDesk.

All notable changes to DaiBan are documented here.

## 1.2.0 — 2026-10-27

### Added

- A native `DaiBan.exe` application host with the app icon, version information and window icon.
- A formal per-user Windows Installer (MSI) with Start menu shortcut, desktop shortcut and an entry in Windows “Installed apps”.
- A single-file portable build.
- The installation directory now contains only `DaiBan.exe`; no visible scripts or console.

### Changed

- The release download is now an MSI instead of a ZIP plus PowerShell installer.
- The native host embeds the WPF resources so the application starts without external `ui.xaml`/theme files.
- The app version is now 1.2.0.

### Kept

- Follow-system / light / dark appearance.
- Custom task data directory.
- Native title-bar dragging and edge resizing.
- Local-only data and undo for delete/clear-completed.

## 1.1.0 — 2026-10-27

### Added

- Settings sheet with light, dark and follow-system appearance.
- User-selectable data directory using the modern Windows folder picker.
- Safe data-directory switching with backup protection.
- Native window dragging.
- Open-source project scaffolding.

### Fixed

- The window can now be dragged by the title bar.
- Duplicate launches exit quietly.
- Adding a task reveals the top of the list.

## 1.0.0 — 2026-10-27

- First local-only minimal todo app.
- Add, complete, edit, delete, clear completed and undo.
- Automatic local persistence.
- Windows 11 custom chrome.
