#!/bin/zsh
# Launches a debug build of NoteCode on a simulator in a known state, and
# prints what ends up on screen. See AGENTS.md, "Debug launch options".
#
#   scripts/debug-launch.sh [--device <name or udid>] [--wait <seconds>]
#                           [--bundle-id <id>] -- <launch arguments>
#
# The app must already be installed on the simulator as a Debug build.
# The bundle id is --bundle-id, else $NOTECODE_BUNDLE_ID, else the app
# target's PRODUCT_BUNDLE_IDENTIFIER, read from the project's build settings
# (a few seconds; pass one of the others to skip it).
#
# Example — the view-switch path that hid a bug on 13 September:
#
#   scripts/debug-launch.sh --device "iPad Air 13-inch (M4)" -- \
#     -debug-note pages -debug-orientation landscape -debug-mode print \
#     -debug-page 4 -debug-then-mode seamless -debug-report

set -euo pipefail

device=booted
wait=4
bundle=${NOTECODE_BUNDLE_ID:-}
while [[ $# -gt 0 && $1 != -- ]]; do
  case $1 in
    --device|--wait|--bundle-id)
      [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; exit 2; }
      case $1 in
        --device) device=$2 ;;
        --wait) wait=$2 ;;
        --bundle-id) bundle=$2 ;;
      esac
      shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ ${1:-} == -- ]] && shift

if [[ -z $bundle ]]; then
  root=${0:A:h:h}
  bundle=$(xcodebuild -showBuildSettings -project "$root/NoteCode.xcodeproj" \
      -target NoteCode -configuration Debug \
      -disableAutomaticPackageResolution -skipPackageUpdates 2>/dev/null |
    awk '$1 == "PRODUCT_BUNDLE_IDENTIFIER" { print $3; exit }' || true)
fi
if [[ -z $bundle ]]; then
  echo "no bundle id: pass --bundle-id <id> or set NOTECODE_BUNDLE_ID (the project's build settings gave none)" >&2
  exit 2
fi
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
