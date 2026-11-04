# Baseline (0D)

Taken at `main` 8767927 (after 0B, T1, F2, F3, 0C1, 0C2) on 2–3 Nov 2026,
iPad Pro 13-inch (M5) simulator, iOS 27.2 SDK, `-parallel-testing-enabled NO`,
one machine, nothing else running on the simulator. Every later PR compares
with this file: `scripts/perf.sh --compare docs/refactor/baseline.md` reads the
`PERF` lines, `scripts/check.sh` reads the `WARNINGS` line.

## 1. The full run

| | |
|---|---|
| Unit tests (`-only-testing:NoteCodeTests`, TipJarTests skipped) | **1,859 test cases in 214 suites (1,355 parameterized arguments among them): 1,858 passed, 1 expected failure, 0 failed** |
| Wall time | **495 s** for `xcodebuild` (warm build): 6 s setup, 487.4 s first test to last, about 1 s to exit. Without coverage 492 s (§2) |
| `TipJarTests` alone | 7 of 7 passed in 6 s (see Findings 1) |
| UI tests (`NoteCodeUITests`, the first run ever) | 18 tests: 10 HotbarUITests (**6 failed**, see Findings 2), 2 ListDragUITests skipped, 2 NoteCodeUITests and 4 launch tests passed. 202 s |
| Clean build of app + both test targets, with first launch | 89 s (22:15:07 to the first test at 22:16:36) |

Commands (taken at `main` 8767927; `<dd>` is an empty `-derivedDataPath`):

```
xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -only-testing:NoteCodeTests -skip-testing:NoteCodeTests/TipJarTests \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  -parallel-testing-enabled NO -enableCodeCoverage YES -derivedDataPath <dd> \
  -resultBundlePath unit.xcresult
# then the same with -only-testing:NoteCodeTests/TipJarTests
# the no-coverage run of §2 is the first command without -enableCodeCoverage YES
# UI + clean build: -only-testing:NoteCodeTests -only-testing:NoteCodeUITests, empty <dd>
```

Since 0C3, `check.sh --full --coverage` runs these as two invocations (unit,
then UI), each with the 120 s allowance, and prints coverage per folder.

### Coverage (`xcrun xccov view --report --json unit.xcresult`, unit tests only; `main` 8767927)

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

Taken at `main` 8767927. Source: `xcrun xcresulttool get test-results tests
--path unit.xcresult` (every Test Case node) and the `xcodebuild` log's own
timestamps and "Suite … passed after N seconds" lines. Two unit runs, the
first with `-enableCodeCoverage YES` and the second without; the commands are
in §1.

**A Test Case node's `durationInSeconds` is one argument's time for a
parameterized test.** Its 68 `Arguments` children hold the rest. Summing
only Test Case nodes gives 217 s of 488 s, which is what the first draft of
this file said and why the 29 Oct "222 s of 566 s" looks the same: it is
almost certainly the same undercount. Summing the arguments where a case has
them:

| Run | xcodebuild wall | Setup (build, boot, launch) | First test to last test | Test cases summed | Last test to exit |
|---|---|---|---|---|---|
| With coverage | 495 s | 6 s | 487.4 s | not re-summed | about 1 s |
| Without coverage | 492 s | 5.9 s | 485.4 s | **484.8 s** (1,859 cases, 1,355 arguments) | about 1 s |

So the tests are the run: 484.8 s of 485 s, with no gap to explain, and
coverage costs 2 s. The 495 s and 492 s add up from the columns. (The result
bundle's folder is last modified 17 s after exit in the coverage run; not
examined, since `xcodebuild` had already exited.) The clean build is 89 s on top
(§1).

**Cheapest saving, measured, not done here:** one parameterized test is 152.5 s
of the 485 s (31%): `HotbarIconPixelTests/visible(name:scheme:)`, 68
arguments of about 2.2 s each (every hotbar control, light and dark). The
next three tests are `pageStaysPut` 17.6 s, `keepsTheTopLine` 14.7 s and
`settlesAtWholePages` 10.7 s. Rendering each argument at
2.2 s is the cost; fewer pixels or one render shared across a control's two
schemes would take most of the 152 s. The next step is T-tests.md's call, not
this PR's.

### 20 slowest tests (seconds, arguments summed)

