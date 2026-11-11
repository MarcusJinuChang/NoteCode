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
| Open-source build (`scripts/build-open-source.sh`, Fast plan; added 5 Nov at `main` 9361442, after 2X7) | **1,753 tests**: `NoteCodeTests` without `NoteCodeTests/Pro/`, plus `OpenSourceEditionTests` |
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
| 8.9 | Page view › However long the note, the canvas is no taller than the screen (`PageViewTests/Canvas/canvasStaysScreenSized()`) |
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

**Retaken 11 Nov 2026 at `main` b18d33b with the Perf test plan** (see
"The base retaken with the Perf plan" below). The `PERF` lines are what
`--compare` reads (seconds): the median of three `scripts/perf.sh` runs on an
idle Mac. They are the only `PERF` lines in this file.

```
PERF CodeFenceCostTests/caretMoveCost.into 0.0004
PERF CodeFenceCostTests/caretMoveCost.keystroke 0.0079
PERF CodeFenceCostTests/caretMoveCost.out 0.0005
PERF LineNumbersTests/keystrokeCost.off 0.0076
PERF LineNumbersTests/keystrokeCost.on 0.0074
PERF LineNumbersTests/longBlockCost 0.0018
PERF MarkdownLayoutCostTests/typingCost.legacy 0.0082
PERF MarkdownLayoutCostTests/typingCost.rendered 0.0093
PERF NoteListFetchCost/everything 0.0464
PERF NoteListFetchCost/live-only 0.0313
PERF NoteListFetchCost/warmup 0.0533
PERF NotePDFTests/printingCost 1.0673
PERF NoteSearchResultsTests/cost.empty 0.0000
PERF PageViewTests/exclusionPathsAreTheCost.paged 0.0053
PERF PageViewTests/exclusionPathsAreTheCost.with 0.1054
PERF PageViewTests/exclusionPathsAreTheCost.without 0.0008
PERF PageViewTests/openingCost.open 0.1919
PERF PageViewTests/openingCost.switch 0.3658
PERF PageViewTests/redrawCost 0.0407
PERF PageViewTests/typingCostLongNote 0.0052
PERF StylingPerformanceTests/fullPassCost 0.0063
PERF StylingPerformanceTests/keystrokeCost 0.0006
PERF StylingPerformanceTests/parseCost 0.0031
PERF TextSizeCostTests/firstFrame 0.0423
```

The first base, taken at `main` 8767927 by the old `perf.sh` (whole suites,
after the full run, no coverage), kept for the record; `--compare` no longer
reads it:

