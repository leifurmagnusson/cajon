#!/bin/bash
# Compila Bolitas.app (universal: Apple Silicon + Intel). Requiere macOS con Xcode o Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
APP="dist/Bolitas.app"
rm -rf dist build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" -o "build/Bolitas-$arch" Sources/*.swift
done
lipo -create build/Bolitas-arm64 build/Bolitas-x86_64 -output "$APP/Contents/MacOS/Bolitas"
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
# Firma con un certificado propio y fijo: así macOS reconoce cada versión nueva como la misma app
# y no vuelve a pedir el permiso de Accesibilidad tras cada actualización.
if [ -n "${CI:-}" ]; then
  KC="$PWD/build/firma.keychain-db"
  security create-keychain -p firma "$KC"
  security set-keychain-settings "$KC"
  security unlock-keychain -p firma "$KC"
  security import signing/magnusson.p12 -k "$KC" -P magnusson -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple: -s -k firma "$KC" >/dev/null
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
  codesign --force --deep --timestamp=none --keychain "$KC" --sign 99D1980B1CB13ABE7E82DA241A3623F3439C8626 "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign -d -r- "$APP" 2>&1 | tail -2
cd dist
ditto -c -k --keepParent "Bolitas.app" Bolitas.zip
tar -czf Bolitas.tar.gz "Bolitas.app"
echo "OK → dist/Bolitas.app"
