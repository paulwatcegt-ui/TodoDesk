# Changelog

All notable changes to DaiBan are documented here.

## 1.1.0 — 2026-10-27

### Added

- Settings sheet with light, dark and follow-system appearance.
- Live theme switching for the main window, dialogs and native title-bar treatment.
- User-selectable data directory, using the modern Windows folder picker.
- Safe data-directory switching: existing files are backed up, and settings are only persisted after the new location is writable.
- Native window dragging via the Windows caption move loop.
- Open-source project scaffolding: installer, uninstaller, validation, packaging, CI and signing documentation.

### Changed

- The completed-task text no longer uses a strikethrough; the blue check and muted text are enough.
- The window keeps three compact title-bar controls: settings, minimize and close.
- Settings and tasks are stored separately so a custom task folder does not move the settings file.

### Fixed

- The window can now be dragged by the title bar.
- Adding a task always reveals the top of the list.
- Duplicate launches exit quietly instead of stacking a second window.

## 1.0.0 — 2026-10-27

- First local-only minimal todo app.
- Add, complete, edit, delete, clear completed and undo.
- Automatic local persistence.
- Windows 11 custom chrome and light appearance.
