# Frozen screenshot and clipboard editor (1.5.1)

Press your **Freeze & edit** shortcut to capture the connected displays and open an editor over the display under the pointer. The picture stays still while videos and apps keep running underneath. Captures are taken when the shortcut runs; connected displays are requested concurrently, rather than waiting until you move to them.

The shortcut is configurable. With AbuBakar's current settings, **Option–1** opens the editor and **Option–2** takes an immediate full-display screenshot.

## Two Freeze & edit workflows

For a quick rectangular screenshot:

1. Press Option–1.
2. Drag the rectangle.
3. Release. ShotKey exports immediately and closes, using the separate **Quick selection** output setting.

For annotation:

1. Press Option–1.
2. Before dragging, choose a tool such as A, R, T, B, C, I, or O. This disables instant export.
3. Annotate and optionally crop. Enter only confirms a pending crop.
4. Press Command–Enter or click the save icon.

Pressing Option–1 again while the editor is visible does nothing. It cannot export accidentally. Edited images use **After capture**; clipboard-image edits use the independent **Clipboard edits** setting. The toolbar, picker lens, crop shading, and messages are never part of the exported image.

## Tools and keys

| Key | Action |
| --- | --- |
| V | Select an annotation, drag to move, or drag its end handle to resize |
| A | Arrow |
| L | Line |
| R | Rectangle |
| E | Ellipse; hold Shift for a circle |
| T | Text; click to type, Enter finishes editing, Shift–Enter adds a line |
| B | Rectangular blur |
| I | Pixel color picker; click to copy six-digit hex without a hash |
| O | Drag a region to copy recognized text with line breaks |
| C | Crop; drag, adjust, then Enter |
| Command–Z | Undo |
| Command–Shift–Z | Redo |
| Command–D | Duplicate selected annotation |
| Delete | Delete selected annotation |
| Arrow keys | Move selection; Shift moves in larger steps |
| Tab | Hide/show the movable toolbar |
| Command–Enter | Export with the configured output behavior |
| Escape | Hide and preserve the editor; restore it from Open Last Edit |

Hold Shift while drawing a line or arrow to snap it to 45-degree increments. Hold Shift for a square rectangle. Use V and double-click a text annotation to edit it again.

The editor starts in a special quick-selection crop mode. Releasing the first drag immediately exports. Choosing any editor tool—including C—switches to normal editing. In normal Crop mode, releasing a drag leaves an adjustable preview; Enter confirms it without exporting. Drag inside to move it or drag a corner to resize. A confirmed crop can be replaced by a larger or smaller crop without undoing first. Cropping remains reversible through Command–Z.

## Remembered options

Each tool remembers its own last color and options across editor sessions and app restarts. Rectangles and ellipses have outline, fill, and outline-plus-fill modes. Text supports adjustable size, a rounded background using the fill color, with its own color (no text outline). Blur strength and stroke width are adjustable.

Selecting an existing annotation displays its saved style. Changing an option updates that annotation and the defaults for its tool; the edit itself is undoable.

## Displays and shortcuts

Only one editor session is visible at a time. Further shortcut presses during initial capture are ignored, and Option–1 does nothing while the editor is visible. After Escape hides and preserves an edit, Option–1 always takes a fresh capture. The preserved edit is restored only when you explicitly choose the toolbar restore icon or **Open Last Edit** from ShotKey's menu.

Move the pointer onto another display to switch to its frozen image. Edits on each screen are retained if you switch back. During a drag, pending crop, text entry, or color selection, switching pauses so the editor does not disappear while you work. Export uses the currently active display's document.

Escape hides the editor in one press without throwing the edit away. Click the circular restore icon in the top toolbar or choose **Open Last Edit** in ShotKey's menu to restore it. **Discard Last Edit** removes it without exporting. Preservation lasts while ShotKey remains running; quitting the app clears it. Starting or exporting a fresh edit does not silently overwrite the preserved one; hiding another edit replaces the older preserved edit.

## Verification and boundaries

Run `./Tools/test-editor.sh` for the regression checks. This works with Xcode Command Line Tools and does not require XCTest or a full Xcode installation. Tests use synthetic images and do not copy to the system clipboard or save into the screenshot destination.

