#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION=debug
MODE=run
BUILD_ONLY=0
APP_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only) BUILD_ONLY=1; shift ;;
    --release) CONFIGURATION=release; shift ;;
    -c|--configuration) CONFIGURATION="${2:?Missing configuration}"; shift 2 ;;
    --verify) MODE=verify; shift ;;
    --debug) MODE=debug; shift ;;
    --logs) MODE=logs; shift ;;
    --telemetry) MODE=telemetry; shift ;;
    -h|--help) printf 'Usage: %s [--release] [--build-only|--verify|--debug|--logs|--telemetry] [-- app arguments]\n' "$0"; exit 0 ;;
    --) shift; APP_ARGS+=("$@"); break ;;
    *) APP_ARGS+=("$1"); shift ;;
  esac
done
"$ROOT/script/build.sh" --configuration "$CONFIGURATION"
[[ "$BUILD_ONLY" -eq 0 ]] || exit 0
pkill -u "$(id -u)" -x MiniCal 2>/dev/null || true
open -n "$ROOT/dist/MiniCal.app" --args "${APP_ARGS[@]}"
for ATTEMPT in 1 2 3 4 5; do
  if pgrep -u "$(id -u)" -x MiniCal >/dev/null; then break; fi
  sleep 1
done
pgrep -u "$(id -u)" -x MiniCal >/dev/null || { printf 'MiniCal exited during launch\n' >&2; exit 1; }
case "$MODE" in
  verify) printf 'MiniCal process is running; UI acceptance is a separate check.\n' ;;
  debug) exec lldb --attach-pid "$(pgrep -u "$(id -u)" -x MiniCal | head -n1)" ;;
  logs) exec /usr/bin/log stream --style compact --info --predicate 'process == "MiniCal"' ;;
  telemetry) exec /usr/bin/log stream --style compact --info --predicate 'subsystem == "com.libukai.MiniCal"' ;;
esac
