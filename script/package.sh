#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
APP="$ROOT/dist/MiniCal.app"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/packages}"
[[ -d "$APP" ]] || { printf 'Run script/build.sh first\n' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
IDENTITY="${SIGNING_IDENTITY:--}"
SUFFIX=local
[[ "$IDENTITY" == - ]] || SUFFIX=developer-id
mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/minical-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/MiniCal.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/docs/INSTALL.txt" "$STAGE/INSTALL.txt"
DMG="$OUTPUT_DIR/MiniCal-$VERSION-arm64-$SUFFIX.dmg"
hdiutil create -volname MiniCal -srcfolder "$STAGE" -format UDZO -ov "$DMG"
if [[ "$IDENTITY" != - ]]; then codesign --force --sign "$IDENTITY" --timestamp "$DMG"; fi
hdiutil verify "$DMG"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf 'Packaged: %s\n' "$DMG"