```
was CodeFenceCostTests/caretMoveCost.into 0.0018
was CodeFenceCostTests/caretMoveCost.keystroke 0.0420
was CodeFenceCostTests/caretMoveCost.out 0.0019
was LineNumbersTests/keystrokeCost.off 0.0347
was LineNumbersTests/keystrokeCost.on 0.0341
was LineNumbersTests/longBlockCost 0.0049
was MarkdownLayoutCostTests/typingCost.legacy 0.0394
was MarkdownLayoutCostTests/typingCost.rendered 0.0394
was NotePDFTests/printingCost 0.8737
was NoteSearchResultsTests/cost.empty 0.0000
was PageViewTests/openingCost.open 0.1475
was PageViewTests/openingCost.switch 0.3195
was StylingPerformanceTests/fullPassCost 0.0062
was StylingPerformanceTests/keystrokeCost 0.0006
was StylingPerformanceTests/parseCost 0.0030
was TextSizeCostTests/firstFrame 0.0920
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

### 2T1d: the old caches deleted (6 Nov, `main` 1e88da4)

`layoutCodeRanges`, `layoutNewlines`, `layoutMarkerRuns` and
`CodeBlockAction.targets(in:blocks:)` are gone; code ranges, marker runs and
each code block's newlines are read from the edit's `DocumentSnapshot`. Same
simulator, run back to back, with other lanes' test runs on the machine (it
read about 20% slow on tests this PR cannot touch, such as `openingCost`), so
the table gives `main` just before and this branch just after, in ms, besides
the 0D numbers above:

| Test | 0D | `main` before | after |
|---|---|---|---|
| StylingPerformanceTests/keystrokeCost | 0.6 | 0.6 | 0.7 |
| CodeFenceCostTests/caretMoveCost.keystroke | 42.0 | 45.3 | 44.4 |
| LineNumbersTests/keystrokeCost.on | 34.1 | 40.7 | 40.3 |
| LineNumbersTests/keystrokeCost.off | 34.7 | 40.4 | 40.6 |
| MarkdownLayoutCostTests/typingCost.rendered | 39.4 | 42.6 | 45.7 |
| MarkdownLayoutCostTests/typingCost.legacy | 39.4 | 45.3 | 45.1 |

No per-keystroke gain shows within the noise: 2T1c had already made the
three caches read the snapshot, so deleting them removes a second copy of
the same value, which no timer can see. The gain of the step (one
`nativeUTF8` and one parse per edit) is held by `MarkdownLayoutTests`
(`snapshotCount` goes up by one per edit and a layout pass adds none). The 0D
rows stay the reference for `--compare`. One perf test throws
`NSRangeException` ("NSMutableRLEArray replaceObjectsInRange … Out of
bounds"); it does so on `main` before this change too.

### F5: page breaks as pushed paragraphs (6 Nov, `main` ff578da)

`scripts/perf.sh --compare` of this branch against `main` just before, ms,
same simulator, run back to back with other lanes on the machine. The
`PERF` lines the new budget was (superseded 11 Nov by §3's lines, which
cover these rows):

```
was PageViewTests/typingCostLongNote 0.0051
was PageViewTests/exclusionPathsAreTheCost.paged 0.0050
was PageViewTests/exclusionPathsAreTheCost.with 0.1007
was PageViewTests/exclusionPathsAreTheCost.without 0.0008
```

| Test | before | after |
|---|---|---|
| `PageViewTests/typingCostLongNote` (a keystroke near the top of 40 pages) | 98.2 | 5.1 |
| `exclusionPathsAreTheCost.with` (the same text with the breaks as paths) | 106.0 | 100.7 |
| `exclusionPathsAreTheCost.without` (no paths) | 0.8 | 0.8 |
| `CodeFenceCostTests/caretMoveCost.keystroke` | 70.0 | 9.4 |
| `LineNumbersTests/keystrokeCost.on` / `.off` | 52 | 7.6 / 7.3 |
| `MarkdownLayoutCostTests/typingCost.rendered` / `.legacy` | 46 / 48 | 9.0 / 8.3 |
| `NotePDFTests/printingCost` | 1177 | 1064 |
| `PageViewTests/openingCost.open` / `.switch` | 212 / 437 | 187 / 360 |
| `LineNumbersTests/longBlockCost` | 2.1 | 1.4 (the block laid out first, see below) |

Every keystroke test that types in a paged note fell about tenfold: they all
paid for the exclusion paths. Nothing is more than 10% worse. Two tests
assumed the note was laid out to its end, which the exclusion paths did on
every edit: `longBlockCost` timed numbering 1,000 lines the edit had already
laid out, and `CodeFenceCostTests` › "A caret move into a block lays nothing
out" counted the fragments its first look at the tail made. Each now lays the
note out first. `TextSizeCostTests` still throws `NSRangeException` (above),
which ends the perf run there, as on `main`.

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

WARNINGS 2

Re-taken at `main` after 2W (6 Nov 2026) on a clean build: 31 warnings before,
2 now. Both are the compiler's and have no replacement that keeps what the
app does, so the ratchet keeps them:

| Count | Warning | Why it stays |
|---|---|---|
| 1 | `[#DeprecatedDeclaration]` `currentOrientationAnchoredAdaptiveBanner(width:)`, AdBanner.swift:61 | The SDK's replacement is the large anchored banner, up to 150pt on an iPad, which Marcus ruled out on 31 Oct (docs/design/shipping.md › Ads). |
| 1 | `[#DeprecatedDeclaration]` `UIWindow(frame:)`, TestWindow.swift:36 | `makeSceneLessTestWindow`: a window with no scene is the thing those tests measure (`PageSettlingTests`, `TextRegionSelectionTests`, `TextRewritingPolicyTests`); `init(windowScene:)` is the other case. |

The 0D count was 13: it also had the StoreKitTest `SKTestTransaction.h:34`
deprecation, which this build does not print. The old ratchet's 61 counted the
compiler's source-excerpt lines; `check.sh` now prints the count by category
too. An incremental build compiles fewer files, so its count is lower, and
the ratchet only means something after a clean build: `check.sh --full`
(without `--only`) cleans first and compares, and every other run prints
"warnings: incremental, not compared".

## 5. The seam

Taken at `main` acdc5a0 (4 Nov 2026, 2X1). Counted by `scripts/check-seam.sh`:
the files outside any `Pro/` folder whose code names a top-level type or
function of `NoteCode/Pro/`; one of the editor's Pro members (`ai`,
`run` or `pro` on a value called `editor`, or `explain`, `summariseNote`,
`insertAnswer`, `runInApp`, `connectRun` or `onRunNeedsPro` by name); or
`explainBlockAtCaret` or `runService` (`runBlockAtCaret` left the list
in 2X5b) (2X-seam.md › Where the code is today). The line below is what
`check.sh` reads; the count may only fall, and 2X7 keeps it at 0.

