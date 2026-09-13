#!/bin/zsh
# Launches a debug build of NoteCode on a simulator in a known state, and
# prints what ends up on screen. See AGENTS.md, "Debug launch options".
#
#   scripts/debug-launch.sh [--device <name or udid>] [--wait <seconds>] -- <launch arguments>
#
# The app must already be installed on the simulator as a Debug build.
#
# Example — the view-switch path that hid a bug on 13 September:
#
#   scripts/debug-launch.sh --device "iPad Air 13-inch (M4)" -- \
#     -debug-note pages -debug-orientation landscape -debug-mode print \
#     -debug-page 4 -debug-then-mode seamless -debug-report

set -euo pipefail

device=booted
wait=4
while [[ $# -gt 0 && $1 != -- ]]; do
  case $1 in
    --device) device=$2; shift 2 ;;
    --wait)   wait=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ ${1:-} == -- ]] && shift

bundle=com.marcus.NoteCode
container=$(xcrun simctl get_app_container "$device" "$bundle" data)
report="$container/tmp/notecode-debug-state.json"

rm -f "$report"
xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
xcrun simctl launch "$device" "$bundle" "$@" >/dev/null
sleep "$wait"

if [[ -f $report ]]; then
  cat "$report"
else
  echo "no report after ${wait}s: pass -debug-report, use a Debug build, or raise --wait" >&2
  exit 1
fi
