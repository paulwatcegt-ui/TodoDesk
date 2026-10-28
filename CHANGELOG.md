# Changelog

## 1.3.0 — Unreleased

- Auto-confirm new-task drafts on outside clicks while keeping priority/reminder configuration safe.
- Added a settings recycle bin for delete/clear operations and completed-task archiving with recovery and undo; stored all collections atomically in the same data file.
- Updated the settings product name to TodoDesk and added MIT/maintainer information while preserving existing copyright notices.

- Show task priority through title colors, expose per-task priority choices only while editing, and hide reminder/edit/delete controls until hover or keyboard focus.
- Added persistent, enabled-by-default switches for priorities and reminders without clearing existing task metadata.
- Commit inline edits on clicks outside the editor while keeping priority-menu interactions safe; replaced the Enter hint with a draft reminder picker for new tasks.

- Refined priority controls into tinted badges and rounded popovers with colored dots, a selected checkmark and consistent theme-aware hover states; removed the native icon gutter and square frame.
- Quieted task rows by showing edit/delete actions on pointer hover or keyboard focus.

- Removed the two hero copy lines to give the list more space.
- Added high/medium/low task priorities with distinct theme-aware colors, composer selection, row menus, persistence and undo; legacy tasks default to medium.
- Replaced the duplicate circular keyboard-focus adorner with focus feedback on the existing completion circle.

- Improved reminder setup with relative-time presets, a calendar, hour/minute steppers and a live summary; cancellation preserves the previous reminder.
- Fixed reminder save/remove callbacks failing to resolve script-local functions when started through the normal application entry point, and added a regression check using that entry path.

- Fixed compact filter-label clipping by measuring the row from its content.
- Added per-task local reminder times, cancellation, overdue catch-up on launch and a separate notification window that works while minimized.

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
