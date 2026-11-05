#!/bin/zsh
# Build and test NoteCode, and print a few lines.
#
#   scripts/check.sh [--full] [--coverage] [--only <Suite> …]
#
#   --only <Suite> …  Run just those suites (or Suite/test).
#   (no flag)         The Fast test plan: every unit test but the .perf ones.
#   --full            The Full plan (every unit test, .perf included), and also NoteCodeUITests, as their own xcodebuild run after
#                     the unit tests (one invocation with both crashed the
#                     unit bundle, baseline.md finding 2), and the run
#                     proxy's `npm test` and `npx tsc --noEmit`.
#   --coverage        Build with -enableCodeCoverage YES and print the app's
#                     line coverage per top-level folder of NoteCode/.
#
# Every test run has a 120s per-test allowance. Runs scripts/lint-traps.sh
# and scripts/check-seam.sh first once they exist. Fails on a failing test, a build error, or more
# warnings than docs/refactor/baseline.md records (a line `WARNINGS <n>`): the
# count may only fall. A warning is a unique `file:line:col: warning:` line, so
# the source excerpts the compiler prints under it are not counted. The count
# is compared only by --full without --only, which cleans the build first;
# otherwise it prints "warnings: incremental, not compared" (see Warnings
# below). The logs are check.log (unit) and check-ui.log, the result bundles
# beside them, in $TMPDIR/notecode-check/<worktree>-<hash>/, one directory
# per worktree; the run's last lines name it.
# NOTECODE_SIM picks the simulator (default iPad Pro 13-inch (M5)).

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

