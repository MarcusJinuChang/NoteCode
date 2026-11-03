# Update 2 (1.2.0): seams and types

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. This file holds Update 2's design and its
steps in outline. When 1.1.1 has shipped, a planning session expands each
step into a brief here (Do, Done when, Read) against the code as it is then.
Its line numbers are from 2 Nov.

**Order.** 2X comes first: it rewrites the files every later track touches
(NoteEditor, DocumentTextView, PageDetailView, CodeFenceDisplay). 2S2 comes
next. Then 2T and 2P run alongside each other, since their files are
different. 2C and 2W come last. T5 (characterisation tests) comes before
each 2T and 2P step that touches untested code. Every step that rewrites one
of those four files is **two commits**: a pure move of the sections it
touches into their own files (`verify-move.sh`), then the change.

## 2X. The extension seam

**Why.** Pro, ads, tips, Run in the app and the AI features are wired into
general types:
- `NoteEditor` stores the `RunSession`, `pro` and the assistant
  (NoteEditor.swift:215–252).
- PageDetailView gates Run and AI.
- `AdConsent.shared` and `AIAssistant.system()` are hard-wired.

After 2X, general code never names a type in `Pro/`, so the public build is
`NoteCode/` minus `Pro/`. Adding or removing a feature becomes a registration.

### Design (decided 2 Nov)

- **`AppExtensions`** holds what an edition adds:
  - the Home footer and the list foot's rows;
  - the Settings sections and the note's side panel;
  - top-bar items;
  - the Welcome note and screen's lines about Run;
  - debug launch options;
  - the editor features.

  `.none` is the default and adds nothing.
- **It is passed in, not only read from the environment.** The edition
  builds it, and it reaches these by an init argument or a factory:
  - `NoteCodeScene(extensions:)`
  - `NoteEditor(features:)`
  - the Coordinator
  - the scene's `.commands`
  - `DebugLaunch.parse(registry:)`

  None of those can read the SwiftUI environment. Views read it from the
  environment. Tests' plain `NoteEditor()` keeps working, because it gets
  `.none`.
- **`EditorFeature`** is a per-note object made from the editor, such as
  `RunFeature` or `AssistantFeature`.
  - It contributes `EditorAction`s: id, title, symbol, placement (the
    code-block menu, the text options row, the title menu, a key command),
    when it is available, and what it does.
  - The menus, the options row and ⌘R render whatever is registered, in
    today's order.
- **Run on the block bar stays general.** By default it opens a compiler
  site (`CodeDestination`), which is what the public build does.
  `RunFeature` replaces that with Run in the app or the paywall.
- **Editions.**
  - The shared bootstrap in `NoteCodeApp.swift` (about 60 lines) moves into
    a general `NoteCodeScene(extensions:)`. That covers the device name,
    `TextInputActivity`, DEBUG seeding, `StorageUnavailableView`,
    appearance and the commands.
  - Each edition is then about ten lines and keeps the name `NoteCodeApp`:
    - `NoteCode/Pro/AppStoreEdition.swift` builds `.appStore`.
    - `OpenSource/OpenSourceEdition.swift`, at the repo root and not
      compiled until the split, builds `.none`.
- **The seam ratchet.** `scripts/check-seam.sh` lands in 2X1 and is
  enforced as a ratchet from then on. It counts the files outside any
  `Pro/` folder that name a type declared in `Pro/`, in `NoteCode/`,
  `NoteCodeTests/` and `NoteCodeUITests/`. The count may only fall, and it
  reaches 0 in 2X7.

### Must not change

- **Launch:**
  - the unnamed `WindowGroup`;
  - the launch order of `ProStatus.shared.start()` and
    `TipJar.shared.start()`;
  - `AdConsent.homeAppeared` stays on Home (HomeView.swift:108), not on a
    footer view that a Pro reader never sees.
- **Order and layout:**
  - the list foot's row order and the `tipJarRow` identifier;
  - the edit menu's order, which `KeyboardAndMenuTests` asserts;
  - the Explain chip's `along: 58` width in the options row.
- **Debug options.** `DebugLaunchOptions.current` is read lazily, by
  ProStatus.swift:80, TipJar.swift:69 and RunSession.swift:313. If the Pro
  options are registered after that first read, `-debug-pro` silently
  becomes an unknown argument, so the registry has to reach `parse`.

### Steps

