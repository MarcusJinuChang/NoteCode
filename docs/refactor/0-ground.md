# 0. The ground: hygiene, scripts, baseline

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. 0A (the device pass) and 0F (a reproducible
build) are Marcus's, in README › Marcus's part.

## 0B. Hygiene

**Do.** Show Marcus each list and wait for his yes before removing anything.

1. **Worktrees.** `git worktree list --porcelain` shows 55 under
   `.claude/worktrees/` (645 MB). For each, give its branch, whether the
   branch is merged into `main` (`git branch --merged main`), and whether
   `git -C <path> status --porcelain` is empty. On his yes, `git worktree
   remove` the clean ones, then `git worktree prune`. A dirty one stays
   unless he names it.
2. **Branches.** Local `claude/*` branches merged into `main`: delete with
   `git branch -d` (never `-D`). Remote ones: the list, then
   `git push origin --delete` only for the ones he approves. Never `main`,
   `gh-pages`, or a branch with an open PR.
3. **Files that aren't the repo's.** `marketing.md`, `release-handwork.md`
   and `tmp-review/` are untracked and not ignored, so one careless
   `git add` publishes them. Ask Marcus where they go (outside the repo);
   they come back as private docs in split.md › S5.
4. **The shared scheme.** `NoteCode.xcodeproj/xcshareddata/` is untracked.
   Check it holds only the scheme (no user data), then commit it: the
   scripts and CI need a shared scheme.
5. **`server/run-proxy/package-lock.json`.** Show the diff. If it is only
   npm dropping an extraneous entry, commit it with the scheme; otherwise
   ask.

Don't touch `.claude/settings.local.json`, `project.pbxproj` or
`Info.plist`.

**Done when.** `git status` shows only Marcus's own project and plist
edits; one PR, "0B: Share the scheme", with the scheme (and the lock file if
it went in).

## 0C1. Scripts: check and perf

**Do.** Plain `zsh`/`bash` scripts with no new tools, short output, and the
full log written to a file under `$TMPDIR`.

- **`scripts/check.sh [--full] [--only <Suite> …]`**
  - Lint first: it calls `scripts/lint-traps.sh` once that exists (0C2).
  - Build and test with `xcodebuild test -project NoteCode.xcodeproj
    -scheme NoteCode -destination "platform=iOS Simulator,name=${NOTECODE_SIM:-iPad Pro 13-inch (M5)}"
    -only-testing:NoteCodeTests -parallel-testing-enabled NO
    -clonedSourcePackagesDirPath ~/Library/Developer/NoteCode-SourcePackages
    -resultBundlePath <tmp>`.
  - `--only` narrows the run to the named suites.
  - Hold a lock around the run (`mkdir` on a lock directory, removed by a
    `trap`), so two sessions never share the simulator; AGENTS.md › Build
    has the "Busy" failures.
  - Print only what a reader needs: errors, the failing tests' names and
    messages, and the summary from
    `xcrun xcresulttool get test-results summary`.
  - **Warnings.** Count the build's unique `warning:` lines, grouped by
    category. Fail if the count is above the one in
    `docs/refactor/baseline.md` (a ratchet: it may only fall).
  - **macOS.** Build only if `xcodebuild -showdestinations` lists the
    platform.
  - **`--full`** adds `NoteCodeUITests` (once T9 exists) and the run
    proxy's `npm test` and `npx tsc --noEmit`, when `node_modules` is
    there.
- **`scripts/perf.sh [--compare docs/refactor/baseline.md]`**
  - Find the cost tests with `grep -rn "Cost\|cost" NoteCodeTests`. Today
    they are:
    - `StylingPerformanceTests`, `CodeFenceCostTests`, `TextSizeCostTests`
    - `MarkdownLayoutCostTests`
    - `LineNumbersTests`' cost test
    - `PageViewTests/openingCost`
    - `NotePDFTests/printingCost`
  - Add a tiny test helper that prints `PERF <test> <seconds>`, and call it
    beside each cost test's existing `#expect`. That is a test-only change;
    the bounds stay as they are.
  - The script runs those tests, collects the `PERF` lines and prints a
    table.
  - With `--compare`, it shows each number's change and exits non-zero if
    any is more than 10% worse.
- **`.github/pull_request_template.md`**
  - **What and why**, for anyone viewing the project.
  - **Checklist:** behaviour change (none, or which fix)? Stored data,
    settings keys or defaults touched? Traps touched (which)? Perf before
    and after? Device lines handed to Marcus?

**Done when.** On `main`, `scripts/check.sh --only SettingsTests` runs and
prints a summary of a few lines. `scripts/perf.sh` prints a table with one
row per cost test. Both are in the PR description with their output.

## 0C2. Lints: traps and moves

**Do.**

