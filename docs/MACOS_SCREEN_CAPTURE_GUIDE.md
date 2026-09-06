# macOS Screen Capture Development Guide

This guide records the problem that made ShotKey appear to have Screen Recording permission while macOS still refused to let it capture. It is written to be useful for ShotKey and for any future macOS app that captures screenshots, records a display, or reads screen content.

## The short version

Four things need to be correct at the same time:

1. Use **ScreenCaptureKit** for modern screen capture.
2. Include `NSScreenCaptureUsageDescription` in the app's `Info.plist`.
3. Keep the app's bundle identifier, installed path, and signing identity stable.
4. Treat every display as having its own origin, scale, and coordinate space.

The difficult ShotKey permission bug was mainly number 3. The app was ad-hoc signed. Each rebuild produced a designated requirement tied to that exact build, so macOS could show an older ShotKey entry as enabled while the rebuilt app was a different identity to TCC, macOS's privacy system.

Apple has confirmed this behavior: ad-hoc signed code cannot maintain a stable identity across versions. Use an **Apple Development** certificate for development builds and **Developer ID Application** plus notarization for direct distribution.

## 1. Add the required usage description

Every target that captures the screen needs this key in its built app's `Info.plist`:

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>This app captures the display or area you choose.</string>
```

Describe the real user-facing reason. Do not claim to record audio if the app does not. On recent macOS versions, System Settings calls the category **Screen & System Audio Recording**, but an app can still capture images with audio explicitly disabled.

Verify the key in the built product, not only the source plist:

```bash
plutil -p MyApp.app/Contents/Info.plist | grep NSScreenCaptureUsageDescription
```

## 2. Ask for permission deliberately

Core Graphics provides simple permission checks that work well before beginning a ScreenCaptureKit operation:

```swift
import CoreGraphics

func ensureScreenCapturePermission(prompt: Bool = true) -> Bool {
    if CGPreflightScreenCaptureAccess() {
        return true
    }
    return prompt ? CGRequestScreenCaptureAccess() : false
}
```

Recommended behavior:

- Check without prompting when updating passive UI state.
- Prompt only after the person performs a capture-related action or during clear onboarding.
- Explain that macOS may require the app to quit and reopen after access is granted.
- Do not repeatedly call the request function in a loop.
- If ScreenCaptureKit fails, check permission again before presenting a generic capture error.

An app cannot switch this privacy permission on for itself. Only the person using the Mac can approve it in System Settings.

## 3. Use ScreenCaptureKit for the capture

For a still image, ShotKey follows this sequence:

1. Read the current pointer location.
2. Find the `CGDirectDisplayID` whose `CGDisplayBounds` contains that point.
3. Retrieve `SCShareableContent`.
4. Match the Core Graphics display ID to an `SCDisplay`.
5. Build an `SCContentFilter` for that display.
6. Configure the output with `SCStreamConfiguration`.
7. Ask `SCScreenshotManager` for one image.

The core pattern is:

```swift
let content = try await SCShareableContent.excludingDesktopWindows(
    false,
    onScreenWindowsOnly: true
)

guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
    throw CaptureError.noDisplay
}

let filter = SCContentFilter(
    display: display,
    excludingApplications: [],
    exceptingWindows: []
)

let configuration = SCStreamConfiguration()
configuration.width = display.width
configuration.height = display.height
configuration.showsCursor = false
configuration.capturesAudio = false

