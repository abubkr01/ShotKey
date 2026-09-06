# Development

ShotKey is a native Swift/AppKit menu-bar application. It uses ScreenCaptureKit for screenshots, Carbon for global hotkeys, Core Graphics for display geometry, AppKit for the interface and clipboard, and ServiceManagement for launch at login.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools
- Swift 5.9 or newer

## Build

```bash
./build-app.sh
```

The script builds the release executable, generates the icon, creates the `.app` bundle, and applies an ad-hoc signature. The result is `outputs/ShotKey.app`.

## Package

```bash
./package-dmg.sh
```

This rebuilds the app and creates `outputs/ShotKey-1.2.dmg` with an Applications shortcut.

## Permission behavior during development

The local build is ad-hoc signed. A rebuild can receive a different code identity, especially on newer macOS releases. If Screen Recording permission appears enabled but a new build cannot capture, remove the stale privacy entry and grant permission to the newly built copy. See [Troubleshooting](TROUBLESHOOTING.md).

For stable distribution, use an Apple Developer ID certificate and notarize the application. That gives future builds a stable identity and avoids Gatekeeper warnings.

For the complete explanation of the permission failure we encountered, the ScreenCaptureKit solution, and a reusable checklist for other apps, see [macOS Screen Capture Development Guide](MACOS_SCREEN_CAPTURE_GUIDE.md).

## Version checkpoint

The branch `checkpoint/v1.2.0` and local tag `v1.2.0` mark the working release with clipboard output modes and corrected multi-display area selection.

To inspect that exact version without disturbing current work:

```bash
git switch checkpoint/v1.2.0
```

To start an experiment safely:

```bash
git switch -c experiment/my-idea checkpoint/v1.2.0
```