SEAM 0

2X6 (4 Nov) took both of DebugLaunch's Pro references out of Debug/ and the debug paywall out of NoteCodeScene: 12 files at main 348a257, 9 after; 8 once merged with 2X4a (PR 168); 6 with 2X4b (PR 171), which took SettingsView and WritingSettings; 1 with 2X5b (PR 172), leaving only PageDetailView; 0 with 2X5c (5 Nov), whose Run control, dock and host reach the page through the editor's features.

At 2X1 it was 16, not the brief's 14: the brief's table predates counting
`runBlockAtCaret` and `runService` by name, which adds `NoteCommands.swift`
(⌘R's `editor?.runBlockAtCaret?()`) and `AppSettings.swift` (where
`AppInfo.runService` is declared).

## 6. Release QA 4A (1.2.0)

Taken at `main` (6 Nov 2026, after 2W), iPad Pro 13-inch (M5) simulator copy,
with two other lanes running on the same Mac (load average about 100).

| Check | Result |
|---|---|
| `check.sh --full` | Unit: 2,047 tests, 2,046 passed and **1 failed** (`TextSizeCostTests/firstFrame`, a crash in the test's own set-up, fixed in this PR; it passes alone after the fix). UI: 16 tests, 12 passed, 4 skipped, 0 failed. Warnings 2 (the ratchet's 2). Seam 0. macOS build fails as expected (ad SDKs have no macOS slice), not counted |
| `build-open-source.sh` | ok in 517 s; 1,864 tests, 1,863 passed, 0 failed (the Fast plan runs one fewer) |
| `perf.sh --compare` | See below |

**The failure.** `TextSizeCostTests.firstFrame` replaced the text of a page opened
by `ReopenTests.open`, which does not call `observeEdits(of:)`. Since 2T1c (6 Nov)
the style session drops its snapshot only when the storage's edit notification
reaches it, so the restyle indexed the new 7,505-character note with the
23,369-character snapshot of the note it had opened and `NSMutableAttributedString`
threw an out-of-range exception. The test now calls `observeEdits(of:)` first. No app code changed.

**Perf.** Two runs, both with the Mac under heavy load from the other lanes
(load average 86 to 104), so the rows that came out worse are not trusted:
`parseCost`, a pure CPU parse that nothing has touched, read 3.0 ms and 5.5 ms
in the two runs. Run 2 against this file (ms; base in parentheses):

| Test | Run 1 | Run 2 | Base |
|---|---|---|---|
| `CodeFenceCostTests/caretMoveCost.into` | 0.4 | 0.5 | 1.8 |
| `CodeFenceCostTests/caretMoveCost.out` | 0.5 | 0.5 | 1.9 |
| `CodeFenceCostTests/caretMoveCost.keystroke` | 41.6 | 40.7 | 42.0 |
| `LineNumbersTests/longBlockCost` | 1.6 | 1.4 | 4.9 |
| `LineNumbersTests/keystrokeCost.on` / `.off` | 38.1 / 38.7 | 44.8 / 47.8 | 34.1 / 34.7 |
| `MarkdownLayoutCostTests/typingCost.legacy` / `.rendered` | 42.6 / 42.1 | 44.0 / 45.8 | 39.4 |
| `NotePDFTests/printingCost` | 1,098.7 | 1,506.9 | 873.7 |
| `PageViewTests/openingCost.open` / `.switch` | 204.3 / 380.9 | 194.8 / 376.3 | 147.5 / 319.5 |
| `TextSizeCostTests/firstFrame` | 111.5 | 108.6 | 92.0 |
| `StylingPerformanceTests/keystrokeCost` | 0.6 | 0.6 | 0.6 |
| `StylingPerformanceTests/fullPassCost` | 6.4 | 6.6 | 6.2 |