| ID | What |
|---|---|
| 2X1 | `AppExtensions`, `EditorFeature`, `EditorAction`, `NoteCodeScene` and the two edition files. Register today's behaviour through them, with nothing visible changing. Add `check-seam.sh` and record its starting count |
| 2X2 | One `ProGate` (whether the reader has Pro; show the paywall for a reason). The five places that present the paywall go through it: AdBanner.swift:48, ProSettings.swift:38, RunPanel.swift:539, PageDetailView.swift:263 and the debug paywall |
| 2X3 | Ads and tips through the slots: `ListFoot`'s ad and tip rows, Home's ad strip, NoteList's tip jar sheet, Settings' Ad Privacy Options row. `AdConsent` is created by the edition |
| 2X4a | The assistant's actions: Explain Block (DocumentTextView.swift:804), Summarise Note (PageDetailView.swift:519) and the Explain chip (TextOptionsRow.swift:355) become `AssistantFeature`'s actions. `ai`, `explain`, `summariseNote` and `insertAnswer` leave `NoteEditor` |
| 2X4b | The assistant's settings section (SettingsView.swift:494, 526–551) becomes a slot, and the result sheet and its state leave PageDetailView |
| 2X5a | `RunRoute`, `KeepInNote` and `AppInfo.runService` move to `Pro/Run`. `RunRoute` takes `isPro`, and `KeepInNote` takes a `RunResult`, so they can't stay general |
| 2X5b | `RunFeature` hooks: the block bar's Run, ⌘R (NoteCommands.swift:247) and `CodeFenceDisplay`'s `run.*` wiring (:30–98) |
| 2X5c | The Notes \| Run switch and its PRO mark, `RunDock` and `RunPanelHost` (PageDetailView.swift:248, 364–410) through the side-panel slot |
| 2X5d | `RunWiringTests`, `RunSessionTests` and `CodeRunnerTests` move to `NoteCodeTests/Pro/`. `CodeDestinationTests` stays general |
| 2X6 | DebugLaunch: `-debug-pro`, `-debug-paywall`, `-debug-run-stub` and `-debug-tip-jar` are registered from `Pro/Debug` and passed to `parse`. `DebugProStore`, `DebugRunStub` and `DebugTipStore` move out of ProStatus, RunSession and TipJar. The Pro lines in WelcomeNote.swift:93 and WelcomeScreen.swift:51 come from the edition, and the public build says the Run button opens a compiler site |
| 2X7 | **`scripts/build-open-source.sh`** proves the public build compiles, with no project edit. It works in a temporary worktree: delete `NoteCode/Pro/` and `NoteCodeTests/Pro/`, then lay over `OpenSource/OpenSourceEdition.swift`, `OpenSource/Info.plist` and `OpenSource/PrivacyInfo.xcprivacy`, then build and run the unit tests. The public `Info.plist` drops `GADApplicationIdentifier`, `SKAdNetworkItems` and `NSUserTrackingUsageDescription`, and keeps `UTExportedTypeDeclarations`, `ITSAppUsesNonExemptEncryption` and the scene manifest. The public privacy manifest has no tracking and keeps the CA92.1 UserDefaults reason. `AppStoreReadinessTests` is split: the tracking and privacy-policy-page assertions go to `NoteCodeTests/Pro/`. The seam count is 0. `check.sh` runs both scripts |

## 2S2. Settings in one place (after 2X; four PRs)

The ~65 `@AppStorage` declarations repeat keys and defaults across 11
files. PageDetailView (:72–144) and SettingsView (:278–569) both declare
the same 14. 2S1 pinned every key and default, so this can't rename one.

- **2S2a. Key tables.** One per feature, each with keys and defaults, plus
  an `@AppStorage` convenience init that takes a table entry. The general
  table is in `Settings/`. The Pro keys (`ai*`, `adHomeVisits`,
  `runPanelWidth`, `runDisclosureAccepted`) live in `Pro/`.
- **2S2b. `NoteViewSettings: DynamicProperty`** replaces PageDetailView's
  16 `@AppStorage`s. Two commits.
- **2S2c. SettingsView reads the tables.**
- **2S2d. `EditorSettings`** with `apply(to:)` replaces the ten or so loose
  settings `DocumentTextView` takes. This follows the AGENTS.md convention,
  as `TextRewritingPolicy` does.

## 2T. The text system (one step at a time)

- **2T1. One `DocumentSnapshot` per edit (four PRs; perf at each).**
  - **Why.** Today a keystroke makes up to five whole-document copies
    (`nativeUTF8` at DocumentTextView.swift:463, 472, 583 and 878, and
    CodeSelectionHighlight.swift:63), each compared by string. It also
    makes four UTF-16 passes: `layouts` twice, `CodeBlockAction.targets`
    and `DocumentCache.codeRanges`. `codeRanges` converts each block with
    `NSRange(_:in:)`, so its cost is blocks × offset.
  - **What.** An immutable snapshot keyed by `editCount`: one source, one
    parse, and the blocks and code ranges worked out once.
  - **The PRs.**
    1. The type.
    2. The styler and the fragment cache use it.
    3. The Coordinator's callers use it.
    4. The old caches go: `layoutCodeRanges`, `cachedCodeRanges` and the
       extra block lists.
- **2T2–2T6. Types out of the Coordinator.**
  - Each has a forwarding facade, since about 34 test files drive the
    Coordinator (`restyle` 27 times, `setRendersMarkdown` 28,
    `textViewDidChangeSelection` 20).
  - Each is two commits.
  - **The steps:**
    - **2T2.** `TextStyleSession`: the document cache, style signatures,
      typography and marker dimming. `NotePDF` (:272) then uses it instead
      of building a whole Coordinator.
    - **2T3.** `SyntaxColouring` (:311–372, 609–705).
    - **2T4.** `EditRouter` with `CaretTracker`. The five re-entrancy flags
      (`isFormatting`, `isApplyingMarkerEdit`, `isRetagging`,
      `isNormalizingCaret`, `isWritingTypedText`, used 32 times over three
      files) go in one place.
    - **2T5.** `KeyboardPolicyController` with `FenceDisplayController`.
      The action bars stay placed from the viewport.
    - **2T6.** `CodeBlockCommands`. A `TextCommandTarget` protocol replaces
      the editor's closure slots (`runBlockAtCaret`, `copyBlockAtCaret` and
      the rest) and the twenty copies of the weak-capture preamble.
