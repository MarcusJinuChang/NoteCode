#!/bin/zsh
# Run the cost tests and print one row per `PERF <test> <seconds>` they report.
#
#   scripts/perf.sh [--compare docs/refactor/baseline.md]
#
# With --compare, each row also shows the change against the `PERF` line of the
# same name in the file, and the script exits 1 if any is more than 10% worse.
# Numbers under 5ms are not judged (noise).
#
# A row over budget is measured again before it counts: one run on this Mac
# can be 10-40% high on any row while the runs either side are at the base
# (docs/refactor/baseline.md › "The base retaken with the Perf plan"). So the
# tests behind the flagged rows, and only those (the Perf plan narrowed with
# -only-testing), run up to twice more, each row keeps its best (lowest)
# value across the runs, and only a row still over budget after that fails.
# A real regression is high on every run, so its best is still high. The
# re-run rows are listed with each run's value. The threshold and the floor
# are the same for every run.
#
# Log: perf.log (perf-rerun<n>.log for re-runs) in this worktree's own
# $TMPDIR/notecode-check/<worktree>-<hash>/ (lib-xcode.sh), printed last.

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

compare=
if [[ ${1:-} == --compare ]]; then compare=${2:?--compare needs a file}; [[ -f $compare ]] || { print -u2 "no $compare"; exit 2; }; fi

export NOTECODE_PLAN=Perf   # TestPlans/Perf.xctestplan: everything tagged .perf (NoteCodeTests/TestSupport/Tags.swift)
reruns=2                    # at most this many more runs of the flagged rows

# The test that reports a row, as an -only-testing identifier. A row is
# `Suite/test` with an optional `.suffix` (TestSupport/Perf.swift); the
# exceptions are rows whose prefix is not the suite's type.
test_of() {
  local name=${1%%.*}
  case $name in
    NoteListFetchCost/*) print NoteCodeTests/NoteListFetchCostTests/fetchCost\(\) ;;
    PageViewTests/*)     print NoteCodeTests/PageViewTests/Cost/${name#*/}\(\) ;;
    *)                   print NoteCodeTests/$name\(\) ;;
  esac
}

# over <secs> <base secs>: true if more than 10% worse and above the floor.
over() { awk -v a=$1 -v b=$2 'BEGIN{exit !(a>b*1.10 && a>0.005)}'; }
ms() { awk -v s=$1 'BEGIN{printf "%.1f", s*1000}'; }

take_lock
log=$tmp/perf.log
xcode_test $log $tmp/perf.xcresult
code=$?
grep -E "^/.*: error: |^error: " $log | sort -u | head -10

rows=$(grep -E "^PERF [^ ]+ [0-9.]+$" $log | sort -u -k2,2)
if [[ -z $rows ]]; then print "no PERF lines (xcodebuild exit $code; log: $log)"; exit 1; fi
(( code == 0 )) || print "note: xcodebuild exit $code (a test failed?)"
rc=$(( code == 0 ? 0 : 1 ))

typeset -A best base runs
names=()
print -r -- "$rows" | while read -r _ name secs; do
  names+=$name; best[$name]=$secs; runs[$name]=$(ms $secs)
  [[ -n $compare ]] && base[$name]=$(grep -E "^PERF $name " $compare | head -1 | awk '{print $3}')
done

flagged() { local n; for n in $names; do [[ -n ${base[$n]:-} ]] && over ${best[$n]} ${base[$n]} && print -r -- $n; done; }

rerun=()
if [[ -n $compare ]]; then
  for pass in {1..$reruns}; do
    todo=($(flagged))
    (( ${#todo} )) || break
    rerun+=($todo)
    only=(); for n in $todo; do only+=("-only-testing:$(test_of $n)"); done
    only=(${(u)only})
    print "re-run $pass of $reruns: ${(j:, :)todo}"
    rlog=$tmp/perf-rerun$pass.log
    xcode_test $rlog $tmp/perf-rerun$pass.xcresult $only
    rcode=$?
    (( rcode == 0 )) || print "note: re-run $pass xcodebuild exit $rcode (a test failed?)"
    for n in $todo; do
      secs=$(grep -E "^PERF $n [0-9.]+$" $rlog | head -1 | awk '{print $3}')
      if [[ -z $secs ]]; then runs[$n]+=", -"; print "note: re-run $pass did not report $n (test_of: $(test_of $n))"; continue; fi
      runs[$n]+=", $(ms $secs)"
      awk -v a=$secs -v b=${best[$n]} 'BEGIN{exit !(a<b)}' && best[$n]=$secs
    done
  done
  rerun=(${(u)rerun})
fi

printf "%-52s %9s" test ms; [[ -n $compare ]] && printf " %9s %8s" base change; print
for name in $names; do
  secs=${best[$name]}
  printf "%-52s %9s" $name $(ms $secs)
  if [[ -n $compare ]]; then
    b=${base[$name]:-}
    if [[ -z $b ]]; then printf " %9s %8s" - new
    else
      pct=$(awk -v a=$secs -v b=$b 'BEGIN{ if (b>0) printf "%+.0f%%", (a-b)/b*100; else print "n/a" }')
      printf " %9s %8s" $(ms $b) $pct
      if over $secs $b; then printf "  WORSE"; rc=1; fi
    fi
  fi
  print
done
if (( ${#rerun} )); then
  print "re-run (best of these, ms):"
  for name in $rerun; do printf "  %-50s %s\n" $name "${runs[$name]}"; done
fi
print "log: $log"
exit $rc
