# Changelog

## 1.3 — Frozen editor

- Replaced overlapping region overlays with one guarded capture/edit session.
- Freeze connected displays before opening the editor; preserve the original frame during annotation.
- Added arrows, lines, rectangles, ellipses, editable text, blur, and reversible cropping.
- Added per-tool style persistence, multi-step undo/redo, selection, movement, resizing, duplication, and deletion.
- Added keyboard tool selection and finishing with the same configurable capture shortcut.
- Added display following, preserving edits separately on each display.
- Added a standalone regression suite and [editor usage guide](docs/EDITOR.md).

## 1.2.0 — 2026-09-06

- Added **Save + Copy to Clipboard**, **Copy to Clipboard Only**, and **Save to Folder Only** output modes.
- Added immediate PNG clipboard copying after capture.
- Fixed the area-selection overlay on external and ultrawide displays with non-zero display coordinates.
- Kept full-display capture tied to the display under the mouse pointer.
- Added PNG and JPEG saving, a remembered destination folder, editable global shortcuts, launch at login, and native menu-bar controls.
- Added a native app icon and **Quit ShotKey (⌘Q)**.

This is the first public checkpoint of ShotKey.
