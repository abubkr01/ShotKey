# Changelog

## 1.5 — Universal picker/OCR and safer editing

- Added configurable global color-picker and OCR shortcuts. They capture the display under the pointer without opening the full editor; the existing I and O editor tools remain.
- The global color picker opens directly under the pointer with an exact-pixel lens, copies six-digit hex, and confirms with a fading color swatch.
- Global OCR lets the user drag around screen text, runs locally, retains detected line breaks, and confirms when copied.
- Option–1 can no longer export an open editor. Keyboard export is Command–Enter only; a fixed save icon provides the mouse alternative.
- Restored instant rectangular capture as the initial Freeze & edit behavior. Its remembered output setting is independent from full-display and edited-image output.
- Escape now hides the editor once while preserving its complete in-memory state; **Open Last Edit** restores it while ShotKey remains running.
- Enter confirms a pending crop but never exports. A confirmed crop can be replaced by a larger selection without first undoing it.

## 1.4 — Clipboard editing, pixel colors, and text extraction

- Configurable Edit Clipboard Image shortcut (Option–3 by default) and a separate resizable editor.
- Independent, remembered clipboard-edit output preference, defaulting to clipboard only.
- Exact-pixel magnifying color picker (I); copies six uppercase hex digits without a hash. Option-click applies fill/background color.
- Local Vision OCR (O), preserving detected line breaks. Drag a region or read the full crop from the menu.
- Compact single-row toolbar with contextual style controls and horizontal scrolling on small screens.
- Export, close, undo, redo and apply-crop actions moved into the overflow/right-click menu.
- First Escape warns; a second within three seconds closes without exporting.
- Enter adds a text newline; Control–Enter commits text. Removed text outlines, retaining background color.
- Confirmed crop exclusions are much darker. Shading, lens and status messages never appear in exported images.
- Regression checks for clipboard output independence, double-Escape, Retina pixel coordinates, hex validation and real multiline OCR.
- Added automatic use of a stable private local signing identity on the development Mac, preventing every rebuild from receiving a new hash-based TCC identity.
- A failed or virtual secondary display no longer aborts every frozen capture and masquerades as a permission failure; successfully captured displays still open in the editor.

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