Covered checks include 500 undo/redo operations, Retina crop dimensions/orientation, shape pixels, blur boundaries, per-tool preference persistence, repeated shortcuts during capture, cancellation of late capture results, and offscreen rendering. Native visual checks are separate from these automated checks.

ScreenCaptureKit still needs macOS Screen Recording permission. An ad-hoc signed rebuild may need permission granted again; see [the permission guide](MACOS_SCREEN_CAPTURE_GUIDE.md). This release captures still images, not video. Its blur is an image effect; use an opaque filled rectangle when content must be completely covered.

Interaction references: [ShareX's editor documentation](https://getsharex.com/docs/image-editor) and [Flameshot](https://github.com/flameshot-org/flameshot). The editor is implemented in Swift/AppKit; no source code from those projects is included.

## Clipboard images

The **Edit clipboard image** shortcut defaults to **Option–3** and is configurable in Settings. It reads the image currently on the system clipboard, not a clipboard-history database. It opens in a separate resizable window at its original pixel resolution, with the initial view scaled to fit. Scroll to pan; use the trackpad magnification gesture to zoom. This workflow does not need Screen Recording permission.

**Clipboard edits** in Settings is independent of **After capture** and defaults to **Copy to Clipboard Only**. Change it there or in the editor's ellipsis menu. Command–Enter or the save icon exports. Only one edit session can be active: opening another clipboard image brings the current edit forward instead of replacing unsaved work.

## Compact toolbar and colors

The single-row toolbar shows contextual options for the active tool. On a smaller screen/window, tools and options scroll horizontally while the ellipsis menu stays accessible. Export, close, undo, redo and apply-crop actions are also in the canvas right-click menu. Tab hides/shows the toolbar. Confirmed crops strongly darken the excluded area; undo restores the previous crop.

Color fields accept six hexadecimal digits without a hash, for example `5785D1`. Press I and move over the frozen image. The lens shows individual source-image pixels, including on Retina displays. Click to copy uppercase hex and apply it to the previous tool's foreground color. Option-click applies fill/background instead. Picking samples the rendered image including annotations, but excludes toolbar, lens and crop shading. Colors are interpreted in sRGB; the six digits describe RGB, not transparency.

## Universal screen utilities

The picker and OCR also work without opening Freeze & edit:

- **Command–Shift–C** starts the global color picker by default.
- **Control–Command–Shift–C** starts global OCR selection by default.

Both shortcuts are configurable in Settings. Each captures only the display under the pointer at the moment the shortcut is pressed. The color lens appears immediately near the pointer; click a pixel to copy its uppercase six-digit RGB value without a hash. A fading confirmation shows both the color swatch and code. Escape cancels without changing the clipboard.

Global OCR freezes the display, lets you drag around text, then closes the overlay and recognizes locally. Success produces a fading copied confirmation. Escape cancels. If the full editor is already visible, either global shortcut selects the corresponding I or O editor tool instead of stacking another overlay.

## Text recognition

Press O and drag around text, or choose **Copy all visible text (OCR)** in the ellipsis menu to read the current crop. Recognition runs locally using Apple's [Vision framework](https://developer.apple.com/documentation/vision/vnrecognizetextrequest). Detected lines remain separate rather than being flattened into one paragraph. No text found or a recognition failure leaves the clipboard unchanged.

OCR is best-effort: language, resolution, fonts, columns and unusual layouts can affect accuracy and reading order. Review important text. Exporting an image later replaces clipboard text if the output mode includes copying the image.

## 1.5.1 verification

The regression runner additionally checks independent clipboard output modes, original import pixel dimensions, suspend/resume, prevention of Option–1 export, explicit export, immediate quick selection, crop expansion, six-digit hex parsing, Retina color coordinates and actual two-line Vision recognition. Tests use a private temporary pasteboard and do not replace the user's clipboard. Native shortcut and toolbar checks are performed separately.

The installed app uses the stable **ShotKey Local Development** identity documented in the permission guide. That identity prevents ordinary local rebuilds from turning into new hash-based apps in macOS privacy settings.