- **`scripts/lint-traps.sh`** greps the sources and exits non-zero with
  `file:line rule` for each hit. Comment lines don't count. A hit that is
  legitimate goes in `scripts/lint-allow.txt` as `rule file:line reason`;
  start from zero hits or an allow-list on `main`. The rules:
  1. `\.layoutManager\b` in `NoteCode/` (the text view drops to TextKit 1).
  2. `\.inkType\b` in `NoteCode/` (traps on eraser ink).
  3. `map`, `reduce`, `compactMap`, `filter`, `first(where:)`, or a
     subscript by position on a `MarkupOrderedSet`. Grep can't see types;
     match the variables named `*markup*`/`*elements*` that hold one, and
     say in the PR what the rule can't catch.
  4. `import SwiftUI` or `import UIKit` in a file under any `Core/` folder.
  5. In tests, `#filePath` followed by `deletingLastPathComponent` (use the
     `repoRoot` helper from T1).
  6. Two Swift files with the same basename in one target's folder.
  7. `UserDefaults.standard` in `NoteCodeTests/`, as a count that may only
     fall. It reaches zero in T1.
- **`scripts/verify-move.sh [base]`** (default `origin/main`) checks that a
  commit only moves code.
  - Collect every removed and every added line in `*.swift` (`git diff -U0
    -M base`), skipping lines that are blank, `}`, `import …`,
    `// MARK: …`, an `extension … {` header, or `#if`/`#endif`.
  - Strip a leading `private`, `fileprivate` or `internal` from both sides,
    and list each line where that was the only difference ("access
    loosened").
  - Sort both sides and diff them. Anything left over means the commit is
    not a pure move.
  - Print the leftovers and exit non-zero. Pure renames show nothing.
- `check.sh` runs `lint-traps.sh` first.

**Done when.** `lint-traps.sh` is clean on `main`, or clean with a short
allow-list that gives reasons. A scratch branch that moves one function to a
new extension file passes `verify-move.sh`. The same move with one line
changed fails, and the PR shows both outputs.

## 0D. Baseline

**Do.** On `main`, after 0C1, write `docs/refactor/baseline.md`, the
reference every later PR compares with:

1. **The full run:** `check.sh --full` gives the test count and wall time.
   With `-enableCodeCoverage YES` on that run, add each top-level folder's
   coverage from `xcrun xccov view --report --json`.
2. **Where the time goes.** Read the result bundle with
   `xcrun xcresulttool get test-results tests` and sum each Test Case
   node's `durationInSeconds`. On 29 Oct the tests summed to 222s of a 566s
   run. Give the 20 slowest tests and the 10 slowest suites. Then find where
   the rest goes, from the bundle's and the log's timestamps: build,
   simulator boot, host launch, first test to last test, and the gap before
   `xcodebuild` exits. Name the cheapest saving. Measuring is the job here,
   not fixing.
3. **Perf:** the `perf.sh` table.
4. **Warnings:** the count by category. This is the number `check.sh`
   ratchets against.

**Done when.** `baseline.md` holds those four, each with the command that
produced it and the `main` commit it was taken at.

## 0C3. Check fixes from the baseline (PR 142)

**Done (PR 142).** 0D's findings 3 and 4, the UI-run split from finding 2,
and the simulator lock. Scripts and docs only.

- **Per-test allowance.** Every `xcodebuild test` run gets
  `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 120`,
  set in `lib-xcode.sh`, so `perf.sh` has it too.
- **Warnings counted once per unique diagnostic:** unique
  `file:line:col: warning:` lines, paths cut to the target folder, by
  category. `baseline.md` holds the new count.
- **`--coverage`** adds `-enableCodeCoverage YES` and a per-top-level-folder
  table from `xccov`.
- **UI tests in their own invocation.** `--full` runs `NoteCodeUITests` as a
  second `xcodebuild` after the unit tests, reported separately.
- **The simulator lock** is at a fixed shared path,
  `${NOTECODE_LOCK_DIR:-$HOME/Library/Caches/NoteCode-check}/sim.lock`, the
  same for every session and worktree. The `EXIT` trap had been set inside
  `take_lock`, and zsh runs it when the function returns, so the lock never
  held; the traps are now at the top level of `lib-xcode.sh`. A waiter
  re-reads the pid before removing a stale lock.
- **`verify-move.sh`** ignores comment-only lines and `import` lines
  (`@testable` and `@preconcurrency` included), and still fails on a changed
  code line.

The PR shows two `check.sh --only SettingsTests` runs started 3s apart, the
second waiting for the first, and a waiter taking the lock after the holder
was killed.

## 0E. CI (optional)

**Do.** `.github/workflows/check.yml` runs `scripts/check.sh` on pull
requests to `main`. The repo is public, so macOS minutes are free.
1. Choose a hosted image whose `xcodebuild -version` is Xcode 27 with an
   iOS 27 simulator, and set `NOTECODE_SIM` to a device that image has.
2. If no hosted image has Xcode 27 yet, commit the workflow with only
   `workflow_dispatch`, and say why in the PR.

**Done when.** One green run on the PR itself, or the PR explains why there
isn't one.
