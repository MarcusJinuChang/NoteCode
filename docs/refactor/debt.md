# Debt register (6 Nov 2026, `main` 5769d87)

What the refactor left, found by the Release QA 4B audit: a fresh read of
`main` against [update-2.md](update-2.md) › Release QA. Each row has a size
(S under an hour, M a PR, L a plan), what it costs if left, and the first
step. Nothing here blocks 1.2.0.

## Audit result

| Check | Result |
|---|---|
| Seam (`check-seam.sh`) | 0 files; the baseline's `SEAM 0` |
| Traps (`lint-traps.sh`) | clean (rule 7: 1 of 1, rule 9: 49 of 49); the three allowed hits in `lint-allow.txt` still read as written |
| Core tests (`core-test.sh`) | 263 tests in 31 suites pass |
| Fast plan (`check.sh`) | CHECK OK: 2,040 tests, 2,039 passed (1 expected failure), 0 failed; macOS build fails as expected |
| Warnings | 2, both the compiler's, listed in baseline.md |
| Files over 600 lines | 12 (below); no app file is over 850 |

## Files over 600 lines

Tests are listed after the app. The budget (lessons.md 4) is a question at
400 and a reason past 600.

| File | Lines | Reason, or follow-up |
|---|---|---|
| `Text/Editor/DocumentStyler.swift` | 845 | Follow-up D1. One `applyStyling` per block kind (2T8a) plus colour helpers; the colour half is a separate type |
| `NotePage/PageView.swift` | 740 | Reason: it is the one `UIScrollView` that owns the layers, and 2P1-2P3 took out the ink pipeline, scroll indicator, zoom, keyboard inset, bands and reading (seven host protocols). What is left is gestures, layout application and the layer hand-off, which share state. 1,611 lines at 4 Nov |
| `NotePage/NoteEditor.swift` | 728 | Follow-up D2. Down from 1,386; the controllers took the typing style, typography, selection size and undo. The remainder is feature plumbing and the settings it observes |
| `Text/Core/InlineParser.swift` | 639 | Reason: one tokenizer and one delimiter resolver, pure, pinned by a snapshot (2T8b). Splitting it would put a seam through the resolver's shared state |
| `Pro/Run/RunPanel.swift` | 610 | Follow-up D4. Six views in one file (panel, dock, toggle, top-bar item, side panel, host); a file per view is a pure move |
| `Text/Core/DocumentNode.swift` | 606 | Reason: the node types and their ranges, 6 lines over; no split is worth the churn |
| `NoteCodeTests/NotePage/PageViewTests.swift` | 1,972 | Follow-up D5. It tests the type that was 1,611 lines; split by the PageView pieces (ink, zoom, bands, reading) |
| `NoteCodeTests/Text/Core/MarkdownLayoutTests.swift` | 697 | Reason: one suite per layout rule; a split would be by rule |
| `NoteCodeTests/InOut/NoteInterchangeTests.swift` | 673 | Reason: import and export cases that share fixtures |
| `NoteCodeTests/Text/Core/TypingStyleTests.swift` | 641 | Reason: parameterised cases |
| `NoteCodeTests/Text/Core/SpanSizeTests.swift` | 608 | Reason: parameterised cases |

## Debt

