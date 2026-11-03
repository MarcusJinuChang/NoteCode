#!/bin/zsh
# 1A2: move NoteCode/*.swift into the folders docs/refactor/folders.md maps.
#
#   scripts/move-to-folders.sh [--dry-run]
#
# Reads the map's table (rows "| `Folder/` | `File`, `File` | n |") and runs
# `git mv NoteCode/File.swift NoteCode/Folder/File.swift` for each. Stops if a
# file is named twice or missing, or if the moved count differs from the
# table's total. Nothing inside any file changes.

set -uo pipefail
cd ${0:A:h:h}
dry=0; [[ ${1:-} == --dry-run ]] && dry=1
map=docs/refactor/folders.md
moved=0; expected=0
typeset -A seen

while IFS= read -r line; do
  [[ $line == '| `'*'/` | '* ]] || continue
  folder=${${line#| \`}%%\`*}
  files=${${line#*\` | }% | *}
  n=${line##*| }; n=${n%% |*}
  count=0
  for f in ${(s:, :)files}; do
    f=${f//\`/}
    src=NoteCode/$f.swift
    [[ -n ${seen[$f]:-} ]] && { print -u2 "named twice: $f"; exit 1 }
    seen[$f]=1
    [[ -f $src ]] || { print -u2 "missing: $src"; exit 1 }
    if (( dry )); then print "$src -> NoteCode/$folder$f.swift"
    else mkdir -p NoteCode/$folder && git mv $src NoteCode/$folder$f.swift || exit 1; fi
    (( count++ )); (( moved++ ))
  done
  (( count == n )) || { print -u2 "$folder: row says $n, lists $count"; exit 1 }
done < $map

expected=$(grep -E '^\| \*\*Total\*\*' $map | grep -oE '[0-9]+' | tail -1)
print "moved $moved, map total $expected"
(( moved == expected )) || exit 1
left=$(ls NoteCode/*.swift 2>/dev/null | wc -l | tr -d ' ')
(( dry )) || print "left at top of NoteCode/: $left swift files"
