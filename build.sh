#!/usr/bin/env bash
# build.sh: compile Menu Bar Guard.app with the Command Line Tools only (swiftc, no Xcode project).
# Usage: ./build.sh [dest-folder]   (default ./build)   --regen-icon re-draws the icon first.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${TARGET:-arm64-apple-macos14.0}"
DEST="${1:-$REPO/build}"; [ "$DEST" = "--regen-icon" ] && DEST="$REPO/build"
[ "${1:-}" = "--regen-icon" ] || [ "${2:-}" = "--regen-icon" ] && swift "$REPO/make-icon.swift"
APP="$DEST/MenuBarGuard.app"; C="$APP/Contents"
rm -rf "$APP"; mkdir -p "$C/MacOS" "$C/Resources"
SRC=(); for f in "$REPO"/*.swift; do [ "$(basename "$f")" = make-icon.swift ] || SRC+=("$f"); done
swiftc -O -parse-as-library -swift-version 5 -target "$TARGET" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -framework ApplicationServices \
  -framework ScreenCaptureKit -framework Carbon \
  "${SRC[@]}" -o "$C/MacOS/MenuBarGuard"
cp "$REPO/Info.plist" "$C/"; cp "$REPO/assets/MenuBarGuard.icns" "$C/Resources/" 2>/dev/null || true
xattr -cr "$APP"
codesign --force --deep --sign "${SIGN_ID:-Apple Development: solomond24@icloud.com (CCW242B7M5)}" "$APP" 2>/dev/null \
  || codesign --force --deep --sign - "$APP"
echo "Built $APP"
