# Frozen screenshot and clipboard editor (1.4)

Press your **Freeze & edit** shortcut to capture the connected displays and open an editor over the display under the pointer. The picture stays still while videos and apps keep running underneath. Captures are taken when the shortcut runs; connected displays are requested concurrently, rather than waiting until you move to them.

The shortcut is configurable. With AbuBakar's current settings, **Option–1** opens the editor and **Option–2** takes an immediate full-display screenshot.

## Quick workflow

1. Press Option–1.
2. Press A and drag an arrow, or choose another tool.
3. Press C and drag the final crop. Press Enter.
4. Press Option–1 again, or press Command–S.

Export uses the output behavior selected in ShotKey Settings: save and copy, clipboard only, or file only. The editor and its toolbar are never part of the exported image.

## Tools and keys

| Key | Action |
| --- | --- |
| V | Select an annotation, drag to move, or drag its end handle to resize |
| A | Arrow |
| L | Line |
| R | Rectangle |
| E | Ellipse; hold Shift for a circle |
| T | Text; click to type, Enter adds a line, Control–Enter commits |
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
| Command–S | Finish with your configured output behavior |
| Escape | First press warns; press again within three seconds to discard and close |

Hold Shift while drawing a line or arrow to snap it to 45-degree increments. Hold Shift for a square rectangle. Use V and double-click a text annotation to edit it again.

The editor starts in Crop mode for quick area screenshots. Releasing a crop drag leaves a preview so you can adjust it before committing. Drag inside the preview to move it, or drag a corner to resize. Cropping is reversible through undo. Annotation history has no fixed step limit and stores shape data rather than a full screenshot for every step.

## Remembered options

Each tool remembers its own last color and options across editor sessions and app restarts. Rectangles and ellipses have outline, fill, and outline-plus-fill modes. Text supports adjustable size, a rounded background using the fill color, with its own color (no text outline). Blur strength and stroke width are adjustable.

Selecting an existing annotation displays its saved style. Changing an option updates that annotation and the defaults for its tool; the edit itself is undoable.

## Displays and shortcuts

Only one editor session can exist. Further shortcut presses during initial capture are ignored. Once the editor is ready, the same shortcut finishes it. A press during an active mouse drag is ignored until the drag ends.

Move the pointer onto another display to switch to its frozen image. Edits on each screen are retained if you switch back. During a drag, pending crop, text entry, or color selection, switching pauses so the editor does not disappear while you work. Export uses the currently active display's document.

The full-display shortcut is ignored while an editor is open to prevent accidentally capturing the editor itself. Closing or exporting restores normal full-display capture.

## Verification and boundaries

Run `./Tools/test-editor.sh` for the regression checks. This works with Xcode Command Line Tools and does not require XCTest or a full Xcode installation. Tests use synthetic images and do not copy to the system clipboard or save into the screenshot destination.

Covered checks include 500 undo/redo operations, Retina crop dimensions/orientation, shape pixels, blur boundaries, per-tool preference persistence, repeated shortcuts during capture, cancellation of late capture results, and offscreen rendering. Native visual checks are separate from these automated checks.

ScreenCaptureKit still needs macOS Screen Recording permission. An ad-hoc signed rebuild may need permission granted again; see [the permission guide](MACOS_SCREEN_CAPTURE_GUIDE.md). This release captures still images, not video. Its blur is an image effect; use an opaque filled rectangle when content must be completely covered.

Interaction references: [ShareX's editor documentation](https://getsharex.com/docs/image-editor) and [Flameshot](https://github.com/flameshot-org/flameshot). The editor is implemented in Swift/AppKit; no source code from those projects is included.

## Clipboard images

The **Edit clipboard image** shortcut defaults to **Option–3** and is configurable in Settings. It reads the image currently on the system clipboard, not a clipboard-history database. It opens in a separate resizable window at its original pixel resolution, with the initial view scaled to fit. Scroll to pan; use the trackpad magnification gesture to zoom. This workflow does not need Screen Recording permission.

**Clipboard edits** in Settings is independent of **After capture** and defaults to **Copy to Clipboard Only**. Change it there or in the editor's ellipsis menu. Command–S exports. Only one edit session can be active: opening another clipboard image brings the current edit forward instead of replacing unsaved work.

## Compact toolbar and colors

The single-row toolbar shows contextual options for the active tool. On a smaller screen/window, tools and options scroll horizontally while the ellipsis menu stays accessible. Export, close, undo, redo and apply-crop actions are also in the canvas right-click menu. Tab hides/shows the toolbar. Confirmed crops strongly darken the excluded area; undo restores the previous crop.

Color fields accept six hexadecimal digits without a hash, for example `5785D1`. Press I and move over the frozen image. The lens shows individual source-image pixels, including on Retina displays. Click to copy uppercase hex and apply it to the previous tool's foreground color. Option-click applies fill/background instead. Picking samples the rendered image including annotations, but excludes toolbar, lens and crop shading. Colors are interpreted in sRGB; the six digits describe RGB, not transparency.

## Text recognition

Press O and drag around text, or choose **Copy all visible text (OCR)** in the ellipsis menu to read the current crop. Recognition runs locally using Apple's [Vision framework](https://developer.apple.com/documentation/vision/vnrecognizetextrequest). Detected lines remain separate rather than being flattened into one paragraph. No text found or a recognition failure leaves the clipboard unchanged.

OCR is best-effort: language, resolution, fonts, columns and unusual layouts can affect accuracy and reading order. Review important text. Exporting an image later replaces clipboard text if the output mode includes copying the image.

## 1.4 verification

The regression runner additionally checks independent clipboard output modes, original import pixel dimensions, double-Escape, six-digit hex parsing, Retina color coordinates and boundary clamping, and actual two-line Vision recognition. Tests use a private temporary pasteboard and do not replace the user's clipboard. The native single-row toolbar was visually checked separately.

On the installed 1.4 build launched normally from Applications, Option–3 opened the system clipboard image in its own window; the first Escape kept it open and the second closed it. The screenshot hotkey was also invoked, but a complete post-update screen capture was not verified. Ad-hoc signing still means macOS may require fresh approval; installing this release does not bypass or reset system permissions.
