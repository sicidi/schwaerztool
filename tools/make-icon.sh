#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"     # build/ ist .gitignore-d
OUT="$ROOT/Resources/AppIcon.icns"

mkdir -p "$ROOT/Resources"
rm -rf "$ICONSET"

echo "→ Icon-Generator kompilieren …"
swiftc -O -swift-version 5 \
    -framework Cocoa -framework ImageIO -framework UniformTypeIdentifiers -framework CoreGraphics \
    "$ROOT/Sources/Core.swift" "$ROOT/tools/make-icon.swift" \
    -o /tmp/schwaerzen_makeicon

echo "→ PNGs rendern …"
/tmp/schwaerzen_makeicon "$ICONSET"

echo "→ .icns bauen …"
iconutil -c icns "$ICONSET" -o "$OUT"

echo "✓ $OUT"
ls -lh "$OUT"
