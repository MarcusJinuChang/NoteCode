#!/bin/bash
# Compares the Compiler Explorer compiler ids pinned in CodeDestination.swift
# with the newest release godbolt.org lists for each language, and checks that
# each pin still compiles and runs a hello-world through the same API the link
# uses (docs/design/code-languages-and-keys.md). Changes nothing: update the
# pins, NoteCodeTests/Code/CodeLanguagesTests.swift and the "checked on" dates
# yourself. Exit 1 if a pin is newer-able or broken.
#
#   scripts/refresh-ce-ids.sh
set -u
cd "$(dirname "$0")/.."
SWIFT=NoteCode/Code/CodeDestination.swift
status=0

# language | pinned case | CE language | name pattern (version in group 1) | hello world
check() {
  local case_name=$1 lang=$2 pattern=$3 flags=$4 source=$5
  local pinned
  pinned=$(grep -E "case \.$case_name:" "$SWIFT" | grep -oE '\("[^"]+"' | head -1 | tr -d '("')
  local newest
  newest=$(curl -fsS -H 'Accept: application/json' "https://godbolt.org/api/compilers/$lang?fields=id,name" |
    python3 -I -c '
import json, re, sys
pattern = sys.argv[1]
rows = []
for c in json.load(sys.stdin):
    m = re.fullmatch(pattern, c["name"])
    if m:
        rows.append((tuple(int(x) for x in m.group(1).split(".")), c["id"]))
print(max(rows)[1])
' "$pattern") || { echo "$case_name: could not list compilers"; status=1; return; }

  local body result
  body=$(python3 -I -c '
import json, sys
print(json.dumps({"source": sys.argv[1], "options": {"userArguments": sys.argv[2],
  "executeParameters": {}, "compilerOptions": {"executorRequest": True},
  "filters": {"execute": True}}}))
' "$source" "$flags")
  result=$(curl -fsS -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "$body" "https://godbolt.org/api/compiler/$pinned/compile" |
    python3 -I -c '
import json, sys
d = json.load(sys.stdin)
out = "".join(l["text"] for l in d.get("stdout", []))
print("ok" if d.get("code") == 0 and "hello" in out else "FAILED")
') || result=FAILED

  local note=""
  [ "$pinned" != "$newest" ] && { note="  <- newer: $newest"; status=1; }
  [ "$result" != ok ] && status=1
  printf '%-7s pinned %-10s runs: %-6s%s\n' "$case_name" "$pinned" "$result" "$note"
}

check cpp    c++    'x86-64 gcc ([0-9.]+)' '-O2 -std=c++17' $'#include <iostream>\nint main(){std::cout<<"hello";}'
check python python 'Python ([0-9.]+)'     ''               'print("hello")'
check c      c      'x86-64 gcc ([0-9.]+)' '-O2 -std=c17'   $'#include <stdio.h>\nint main(){puts("hello");}'
check rust   rust   'rustc ([0-9.]+)'      '-O'             'fn main(){println!("hello");}'
check go     go     'x86-64 gc ([0-9.]+)'  ''               $'package main\nimport "fmt"\nfunc main(){fmt.Println("hello")}'
exit $status
