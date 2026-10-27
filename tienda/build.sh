#!/bin/bash
# Compila Magnusson.app (la tienda de la familia). Universal: Apple Silicon + Intel.
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/Magnusson.app"
rm -rf dist build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" -o "build/Magnusson-$arch" Sources/*.swift
done
lipo -create build/Magnusson-arm64 build/Magnusson-x86_64 -output "$APP/Contents/MacOS/Magnusson"
cp Info.plist "$APP/Contents/Info.plist"
BUILD="${GITHUB_RUN_NUMBER:-0}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.$BUILD" "$APP/Contents/Info.plist"
ICONSET=build/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
cd dist
ditto -c -k --keepParent "Magnusson.app" Magnusson.zip
echo "OK → tienda/dist/Magnusson.app"