- **2T7. `NoteEditor` splits** into these, and stays the `@Observable`
  facade:
  - `EditorModeState`
  - `TypingStyleController`
  - `SelectionSizeController`
  - `NoteTypographyController`
  - `UndoRouter`, which owns the 14 hand calls to `refreshUndoState()`

  The pure size helpers (:1028–1133) move to `Text/Core`.
- **2T8. Long functions (three PRs):**
  - `DocumentStyler.applyStyling` (141 lines) becomes one function per
    block kind.
  - `InlineParser.collect` (137) becomes one tokenizer per case and a
    delimiter resolver.
  - `DocumentParser.parse` (85) becomes a fence scanner and a math scanner.
- **2T9. One helper per repeated piece of logic, tests first.**
  - `CodeBlock.tag` replaces the seven copies of
    `infoString.split(separator: " ").first`.
  - One newline constant replaces eight `0x0A` and `10` literals.
  - A code-range `contains` replaces about twenty hand-written checks.
  - One `TextEditExecutor` replaces the seven position-to-`textRange`
    conversions.
  - "Block at offset" (six versions) is unified only where the
    end-of-document rule is identical.

## 2P. Page, ink and shell (alongside 2T)

- **2P1. `PageInkPipeline` out of `PageView` (three PRs; perf; Marcus
  checks with the Pencil after each).** This is the most trap-heavy work in
  the plan. AGENTS.md's ink lines all apply, and `openingCost` and
  `printingCost` must hold.
  1. The static `InkMarkupTransforms` (`frames`, `convert`,
     `withoutOverflow`).
  2. The state and its generation: `inkState`, `newestSnapshot`,
     `snapshotSerial`, `isCapturing`, `inkGeneration`, `inkBottom`.
  3. `showInk`, `captureInk` and `commitInk`.
- **2P2.** `PageScrollIndicator` (:1500–1571), `PageKeyboardInset`
  (:309–453) and zoom.
- **2P3. PageDetailView** becomes `NoteHeader`, `NoteMoreMenu`,
  `PencilGestureRouter` and `PageBadgeModel`. `@State NoteEditor()` and
  `DrawingSaveScheduler` (:51, :202) stop being allocated on every `init`.
- **2P4. ContentView.**
  - `NavigationModel` (`@Observable`) and `LaunchCoordinator` take over.
  - One `NoteActions` handles create and delete with Undo. NoteList uses it
    too, which removes the duplicate copy.
  - One layout-class value replaces the four ways "compact" is worked out.
  - **Leave the split view's `.balanced`/`.prominentDetail` `if/else`
    (:215–226) exactly as it is.** It depends on view identity.
- **2P5. One `InkToolStore`** replaces the five copies of pen, highlighter,
  eraser and finger settings:
  - `NoteEditor.inkTool`
  - `InkToolPersistence`
  - `InkSwatches`
  - `DrawingSettings`
  - `SelectionOptions`

  Marcus checks it on the iPad.
- **2P6. Persistence.**
  - `Storage.save(_:reason:)` logs a failed save (`os.Logger`) in place of
    16 `try?`s.
  - `Page.settledID`, a getter that saves, becomes a method.
  - The model's extensions move out of the frozen class files. Extensions
    don't change the hashes, and `ModelFreezeTests` proves it.

## 2C and 2W

- **2C. The rest of the pure core** moves into `Text/Core`:
  - `MarkdownLayout`'s planning half (`Run`, `runs`, `displayRuns`,
    `formulaRun`, `listRuns`)
  - `CodeBlockPosition`
  - `HeadingMarkerVisibility`
  - `ProseLine`
  - `CaretHeight`

  The whole-file `#if canImport(UIKit)` comes off files that are truly pure.
- **2W. Fix the warnings** counted in 0D, down to zero, with the
  `check.sh` ratchet. Don't use a command-line warnings-as-errors flag: it
  would hit the packages too.

## Release QA for 1.2.0

1. **An agent:**
   - `check.sh --full` passes.
   - `perf.sh --compare`: nothing more than 10% worse, and the gains are
     recorded.
   - `build-open-source.sh` passes, and the warning count is 0.
2. **A fresh reviewer session audits the architecture:**
   - The seam count is 0, and the traps are intact.
   - No file is over 600 lines without a reason.
   - AGENTS.md is rewritten for the new layout: the folder map, how a
     feature plugs in, and the scripts. `features.md` is current.
   - A debt register for what is left (`engineering:tech-debt`).
3. **Marcus:** the device lines from every PR, and a TestFlight sandbox pass.
4. **Marcus:** the build number, archive and submit.