- **Gains that survive the load:** the caret-move costs into and out of a code
  block fell by about 75% (1.8 and 1.9 ms to 0.5 ms) and a long code block by
  about 70% (4.9 to 1.4 ms) in both runs.
- **The worse rows are load, shown by a control (6 Nov, load average 40 to 70
  throughout; the other lanes never leave the Mac quiet).** `perf.sh --compare` was
  run on this branch, then on `main` 8767927 (the commit this file was taken at,
  checked out in the same worktree and simulator), back to back, then on this branch
  again (ms; base in parentheses):

  | Test | This branch, run 1 | `8767927` | This branch, run 2 | Base |
  |---|---|---|---|---|
  | `LineNumbersTests/keystrokeCost.on` | 46.6 | 40.1 | 48.8 | 34.1 |
  | `MarkdownLayoutCostTests/typingCost.rendered` | 48.0 | 46.8 | 46.6 | 39.4 |
  | `NotePDFTests/printingCost` | 2,098.7 | 1,362.7 | 1,318.1 | 873.7 |
  | `PageViewTests/openingCost.open` / `.switch` | 222.6 / 475.0 | 198.1 / 393.9 | 196.5 / 377.6 | 147.5 / 319.5 |

  The unrefactored commit is 18% to 56% worse than its own base under this load, and
  this branch's second run matches it within a few percent. So the rows read worse
  because the Mac is busy, not because of the code. The gains held in every run
  (caret moves 67% to 68% better, long block 55%). Those figures do not meet "nothing
  more than 10% worse" in absolute terms: a run on an idle Mac is still owed, and
  Release QA item 1 is met only on the control's evidence until then.
- **New rows with no base yet:** `PageViewTests/exclusionPathsAreTheCost.with`
  98.8 to 111.1 ms, `.without` 0.8 ms and `PageViewTests/typingCostLongNote`
  96.6 to 98.4 ms (F5).

### D8: perf on an idle Mac (11 Nov 2026, `main` 3096763)

Mac17,2 (Apple M5, 10 cores, 32 GB), macOS 27.3, Xcode 27.2; a fresh
simulator ("NoteCode Lane Perf", iPad Pro 13-inch (M5), iOS 27.0). No other
xcodebuild or simulator on the Mac; each run started with the 1-minute load
average under 3 (2.2 to 3.0). Our own build and simulator raise it to about
55 during a run, as they did for the base. `perf.sh --compare` three times on
`main`, and once on `8767927` (the commit §3 was taken at) as a control, ms:

| Test | Run 1 | Run 2 | Run 3 | `8767927` | Base |
|---|---|---|---|---|---|
| `CodeFenceCostTests/caretMoveCost.into` / `.out` | 0.4 / 0.5 | 0.4 / 0.5 | 0.4 / 0.5 | 1.8 / 1.9 | 1.8 / 1.9 |
| `CodeFenceCostTests/caretMoveCost.keystroke` | 7.6 | 7.8 | 8.2 | 50.0 | 42.0 |
| `LineNumbersTests/keystrokeCost.on` / `.off` | 7.2 / 7.3 | 7.3 / 7.8 | 7.3 / 7.4 | 36.7 / 38.7 | 34.1 / 34.7 |
| `LineNumbersTests/longBlockCost` | 1.7 | 1.8 | 3.7 | - | 4.9 |
| `MarkdownLayoutCostTests/typingCost.legacy` / `.rendered` | 8.0 / 9.3 | 7.9 / 8.7 | 7.9 / 9.2 | 43.5 / 43.5 | 39.4 |
| `NotePDFTests/printingCost` | 1,123.5 | 978.2 | 1,004.5 | 945.8 | 873.7 |
| `PageViewTests/openingCost.open` | 159.2 | 187.6 | 186.8 | 180.2 | 147.5 |
| `PageViewTests/openingCost.switch` | 311.6 | 340.3 | 356.8 | 354.2 | 319.5 |
| `PageViewTests/typingCostLongNote` | 5.3 | 5.1 | 5.0 | - | 5.1 |
| `StylingPerformanceTests/fullPassCost` | 6.2 | 7.0 | 7.8 | 6.3 | 6.2 |
| `StylingPerformanceTests/parseCost` / `keystrokeCost` | 3.1 / 0.6 | 3.0 / 0.6 | - / 0.6 | 3.1 / 0.6 | 3.0 / 0.6 |
| `TextSizeCostTests/firstFrame` | 34.7 | 35.3 | 35.5 | 76.3 | 92.0 |

