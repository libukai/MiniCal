#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
FLAGS=(--arch arm64 --sdk "$(xcrun --sdk macosx --show-sdk-path)")
PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
if [[ -f "$PLUGIN" ]]; then FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"); fi
swift test "${FLAGS[@]}" "$@"
