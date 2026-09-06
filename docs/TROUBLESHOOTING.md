# Troubleshooting

## Screen Recording looks enabled, but ShotKey still says it needs permission

This can happen with locally built Mac apps. macOS remembers Screen Recording permission against the app's signed identity. Rebuilding the app with ad-hoc signing can change that identity while the old ShotKey entry still looks enabled in Settings.

Try these steps in order:

1. Quit ShotKey completely with **⌘Q**.
2. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
3. Turn ShotKey off. If a minus button is available, remove the old ShotKey entry.
4. Make sure the current app is installed at `/Applications/ShotKey.app`.
5. Open that exact copy of ShotKey and enable its permission when asked.
6. Click **Quit & Reopen**, or quit ShotKey and open it again yourself.

If the stale entry remains, reset ShotKey's Screen Recording permission in Terminal:

```bash
tccutil reset ScreenCapture com.abubakar.ShotKey
```

Then open `/Applications/ShotKey.app` and grant access again.

## The shortcut does nothing

- Open ShotKey from the menu bar and check that the shortcut shown is the one you expect.
- Record a different combination if another app or macOS already uses that shortcut.
- Confirm ShotKey is still running in the menu bar.
- Confirm Screen Recording access is enabled.

## The wrong display is captured

Move the pointer onto the display you want before using either shortcut. ShotKey deliberately chooses the display under the pointer rather than the main display.

## Area selection is cancelled

The selector closes when you press Escape or when the selected area is too small. Drag a visible rectangle and release the mouse to capture.

## Why macOS calls it “Screen & System Audio Recording”

That is the name of the macOS privacy category. ShotKey captures still images and does not record or store system audio.
