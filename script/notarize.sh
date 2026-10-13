#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set a pre-existing notarytool Keychain profile name}"
[[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { printf 'A Developer ID Application identity is required\n' >&2; exit 1; }
xcrun --find notarytool >/dev/null
"$ROOT/script/build.sh" --release
APP="$ROOT/dist/MiniCal.app"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/packages}"
mkdir -p "$OUTPUT_DIR"
SUBMISSION="$OUTPUT_DIR/MiniCal-notary-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUTPUT_DIR/app-notarization.json"
python3 - "$OUTPUT_DIR/app-notarization.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]));assert r.get('status')=='Accepted',r
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
OUTPUT_DIR="$OUTPUT_DIR" "$ROOT/script/package.sh"
DMG="$OUTPUT_DIR/MiniCal-$(cat "$ROOT/VERSION")-arm64-developer-id.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUTPUT_DIR/dmg-notarization.json"
python3 - "$OUTPUT_DIR/dmg-notarization.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]));assert r.get('status')=='Accepted',r
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
printf 'Notarized and stapled: %s\n' "$DMG"
