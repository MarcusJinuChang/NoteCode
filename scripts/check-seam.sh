#!/bin/zsh
# Count the files outside any Pro/ folder that reach into NoteCode/Pro/
# (docs/refactor/2X-seam.md). Prints `file: name×n …` for each and the count,
# and fails if the count is above the `SEAM <n>` line in
# docs/refactor/baseline.md. The count may only fall; 2X7 brings it to 0.
#
#   scripts/check-seam.sh
#
# A file counts when its code, with comments and string literals stripped,
# names as a whole word:
#  - a top-level type or function declared in NoteCode/Pro/ (any file there);
#  - one of the editor's Pro members (`editor.ai`, `.run`, `.pro`, and
#    `explain`, `summariseNote`, `insertAnswer`, `runInApp`, `connectRun`,
#    `onRunNeedsPro`), reached on a value called `editor`, or the named ones
#    on their own;
#  - the closures and setting that lead to Pro without naming it:
#    `explainBlockAtCaret`, `runService`. (`runBlockAtCaret` left the list in
#    2X5b: ⌘R now asks the editor's features, then opens a compiler site.)
# NoteCode/, NoteCodeTests/ and NoteCodeUITests/ are searched.

set -uo pipefail
cd ${0:A:h:h}

# Every top-level declaration in Pro/: a line that starts at column 0.
types=(${(f)"$( { grep -rhoE '^((public|internal|private|fileprivate|final|nonisolated|@MainActor|@Observable) )*(struct|class|enum|actor|protocol|typealias|func) [A-Za-z_][A-Za-z0-9_]*' NoteCode/Pro --include='*.swift' | awk '{print $NF}'; } | sort -u)"})
# Members named on their own, and those only counted on `editor`.
members=(explain summariseNote insertAnswer runInApp connectRun onRunNeedsPro
         explainBlockAtCaret runService)
words="${(j:|:)types}|${(j:|:)members}"
# `editor.run`, `editor?.pro`, `editor!.ai`, `self.editor.run` …
onEditor='editor[?!]?\.(ai|run|pro)'

# Code only: drop // comments and the contents of "…" literals.
strip() { perl -pe 's{"(?:[^"\\]|\\.)*"}{""}g; s{//.*$}{}' $1 }

n=0
for f in $(find NoteCode NoteCodeTests NoteCodeUITests -name '*.swift' -not -path '*/Pro/*' 2>/dev/null | sort); do
  code=$(strip $f)
  hits=$( { print -r -- $code | grep -owE "\\b($words)\\b"; print -r -- $code | grep -oE "\\b$onEditor\\b" | sed -E 's/[?!]//'; } \
    | sort | uniq -c | awk '{ printf "%s%s×%s", (NR > 1 ? " " : ""), $2, $1 }')
  [[ -n $hits ]] || continue
  n=$(( n + 1 ))
  print -r -- "$f: $hits"
done
print "seam: $n files"

baseline=docs/refactor/baseline.md
limit=$(grep -E '^SEAM [0-9]+' $baseline 2>/dev/null | head -1 | awk '{print $2}')
if [[ -z $limit ]]; then
  print "(no SEAM line in $baseline yet: not enforced)"; exit 0
fi
if (( n > limit )); then
  print "FAIL: $n files reach into Pro/, baseline allows $limit"; exit 1
fi
print "seam within baseline ($limit)"
