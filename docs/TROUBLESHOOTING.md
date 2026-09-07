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
tccutil reset ScreenCapture com.abubakar.shotkey
```

Then open `/Applications/ShotKey.app` and grant access again.

After resetting, keep that installed build unchanged until approval and a real capture test succeed. Do not rebuild or re-sign it in between. macOS requires the person using the Mac to approve Screen Recording; the reset command cannot grant it.

For future development builds, the build script first looks for the private **ShotKey Local Development** identity in AbuBakar's login keychain. It also accepts `SHOTKEY_SIGNING_IDENTITY` with the name of an installed Apple Development certificate. Without either identity it uses ad-hoc signing and prints a warning. Switching to ScreenCaptureKit alone does not make ad-hoc identities stable.

The bundle identifier must match exactly, including capitalization. Developers can use the reusable [macOS Screen Capture Development Guide](MACOS_SCREEN_CAPTURE_GUIDE.md) for signing diagnostics, ScreenCaptureKit implementation notes, and multi-display testing.

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
