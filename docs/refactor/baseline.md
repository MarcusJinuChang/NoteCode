# Baseline (0D)

Taken at `main` 8767927 (after 0B, T1, F2, F3, 0C1, 0C2) on 2–3 Nov 2026,
iPad Pro 13-inch (M5) simulator, iOS 27.2 SDK, `-parallel-testing-enabled NO`,
one machine, nothing else running on the simulator. Every later PR compares
with this file: `scripts/perf.sh --compare docs/refactor/baseline.md` reads the
`PERF` lines, `scripts/check.sh` reads the `WARNINGS` line.

## 1. The full run

| | |
|---|---|
| Unit tests (`-only-testing:NoteCodeTests`, TipJarTests skipped) | **1,859 tests in 214 suites: 1,858 passed, 1 known issue (expected failure), 0 failed** |
| Wall time | **495 s** for `xcodebuild` (warm build); 488 s from first to last test; the result bundle is written 18 s after the last test |
| `TipJarTests` alone | 7 of 7 passed in 6 s (see Findings 1) |
| UI tests (`NoteCodeUITests`, the first run ever) | 18 tests: 10 HotbarUITests (**6 failed**, see Findings 2), 2 ListDragUITests skipped, 2 NoteCodeUITests and 4 launch tests passed. 202 s |
| Clean build of app + both test targets, with first launch | 89 s (22:15:07 to the first test at 22:16:36) |

Commands:

```
xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:NoteCodeTests -skip-testing:NoteCodeTests/TipJarTests \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  -parallel-testing-enabled NO -enableCodeCoverage YES -derivedDataPath <dd> \
  -resultBundlePath unit.xcresult
# then the same with -only-testing:NoteCodeTests/TipJarTests
# UI + clean build: -only-testing:NoteCodeTests -only-testing:NoteCodeUITests, empty <dd>
```

`check.sh --full` as it stands does not give these numbers: it has no
coverage flag and no time allowance (Findings 3).

### Coverage (`xcrun xccov view --report --json unit.xcresult`, unit tests only)

`NoteCode/` has no subfolders (156 `.swift` files at the top level, plus
`Assets.xcassets`), so per-folder coverage does not exist yet. 1A creates the
folders; re-take this table per folder after it.

| Target | Covered / executable lines | |
|---|---|---|
| NoteCode.app | 23,450 / 33,807 | **69.4%** |
| NoteCodeTests.xctest | 25,071 / 25,449 | 98.5% |
| NoteCodeUITests.xctest | 0 / 353 | 0% (not in this run) |
| GoogleMobileAds, UMP | 0 / 0 | |

## 2. Where the time goes

Unit run, `xcresulttool get test-results tests`, sum of every Test Case's
`durationInSeconds`: **217 s of the 488 s test window** (29 Oct: 222 s of
566 s). 271 s (55%) is outside any test case: per-test and per-suite setup,
main-actor hops between tests, and this run's coverage instrumentation (the
29 Oct run is not known to have had it). The measurement does not separate
those, so it is not claimed. Phases of this run, from the log:

| Phase | Time |
|---|---|
| Build (incremental, warm) + boot + host launch | 6 s |
| First test to last test | 488 s |
| Last test to `xcodebuild` exit (coverage merge, result bundle) | 18 s |

The clean build (89 s, UI run) is the build cost of a fresh checkout.

**Cheapest saving, not done here:** the 271 s of overhead outside test cases.
Run the same set once without `-enableCodeCoverage` to see how much is
instrumentation; `check.sh` already runs without it, so its wall time is the
number to watch. The 20 slowest tests together are only 74 s.

### 20 slowest tests (seconds)

| s | Suite / test |
|---|---|
| 9.0 | Page view |
| 6.7 | Rich paste: runs to Markdown |
| 5.8 | Hotbar layout |
| 5.4 | Note as a PDF |
| 5.2 | Text size: what a change costs |
| 4.2 | Markdown layout cost |
| 3.6 | Room around and inside a code block |
| 3.6 | Page settling |
| 3.2 | Page settling |
| 3.1 | Appearance setting |
| 2.9 | Text size: re-flowing keeps the reader's place |
| 2.8 | Page settling |
| 2.7 | Finger Draws carries over |
| 2.7 | Page settling |
| 2.5 | Code fences, away and editing |
| 2.4 | Text size: re-flowing keeps the reader's place |
| 2.2 | Hidden markers in the text view |
| 2.2 | Hotbar icons are visible |
| 2.2 | Outline: going to a heading |
| 1.9 | Reopening at the last page |