full=0; cov=0; suites=()
while (( $# )); do
  case $1 in
    --full) full=1 ;;
    --coverage) cov=1 ;;
    --only) shift; while (( $# )) && [[ $1 != --* ]]; do suites+=($1); shift; done; continue ;;
    *) print -u2 "usage: check.sh [--full] [--coverage] [--only <Suite> …]"; exit 2 ;;
  esac
  shift
done

# --only names suites that may be .perf ones, so it runs inside Full.
(( full || ${#suites} )) && export NOTECODE_PLAN=Full
rc=0
log=$tmp/check.log bundle=$tmp/check.xcresult

if [[ -x scripts/lint-traps.sh ]]; then
  print "lint:"; scripts/lint-traps.sh || rc=1
fi
if [[ -x scripts/check-seam.sh ]]; then
  print "seam:"; scripts/check-seam.sh || rc=1
fi

# A reliable warning count needs every file compiled: see Warnings below.
counted=$(( full && ! ${#suites} ))
if (( counted )); then
  start=$SECONDS
  xcode_clean $tmp/check-clean.log || print "clean: xcodebuild clean failed (log: $tmp/check-clean.log)"
  print "clean: $(( SECONDS - start ))s"
fi

take_lock
export NOTECODE_COVERAGE=$cov
only=(${(f)"$(only_args $suites)"})
logs=()

# summarise <log> <bundle> <label>: errors, failing tests and the totals.
summarise() {
  local log=$1 bundle=$2 label=$3
  grep -E "^/.*: error: |^error: " $log | sort -u | head -20
  grep -E "✘|Test .* failed|Issue recorded" $log | sort -u | head -20
  [[ -d $bundle ]] || return 0
  xcrun xcresulttool get test-results summary --path $bundle 2>/dev/null \
    | python3 -I -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
keys=("result","totalTestCount","passedTests","failedTests","skippedTests")
print("'"$label"' tests: "+", ".join(f"{k}={d[k]}" for k in keys if k in d))
for f in d.get("testFailures",[]):
    print("  FAIL", f.get("testName",""), "-", f.get("failureText","")[:200])
'
}

start=$SECONDS
xcode_test $log $bundle $only
code=$?
print "unit: xcodebuild exit $code in $(( SECONDS - start ))s  (log: $log)"
logs+=($log)
summarise $log $bundle unit
(( code == 0 )) || rc=1

# UI tests: their own invocation, reported on their own. Not with --only.
if (( full )) && [[ -d NoteCodeUITests ]] && (( ! ${#suites} )); then
  uilog=$tmp/check-ui.log uibundle=$tmp/check-ui.xcresult
  start=$SECONDS
  xcode_test $uilog $uibundle -only-testing:NoteCodeUITests
  uicode=$?
  print "ui: xcodebuild exit $uicode in $(( SECONDS - start ))s  (log: $uilog)"
  logs+=($uilog)
  summarise $uilog $uibundle ui
  (( uicode == 0 )) || rc=1
fi

if (( cov )) && [[ -d $bundle ]]; then
  print "coverage (NoteCode.app, unit run, executable lines):"
  xcrun xccov view --report --json $bundle 2>/dev/null | python3 -I -c '
import json,sys,collections
try: d=json.load(sys.stdin)
except Exception: print("  (no coverage report)"); sys.exit()
cov=collections.defaultdict(lambda:[0,0])
for t in d.get("targets",[]):
    if t.get("name")!="NoteCode.app": continue
    for f in t.get("files",[]):
        p=f.get("path","")
        pre=sys.argv[1]+"/NoteCode/"
        rel=p[len(pre):] if p.startswith(pre) else p
        folder=rel.split("/")[0] if "/" in rel else "(top level)"
        cov[folder][0]+=f.get("coveredLines",0); cov[folder][1]+=f.get("executableLines",0)
total="total"
tc=sum(v[0] for v in cov.values()); te=sum(v[1] for v in cov.values())
for k,(c,e) in sorted(cov.items()):
    print(f"  {k:<14}{c:>7} /{e:>7}  {100*c/e if e else 0:5.1f}%")
print(f"  {total:<14}{tc:>7} /{te:>7}  {100*tc/te if te else 0:5.1f}%")
' "$root"
fi

# Warnings: unique lines, grouped by [category] where the compiler gives one.
# The same warning prints once per build path (/var/… and /private/var/…) and
# per architecture, so paths are cut to start at the target folder before the
# de-duplication.
#
# The compiler prints a file's warnings only when it compiles that file, so an
# incremental build's log holds the warnings of the files it rebuilt: 0 to 9
# against a baseline of 12. Two ways to see them all: a clean build, or
# rebuilding with every file's warnings cached between runs. The cache would
# have to know when a file stopped warning, was deleted or moved target, and
# an Xcode upgrade that adds warnings would only show as files are touched;
# the clean build has none of that. It costs about 90s (baseline.md § 1,
# packages included) on a --full run that already takes ten minutes, and
# would double a Fast run, so only --full cleans and compares, and the Fast
# loop does neither. --full also builds the UI target, as baseline.md's count
# does; with --only it runs no UI tests, so it is not compared either.
warnings=$(cat $logs | grep -E "^/.*:[0-9]+:[0-9]+: warning: " \
  | sed -E 's#^.*/(NoteCode(Tests|UITests)?/)#\1#' | sort -u)
count=$(print -r -- "$warnings" | grep -c . || true)
baseline=docs/refactor/baseline.md
if (( ! counted )); then
  print "warnings: incremental, not compared ($count in the files this build compiled; --full counts them all)"
else
  print "warnings: $count (clean build)"
  print -r -- "$warnings" | grep . | awk '{ if (match($0, /\[#?[A-Za-z]+\]$/)) print substr($0, RSTART); else print "(no category)" }' | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /'
  if [[ -f $baseline ]] && limit=$(grep -E "^WARNINGS [0-9]+" $baseline | head -1 | awk '{print $2}') && [[ -n $limit ]]; then
    if (( count > limit )); then print "FAIL: $count warnings, baseline allows $limit"; rc=1
    else print "warnings within baseline ($limit)"; fi
  else
    print "(no WARNINGS line in $baseline yet: not enforced)"
  fi
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

print "logs: $tmp"
(( rc == 0 )) && print "CHECK OK" || print "CHECK FAILED"
exit $rc
