#!/bin/bash
# Installs the latest note4meet release.
#
#   curl -fsSL https://raw.githubusercontent.com/note4meet/note4meet/main/install.sh | bash
#
# Files downloaded with curl are not flagged as "downloaded from the internet",
# so macOS opens the app without the Gatekeeper warning. Read this script before
# running it – it only downloads the release ZIP from GitHub and copies the app.
set -euo pipefail

REPO="note4meet/note4meet"
URL="https://github.com/$REPO/releases/latest/download/note4meet.zip"

if [[ -w /Applications ]]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading note4meet …"
curl -fsSL "$URL" -o "$TMP/note4meet.zip"
ditto -x -k "$TMP/note4meet.zip" "$TMP"

pkill -x note4meet 2>/dev/null || true
rm -rf "$DEST/note4meet.app"
cp -R "$TMP/note4meet.app" "$DEST/"
echo "Installed to $DEST/note4meet.app"
open "$DEST/note4meet.app"