Run 1 followed this worktree's first (full) build. The `exclusionPathsAreTheCost`
rows are within 4% of their F5 base in runs 1 and 2. New rows with no base yet:
`NoteListFetchCost/everything` 45 to 47, `/live-only` 32 to 34, `/warmup` 51,
`PageViewTests/redrawCost` 35 to 40.

**What `--compare` flags.** `printingCost` (+12% to +29%), `openingCost.open`
(+27% in runs 2 and 3), `openingCost.switch` (+12% in run 3) and
`fullPassCost` (+13%, +26%). The control reads `printingCost` +8%,
`openingCost.open` +22% and `.switch` +11% on an idle Mac, so the base is not
met by the commit it was taken from either.

**Why: the Perf plan runs the cost tests cold.** §3 was taken by the old
`perf.sh`, which ran whole suites, so each cost test ran after its suite's
other tests; the Perf plan (T3) runs only the `.perf` ones. The three suites
run alone, as whole suites, the same way on both commits, back to back (ms):

| Test | `main` (Full plan) | | `8767927` | | `main` (Perf plan) | |
|---|---|---|---|---|---|---|
| `NotePDFTests/printingCost` | 883.9 | 993.7 | 995.9 | 876.8 | 1,625.7 | 1,740.6 |
| `PageViewTests/openingCost.open` | 151.8 | 151.9 | 151.8 | 152.5 | 211.3 | 214.2 |
| `PageViewTests/openingCost.switch` | 289.2 | 291.3 | 311.0 | 308.4 | 377.9 | 387.3 |
| `StylingPerformanceTests/fullPassCost` | 6.0 | 5.9 | 6.3 | 6.3 | 10.3 | 14.5 |

Running the same tests, `main` matches `8767927` (printing within the two
commits' own spread, opening equal, a switch 6% faster, a full pass 5%
faster). The same tests in the Perf plan alone are 30% to 145% slower, on the
same build. **No regression is shown.** The keystroke, caret-move and
first-frame gains (F5, 2T1, the 4A fix) hold in every run. Release QA item 1
("nothing more than 10% worse") is met when like is compared with like on an
idle Mac, not by `perf.sh`'s own output; the rows above 10% are the plan's
warm-up, not the code. Left as is: the `PERF` lines still read as a whole-suite run, so
`perf.sh --compare` flags these four rows on every machine until the plan
warms up or the base is retaken with it.
(Retaken with the plan the same day; see the next section.)

### The base retaken with the Perf plan (11 Nov 2026, `main` b18d33b)

Follow-up to D8: §3's `PERF` lines are now taken the way `perf.sh --compare`
runs, with the Perf test plan (only the `.perf` tests, cold), instead of whole
suites. Same Mac and setup as D8 (a fresh "NoteCode Lane Perf" simulator,
iPad Pro 13-inch (M5), iOS 27.0). Before each run: no other xcodebuild or
simulator process, 1-minute load average under 3 (1.8 to 2.9 at each start), 60 GB+ disk
and 25%+ memory free. `perf.sh --compare` three times (runs 1 to 3); §3's
lines are each row's median of those three. Then three more `--compare`
runs against the new lines (4 to 6; before run 6 also waited for every
process to be under 30% CPU). ms:

