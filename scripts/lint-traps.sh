#!/bin/zsh
# Grep for the AGENTS.md traps a grep can find. Prints `file:line rule` for
# each hit and exits non-zero if there is one. Comment lines don't count.
#
#   scripts/lint-traps.sh
#
# A legitimate hit goes in scripts/lint-allow.txt as `rule file:line reason`.
# Rule 7 is a count that may only fall: `limit 7 <n>` in the same file.
#
# Rules:
#  1 .layoutManager in NoteCode/        (text view drops to TextKit 1)
#  2 .inkType in NoteCode/              (PKInk.inkType traps on eraser ink)
#  3 map/reduce/compactMap/filter/first(where:)/subscript on a variable named
#    *markup* or *elements* (a MarkupOrderedSet; grep can't see types, so a
#    set under another name, or a `markup` that is a plain array, is missed
#    or flagged wrongly)
#  4 import SwiftUI/UIKit in a file under any NoteCode/**/Core/ folder (the tests may)
#  5 #filePath near deletingLastPathComponent in tests (use TestPaths.repoRoot)
#  6 two Swift files with one basename in one target's folder
#  7 UserDefaults.standard or UserDefaults() in NoteCodeTests/, as a count that may only fall
#  8 reportPerf in a test without .perf on itself or its suite (perf.sh runs
#    only the Perf plan, so its PERF line would never be read). The test is
#    the last @Test above the call, and the suite the last @Suite
#  9 a sleep or run-loop spin in NoteCodeTests/ (Task.sleep, RunLoop.main.run,
#    RunLoop.current.run, usleep, Thread.sleep, and a fixed delay written as
#    a wait for a condition that never holds, `waitFor({ false }`), as a count that may only
#    fall (T6). A test awaits the work's hook, or moves a ManualClock

set -uo pipefail
cd ${0:A:h:h}
allow=scripts/lint-allow.txt
hits=()

allowed() { [[ -f $allow ]] && awk -v k="$1 $2" '!/^#/ && ($1 " " $2) == k { f = 1 } END { exit !f }' $allow; }
hit() {  # rule file:line
  allowed $1 $2 || hits+=("$2 rule $1: $3")
}

# Swift lines with comments dropped: "file:line:text" for every code line.
code_lines() {  # dir...
  find "$@" -name '*.swift' 2>/dev/null | sort | while read -r f; do
    awk -v f="$f" '
      /^[[:space:]]*\/\// { next }
      { sub(/[[:space:]]\/\/.*$/, ""); print f ":" NR ":" $0 }' "$f"
  done
}

scan() {  # rule regex dir...
  local rule=$1 re=$2; shift 2
  code_lines "$@" | RE="$re" awk -F: -v rule=$rule 'BEGIN { re = ENVIRON["RE"] } { t = $0; sub(/^[^:]*:[0-9]+:/, "", t); if (t ~ re) print rule, $1 ":" $2 }'
}

# 1, 2, 3
for spec in \
  '1|\.layoutManager([^A-Za-z0-9_]|$)|reading it downgrades the text view to TextKit 1' \
  '2|\.inkType([^A-Za-z0-9_]|$)|PKInk.inkType traps on eraser ink; use InkContent.inkIdentifier' \
  '3|[A-Za-z_]*([Mm]arkup|[Ee]lements)[A-Za-z_]*(\??\.(map|reduce|compactMap|flatMap|filter|first\(where|firstIndex|last\(where)([^A-Za-z0-9_]|$)|\[[0-9a-z]+\])|a MarkupOrderedSet is walked with for-in, never read by position'; do
  rule=${spec%%|*}; rest=${spec#*|}; msg=${rest##*|}; re=${rest%|*}
  while read -r r loc; do hit $r $loc "$msg"; done < <(scan $rule "$re" NoteCode)
done

# 4
for f in $(find . -path ./.git -prune -o -path ./.claude -prune -o -path './NoteCode/*/Core/*' -name '*.swift' -print | sed 's|^\./||'); do
  grep -nE '^[[:space:]]*import (SwiftUI|UIKit)\b' $f | while IFS=: read -r n _; do
    hit 4 $f:$n "Core/ stays free of SwiftUI and UIKit"
  done
done

# 5
for f in $(find NoteCodeTests -name '*.swift' | sort); do
  awk -v f=$f '
    /^[[:space:]]*\/\// { next }
    /#filePath/ { last = NR }
    /deletingLastPathComponent/ && last && NR - last <= 3 { print NR }' $f | while read -r n; do
    hit 5 $f:$n "use TestPaths.repoRoot, not #filePath walked by hand"
  done
done

# 6
for dir in NoteCode NoteCodeTests NoteCodeUITests; do
  [[ -d $dir ]] || continue
  find $dir -name '*.swift' | awk -F/ '{n[$NF]++; p[$NF]=p[$NF] " " $0} END {for (k in n) if (n[k] > 1) print k ":" p[k]}' \
    | while IFS=: read -r name paths; do hit 6 $dir/$name:0 "same basename:$paths"; done
done

# 7
count=$(code_lines NoteCodeTests | grep -cE 'UserDefaults\.standard|UserDefaults\(\)')
limit=$(awk '$1 == "limit" && $2 == 7 { print $3 }' $allow 2>/dev/null)
if [[ -z $limit ]]; then limit=0; fi
(( count > limit )) && hits+=("NoteCodeTests rule 7: UserDefaults.standard or UserDefaults() $count times, limit $limit (the count may only fall)")

# 9
sleeps=$(code_lines NoteCodeTests | grep -cE 'Task\.sleep|RunLoop\.(main|current)\.run|usleep|Thread\.sleep|waitFor *\( *\{ *false *\}')
sleepLimit=$(awk '$1 == "limit" && $2 == 9 { print $3 }' $allow 2>/dev/null)
if [[ -z $sleepLimit ]]; then sleepLimit=0; fi
(( sleeps > sleepLimit )) && hits+=("NoteCodeTests rule 9: $sleeps sleeps or run-loop spins, limit $sleepLimit (the count may only fall)")

# 8
for f in $(grep -rl 'reportPerf(' NoteCodeTests --include='*.swift' | grep -v '/TestSupport/Perf\.swift$' | sort); do
  awk '
    /^[[:space:]]*\/\// { next }
    /@Suite/ { suite = ""; insuite = 1 }
    insuite { suite = suite $0; if ($0 ~ /(struct|class|enum|extension)[[:space:]]/) insuite = 0 }
    /@Test/ { test = ""; intest = 1 }
    intest { test = test $0; if ($0 ~ /func[[:space:]]/) intest = 0 }
    /reportPerf\(/ && suite !~ /\.perf[^A-Za-z0-9_]/ && test !~ /\.perf[^A-Za-z0-9_]/ { print NR }' $f | while read -r n; do
    hit 8 $f:$n "reportPerf in a test with no .perf tag on it or its suite; perf.sh never runs it"
  done
done

if (( ${#hits} )); then
  print -l -- $hits
  print "lint-traps: ${#hits} hit(s)"; exit 1
fi
print "lint-traps: clean (rule 7: $count/$limit, rule 9: $sleeps/$sleepLimit)"
