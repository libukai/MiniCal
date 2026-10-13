#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIGURATION=debug
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIGURATION=release; shift ;;
    -c|--configuration) CONFIGURATION="${2:?Missing configuration}"; shift 2 ;;
    -h|--help) printf 'Usage: %s [--release|-c debug|release]\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || { printf 'Configuration must be debug or release\n' >&2; exit 2; }
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
FLAGS=(--arch arm64 --sdk "$SDK_PATH" --configuration "$CONFIGURATION"
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
swift build "${FLAGS[@]}" --product MiniCal
swift build "${FLAGS[@]}" --product MiniCalWidget
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"
APP="$ROOT/dist/MiniCal.app"
WIDGET="$APP/Contents/PlugIns/MiniCalWidget.appex"
# Only the generated bundle in this repository's dist directory is replaced.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGET/Contents/MacOS" "$WIDGET/Contents/Resources"
cp "$BIN_DIR/MiniCal" "$APP/Contents/MacOS/MiniCal"
cp "$BIN_DIR/MiniCalWidget" "$WIDGET/Contents/MacOS/MiniCalWidget"
cp "$ROOT/Sources/MiniCal/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for BUNDLE in "$BIN_DIR"/*.bundle; do
  [[ -d "$BUNDLE" ]] || continue
  ditto "$BUNDLE" "$APP/Contents/Resources/$(basename "$BUNDLE")"
  if [[ "$BUNDLE" == *MiniCalCore.bundle ]]; then ditto "$BUNDLE" "$WIDGET/Contents/Resources/$(basename "$BUNDLE")"; fi
done
python3 - "$APP" "$WIDGET" "$ROOT/VERSION" <<'PY'
import os,plistlib,re,sys
from pathlib import Path
app,widget=map(Path,sys.argv[1:3]); version=Path(sys.argv[3]).read_text().strip(); build=os.environ.get('BUILD_NUMBER','1')
if not re.fullmatch(r'\d+\.\d+\.\d+',version) or not re.fullmatch(r'\d+',build): raise SystemExit('Invalid version or build number')
common={'CFBundleDevelopmentRegion':'zh-Hans','CFBundleInfoDictionaryVersion':'6.0','CFBundleShortVersionString':version,'CFBundleVersion':build,'LSMinimumSystemVersion':'14.0','CFBundleSupportedPlatforms':['MacOSX'],'NSHighResolutionCapable':True}
host=common|{'CFBundleIdentifier':'com.libukai.MiniCal','CFBundleName':'MiniCal','CFBundleDisplayName':'MiniCal','CFBundleIconFile':'AppIcon','CFBundleExecutable':'MiniCal','CFBundlePackageType':'APPL','LSUIElement':True,'NSPrincipalClass':'NSApplication','LSApplicationCategoryType':'public.app-category.productivity','NSCalendarsFullAccessUsageDescription':'在MiniCal中查看并管理您授权的日历事件。','NSRemindersFullAccessUsageDescription':'在MiniCal中查看并管理您授权的提醒事项。','NSCalendarsUsageDescription':'在MiniCal中查看并管理您授权的日历事件。','NSRemindersUsageDescription':'在MiniCal中查看并管理您授权的提醒事项。','CFBundleURLTypes':[{'CFBundleURLName':'com.libukai.MiniCal.show','CFBundleURLSchemes':['minical']}],'NSHumanReadableCopyright':'Copyright © 2026 Libukai. MIT License.'}
widget_info=common|{'CFBundleIdentifier':'com.libukai.MiniCal.widget','CFBundleName':'MiniCalWidget','CFBundleDisplayName':'MiniCal 月历与农历','CFBundleExecutable':'MiniCalWidget','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
for bundle,info in [(app,host),(widget,widget_info)]: (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info,sort_keys=False))
PY
IDENTITY="${SIGNING_IDENTITY:--}"
if [[ "$IDENTITY" == - ]]; then
  codesign --force --sign - --timestamp=none --entitlements "$ROOT/config/widget.entitlements" "$WIDGET"
  codesign --force --sign - --timestamp=none "$APP"
  printf 'Local ad-hoc build: not notarized for public distribution.\n'
else
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT/config/widget.entitlements" "$WIDGET"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
  printf 'Identity-signed build: notarization is still required before public distribution.\n'
fi
codesign --verify --deep --strict "$APP"
[[ "$(lipo -archs "$APP/Contents/MacOS/MiniCal")" == arm64 ]] || exit 1
[[ "$(lipo -archs "$WIDGET/Contents/MacOS/MiniCalWidget")" == arm64 ]] || exit 1
printf 'Built: %s\n' "$APP"
