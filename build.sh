#!/bin/bash
# Build Winndow.app (universal: Apple silicon + Intel). Needs only the Xcode Command Line Tools.
#   ./build.sh        -> build/Winndow.app and build/Winndow.zip
#   ./build.sh test   -> run the geometry self-check
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
mkdir -p build

if [[ "${1:-}" == "test" ]]; then
  cat Sources/Layout.swift Tests/LayoutCheck.swift > build/check.swift
  swiftc build/check.swift -o build/check && ./build/check
  exit
fi

APP=build/Winndow.app
rm -rf "$APP" build/Winndow.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" Sources/*.swift -o "build/Winndow-$arch"
done
lipo -create build/Winndow-arm64 build/Winndow-x86_64 -output "$APP/Contents/MacOS/Winndow"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A stable local identity keeps macOS's Accessibility grant across rebuilds; CI falls back to ad-hoc.
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-identity -p codesigning | grep -q "Winndow Local Signing"; then
  SIGN_IDENTITY="Winndow Local Signing"
fi
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP"
ditto -c -k --keepParent "$APP" build/Winndow.zip
echo "Built $APP ($VERSION) and build/Winndow.zip"
