# Debt register (6 Nov 2026, `main` 5769d87)

What the refactor left, found by the Release QA 4B audit: a fresh read of
`main` against [update-2.md](update-2.md) › Release QA. Each row has a size
(S under an hour, M a PR, L a plan), what it costs if left, and the first
step. Nothing here blocks 1.2.0.

## Audit result

| Check | Result |
|---|---|
| Seam (`check-seam.sh`) | 0 files; the baseline's `SEAM 0` |
| Traps (`lint-traps.sh`) | clean (rule 7: 1 of 1, rule 9: 36 of 36); the three allowed hits in `lint-allow.txt` still read as written |
| Core tests (`core-test.sh`) | 263 tests in 31 suites pass |
| Fast plan (`check.sh`) | CHECK OK: 2,040 tests, 2,039 passed (1 expected failure), 0 failed; macOS build fails as expected |
| Warnings | 2, both the compiler's, listed in baseline.md |
| Files over 600 lines | 11 (below); no app file is over 850 |

## Files over 600 lines

Tests are listed after the app. The budget (lessons.md 4) is a question at
400 and a reason past 600.

| File | Lines | Reason, or follow-up |
|---|---|---|
| `Text/Editor/DocumentStyler.swift` | 660 | D1 done (#255): the colour half moved to `DocumentStyler+Colour.swift`. What is left is one `applyStyling` per block kind (2T8a), fonts and typing attributes |
| `NotePage/PageView.swift` | 740 | Reason: it is the one `UIScrollView` that owns the layers, and 2P1-2P3 took out the ink pipeline, scroll indicator, zoom, keyboard inset, bands and reading (seven host protocols). What is left is gestures, layout application and the layer hand-off, which share state. 1,611 lines at 4 Nov |
| `NotePage/NoteEditor.swift` | 728 | Follow-up D2. Down from 1,386; the controllers took the typing style, typography, selection size and undo. The remainder is text commands (about 220 lines), requests to the page (130, about 90 of them movable), forwarders (150) and the feature plumbing (55); see [d2-note-editor.md](d2-note-editor.md) |
| `Text/Core/InlineParser.swift` | 639 | Reason: one tokenizer and one delimiter resolver, pure, pinned by a snapshot (2T8b). Splitting it would put a seam through the resolver's shared state |
| `Text/Core/DocumentNode.swift` | 606 | Reason: the node types and their ranges, 6 lines over; no split is worth the churn |
| `NoteCodeTests/Text/Core/MarkdownLayoutTests.swift` | 697 | Reason: one suite per layout rule; a split would be by rule |
| `NoteCodeTests/InOut/NoteInterchangeTests.swift` | 673 | Reason: import and export cases that share fixtures |
| `NoteCodeTests/Text/Core/TypingStyleTests.swift` | 641 | Reason: parameterised cases |
| `NoteCodeTests/Text/Core/SpanSizeTests.swift` | 608 | Reason: parameterised cases |

## Debt

| # | Debt | Size | Cost if left | First step |
|---|---|---|---|---|
| D1 | ~~`DocumentStyler.swift` 845 lines (above)~~ **Done, #255** | M | The largest app file; a styling change reads both halves | Moved the colour helpers (`codeColors`, `inheritedCodeColor`, `TextColourCache`, and `applyColors`, `syntaxFont`, `syntaxAttributes`, `textColour`, `highlightColour`) to `DocumentStyler+Colour.swift` as a pure move; 660 lines left |
| D2 | `NoteEditor.swift` 728 lines | M | The editor is still the one place features, settings and controllers meet | **Done, #253 ([d2-note-editor.md](d2-note-editor.md)):** no. The plumbing is about 55 lines and features are made from the whole editor. Instead, two pure moves into `NoteEditor+Formatting.swift` and `NoteEditor+Page.swift` take it to about 440 lines; no access changes. Not needed before the split |
| D3 | ~~`NoteList.swift` 613 lines~~ **Done (PR #254)**: 583 lines; the Empty states went to `NoteListEmptyStates.swift` as a pure move (the Menus section reads about eleven private members) | S | — | — |
| D4 | ~~`RunPanel.swift` 610 lines, six views~~ **Done (PR #257)**: 383 lines; `RunDock` (with `RunDockWidth`), `NotesRunToggle`, `RunTopBarItem`, `RunSidePanel` and `RunPanelHost` each went to their own file in `Pro/Run/` as a pure move, no access changes. The panel's private output, input and chip views stay with it | S | — | — |
| D5 | ~~`PageViewTests.swift` 1,972 lines~~ **Done (PR #259)**: ten suites nested in `PageViewTests` (`Keyboard`, `Scale`, `Pages`, `Ink`, `InkBreaks`, `Bands`, `Canvas`, `Cost`, `Window`, `AddPage`), one file each, the largest 411 lines (`PageViewTests+InkBreaks.swift`). Helpers two suites use are `PageViewSuite`'s, in `PageViewTests.swift`; the rest stay private to their suite. Every test kept with its name and tags: 101 `@Test`s, 97 in the Fast plan (151 runs) before and after | M | — | — |
| D6 | ~~**Old settings names still forward.** 29 `static let …Key = SettingKeys.…` lines in 19 files (for example `CodeIndent.widthKey`)~~ **Done, #258** | M | — | Every name forwarder (31) and its paired default forwarder deleted; callers name the `SettingKey`. `SnapHaptic` and `LineNumbers` went with them. The owners' `default`/`standard` values stay as domain values, checked against the table by `SettingKeysTests` |
| D7 | **The docs system is not on `main`.** AGENTS.md links `docs/README.md`, `docs/NOW.md`, `docs/process.md` and `docs/plans/`; none is on `origin/main`. They exist only on the branch `docs/process-and-retrospective` (commit 09af6d1) | S | The three links in AGENTS.md are dead for anyone cloning `main`, including the public repo | Marcus: merge that branch, or say it should stay private (then drop the links) |
| D8 | **Release QA 4A's perf is not met in absolute terms.** On a loaded Mac a control run of the baseline commit reads 18% to 56% worse than its own base | S, a Mac | "Nothing more than 10% worse" is shown only by the control, not by a run | Run `perf.sh --compare docs/refactor/baseline.md` on an idle Mac and record it in baseline.md |
| D9 | **Typing in a 40-page note costs about 97ms** (F5): the pages' exclusion paths are the cost and no safe fix was found | L | A long paged note types slower than a short one | A design note: fewer exclusion paths, or one per page region |
| D10 | ~~**A StoreKit test hung 11.5 hours** (baseline.md finding 1)~~ **Done, #261**: the cause is a fresh simulator. On one never used for a StoreKit test session (just made or erased), the first test process's purchases go to the real App Store, whose daemon waits on a "Sign in to Apple Account" alert nobody answers; StoreKit's calls take no timeout and ignore cancellation. Every later process on that simulator passes in under half a second, reboots included, so overnight runs that made their own simulator hit it most. Seen in the 6 Nov spindump (appstored in AuthKit's login UI) and reproduced 8 Nov by erasing a simulator, 3 of 3. Each StoreKit call in `TipJarTests` now has a 20 s deadline, so a fresh simulator fails those three tests in about a minute with the reason, instead of the 120 s allowance or forever | S | A first run on a new simulator still fails the three StoreKit tests (in about 60 s, saying why); the second passes | If wanted: warm a new simulator in `check.sh` by running `TipJarTests` once before the plan, or create simulators by cloning a used one |
| D11 | **Four UI tests are skipped** (T9) and the hotbar gap tests were fixed or skipped | M | The UI plan checks less than it appears to | Un-skip each when the simulator can run it |
| D12 | ~~**Test sleeps: 49** (lint rule 9's ratchet, from 59) and one `UserDefaults.standard` in tests (rule 7)~~ **Partly done, #260**: rule 7 at 1 (it now counts `UserDefaults()` as well; the one is TestSupportTests reading the app domain), rule 9 at 36; the suites whose waits are now unbounded awaits carry `.timeLimit(.minutes(1))`, so a hang fails in a minute (D10) | M | Sleeps are the flaky tests | Converted 13: the toast's stay (`ManualClock`), Export All's and the assistant's runs (a `settled()` on `NoteExportJob` and `AIAssistant`, as `ToastCenter` has), the Run gate and the hanging stub request (awaited hooks in the test doubles), and four waits after notification posts, which observers on `.main` receive inside `post`. Left, with no hook of ours to await: run-loop turns that close an undo group (`EditorHarness.nextTap`, `StyledLineTests`, `RunWiringTests`), SwiftUI and UIKit layout spins (Settings, FingerDraws, CompactLayout, NoteTopBar, HotbarLayout, TextRewritingPolicy, HotbarIconPixel, `AdTests`), PaperKit (`RenderingSnapshotTests`, `InkSelectionTests`), StoreKit (`TipJarTests`, `ProStatusTests`), simulated latency in test doubles, the polling helpers (`waitFor`, `PageSettlingTests`, `AIFeaturesTests.wait`), the leak tests' waits for deferred releases, `NoteSearchTests`' reveal and the export restart's wait for progress |
| D13 | **Closure coupling that the seam script cannot see.** `check-seam.sh` counts names. Behaviour that reaches Pro through closures and settings (for example the editor's feature hooks) is checked by review | S | A second path to Pro can appear without the count moving | A test that builds the open-source edition and exercises Run and Explain (already: `OpenSourceEditionTests`); review new `AppExtensions` members |
| D14 | **The macOS build fails**: the ad SDKs have no macOS slice. **Settled 8 Nov:** 1.2.0 shipped iOS-only (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, committed in #251). `check.sh` still tries a macOS build, since `-showdestinations` lists a Mac destination, and doesn't count it | S | A failing step that every run prints and ignores | Drop the step from `check.sh`, or match only a native macOS destination. A Mac editor is NOW.md's queue item 6, built from the open-source edition |
| D15 | **Two compiler warnings are kept** (baseline.md): the deprecated adaptive banner (AdBanner.swift:61) and `UIWindow(frame:)` in `TestWindow` | S | The ratchet is 2, not 0 | The banner's, if Marcus ever accepts the larger banner; the test window's, when the tests can have a scene |
| D16 | **Nothing here is checked on a device.** The device lines from every refactor PR, `ipad-test-checklist.md` and a TestFlight sandbox pass are owed (Release QA 3) | L, Marcus | Behaviour a test cannot see (touch, Pencil, drag and drop, feel) | The one device pass on the release build |
| D17 | Public-repo prerequisites in `split.md` (S1 the pages move, S2 editions in the project) are not started; 0F was done 8 Nov (#251) | L | The open-source build is proved by script only; the project has no target for it | After 1.2.0 ships, as split.md says |
| D18 | **`WindowActions` is a focused value made of closures** (ContentView.swift:191), rebuilt on every build: the pattern that froze sheets over a note on iPhone (`OpenNote`, PR #234). It sits in the root hosting view only and Home showed no hang | S | A sheet over Home could spin the same way if a second hosting view starts building it | If it ever shows, give it `OpenNote`'s shape: references and plain values, the closures in a box kept in `@State` |
| D19 | **The public export is not clean yet** (S3 step 1, PR #252). `scripts/export-public.sh` exports 523 files and finds: the team id, `com.marcus` bundle ids and the Google Mobile Ads package in the project and `Package.resolved`; the scheme's `Pro.xctestplan`; `com.marcus.NoteCode` in `debug-launch.sh` and two design notes; the product id and price in `features.md` and `decisions.md`; a local path in `docs/README.md`; 19 links to docs left out. No AdMob id, proxy URL or email address (the public support address is allowed). `docs/archive/feedback-plan.md` goes public and is to be read in S3.2 with the roadmap and timeline. gitleaks was not installed, so not run | M | The public repo cannot be made until it is 0 | S2 removes the project's hits; then rewrite the doc lines, and install gitleaks |

## Not debt

Recorded so a later audit does not raise them again:

- `PageView` at 740 lines: a reason, above.
- `DocumentUITextView`'s stored properties are Optional because its
  initialiser skips initialisers; a test covers it (T8).
- `Page.paperStyle` and `runDestination` stay in the model, unused, until a
  version 2 (the model is frozen).
