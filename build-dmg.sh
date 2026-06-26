#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="Schwaerzen"
VOL="Schwärzen"
VER="1.0"
DIST="$ROOT/dist"
STAGE="$DIST/dmgroot"
DMG="$DIST/${BUNDLE}-${VER}.dmg"

echo "→ App frisch bauen …"
bash "$ROOT/build.sh"

echo "→ Signatur der App prüfen …"
codesign --verify --strict "$ROOT/build/$BUNDLE.app"

echo "→ DMG-Inhalt zusammenstellen …"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$ROOT/build/$BUNDLE.app" "$STAGE/$BUNDLE.app"   # signiertes Bundle 1:1 übernehmen
ln -s /Applications "$STAGE/Applications"               # Drag-to-Install-Ziel
cp "$ROOT/packaging/Erste Schritte.txt" "$STAGE/Erste Schritte.txt"

echo "→ DMG erzeugen …"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE"
echo "✓ Fertig: $DMG"
ls -lh "$DMG"