let image = try await SCScreenshotManager.captureImage(
    contentFilter: filter,
    configuration: configuration
)
```

Setting `capturesAudio = false` makes the intent explicit for screenshot-only applications.

## 4. Understand the permission identity trap

macOS does not remember privacy permission using only the app name shown in Settings. It evaluates the app's code identity using its signature and designated requirement.

Inspect an app with:

```bash
codesign --display --verbose=4 MyApp.app
codesign --display -r- MyApp.app
codesign --verify --deep --strict --verbose=2 MyApp.app
```

An ad-hoc signature commonly produces a designated requirement based on a code-directory hash, similar to:

```text
designated => cdhash H"..."
```

When the executable changes, that hash changes. TCC can then treat the rebuild as a new app even though System Settings still displays an enabled entry with the same name and icon.

### Development signing

In Xcode:

1. Select the app target.
2. Open **Signing & Capabilities**.
3. Select your development team.
4. Use an **Apple Development** signing certificate for Debug builds.
5. Keep the bundle identifier unchanged.

If building from scripts, sign every build with the same valid Apple Development identity instead of `codesign --sign -`, where `-` means ad-hoc signing.

### Distribution signing

For an app distributed outside the Mac App Store:

1. Sign it with a **Developer ID Application** certificate.
2. Submit it to Apple for notarization.
3. Staple the notarization ticket to the app or DMG.
4. Verify the final artifact before publishing it.

This also prevents the normal “unidentified developer” experience caused by ad-hoc distribution.

## 5. Repair a stale permission entry

First determine the exact bundle identifier from the installed app:

```bash
defaults read /Applications/MyApp.app/Contents/Info CFBundleIdentifier
```

Then:

1. Quit every running copy of the app.
2. Delete or archive older copies so only the intended build remains.
3. Put the current build at its stable location, normally `/Applications/MyApp.app`.
4. Open **System Settings → Privacy & Security → Screen & System Audio Recording**.
5. Disable or remove the stale entry.
6. Reset the record using the exact bundle identifier:

```bash
tccutil reset ScreenCapture com.example.MyApp
```

7. Launch the installed copy, request access again, then quit and reopen it.

For ShotKey, the exact command is:

```bash
tccutil reset ScreenCapture com.abubakar.shotkey
```

Resetting TCC does not grant permission. It only removes the old decision so macOS can ask again.

Run the included helper against any built app to inspect the most important values and print the correct reset command:

```bash
./Tools/diagnose-screen-capture.sh /Applications/MyApp.app
```

## 6. Avoid testing the wrong copy

A common development mistake is having several apps with the same display name:

- an Xcode DerivedData build;
- an app in the project output folder;
- an older app in Downloads;
- the installed app in Applications.

System Settings may show them all as one friendly name even though their paths or signatures differ. Before testing, quit all copies and launch the exact path you mean to test:

```bash
open /Applications/MyApp.app
```

Also keep `CFBundleIdentifier` identical across rebuilds of the same development variant. If you intentionally maintain Debug and Release variants, consider distinct bundle identifiers so their permissions do not become confusing.

## 7. Handle multiple displays correctly

Do not assume the main screen begins at `(0, 0)`. A display positioned left of or above the main display can have a negative global origin. An ultrawide display can also use a different point-to-pixel scale than a Retina internal display.

ShotKey uses the pointer to choose the display:

```swift
let point = CGEvent(source: nil)?.location
let display = displays.first { CGDisplayBounds($0).contains(point) }
```

It then maps the selected display ID to `NSScreen` using `NSScreenNumber` rather than assuming `NSScreen.main` is correct.

### The external-display overlay fix

The area selector originally appeared as a small rectangle near the top-left of the ultrawide display because the borderless window mixed local content coordinates with the external display's global frame.

The reliable pattern is to create the window content at local origin zero, then explicitly place the finished window at the screen's global frame:

```swift
let window = SelectionWindow(
    contentRect: NSRect(origin: .zero, size: screen.frame.size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false,
    screen: screen
)
window.setFrame(screen.frame, display: true)
```

The selection view continues to work in display-local coordinates. This separation is important: the window uses the global desktop frame, while the drag rectangle uses coordinates relative to the selected screen.

### Convert the selected rectangle

AppKit view coordinates and ScreenCaptureKit's display source rectangle use different vertical orientation in this setup. ShotKey flips the Y value within the selected screen:

```swift
let sourceRect = CGRect(
    x: selection.minX,
    y: screen.frame.height - selection.maxY,
    width: selection.width,
    height: selection.height
)
```

Then convert points to pixels independently for each axis:

```swift
let displayBounds = CGDisplayBounds(displayID)
let scaleX = displayBounds.width / screen.frame.width
let scaleY = displayBounds.height / screen.frame.height

configuration.width = Int((sourceRect.width * scaleX).rounded())
configuration.height = Int((sourceRect.height * scaleY).rounded())
```

Do not hard-code `2.0` for Retina. Mixed-display setups can have different scaling.

## 8. A practical test matrix

Test a capture app in all of these situations before calling multi-display support complete:

- internal screen only;
- external screen only;
- pointer on each screen for full-display capture;
- area selection on each screen;
- external display placed left, right, above, and below the main screen;
- Retina and non-Retina or scaled displays together;
- different resolutions and an ultrawide aspect ratio;
- a fullscreen application and a different macOS Space;
- selector cancellation with Escape;
- permission denied, granted, revoked, and granted again;
- a clean install and an in-place rebuilt app;
- signed identity before and after rebuilding;
- saved file dimensions and clipboard image dimensions.

For every area capture, compare the rectangle shown during selection with the pixels in the final image. A capture can appear to succeed while using the wrong origin, Y direction, or scale.

## 9. Release checklist

Before shipping any screen-capture app:

- [ ] `NSScreenCaptureUsageDescription` exists in the built app.
- [ ] The bundle identifier is final and spelled consistently.
- [ ] Debug builds use a stable Apple Development identity.
- [ ] Public builds use Developer ID signing and notarization.
- [ ] `codesign --verify --deep --strict` succeeds.
- [ ] The installed copy is the same copy tested in System Settings.
- [ ] Permission denial produces a useful explanation rather than repeated prompts.
- [ ] Capture uses ScreenCaptureKit.
- [ ] Audio is disabled when it is not required.
- [ ] Multiple display origins and scales are tested.
- [ ] A clean Mac installation is tested before release.

## Apple references

- [ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit)
- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent)
- [TN3127: Inside Code Signing — Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple Developer Forums: ScreenCaptureKit permissions lost after every build](https://developer.apple.com/forums/thread/819406)

The forum thread includes confirmation from Apple Developer Technical Support that ad-hoc signing causes the system to treat each changed build as new code. TN3127 explains the underlying designated-requirement behavior in detail.
