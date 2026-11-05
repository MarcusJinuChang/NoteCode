#!/bin/zsh
# Run the cost tests and print one row per `PERF <test> <seconds>` they report.
#
#   scripts/perf.sh [--compare docs/refactor/baseline.md]
#
# With --compare, each row also shows the change against the `PERF` line of the
# same name in the file, and the script exits 1 if any is more than 10% worse.
# Numbers under 5ms are not judged (noise). Log: perf.log in this worktree's
# own $TMPDIR/notecode-check/<worktree>-<hash>/ (lib-xcode.sh), printed last.

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

compare=
if [[ ${1:-} == --compare ]]; then compare=${2:?--compare needs a file}; [[ -f $compare ]] || { print -u2 "no $compare"; exit 2; }; fi

export NOTECODE_PLAN=Perf   # TestPlans/Perf.xctestplan: everything tagged .perf (NoteCodeTests/TestSupport/Tags.swift)

take_lock
log=$tmp/perf.log
xcode_test $log $tmp/perf.xcresult
code=$?
grep -E "^/.*: error: |^error: " $log | sort -u | head -10

rows=$(grep -E "^PERF [^ ]+ [0-9.]+$" $log | sort -u -k2,2)
if [[ -z $rows ]]; then print "no PERF lines (xcodebuild exit $code; log: $log)"; exit 1; fi
(( code == 0 )) || print "note: xcodebuild exit $code (a test failed?)"

rc=$(( code == 0 ? 0 : 1 ))
printf "%-52s %9s" test ms; [[ -n $compare ]] && printf " %9s %8s" base change; print
print -r -- "$rows" | while read -r _ name secs; do
  ms=$(awk -v s=$secs 'BEGIN{printf "%.1f", s*1000}')
  printf "%-52s %9s" $name $ms
  if [[ -n $compare ]]; then
    base=$(grep -E "^PERF $name " $compare | head -1 | awk '{print $3}')
    if [[ -z $base ]]; then printf " %9s %8s" - new
    else
      bms=$(awk -v s=$base 'BEGIN{printf "%.1f", s*1000}')
      pct=$(awk -v a=$secs -v b=$base 'BEGIN{ if (b>0) printf "%+.0f%%", (a-b)/b*100; else print "n/a" }')
      printf " %9s %8s" $bms $pct
      if awk -v a=$secs -v b=$base 'BEGIN{exit !(a>b*1.10 && a>0.005)}'; then printf "  WORSE"; rc=1; fi
    fi
  fi
  print
done
print "log: $log"
exit $rc
