#!/bin/zsh
# Prove the open-source edition compiles and its unit tests pass, with no
# project edit (docs/refactor/2X-seam.md › 2X7).
#
#   scripts/build-open-source.sh
#
# Works in a temporary worktree of HEAD (committed changes only), under
# $TMPDIR, removed however the script ends. There it deletes NoteCode/Pro/
# and NoteCodeTests/Pro/, copies OpenSource/OpenSourceEdition.swift into
# NoteCode/App/ and OpenSource/Info.plist and PrivacyInfo.xcprivacy over
# NoteCode/'s, then builds and runs the Fast plan. The folders are
# synchronized groups, so the project picks up the difference by itself.
# Prints the build result and the test totals. Log and result bundle:
# open-source.log and open-source.xcresult in this worktree's
# $TMPDIR/notecode-check/<worktree>-<hash>/ (lib-xcode.sh).
#
# The Google Mobile Ads and UMP packages stay linked: they are the target's
# package dependencies, and removing them is a project edit (the split).
# Only Pro/ imports them, so nothing here calls them.

set -uo pipefail
source ${0:A:h}/lib-xcode.sh
cd "$root"

repo=$root
work=$(mktemp -d "${TMPDIR:-/tmp}/notecode-open-source.XXXXXX") || exit 1
rmdir "$work"   # git worktree add wants to make it

# One EXIT trap for both: lib-xcode.sh's releases the simulator lock, and a
# second `trap … EXIT` would replace it.
cleanup() {
  [[ -n ${_sim_lock:-} ]] && rm -rf "$_sim_lock"
  if [[ -d $work ]]; then
    git -C "$repo" worktree remove --force "$work" >/dev/null 2>&1 || rm -rf "$work"
  fi
  git -C "$repo" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT

if ! git -C "$repo" worktree add --detach --quiet "$work" HEAD; then
  print "open-source: git worktree add failed"; exit 1
fi

# The public tree: NoteCode/ minus Pro/ plus the edition file.
rm -rf "$work/NoteCode/Pro" "$work/NoteCodeTests/Pro"
cp "$repo/OpenSource/OpenSourceEdition.swift" "$work/NoteCode/App/" || exit 1
cp "$repo/OpenSource/Info.plist" "$work/NoteCode/Info.plist" || exit 1
cp "$repo/OpenSource/PrivacyInfo.xcprivacy" "$work/NoteCode/PrivacyInfo.xcprivacy" || exit 1

# xcode_test builds $root's project; point it at the public tree. The logs
# stay in this worktree's $tmp.
root=$work
log=$tmp/open-source.log bundle=$tmp/open-source.xcresult
export NOTECODE_PLAN=Fast NOTECODE_COVERAGE=0

take_lock
start=$SECONDS
xcode_test $log $bundle -only-testing:NoteCodeTests
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