| s | Suite › test (identifier) |
|---|---|
| 152.5 | Hotbar icons are visible › Every drawn control shows its icon on the bar in every state, light an (`HotbarIconPixelTests/visible(name:scheme:)`) |
| 17.6 | Hotbar layout › The page is the same size and in the same place in text mode, ink mode (`HotbarLayoutTests/pageStaysPut(dock:)`) |
| 14.7 | Text size: re-flowing keeps the reader's place › A size change keeps the line the reader was on at the top, as a note l (`TextSizeReflowTests/keepsTheTopLine(mode:size:)`) |
| 10.7 | Page settling › After a mode switch the note settles at whole pages, with nothing forc (`PageSettlingTests/settlesAtWholePages(target:)`) |
| 9.1 | Caret anywhere: a tap below the text › A tap k lines below the end puts the caret on that line, at the end of (`CaretAnywhereTests/reachesTheTap(_:lines:)`) |
| 8.9 | Page view › However long the note, the canvas is no taller than the screen (`PageViewTests/canvasStaysScreenSized()`) |
| 8.0 | Return and Backspace through the coordinator › A Return moves the text below it by exactly one line, in code and out (`ReturnAndBackspaceTests/returnAddsOneLine(_:)`) |
| 7.9 | Hotbar layout › The buffer leaves the text container at the pages' own width in every  (`HotbarLayoutTests/bufferLeavesTheLayoutAlone(mode:dock:)`) |
| 7.9 | Return and Backspace through the coordinator › Every held Return and Backspace changes the text and moves the caret (`ReturnAndBackspaceTests/everyPressRegisters(_:)`) |
| 6.7 | Rich paste: runs to Markdown › Random pastes keep their characters, or are plain (`RichPasteTests/property()`) |
| 6.6 | Outline: going to a heading › A tap puts that heading's line at the top, as a laid-out note has it (`NoteOutlineScrollTests/headingGoesToTheTop(mode:)`) |
| 6.5 | Page settling › Seamless, then print, scrolled deep, then seamless again: the page's o (`PageSettlingTests/roundTripDeepShowsPagesFirstLine(orientation:)`) |
| 5.9 | Reopening at the last page › A note opens with the page it was left at at the top: its first line,  (`ReopenTests/opensAtThePage(mode:orientation:)`) |
| 5.7 | Page settling › From a sheet's top margin, switching to seamless shows that page from  (`PageSettlingTests/sheetTopSurvivesSettling(orientation:)`) |
| 5.4 | Note as a PDF › Code prints in the light theme's colours even when the device is dark (`NotePDFTests/lightSyntaxOnDarkDevice()`) |
| 5.4 | Page settling › Deep in a note scrolled to by hand, switching to seamless shows the pa (`PageSettlingTests/deepSheetTopShowsPagesFirstLine(orientation:)`) |
| 5.3 | Hotbar layout › The page is Hotbar.pageBuffer from every screen edge the bar doesn't t (`HotbarLayoutTests/pageKeepsOffTheEdges(dock:held:)`) |
| 5.2 | Text size: what a change costs › A size change on a 250-line note reaches its first frame within budget (`TextSizeCostTests/firstFrame()`) |
| 4.8 | Heading markers › The hashes show in the margin while the caret is on the heading, in se (`HeadingMarkerTests/drawnInTheMargin(layout:style:)`) |
| 4.0 | Markdown layout cost › A keystroke in a rendered note costs no more than in a legacy one, on  (`MarkdownLayoutCostTests/typingCost()`) |

### 10 slowest suites

| Suite wall s | Test-case s | Tests | Suite |
|---|---|---|---|
| 152.6 | 152.5 | 1 | Hotbar icons are visible |
| 35.3 | 35.2 | 98 | Page view |
| 33.8 | 33.8 | 6 | Page settling |
| 31.0 | 30.9 | 4 | Hotbar layout |
| 19.3 | 19.3 | 3 | Text size: re-flowing keeps the reader's place |
| 17.0 | 17.0 | 3 | Return and Backspace through the coordinator |
| 16.2 | 16.2 | 21 | Code fences, away and editing |
| 13.8 | 13.8 | 6 | Reopening at the last page |
| 11.4 | 11.4 | 15 | Line numbers |
| 11.0 | 11.0 | 6 | Caret anywhere: a tap below the text |

(Suite names are the Swift Testing display names; the identifier in the first
table is `Suite/function`, so rows are unique.)

## 3. Perf

Taken at `main` 8767927.

