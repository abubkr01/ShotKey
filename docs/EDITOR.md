# Frozen screenshot editor (1.3)

Press your **Freeze & edit** shortcut to capture the connected displays and open an editor over the display under the pointer. The picture stays still while videos and apps keep running underneath. Captures are taken when the shortcut runs; connected displays are requested concurrently, rather than waiting until you move to them.

The shortcut is configurable. With AbuBakar's current settings, **Option–1** opens the editor and **Option–2** takes an immediate full-display screenshot.

## Quick workflow

1. Press Option–1.
2. Press A and drag an arrow, or choose another tool.
3. Press C and drag the final crop. Press Enter or click **✓ Crop**.
4. Press Option–1 again, or click **Done**.

Done uses the output behavior selected in ShotKey Settings: save and copy, clipboard only, or file only. The editor and its toolbar are never part of the exported image.

## Tools and keys

| Key | Action |
| --- | --- |
| V | Select an annotation, drag to move, or drag its end handle to resize |
| A | Arrow |
| L | Line |
| R | Rectangle |
| E | Ellipse; hold Shift for a circle |
| T | Text; click to type, Enter commits, Shift–Enter adds a line |
| B | Rectangular blur |
| C | Crop; drag, adjust, then Enter or ✓ Crop |
| Command–Z | Undo |
| Command–Shift–Z | Redo |
| Command–D | Duplicate selected annotation |
| Delete | Delete selected annotation |
| Arrow keys | Move selection; Shift moves in larger steps |
| Tab | Hide/show the movable toolbar |
| Command–S | Finish with your configured output behavior |
| Escape | Cancel current typing/drag/crop; press again to close the editor |

Hold Shift while drawing a line or arrow to snap it to 45-degree increments. Hold Shift for a square rectangle. Use V and double-click a text annotation to edit it again.

The editor starts in Crop mode for quick area screenshots. Releasing a crop drag leaves a preview so you can adjust it before committing. Drag inside the preview to move it, or drag a corner to resize. Cropping is reversible through undo. Annotation history has no fixed step limit and stores shape data rather than a full screenshot for every step.

## Remembered options

Each tool remembers its own last color and options across editor sessions and app restarts. Rectangles and ellipses have outline, fill, and outline-plus-fill modes. Text supports adjustable size, a rounded background using the fill color, and a separately colored outline. Blur strength and stroke width are adjustable.

Selecting an existing annotation displays its saved style. Changing an option updates that annotation and the defaults for its tool; the edit itself is undoable.

## Displays and shortcuts

Only one editor session can exist. Further shortcut presses during initial capture are ignored. Once the editor is ready, the same shortcut finishes it. A press during an active mouse drag is ignored until the drag ends.

Move the pointer onto another display to switch to its frozen image. Edits on each screen are retained if you switch back. During a drag, pending crop, text entry, or color selection, switching pauses so the editor does not disappear while you work. Done exports the currently active display's document.

The full-display shortcut is ignored while an editor is open to prevent accidentally capturing the editor itself. Escape or Done restores normal full-display capture.

## Verification and boundaries

Run `./Tools/test-editor.sh` for the regression checks. This works with Xcode Command Line Tools and does not require XCTest or a full Xcode installation. Tests use synthetic images and do not copy to the system clipboard or save into the screenshot destination.

Covered checks include 500 undo/redo operations, Retina crop dimensions/orientation, shape pixels, blur boundaries, per-tool preference persistence, repeated shortcuts during capture, cancellation of late capture results, and offscreen rendering. Native visual checks are separate from these automated checks.

ScreenCaptureKit still needs macOS Screen Recording permission. An ad-hoc signed rebuild may need permission granted again; see [the permission guide](MACOS_SCREEN_CAPTURE_GUIDE.md). This release captures still images, not video. Its blur is an image effect; use an opaque filled rectangle when content must be completely covered.

Interaction references: [ShareX's editor documentation](https://getsharex.com/docs/image-editor) and [Flameshot](https://github.com/flameshot-org/flameshot). The editor is implemented in Swift/AppKit; no source code from those projects is included.