| Test | 1 | 2 | 3 | Base (median) | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| `CodeFenceCostTests/caretMoveCost.keystroke` | 7.9 | 7.9 | 7.2 | 7.9 | 7.5 | 7.3 | 7.7 |
| `LineNumbersTests/keystrokeCost.on` / `.off` | 8.2 / 7.8 | 7.4 / 7.6 | 7.0 / 6.7 | 7.4 / 7.6 | 7.3 / 6.9 | 6.7 / 6.6 | 7.5 / 6.9 |
| `MarkdownLayoutCostTests/typingCost.rendered` | 9.3 | 9.3 | 8.3 | 9.3 | 9.2 | 8.5 | 8.2 |
| `NoteListFetchCost/everything` | 46.4 | 55.8 | 43.6 | 46.4 | 44.0 | 45.5 | **58.1** |
| `NoteListFetchCost/live-only` | 31.3 | 34.8 | 30.6 | 31.3 | 31.9 | 31.9 | **44.3** |
| `NoteListFetchCost/warmup` | 53.3 | 62.7 | 45.9 | 53.3 | **69.5** | 48.7 | **80.6** |
| `NotePDFTests/printingCost` | 1,067.3 | 1,070.7 | 1,039.7 | 1,067.3 | **1,402.0** | 963.7 | **1,482.3** |
| `PageViewTests/exclusionPathsAreTheCost.with` | 105.4 | 109.4 | 102.6 | 105.4 | 111.0 | 103.4 | **117.0** |
| `PageViewTests/openingCost.open` | 191.9 | 200.2 | 180.7 | 191.9 | 202.3 | **267.3** | 195.3 |
| `PageViewTests/openingCost.switch` | 365.8 | 370.8 | 329.8 | 365.8 | 380.4 | **449.3** | 393.5 |
| `PageViewTests/redrawCost` | 40.7 | 40.7 | 40.3 | 40.7 | 41.7 | **48.2** | 40.8 |
| `PageViewTests/typingCostLongNote` | 5.2 | 5.5 | 4.6 | 5.2 | 5.7 | 5.0 | 4.8 |
| `StylingPerformanceTests/fullPassCost` | 6.6 | 6.3 | 6.2 | 6.3 | 6.3 | **15.1** | 6.6 |
| `StylingPerformanceTests/parseCost` | 3.4 | 3.1 | 3.1 | 3.1 | 2.9 | 3.0 | 5.8 |
| `TextSizeCostTests/firstFrame` | 42.3 | 37.2 | 56.5 | 42.3 | 42.6 | **50.6** | **57.5** |

Rows under 5 ms everywhere (the caret moves, `longBlockCost`, `.paged`,
`.without`, `keystrokeCost`, `cost.empty`) are left out; they are in §3.
Bold is more than 10% over the new base, which `--compare` flags.

**What changed.** The four rows D8 found flagged on every run (printing,
opening, a switch, a full pass) are now measured like with like: in runs
1 to 3 all four sit within 10% of their median. In runs 4 to 6 printing is
over twice, opening and a switch once (the same run) and a full pass once.

**What did not.** `perf.sh --compare` still exited 1 in all three of runs 4
to 6, each time on different rows, by 11% to 140%, on the same build and
with nothing else of ours running. Every flagged value is one run high
while the runs around it are at the base (printing 1,040 to 1,071 in five
runs, 1,402 and 1,482 in two). So one run of the cost tests on this Mac
varies by more than the 10% budget, and a single `--compare` run cannot
show "nothing more than 10% worse" by itself. After each run two
`ReportCrash` processes took 100% CPU each for a minute or more, which is
one likely source. Not changed here: `perf.sh`'s threshold, and how many times
a cost test measures before it reports.

## Findings (recorded, not fixed)

1. **A StoreKit test hung for 11.5 hours.** In the first unit run,
   `TipJarTests` › "The jar asks for the products the configuration sells,
   and a tip is thanked and finished" (a StoreKit test purchase) waited
   with no timeout until Marcus stopped the run; the 1,826 tests before it had
   passed. Rerun alone with a 120 s allowance, all 7 passed in 6 s, so it
   is intermittent. Environment: Xcode 27.2, iOS 27.2 simulator (iPad Pro
   13-inch M5); no simulator log was kept from the hung run. Its own fix PR:
   a timeout in the test and a cause. **(Found and guarded in D10, #261:** the first
   StoreKit test process on a fresh simulator buys from the real App Store,
   which waits on an Apple ID sign-in alert.)
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