### 10 slowest suites (sum of their tests)

| s | Tests | Suite |
|---|---|---|
| 216.7 | 1857 | NoteCodeTests |
| 0.0 | 2 | Outline: going to a heading |

(Suite names are the Swift Testing display names.)

## 3. Perf

`scripts/perf.sh`, run after the full run, no coverage. The `PERF` lines are
what `--compare` reads (seconds).

```
PERF CodeFenceCostTests/caretMoveCost.into 0.0018
PERF CodeFenceCostTests/caretMoveCost.keystroke 0.0420
PERF CodeFenceCostTests/caretMoveCost.out 0.0019
PERF LineNumbersTests/keystrokeCost.off 0.0347
PERF LineNumbersTests/keystrokeCost.on 0.0341
PERF MarkdownLayoutCostTests/typingCost.legacy 0.0394
PERF MarkdownLayoutCostTests/typingCost.rendered 0.0394
PERF NotePDFTests/printingCost 0.8737
PERF PageViewTests/openingCost.open 0.1475
PERF PageViewTests/openingCost.switch 0.3195
PERF StylingPerformanceTests/fullPassCost 0.0062
PERF StylingPerformanceTests/keystrokeCost 0.0006
PERF StylingPerformanceTests/parseCost 0.0030
PERF TextSizeCostTests/firstFrame 0.0920
```

NotePDFTests/printingCost (0.87 s) and PageViewTests/openingCost.switch
(0.32 s) are the large ones; AGENTS.md records 1.8 s and 323 ms for the same
two on 10 Oct.

## 4. Warnings

Counted the way `scripts/check.sh` counts (`grep "warning:" | sort -u`), on
the clean build of the app, unit and UI targets: the line below is what the
ratchet reads.

WARNINGS 61

That count includes compiler art lines (the `|` source excerpts under each
warning). The warnings themselves are **13**, by category:

| Count | Warning |
|---|---|
| 5 | main actor-isolated static member referenced from a Sendable or nonisolated context (Swift 6 error): ProStatus.swift:250, ProStatusTests:64, PaywallTests:21 and :63, FormulaEditingTests:154 |
| 3 | `[#DeprecatedDeclaration]`: `UIWindow(frame:)` in TestWindow.swift:36 and TextRewritingPolicyTests:338, `traitCollectionDidChange` in PageWindowChrome.swift:94 |
| 1 | StoreKitTest's `SKTestTransaction.h:34` deprecated (`PurchaseResult` instead), reached from a test |
| 1 | `[#DeprecatedDeclaration]` Google Mobile Ads banner size, AdBanner.swift:62 |
| 1 | `[#UnnecessaryEffectMarker]` TipJarTests.swift:199 |
| 1 | code after `throw` never executed, ListDragUITests.swift:27 |
| 1 | "consider using asynchronous alternative function", AdConsent.swift:149 |

Command: `grep -E "^/.*:[0-9]+:[0-9]+: warning: " build.log | sort -u`.

## Findings (recorded, not fixed)

1. **A StoreKit test hung for 11.5 hours.** In the first unit run,
   `TipJarTests` › "The jar asks for the products the configuration sells,
   and a tip is thanked and finished" (a StoreKit test purchase) waited
   with no timeout until Marcus stopped the run; the 1,826 tests before it had
   passed. Rerun alone with a 120 s allowance, all 7 passed in 6 s, so it
   is intermittent. Its own fix PR: a timeout in the test and a cause.
2. **6 of 10 `HotbarUITests` fail, the first UI-test run ever.**
   `testAutocorrectOffKeepsThreeHyphens` (app not running),
   `testReachDockedLeft` and `testReachDockedRight` (no element with identifier
   "Red"), `testRowBesideBarDockedAtTheBottom`, `…Left` and `…Right` (gap 12.0,
   expected 8.0 ±1). Each is the UI test being stale or the layout having
   changed; which, is for the fix PR. The same run's unit bundle crashed
   ("Test crashed with signal kill before establishing connection") when
   both bundles ran in one invocation, so UI tests need their own run.
3. **`check.sh` needs a per-test time allowance** (`-test-timeouts-enabled YES
   -maximum-test-execution-time-allowance 120`), or one hung test stalls it
   and holds the simulator lock for as long. It also lacks a coverage option.
4. **The `WARNINGS` ratchet counts art lines (61), not warnings (13).** A
   warning gaining a longer source excerpt raises it. Count lines matching
   `^/.*:[0-9]+:[0-9]+: warning:` instead, and set the number to 13.
