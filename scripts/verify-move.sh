#!/bin/zsh
# Check that a change only moves code.
#
#   scripts/verify-move.sh [base]      (default origin/main)
#
# Compares base with the working tree's HEAD (committed changes). Every
# removed and every added line in *.swift is collected, skipping blank lines,
# `}`, `import …` (with any `@testable`-style attribute), comment-only lines
# (`//`, `/*`, `*`, which includes `// MARK:`), `extension … {` headers and #if/#else/#endif.
# A leading private/fileprivate/internal (after any attributes, `@Environment(…)`
# and `@AppStorage(…)` included) is stripped from both sides, and a
# line where that was the only difference is listed as "access loosened".
# The two sides are sorted and compared as multisets: anything left over means
# the change is not a pure move. Prints the leftovers and exits 1.

set -uo pipefail
cd ${0:A:h:h}
base=${1:-origin/main}
tmp=$(mktemp -d); trap 'rm -rf $tmp' EXIT

git diff -U0 -M $base HEAD -- '*.swift' > $tmp/diff || { print -u2 "git diff failed"; exit 2; }

# "sign<TAB>file<TAB>raw line" for each changed line worth comparing.
awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^--- a\//    { file = substr($0, 7); next }
  /^(---|\+\+\+) / { next }
  /^[-+]/ {
    sign = substr($0, 1, 1); line = substr($0, 2)
    t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "" || t == "}" || t ~ /^(@[A-Za-z]+ )*import / || t ~ /^\/\// || t ~ /^\/\*/ || t ~ /^\*/ || t ~ /^\/\/ MARK:/ || t ~ /^(public |private |fileprivate |internal )?extension .*\{$/ || t ~ /^#(if|else|elseif|endif)/) next
    print sign "\t" file "\t" t
  }' $tmp/diff > $tmp/lines

strip() { sed -E 's/^((@[A-Za-z]+(\([^)]*\))?[[:space:]]+|static[[:space:]]+|final[[:space:]]+|override[[:space:]]+|lazy[[:space:]]+|nonisolated[[:space:]]+|mutating[[:space:]]+)*)(private|fileprivate|internal)(\(set\))?[[:space:]]+/\1/; s/[[:space:]]+/ /g'; }
for s in - +; do
  awk -F'\t' -v s=$s '$1 == s { print $3 }' $tmp/lines | strip | sort > $tmp/$s.norm
  awk -F'\t' -v s=$s '$1 == s { print $3 }' $tmp/lines | sort > $tmp/$s.raw
done

# Access loosened: raw text differs but the normalised text matches on both sides.
loosened=$(comm -12 $tmp/-.norm $tmp/+.norm | while IFS= read -r n; do
  awk -F'\t' -v n="$n" '$1 == "+" { print $3 }' $tmp/lines | while IFS= read -r a; do
    na=$(print -r -- "$a" | strip)
    [[ $na == $n ]] || continue
    grep -qxF -- "$a" $tmp/-.raw || print -r -- "$a"
  done
done | sort -u)

left=$(comm -23 $tmp/-.norm $tmp/+.norm)
right=$(comm -13 $tmp/-.norm $tmp/+.norm)

if [[ -n $loosened ]]; then print "access changed (check each is intended):"; print -r -- "$loosened" | sed 's/^/  /'; fi
if [[ -z $left && -z $right ]]; then
  print "verify-move: pure move ($(wc -l < $tmp/-.norm | tr -d ' ') lines each side)"; exit 0
fi
[[ -n $left ]] && { print "removed, not added anywhere:"; print -r -- "$left" | sed 's/^/  - /'; }
[[ -n $right ]] && { print "added, not removed anywhere:"; print -r -- "$right" | sed 's/^/  + /'; }
print "verify-move: NOT a pure move"; exit 1