Command: `scripts/perf.sh`, run after the full run, no coverage. The `PERF` lines are
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
PERF NoteSearchResultsTests/cost.empty 0.0000
PERF PageViewTests/openingCost.open 0.1475
PERF PageViewTests/openingCost.switch 0.3195
PERF StylingPerformanceTests/fullPassCost 0.0062
PERF StylingPerformanceTests/keystrokeCost 0.0006
PERF StylingPerformanceTests/parseCost 0.0030
PERF TextSizeCostTests/firstFrame 0.0920
```

NotePDFTests/printingCost (0.87 s) and PageViewTests/openingCost.switch
(0.32 s) are the large ones. AGENTS.md records 1.8 s and 323 ms (10 Oct) for
the same two tests; both are at 2,000 strokes, so they are comparable:
printing is faster since, opening a switch is unchanged. Those AGENTS.md
figures predate the baseline and are not enforced; this table is.

`NoteSearchResultsTests/cost.empty` (F4a, 3 Nov) is the note list's search call
with an empty query over 500 notes of 200 lines. It was 0.6 ms (median of 3,
back to back) because it read every note's text; now it reads none, under
0.05 ms. Its budget is 5 ms (the test's bound); perf.sh does not judge numbers
under 5 ms.

## 4. Warnings

Taken at `main` 8767927.

Counted by `scripts/check.sh` (0C3): each unique `file:line:col: warning:`
diagnostic once, with paths cut to start at the target folder so the same
warning printed under two build paths counts once. The line below is what the
ratchet reads. Taken at `main` a5ff416 (3 Nov 2026, after 1A2), on a
clean build of the app, unit and UI targets:

    xcodebuild clean -project NoteCode.xcodeproj -scheme NoteCode
    xcodebuild build-for-testing -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' > build.log
    grep -E "^/.*:[0-9]+:[0-9]+: warning: " build.log \
      | sed -E 's#^.*/(NoteCode(Tests|UITests)?/)#\1#' | sort -u | wc -l

WARNINGS 12

By category:

| Count | Warning |
|---|---|
| 5 | main actor-isolated static member referenced from a Sendable or nonisolated context (Swift 6 error): ProStatus.swift:250, ProStatusTests:64, PaywallTests:21 and :63, FormulaEditingTests:154 |
| 3 | `[#DeprecatedDeclaration]`: `UIWindow(frame:)` in TestWindow.swift:36 and TextRewritingPolicyTests:338, `traitCollectionDidChange` in PageWindowChrome.swift:94 |
| 1 | `[#DeprecatedDeclaration]` Google Mobile Ads banner size, AdBanner.swift:62 |
| 1 | `[#UnnecessaryEffectMarker]` TipJarTests.swift:199 |
| 1 | code after `throw` never executed, ListDragUITests.swift:27 |
| 1 | "consider using asynchronous alternative function", AdConsent.swift:149 |

The 0D count was 13: it also had the StoreKitTest `SKTestTransaction.h:34`
deprecation, which this build does not print. The old ratchet's 61 counted the
compiler's source-excerpt lines; `check.sh` now prints the count by category
too. A run with `--only` compiles fewer files, so its count is lower; the
ratchet only means something after a clean build.

## Findings (recorded, not fixed)

1. **A StoreKit test hung for 11.5 hours.** In the first unit run,
   `TipJarTests` › "The jar asks for the products the configuration sells,
   and a tip is thanked and finished" (a StoreKit test purchase) waited
   with no timeout until Marcus stopped the run; the 1,826 tests before it had
   passed. Rerun alone with a 120 s allowance, all 7 passed in 6 s, so it
   is intermittent. Environment: Xcode 27.2, iOS 27.2 simulator (iPad Pro
   13-inch M5); no simulator log was kept from the hung run. Its own fix PR:
   a timeout in the test and a cause.
2. **6 of 10 `HotbarUITests` fail, the first UI-test run ever.**
   `testAutocorrectOffKeepsThreeHyphens` (app not running),
   `testReachDockedLeft` and `testReachDockedRight` (no element with identifier
   "Red"), `testRowBesideBarDockedAtTheBottom`, `…Left` and `…Right` (gap 12.0,
   expected 8.0 ±1). Two fix PRs, not one: the three gap
   failures (12.0 where 8.0 is expected: a layout change or a stale
   expectation) and the three "Red" / app-not-running ones (stale
   identifiers, or the app dying at launch). The same run's unit bundle crashed
   ("Test crashed with signal kill before establishing connection") when
   both bundles ran in one invocation, so UI tests need their own run.
3. **(Fixed in 0C3.) `check.sh` needs a per-test time allowance** (`-test-timeouts-enabled YES
   -maximum-test-execution-time-allowance 120`), or one hung test stalls it
   and holds the simulator lock for as long. It also lacks a coverage option.
4. **(Fixed in 0C3.) The `WARNINGS` ratchet counts art lines (61), not warnings (13).** A
   warning gaining a longer source excerpt raises it. Count lines matching
   `^/.*:[0-9]+:[0-9]+: warning:` instead (this changes `check.sh` line 68),
   which moves the ratchet from 61 to 13.
