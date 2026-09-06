#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/MyApp.app" >&2
  exit 64
fi

APP_PATH="$1"
INFO_PATH="$APP_PATH/Contents/Info.plist"

if [[ ! -d "$APP_PATH" || ! -f "$INFO_PATH" ]]; then
  echo "Not a macOS app bundle: $APP_PATH" >&2
  exit 66
fi

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PATH")
USAGE_DESCRIPTION=$(/usr/libexec/PlistBuddy -c 'Print :NSScreenCaptureUsageDescription' "$INFO_PATH" 2>/dev/null || true)

echo "App: $APP_PATH"
echo "Bundle identifier: $BUNDLE_ID"
if [[ -n "$USAGE_DESCRIPTION" ]]; then
  echo "Screen capture usage description: present"
else
  echo "Screen capture usage description: MISSING"
fi

echo
echo "Signature:"
/usr/bin/codesign --display --verbose=2 "$APP_PATH" 2>&1 | /usr/bin/grep -E '^(Identifier|Authority|TeamIdentifier|Signature)=' || true

echo
echo "Designated requirement:"
/usr/bin/codesign --display -r- "$APP_PATH" 2>&1 || true

echo
if /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
  echo "Code signature verification: valid"
else
  echo "Code signature verification: FAILED"
fi

echo
echo "To remove this app's stale Screen Recording decision:"
echo "tccutil reset ScreenCapture $BUNDLE_ID"
echo "This resets the decision; it does not grant access automatically."
