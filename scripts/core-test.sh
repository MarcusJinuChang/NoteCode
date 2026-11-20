#!/bin/zsh
# Run the pure tests with `swift test` on the Mac: no simulator, no Xcode
# project (Package.swift, docs/refactor/T11-core-package.md, option B).
#
#   scripts/core-test.sh [swift test arguments, e.g. --filter <Suite>]
#
# Package.swift compiles NoteCode/Text/Core in place under the module name
# NoteCode, with the Core tests, so a test that needs UIKit or an app type
# outside Core does not belong in NoteCodeTests/Text/Core: it fails to
# compile here. The same files run in the app's test bundle too, where
# check.sh counts them, so nothing is tested only in one place.
#
# Prints the build and test errors, any failing test, and a line with the
# count and the time. The build is in .build/ (ignored by git), one per
# worktree. Exits non-zero on a failed build or test.

set -uo pipefail
cd ${0:A:h:h}

log=$(mktemp) ; trap 'rm -f $log' EXIT
start=$SECONDS
swift test "$@" > $log 2>&1
code=$?
sed -i '' $'s/\x1b\\[[0-9;]*m//g' $log

grep -E "^/.*: error: |^error: " $log | sort -u | head -20
grep -E "^✘|Issue recorded" $log | sort -u | head -20
summary=$(grep -E "Test run with [0-9]+ tests? .*(passed|failed)" $log | tail -1)
print "core: swift test exit $code in $(( SECONDS - start ))s: ${summary:-no test run}"
(( code == 0 ))
