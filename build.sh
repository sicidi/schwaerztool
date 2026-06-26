#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="Schwaerzen"
APPDIR="$ROOT/build/$BUNDLE.app"
MACOS="$APPDIR/Contents/MacOS"

echo "→ Räume altes Build auf …"
rm -rf "$APPDIR"
mkdir -p "$MACOS" "$APPDIR/Contents/Resources"

echo "→ Kopiere Info.plist & Icon …"
cp "$ROOT/Info.plist" "$APPDIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APPDIR/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/cgi-logo.png" "$APPDIR/Contents/Resources/cgi-logo.png"

echo "→ Kompiliere (Swift, arm64) …"
swiftc -O -swift-version 5 \
    -framework Cocoa \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -framework CoreGraphics \
    "$ROOT/Sources/Core.swift" \
    "$ROOT/Sources/main.swift" \
    -o "$MACOS/$BUNDLE"

echo "→ Signiere (ad-hoc) …"
codesign --force --sign - "$APPDIR"

echo "✓ Fertig: $APPDIR"
