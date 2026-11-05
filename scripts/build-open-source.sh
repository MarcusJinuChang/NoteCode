#!/bin/zsh
# Prove the open-source edition compiles and its unit tests pass, with no
# project edit (docs/refactor/2X-seam.md › 2X7).
#
#   scripts/build-open-source.sh
#
# Works in a temporary worktree of HEAD (committed changes only), removed
# however the script ends. There it deletes NoteCode/Pro/ and
# NoteCodeTests/Pro/, copies the worktree's OpenSource/OpenSourceEdition.swift
# into NoteCode/App/, OpenSourceEditionTests.swift into NoteCodeTests/App/,
# and OpenSource/Info.plist and PrivacyInfo.xcprivacy over NoteCode/'s, then
# builds and runs the Fast plan. The folders are synchronized groups, so the
# project picks up the difference by itself. Prints the build result and the
# test totals. Log and result bundle: open-source.log and open-source.xcresult
# in this worktree's $TMPDIR/notecode-check/<worktree>-<hash>/ (lib-xcode.sh).
#
# The worktree and its DerivedData have fixed paths, one pair per checkout,
# under ~/Library/Caches/NoteCode-open-source/<worktree>-<hash>/ (`tree` and
# `dd`; NOTECODE_OPEN_SOURCE_CACHE moves it). The DerivedData stays between
# runs, so a rerun reuses the built packages and module caches instead of
# leaving a new ~/Library/Developer/Xcode/DerivedData folder (370 MB) behind
# each time. Only the tree is removed.
#
# The Google Mobile Ads and UMP packages stay linked: they are the target's
# package dependencies, and removing them is a project edit (the split).
# Only Pro/ imports them, so nothing here calls them.

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

repo=$root
cache=${NOTECODE_OPEN_SOURCE_CACHE:-$HOME/Library/Caches/NoteCode-open-source}/${tmp:t}
work=$cache/tree dd=$cache/dd
mkdir -p "$cache"

remove_tree() {
  if [[ -e $work ]]; then
    git -C "$repo" worktree remove --force "$work" >/dev/null 2>&1 || rm -rf "$work"
  fi
  git -C "$repo" worktree prune >/dev/null 2>&1
}
# One EXIT trap for both: lib-xcode.sh's releases the simulator lock, and a
# second `trap … EXIT` would replace it.
cleanup() {
  remove_tree
  [[ -n ${_sim_lock:-} ]] && rm -rf "$_sim_lock"
}
trap cleanup EXIT

# The lock first: the tree's path is fixed, so two runs from this checkout
# must not share it. A tree left by a killed run goes before the new one.
take_lock
remove_tree
if ! git -C "$repo" worktree add --detach --quiet "$work" HEAD; then
  print "open-source: git worktree add failed"; exit 1
fi

# The public tree: NoteCode/ minus Pro/ plus the edition's files, all from
# HEAD's OpenSource/, not this checkout's.
rm -rf "$work/NoteCode/Pro" "$work/NoteCodeTests/Pro"
cp "$work/OpenSource/OpenSourceEdition.swift" "$work/NoteCode/App/" || exit 1
cp "$work/OpenSource/OpenSourceEditionTests.swift" "$work/NoteCodeTests/App/" || exit 1
cp "$work/OpenSource/Info.plist" "$work/NoteCode/Info.plist" || exit 1
cp "$work/OpenSource/PrivacyInfo.xcprivacy" "$work/NoteCode/PrivacyInfo.xcprivacy" || exit 1

# xcode_test builds $root's project; point it at the public tree. The logs
# stay in this checkout's $tmp.
root=$work
log=$tmp/open-source.log bundle=$tmp/open-source.xcresult
export NOTECODE_PLAN=Fast NOTECODE_COVERAGE=0

start=$SECONDS
xcode_test $log $bundle -only-testing:NoteCodeTests -derivedDataPath "$dd"
code=$?
secs=$(( SECONDS - start ))

if grep -qE "^/.*: error: |^error: |BUILD FAILED" $log; then
  print "open-source build: FAILED in ${secs}s"
else
  print "open-source build: ok in ${secs}s"
fi
# Paths are cut to start at the target folder: the worktree is gone by the
# time anyone reads this.
grep -E "^/.*: error: |^error: " $log | sed -E 's#^.*/(NoteCode(Tests|UITests)?/)#\1#' | sort -u | head -20
grep -E "✘" $log | sort -u | head -20
if [[ -d $bundle ]]; then
  xcrun xcresulttool get test-results summary --path $bundle 2>/dev/null \
    | python3 -I -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
keys=("result","totalTestCount","passedTests","failedTests","skippedTests")
print("open-source tests: "+", ".join(f"{k}={d[k]}" for k in keys if k in d))
for f in d.get("testFailures",[]):
    print("  FAIL", f.get("testName",""), "-", f.get("failureText","")[:200])
'
fi

if (( code == 0 )); then print "OPEN SOURCE OK"; else print "OPEN SOURCE FAILED (xcodebuild exit $code; log: $log)"; fi
exit $code
