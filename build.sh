#!/bin/bash
# Baut note4meet.app. Mit --install wird die App nach ~/Applications kopiert und gestartet.
set -euo pipefail
cd "$(dirname "$0")"

# Universal-App für Intel- und Apple-Chip-Macs
# Getrennte Zwischenspeicher je Architektur, sonst scheitern erneute Builds
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build/x86_64
swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build/arm64

APP="build/note4meet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/note4meet" \
  .build/x86_64/x86_64-apple-macosx/release/note4meet \
  .build/arm64/arm64-apple-macosx/release/note4meet
cp Support/Info.plist "$APP/Contents/Info.plist"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/"
cp -R Support/en.lproj Support/de.lproj "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --sign - --identifier io.github.note4meet "$APP"
echo "Gebaut: $APP"

if [[ " $* " == *" --install "* ]]; then
  pkill -x note4meet 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/note4meet.app"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/note4meet.app"
  echo "Installiert und gestartet: ~/Applications/note4meet.app"
fi

if [[ " $* " == *" --zip "* ]]; then
  DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs/note4meet Installation"
  mkdir -p "$DEST"
  rm -f "$DEST/note4meet.zip"
  ditto -c -k --keepParent "$APP" "$DEST/note4meet.zip"
  cp Support/Installation-weiterer-Mac.md "$DEST/Anleitung.md"
  echo "ZIP abgelegt: iCloud Drive/note4meet Installation/"
fi

# Release-Paket für GitHub: dist/note4meet.zip (+ Prüfsumme)
if [[ " $* " == *" --release "* ]]; then
  mkdir -p dist
  rm -f dist/note4meet.zip
  ditto -c -k --keepParent "$APP" dist/note4meet.zip
  shasum -a 256 dist/note4meet.zip | tee dist/note4meet.zip.sha256
  echo "Release-Paket: dist/note4meet.zip"
fi