| # | Debt | Size | Cost if left | First step |
|---|---|---|---|---|
| D1 | `DocumentStyler.swift` 845 lines (above) | M | The largest app file; a styling change reads both halves | Move the colour helpers (`codeColors` :494, `inheritedCodeColor` :790, `TextColourCache` :833) to `DocumentStyler+Colour.swift`, as a pure move with `verify-move.sh` |
| D2 | `NoteEditor.swift` 728 lines | M | The editor is still the one place features, settings and controllers meet | Ask whether the feature plumbing (`EditorServices`, the installed features) is a type of its own |
| D3 | ~~`NoteList.swift` 613 lines~~ **Done (PR #PRNUM)**: 583 lines; the Empty states went to `NoteListEmptyStates.swift` as a pure move (the Menus section reads about eleven private members) | S | — | — |
| D4 | `RunPanel.swift` 610 lines, six views | S | Pro-only; 10 over | One file per view (`RunDock`, `NotesRunToggle`, `RunTopBarItem`, `RunSidePanel`, `RunPanelHost`) |
| D5 | `PageViewTests.swift` 1,972 lines | M | Slow to navigate; a failure names a 2,000-line file | Split by the PageView piece it tests |
| D6 | **Old settings names still forward.** 29 `static let …Key = SettingKeys.…` lines in 19 files (for example `CodeIndent.widthKey`). SettingKeys.swift's header says they go in the last of 2S2b-2S2d | M | A new setting can be declared two ways, which is the drift 2S2 was to end | Move each caller to the `SettingKey`, delete the forwarder; `SettingKeysTests` keep the names |
| D7 | **The docs system is not on `main`.** AGENTS.md links `docs/README.md`, `docs/NOW.md`, `docs/process.md` and `docs/plans/`; none is on `origin/main`. They exist only on the branch `docs/process-and-retrospective` (commit 09af6d1) | S | The three links in AGENTS.md are dead for anyone cloning `main`, including the public repo | Marcus: merge that branch, or say it should stay private (then drop the links) |
| D8 | **Release QA 4A's perf is not met in absolute terms.** On a loaded Mac a control run of the baseline commit reads 18% to 56% worse than its own base | S, a Mac | "Nothing more than 10% worse" is shown only by the control, not by a run | Run `perf.sh --compare docs/refactor/baseline.md` on an idle Mac and record it in baseline.md |
| D9 | **Typing in a 40-page note costs about 97ms** (F5): the pages' exclusion paths are the cost and no safe fix was found | L | A long paged note types slower than a short one | A design note: fewer exclusion paths, or one per page region |
| D10 | **A StoreKit test hung 11.5 hours** (baseline.md finding 1): `TipJarTests` waited with no timeout and the 120 s allowance did not end it. Intermittent | S | An overnight `check.sh --full` can stall on it | Read the hung run's log if it recurs; guard the purchase with a timeout inside the test |
| D11 | **Four UI tests are skipped** (T9) and the hotbar gap tests were fixed or skipped | M | The UI plan checks less than it appears to | Un-skip each when the simulator can run it |
| D12 | **Test sleeps: 49** (lint rule 9's ratchet, from 59) and one `UserDefaults.standard` in tests (rule 7) | M | Sleeps are the flaky tests | Replace with `ManualClock` or a settled hook, lowering the ratchet each time |
| D13 | **Closure coupling that the seam script cannot see.** `check-seam.sh` counts names. Behaviour that reaches Pro through closures and settings (for example the editor's feature hooks) is checked by review | S | A second path to Pro can appear without the count moving | A test that builds the open-source edition and exercises Run and Explain (already: `OpenSourceEditionTests`); review new `AppExtensions` members |
| D14 | **The macOS build fails**: the ad SDKs have no macOS slice, so `check.sh`'s macOS step fails and is not counted. The editor on a Mac is a plain `TextEditor` | L | Nothing detects a macOS-only break | Decide whether macOS is a target for 1.x; if so, build it from the open-source edition |
| D15 | **Two compiler warnings are kept** (baseline.md): the deprecated adaptive banner (AdBanner.swift:61) and `UIWindow(frame:)` in `TestWindow` | S | The ratchet is 2, not 0 | The banner's, if Marcus ever accepts the larger banner; the test window's, when the tests can have a scene |
| D16 | **Nothing here is checked on a device.** The device lines from every refactor PR, `ipad-test-checklist.md` and a TestFlight sandbox pass are owed (Release QA 3) | L, Marcus | Behaviour a test cannot see (touch, Pencil, drag and drop, feel) | The one device pass on the release build |
| D17 | Public-repo prerequisites in `split.md` (S1 the pages move, S2 editions in the project, build-number reproducibility 0F) are not started | L | The open-source build is proved by script only; the project has no target for it | After 1.2.0 ships, as split.md says |
| D18 | **`WindowActions` is a focused value made of closures** (ContentView.swift:191), rebuilt on every build: the pattern that froze sheets over a note on iPhone (`OpenNote`, PR #234). It sits in the root hosting view only and Home showed no hang | S | A sheet over Home could spin the same way if a second hosting view starts building it | If it ever shows, give it `OpenNote`'s shape: references and plain values, the closures in a box kept in `@State` |

## Not debt

Recorded so a later audit does not raise them again:

- `PageView` at 740 lines: a reason, above.
- `DocumentUITextView`'s stored properties are Optional because its
  initialiser skips initialisers; a test covers it (T8).
- `Page.paperStyle` and `runDestination` stay in the model, unused, until a
  version 2 (the model is frozen).
