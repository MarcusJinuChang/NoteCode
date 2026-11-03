#!/bin/zsh
# Build and test NoteCode, and print a few lines.
#
#   scripts/check.sh [--full] [--only <Suite> …]
#
#   --only <Suite> …  Run just those suites (or Suite/test).
#   --full            Also NoteCodeUITests (once they exist), and the run
#                     proxy's `npm test` and `npx tsc --noEmit`.
#
# Runs scripts/lint-traps.sh first once it exists. Fails on a failing test,
# a build error, or more warnings than docs/refactor/baseline.md records
# (a line `WARNINGS <n>`): the count may only fall. Only files the build
# compiled are counted, so the ratchet means something after a clean build.
# The full log is $TMPDIR/notecode-check/check.log; the result bundle beside it.
# NOTECODE_SIM picks the simulator (default iPad Pro 13-inch (M5)).

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

full=0; suites=()
while (( $# )); do
  case $1 in
    --full) full=1 ;;
    --only) shift; while (( $# )) && [[ $1 != --* ]]; do suites+=($1); shift; done; continue ;;
    *) print -u2 "usage: check.sh [--full] [--only <Suite> …]"; exit 2 ;;
  esac
  shift
done

rc=0
log=$tmp/check.log bundle=$tmp/check.xcresult

if [[ -x scripts/lint-traps.sh ]]; then
  print "lint:"; scripts/lint-traps.sh || rc=1
fi

take_lock
only=(${(f)"$(only_args $suites)"})
if (( full )) && [[ -d NoteCodeUITests ]] && (( ! ${#suites} )); then
  only=(-only-testing:NoteCodeTests -only-testing:NoteCodeUITests)
fi

start=$SECONDS
xcode_test $log $bundle $only
code=$?
print "xcodebuild exit $code in $(( SECONDS - start ))s  (log: $log)"

# Build errors and failing tests, by name.
grep -E "^/.*: error: |^error: " $log | sort -u | head -20
grep -E "✘|Test .* failed|Issue recorded" $log | sort -u | head -20

if [[ -d $bundle ]]; then
  xcrun xcresulttool get test-results summary --path $bundle 2>/dev/null \
    | python3 -I -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
keys=("result","totalTestCount","passedTests","failedTests","skippedTests")
print("tests: "+", ".join(f"{k}={d[k]}" for k in keys if k in d))
for f in d.get("testFailures",[]):
    print("  FAIL", f.get("testName",""), "-", f.get("failureText","")[:200])
'
fi
(( code == 0 )) || rc=1

# Warnings: unique lines, grouped by [category] where the compiler gives one.
warnings=$(grep -E "warning:" $log | sed -E 's/^[[:space:]]+//' | sort -u)
count=$(print -r -- "$warnings" | grep -c . || true)
print "warnings: $count"
print -r -- "$warnings" | grep -oE "\[[A-Za-z]+\]$" | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /'
baseline=docs/refactor/baseline.md
if [[ -f $baseline ]] && limit=$(grep -E "^WARNINGS [0-9]+" $baseline | head -1 | awk '{print $2}') && [[ -n $limit ]]; then
  if (( count > limit )); then print "FAIL: $count warnings, baseline allows $limit"; rc=1
  else print "warnings within baseline ($limit)"; fi
else
  print "(no WARNINGS line in $baseline yet: not enforced)"
fi

# macOS only if the scheme lists it. Informational: the Google Mobile Ads
# and UMP xcframeworks have no macOS slice, so this fails on main today
# (docs/refactor: a finding for the split, whose public build has no ads).
if xcodebuild -showdestinations -project NoteCode.xcodeproj -scheme NoteCode 2>/dev/null | grep -q "platform:macOS"; then
  if xcodebuild build -project NoteCode.xcodeproj -scheme NoteCode -destination "platform=macOS" \
      -clonedSourcePackagesDirPath "$packages" > $tmp/check-mac.log 2>&1; then
    print "macOS build: ok"
  else
    print "macOS build: FAILED, not counted (log: $tmp/check-mac.log)"
    grep -E "^/.*: error: |^error: " $tmp/check-mac.log | sed -E 's/^.*: error: //' | sort -u | head -2 | cut -c1-160
  fi
else
  print "macOS: not a destination, skipped"
fi

if (( full )) && [[ -d server/run-proxy/node_modules ]]; then
  ( cd server/run-proxy && npm test --silent 2>&1 | tail -5 && npx tsc --noEmit ) \
    && print "run-proxy: ok" || { print "run-proxy: FAILED"; rc=1; }
fi

(( rc == 0 )) && print "CHECK OK" || print "CHECK FAILED"
exit $rc
