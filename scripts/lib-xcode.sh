#!/bin/zsh
# Shared by check.sh and perf.sh: the destination, the simulator lock and the
# one xcodebuild invocation. Source it; it runs nothing.

root=${0:A:h:h}
sim=${NOTECODE_SIM:-iPad Pro 13-inch (M5)}
packages=~/Library/Developer/NoteCode-SourcePackages
# Logs and result bundles: one directory per worktree. Sessions on this Mac
# can share $TMPDIR, and with one fixed directory a session read another
# worktree's check.log and reported its warnings as its own. Keyed by the
# worktree folder's name and a hash of its absolute path, so two checkouts
# with the same folder name still differ.
tmp=${TMPDIR:-/tmp}/notecode-check/${root:t}-$(print -rn -- "$root" | shasum | cut -c1-10)
mkdir -p "$tmp"

# Two sessions must never share the simulator (AGENTS.md › Build/test: the
# "Busy … failed preflight checks" failures). mkdir is atomic; the trap
# removes the lock however the script ends (see the traps below). A lock left by a dead run is
# taken over once its pid is gone. The lock is one fixed path for every
# worktree and session (a lock under $tmp, which is per worktree, would never
# be shared); NOTECODE_LOCK_DIR moves it. The logs stay under $tmp.
# One lock per simulator: runs on different simulators (NOTECODE_SIM, e.g.
# the "NoteCode Lane B" and "NoteCode Lane C" copies of the iPad Pro 13-inch)
# go at once; two runs on one simulator still queue. The default simulator
# keeps the old path, sim.lock.
take_lock() {
  local lockdir=${NOTECODE_LOCK_DIR:-$HOME/Library/Caches/NoteCode-check}
  mkdir -p "$lockdir"
  local lock=$lockdir/sim.lock owner
  [[ -n ${NOTECODE_SIM:-} && $sim != "iPad Pro 13-inch (M5)" ]] &&
    lock=$lockdir/sim-$(print -rn -- "$sim" | shasum | cut -c1-10).lock
  while ! mkdir "$lock" 2>/dev/null; do
    owner=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n $owner ]] && ! kill -0 "$owner" 2>/dev/null; then
      # Re-read just before taking over, so a waiter that lost the race does
      # not remove the new holder's lock.
      [[ $(cat "$lock/pid" 2>/dev/null || true) == $owner ]] && rm -rf "$lock"
      continue
    fi
    print -u2 "waiting for the simulator (held by pid ${owner:-?})…"
    sleep 5
  done
  print $$ > "$lock/pid"
  _sim_lock=$lock
}

# The traps are at the top level of this file, which the calling script
# sources: zsh runs an EXIT trap set inside a function when the function
# returns, which released the lock the moment take_lock came back. INT and
# TERM must exit, or zsh runs the handler and carries on.
trap '[[ -n ${_sim_lock:-} ]] && rm -rf "$_sim_lock"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# xcode_test <log> <result bundle> <-only-testing:… …>
# Every run gets a per-test time allowance, so a hung test fails after two
# minutes instead of holding the simulator lock all night (0D finding 1).
# NOTECODE_COVERAGE=1 adds -enableCodeCoverage YES (check.sh --coverage).
# NOTECODE_PLAN picks the test plan (TestPlans/<name>.xctestplan, T3): Fast
# (the default) is everything but the .perf tests, Full is all, Perf is .perf
# only, Pro is .pro only. An -only-testing argument narrows the plan it runs in.
xcode_test() {
  local log=$1 bundle=$2; shift 2
  local extra=(-test-timeouts-enabled YES -maximum-test-execution-time-allowance 120)
  [[ ${NOTECODE_COVERAGE:-0} == 1 ]] && extra+=(-enableCodeCoverage YES)
  rm -rf "$bundle"
  xcodebuild test -project "$root/NoteCode.xcodeproj" -scheme NoteCode -testPlan "${NOTECODE_PLAN:-Fast}" \
    -destination "platform=iOS Simulator,name=$sim" \
    "$@" $extra -parallel-testing-enabled NO \
    -clonedSourcePackagesDirPath "$packages" \
    -resultBundlePath "$bundle" > "$log" 2>&1
}

# xcode_clean <log>: removes this worktree's build products (its own
# DerivedData folder), so the next xcodebuild compiles every file and its log
# carries every warning (check.sh --full's count). Call it holding the lock:
# it needs no simulator, but xcodebuild resolves packages into the shared
# $packages folder first, and the lock is what keeps two worktrees'
# xcodebuilds off it at once. -disableAutomaticPackageResolution would avoid
# the write, but fails a clean on a machine (or after a Package.resolved
# change) whose packages are not resolved yet, and the clean is ~2s.
xcode_clean() {
  xcodebuild clean -project "$root/NoteCode.xcodeproj" -scheme NoteCode \
    -destination "platform=iOS Simulator,name=$sim" \
    -clonedSourcePackagesDirPath "$packages" > "$1" 2>&1
}

# Suite names → -only-testing arguments. A bare name is a suite (or a
# Suite/test); Swift Testing matches on the type name.
only_args() {
  if (( $# == 0 )); then print -- "-only-testing:NoteCodeTests"; return; fi
  local s; for s in "$@"; do print -- "-only-testing:NoteCodeTests/$s"; done
}
