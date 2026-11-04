# 2X. The extension seam

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. The design and why are in
[update-2.md](update-2.md) › 2X; this file is the briefs. Line numbers were
checked on `main` at `07a5c34` (4 Nov); find the code by name if they have
moved.

**What "done" means for the whole stream.** No file outside a `Pro/` folder
names a type or a member that `NoteCode/Pro/` declares, so the public build
is `NoteCode/` minus `Pro/` plus one edition file, and it compiles (2X7).
Nothing a reader sees changes in the App Store build.

## Where the code is today

`scripts/check-seam.sh` doesn't exist yet. Counted by hand on 4 Nov the way
2X1's script will count (every top-level type and function declared under
`NoteCode/Pro/`, matched as a whole word in code outside any `Pro/` folder,
comments and string literals stripped), plus the editor's Pro members
(`editor.ai`, `.run`, `.pro`, `explain`, `summariseNote`, `insertAnswer`,
`runInApp`, `connectRun`, `onRunNeedsPro`, `explainBlockAtCaret`) and
`AppInfo.runService`: **14 files**. By type names alone it is 13, the
number `folders.md` › Seams and `feature-audit.md` › A1 give; the
fourteenth is TextOptionsRow, which reaches the assistant only through
`editor.ai`.

**What a name count can't see.** Pro behaviour reached through a closure
or a general-looking member names nothing in `Pro/`:
`explainBlockAtCaret` (TextOptionsRow.swift:356, set at
CodeFenceDisplay.swift:95), `runBlockAtCaret` (NoteCommands.swift:247, set
at CodeFenceDisplay.swift:72, leading to `RunRoute`), and
`AppInfo.runService` (AppSettings.swift:123, declared in general code and
read by Pro). The script counts these names too, and 2X4a and 2X5b remove
or re-point each one; 2X7's acceptance checks every one by name.

| File | Names | Removed by |
|---|---|---|
| `App/NoteCodeApp.swift` | `ProStatus` ×3, `TipJar` ×2, `PaywallView` | 2X1 (bootstrap), 2X6 (debug paywall) |
| `App/ContentView.swift` | `ProStatus` ×2, `AdConsent`, `ConsentGate` | 2X3 |
| `Library/HomeView.swift` | `ProStatus` ×2, `AdConsent`, `AdSlot` | 2X3 |
| `Library/ListFoot.swift` | `ProStatus` ×2, `AdConsent`, `AdSlot`, `adBannerShows`, `TipJar` | 2X3 |
| `Library/NoteList.swift` | `TipJar` ×2, `TipJarView` | 2X3 |
| `Settings/AboutSettings.swift` | `ProStatus` ×2, `AdConsent` | 2X3 |
| `Settings/SettingsView.swift` | `ProSettings` | 2X4b (the Settings slot) |
| `Settings/WritingSettings.swift` | `AIFeatureSettings` ×3, `AIAnswerLength` ×2, `AIInsertStyle` ×2, `AIAssistant` | 2X4b |
| `NotePage/NoteEditor.swift` | `AIAssistant`, `AIPrompts` ×2, `AIInsertion` ×2, `AIInsertStyle`, `ProStatus`, `RunSession`, `RunBlock` | 2X4a, 2X5b |
| `NotePage/PageDetailView.swift` | `AIFeatureSettings` ×5, `AIAction` ×2, `AIAnswerLength`, `AIInsertStyle`, `AIResultSheet`, `PaywallView`, `ProStatus` ×2, `NotesRunToggle`, `RunDock`, `RunPanelHost` | 2X4a, 2X4b, 2X5c |
| `NotePage/TextOptionsRow.swift` | `editor.ai` (:355) | 2X4a |
| `Text/Editor/DocumentTextView.swift` | `RunRoute`, `AIAction`, `editor.run`/`.pro`/`.ai` | 2X4a, 2X5b |
| `Code/CodeFenceDisplay.swift` | `KeepInNote` ×2, `editor.run` | 2X5b |
| `Debug/DebugLaunch.swift` | `DebugRunStubKind`, `RunDisclosure` | 2X6 |

No test outside `NoteCodeTests/Pro/` names a Pro type or member, and no UI
test does (grep, 4 Nov).

**Where the design no longer fits the code** (each brief says which smaller
change it takes):

- **1A already moved the files.** `RunRoute`, `KeepInNote` and
  `RunDisclosure` are in `Pro/Run/RunRouting.swift`, and `RunWiringTests`,
  `RunSessionTests` and `CodeRunnerTests` are in `NoteCodeTests/Pro/Run/`.
  What is left of 2X5a is moving `AppInfo.runService`, so it folds into 2X5b.
  2X5d has nothing left to do and is dropped.
- **1B5 split SettingsView.** The assistant's section is
  `WritingSettings.assistantSection` (WritingSettings.swift:55–77), the Pro
  row is SettingsView.swift:87–91, and the Ad Privacy Options row is
  AboutSettings.swift:47–50.
- **⌘R needs no change.** NoteCommands.swift:247 calls
  `editor?.runBlockAtCaret?()`, which CodeFenceDisplay.swift:72 points at
  `Coordinator.run`. Once `run` asks the feature, ⌘R follows.
- **Not everything the design lists needs the seam.** The scene's
  `.commands` (`SettingsCommands`, `NoteCommands`) name nothing in `Pro/`,
  and the Coordinator reaches the features through the editor it is
  connected to. Neither takes an `AppExtensions`.
- **Two Pro dependencies the design doesn't list.** The rating prompt waits
  for the tracking answer (`pro?.isPro == true || AdConsent.shared.trackingAnswered`,
  ContentView.swift:563), and `-debug-first-launch` clears `RunDisclosure.key`
  (DebugLaunch.swift:507–508). 2X3 and 2X6 take them.
- **`Summarise Note` is in the ••• menu** (PageDetailView.swift:519–524),
  not the title menu.

## Order

2X1 alone first. Then 2X2, 2X3 and A5 together (different files); 2X6
after A5. A5 (`feature-audit.md` › A5) is a pure move with its own PR:
DebugLaunch.swift becomes `DebugLaunchOptions.swift` (the options and
`parse`, untouched), `DebugStateReport.swift`, `DebugSeed.swift` and
`DebugSession.swift`, and DebugProbe.swift is renamed `DeviceProbe.swift`
after the type it holds; all `#if DEBUG`, `verify-move.sh` clean. 2X6 then
edits one file instead of a 728-line one. 2X4a
after 2X2 (both edit PageDetailView's sheets). Then 2X4b and 2X5b together
if the sessions keep to their files (2X4b: settings and the result sheet;
2X5b: the Coordinator's run path); else one after the other. 2X5c after
2X5b. 2X7 last, alone.

The open PR #155 (T9) adds one identifier in PageDetailView. Rebase on it if
it has merged.

**Two commits** where a step rewrites NoteEditor, DocumentTextView,
PageDetailView or CodeFenceDisplay (2X4a, 2X4b, 2X5b, 2X5c): first a pure
move of the section the step changes into a `Type+Area.swift` file
(`scripts/verify-move.sh`), then the change.

## Must not change (every step)

From update-2.md › Must not change, checked against today's code:

- The unnamed `WindowGroup` (NoteCodeApp.swift:56).
- `TipJar.shared.start()` before `ProStatus.shared.start()`, both before the
  DEBUG seeding (NoteCodeApp.swift:30–32).
- `AdConsent.homeAppeared` runs from Home's own `.task(id: consentMayStart)`
  (HomeView.swift:106–109), not from the ad strip's view, which a Pro reader
  never sees.
- The list foot's row order (ad, Tip Jar, Feature Request, Send Feedback,
  Privacy Policy; ListFoot.swift:27–48) and the `tipJarRow` identifier.
- The code-block edit menu's order: Run Block, Copy Block, Share Block, then
  Explain Block (DocumentTextView.swift:790–818). `KeyboardAndMenuTests`
  asserts the start of it (:280).
- The Explain chip's `along: 58` (TextOptionsRow.swift:356), after
  `+ Output`.
- The top bar's order: the Notes | Run control, then Share, then •••
  (PageDetailView.swift:444–450).
- `DebugLaunchOptions.current` is read lazily, first by `TipJar.shared`
  (TipJar.swift:69), `ProStatus.shared` (ProStatus.swift:80) and
  `RunServiceFactory.make` (RunSession.swift:313). An option registered
  after that first read silently becomes "unknown argument" (2X6).
- Every string a reader sees, every accessibility identifier, every
  settings key and default.

## 2X1. The scene and the editions

**Goal.** The app's bootstrap is general and takes what an edition adds; the
App Store edition is a ten-line file in `Pro/`. The seam is counted.

**Files.**
- `NoteCode/App/NoteCodeApp.swift` (113 lines): the `@main` struct
  (:9–76), `StorageUnavailableView` (:78–98), `DebugPaywall` (:100–112).
- New: `NoteCode/App/AppExtensions.swift`, `NoteCode/Pro/AppStoreEdition.swift`,
  `OpenSource/OpenSourceEdition.swift` (repo root: outside the synchronized
  folders, so not compiled), `scripts/check-seam.sh`.
- `scripts/check.sh` (runs the seam script), `docs/refactor/baseline.md`
  (a `SEAM <n>` line, read the way `WARNINGS` is at check.sh:125).

**Do.**
1. `git mv NoteCode/App/NoteCodeApp.swift NoteCode/App/NoteCodeScene.swift`,
   then turn the struct into `struct NoteCodeScene: Scene` with
   `init(extensions: AppExtensions)`. Its body is today's `init` and `body`
   with the Pro lines replaced by calls on `extensions`.
2. `AppExtensions` (a struct, `.none` adds nothing) gets **only what this
   step uses**; each later step adds its own members:
   - `start: @MainActor () -> Void`, called where :28–32 are now. The App
     Store edition's starts `TipJar.shared` then `ProStatus.shared`.
   - `root: (AnyView) -> AnyView` (or a `ViewModifier` box), applied where
     `.environment(TipJar.shared)` and `.environment(ProStatus.shared)` are
     (:60–61). Keep `.modifier(DebugPaywall())` where it is until 2X6.
   - It goes into the environment (`@Entry var appExtensions`) at the same
     place, so later steps' views can read it.
3. `NoteCode/Pro/AppStoreEdition.swift`: `@main struct NoteCodeApp: App`
   whose body is `NoteCodeScene(extensions: .appStore)`, and
   `extension AppExtensions { static let appStore }`.
   `OpenSource/OpenSourceEdition.swift`: the same with `.none`.
4. `scripts/check-seam.sh` counts as "Where the code is today" says (type
   names, the editor's Pro members, `runBlockAtCaret`,
   `explainBlockAtCaret` and `runService`), prints
   `file: names` for each file and the count, and fails if the count is
   above the `SEAM` line in baseline.md. The count may only fall. Record
   today's count (14 if nothing else merged first; say if it differs, and
   why). `check.sh` runs it next to `lint-traps.sh`.

**Must not.** Change the order of anything in `init`; name `ProStatus`,
`TipJar` or `PaywallView` anywhere outside `Pro/` that didn't before; add
members to `AppExtensions` that no code reads yet; touch `.commands`.

**Acceptance.**
- Build passes; `check.sh` passes with the same test count.
- `check-seam.sh` prints the table above minus `NoteCodeApp.swift`'s bootstrap
  lines (it still names `PaywallView` and `ProStatus` in `DebugPaywall`
  until 2X6), and fails when a scratch edit adds a `ProStatus` reference to
  a general file. Put both outputs in the PR.
- One launch with `-debug-home` and a screenshot: Home, the list foot's Tip
  Jar row where the tip jar answers, as before.

**Device line.** Launch from cold: Home appears, the tip jar row is in the
list foot, Settings › Pro shows the right status.

## 2X2. One way to show the paywall

**Goal.** One `ProGate` in `Pro/Store/` says whether the reader has Pro and
presents the paywall for a reason. It is **the only "is Pro" check**, and
the paywall sheets that stay in Pro go through it.

**"Is Pro" is asked three ways today** (`feature-audit.md` › A1):
- a copy on the editor: `editor.pro = pro` (RunPanel.swift:518), read by
  DocumentTextView.swift:549 and NoteEditor.swift:230;
- `ProStatus.shared.isPro` in a closure (SystemTextModelClient.swift:87,
  the assistant's gate);
- the environment's `ProStatus` in the view (PageDetailView.swift:378 and
  :390, the Run control's PRO mark and `showRun`).

All three read `ProGate.isPro` after this step; `NoteEditor.pro` goes
(its two readers move to `ProGate`, and 2X5b moves them into `RunFeature`).
While here: `showsRunIsPro` becomes `showsRunPaywall`, and its stale
comment ("P2's paywall replaces this alert", PageDetailView.swift:65–67) says
what it is; `RunPanelHost` takes the signed transaction once, not as both
`transaction:` and `pro:` (PageDetailView.swift:250, RunPanel.swift:512–513).

**Files.** Today's presenters (`grep -rn "PaywallView(" NoteCode`, 5):
AdBanner.swift:48, ProSettings.swift:38, RunPanel.swift:539,
PageDetailView.swift:263–265, NoteCodeApp.swift:107 (the debug paywall).

**The smaller change.** update-2.md reads as one gate presenting from one
place. That would move the sheet's presenter: ProSettings' paywall is
presented from inside the Settings sheet, and a sheet presented from the
root while another is up never appears. So `ProGate` keeps each sheet where
it is today and only unifies the copies:
- `ProGate.isPro` (reads `ProStatus.shared`) and the three reasons as
  constants (`removesAds`, `runInApp`, `assistant`), so the strings live in
  one place;
- one modifier, `.paywall(isPresented:reason:)`, that the three Pro sites
  use: AdBanner, ProSettings and RunPanelHost.

Leave PageDetailView.swift:263 (it leaves with the assistant in 2X4a, which
uses the modifier from inside `Pro/`) and the debug paywall (2X6).

**Must not.** Move any sheet to a different view; change a reason string;
change ProSettings' "See NoteCode Pro" identifier (`seeProButton`); change
when a renewal or refund lifts or brings back the gate (`PaywallTests`
"Buying Pro lifts the gate without a relaunch").

**Acceptance.** `PaywallTests`, `ProStatusTests`, `AdTests` and
`RunWiringTests` pass; build passes; `grep -rn "\.isPro\b" NoteCode` outside
`Pro/Store/` reads only `ProGate.isPro` (and `AIAssistant.isPro`, the
assistant's injected closure); `grep -c "PaywallView(" NoteCode -r`
is 2 outside `Pro/Store` (PageDetailView, NoteCodeApp) and falls to 0 after
2X4a and 2X6. Seam count falls by 0 or 1 (PageDetailView still names `ProStatus` for
`pro?.signedTransaction` until 2X5c, unless the transaction moves to
`ProGate` too; say which).

**Device line.** Free reader (sandbox, no Pro): Settings › Pro › See NoteCode
Pro opens the paywall over Settings; Home's ad's "Remove ads" opens it; Run
on a block opens it with "Run in the app is part of NoteCode Pro."

## 2X3. Ads and tips through slots

**Goal.** Home, the list foot, NoteList, ContentView and Help and About name
nothing in `Pro/Ads` or `Pro/Store`.

**Files and call sites** (all counted 4 Nov):
- HomeView.swift: `@Environment(ProStatus.self)` :72, `AdSlot(placement: .home, opaque: true)` :104,
  `AdConsent.shared.homeAppeared(pro:)` :108.
- ListFoot.swift: `tipJar: TipJar?` :19, `@Environment(ProStatus.self)` :21,
  `AdConsent.shared` :22, the ad row :26–29, the tip row :30–35,
  `.task { tipJar?.load() }` :69.
- NoteList.swift: `showsTipJar` :110, `@Environment(TipJar.self)` :113,
  `ListFoot(tipJar:)` :177, the sheet :265–267.
- ContentView.swift: `@Environment(ProStatus.self)` :100,
  `ConsentGate.isOpen` :338, the review gate :563.
- AboutSettings.swift: `@Environment(ProStatus.self)` :13,
  `AdConsent.shared` :14, the Ad Privacy Options row :47–50,
  `.task { await consent.settingsAppeared(pro:) }` :56.

**Do.** Add to `AppExtensions`, each `.none` by default:
- `homeFooter` (a view; the App Store's is today's `AdSlot(.home, opaque: true)`)
  and `homeAppeared: @MainActor () async -> Void` (today's
  `AdConsent.shared.homeAppeared(pro: ProStatus.shared)`), which HomeView
  calls from its own `.task(id: consentMayStart)`, as now.
- `listFootRows(present:)`: the ad row and the Tip Jar row, in that order,
  in front of the general rows; `present` hands NoteList a sheet to show.
  NoteList's `showsTipJar` becomes one general `@State` item (an
  `Identifiable` wrapper over the sheet's view), so the sheet is still
  presented by NoteList (:265), not by a row. The tip jar's `load()` moves
  with its row.
- `aboutRows` (Ad Privacy Options) and `settingsAppeared` (consent's
  `settingsAppeared`), in AboutSettings where they are now.
- **The rating prompt** (`feature-audit.md` › A1): it is general, and it
  waits on Pro's ad consent, so without this hook the public build breaks
  at ContentView.swift:563. `mayAskForReview: @MainActor () -> Bool` (today's
  `pro?.isPro == true || AdConsent.shared.trackingAnswered`; `.none` is
  `true`), read by ContentView.swift:563.
- `ConsentGate` is a pure `launchSettled && !titleScreenUp`, and HomeView's
  `consentMayStart` is general. Move it out of `AdConsent.swift` to
  `App/` (renamed `HomeInFront` or kept; say which), with its test lines
  (AdTests.swift:87–89) moving to a general test file.
- `AdConsent` is created by the App Store edition: `.appStore` holds the
  instance, and general code never reads `AdConsent.shared`. Pro's own
  files (AdBanner.swift:26) may keep `.shared`.

**Must not.** Change the list foot's row order, the `tipJarRow` identifier,
when consent starts (`ConsentGate`'s two conditions), or the rating
prompt's conditions; move `homeAppeared` onto the ad strip's view.

**Acceptance.** `AdTests`, `TipJarTests`, `NoteListTests`, `HomeSectionsTests`,
`ReviewPromptTests` and `SidebarOnHomeTests` pass. A new test: with
`.none`, `ListFoot` has no ad or tip row, and the general rows keep their
order; with `.appStore` and a stand-in jar the Tip Jar row is first after
the ad. The seam count falls by 5 (ContentView, HomeView, ListFoot,
NoteList, AboutSettings).

**Device line.** Free reader: Home's ad strip loads after the title screen
and the consent form (first launch); the list foot shows the ad, then Tip
Jar; Tip Jar opens its sheet from the list; Settings › Help and About shows
Ad Privacy Options where UMP requires it. Pro reader: no ad anywhere.

## 2X4a. The assistant's actions as an editor feature

**Goal.** `EditorFeature` and `EditorAction` exist, and Explain Block,
Summarise Note and the Explain chip come from `AssistantFeature`'s actions.
`ai`, `explain`, `summariseNote`, `canInsertAnswer` and `insertAnswer`
leave `NoteEditor`.

**Why here and not in 2X1.** 2X1 would have declared them with nothing to
register; their first user is this step, so they land with it.

**Files and call sites.**
- NoteEditor.swift: `ai` :252, `explainBlockAtCaret` :254–256, the MARK
  "The on-device assistant" :773–819 (`explain`, `summariseNote`,
  `canInsertAnswer`, `insertAnswer`). `insertAnswer` calls the private
  `perform` (:598–608): loosen one, or add an internal `apply(_:)`.
- DocumentTextView.swift: Explain Block in `codeBlockMenu` :809–814.
- CodeFenceDisplay.swift: `editor?.explainBlockAtCaret` :95–100.
- TextOptionsRow.swift: the Explain chip :355–357.
- PageDetailView.swift: Summarise Note :519–524, the result sheet :256–262,
  the AI paywall :263–265, `aiSettings` and `.onChange(of: aiSettings)`
  :130–136 and :266–268 (those last two stay until 2X4b if the sheet and
  settings move there; say which you did).
- AIResultSheet.swift: `editor.ai`, `editor.canInsertAnswer`,
  `editor.insertAnswer` (:20, :115, :124).
- Tests: `AIEditorTests` (`harness.editor.ai` ×10, `summariseNote`,
  `insertAnswer` ×4, `explainBlockAtCaret`), `PaywallTests`,
  `AIFeaturesTests`. `EditorHarness` (TestSupport/EditorHarness.swift:33)
  makes `NoteEditor()`; give it a `features:` argument.

**Do.**
1. *Commit 1, a pure move:* NoteEditor's assistant section to
   `NoteEditor+Assistant.swift`; `verify-move.sh` passes.
2. `NotePage/EditorFeature.swift`:
   - `EditorAction`: id, title (which may depend on Pro, as "Explain Block
     (Pro)" does), symbol, placement, `isAvailable`, `perform`. Placements
     needed today: `.codeBlockMenu`, `.codeBlockRow` (the options row's
     chip) and `.noteMenu` (•••). No key-command placement: no assistant
     action has one, and ⌘R stays general.
   - `EditorFeature: AnyObject`, made from the editor, with
     `actions(for target:)` and default no-op hooks.
   - `explainBlockAtCaret` (NoteEditor.swift:254–256, set at
     CodeFenceDisplay.swift:95–100) goes: the options row's chip performs
     the registered `.codeBlockRow` action on the caret's block, so no
     closure slot leads to the assistant.
   - `NoteEditor(features:)`, a list of factories `(NoteEditor) -> any EditorFeature`;
     `NoteEditor()` keeps meaning no features, so the 18 `NoteEditor()` calls
     in tests don't change.
3. `Pro/Assistant/AssistantFeature.swift` takes the moved section, `ai`,
   the AI paywall sheet and the result sheet's presentation. The menus, the
   row and ••• render whatever actions are registered, after today's items,
   in today's order.
4. PageDetailView gets the factories from `AppExtensions.editorFeatures`:
   ContentView passes the extensions in at its one `PageDetailView(` site
   (ContentView.swift:304), since `@State` can't read the environment in
   `init`.

5. `AIAssistant`'s `isPro` becomes required (AIAssistant.swift:92 defaults
   it to `{ true }`, so a new caller is Pro unless it says otherwise). Three
   test calls pass it today without it (AIEditorTests, AIFeaturesTests,
   PaywallTests); they pass `{ true }` explicitly.

**Must not.** Change the menu order or titles; change `along: 58`; start a
model session for a free reader (`PaywallTests` covers it); make Explain
appear on an output block or in prose.

**Acceptance.** `AIEditorTests`, `AIFeaturesTests`, `PaywallTests`,
`KeyboardAndMenuTests`, `TextRowTests`, `NoteEditorTests` pass. A new test:
with no features, a code block's menu is Run, Copy, Share and the options
row has no Explain. Seam count falls by 2 or more (TextOptionsRow,
NoteEditor if run is also gone, else later). Build passes.

**Device line.** In a code block: edit menu Explain Block opens the sheet;
the options row's Explain does too; ••• › Summarise Note works; Insert
Below lands under the block and one Undo takes it back. A free reader gets
the paywall, marked "(Pro)".

## 2X4b. The assistant's settings and sheet state

**Goal.** Settings › Writing's assistant section and Settings' Pro row come
from the edition; PageDetailView keeps no AI state.

**Files.**
- WritingSettings.swift: the three `@AppStorage`s :18–20, `assistantSection`
  :55–69, `assistantFooter` :71–77 (`AIAssistant.systemClient` :73).
- SettingsView.swift: the Pro row :87–91 (between General and Notes).
- PageDetailView.swift: the three `@AppStorage`s :130–132, `aiSettings`
  :134–136, `.onChange(of: aiSettings, initial: true)` :266–268 (whatever
  2X4a left).

**Do.** *Commit 1:* PageDetailView's AI state to `PageDetailView+Assistant.swift`
(pure move). Then:
- `AppExtensions.settingsSections` with placements: `.afterGeneral`
  (Settings' list: the Pro row) and `.writing` (the end of Writing's form:
  the assistant section).
- The `@AppStorage`s and `apply(to:)` move into `AssistantFeature`, which
  observes them itself (a small `DynamicProperty` view or a modifier the
  feature contributes), so PageDetailView reads none of them. The keys and
  defaults stay byte for byte (`ProKeysTests` pins them).

**Must not.** Change any key, default, footer text or the order of Settings'
rows; read the AI keys in general code.

**Acceptance.** `SettingsTests`, `ProKeysTests`, `AIFeaturesTests`
("Assistant settings") pass. Seam count falls by 2 (SettingsView,
WritingSettings) and PageDetailView names no `AI*` type. A test: with
`.none` Settings' list has no Pro row, and Writing has no assistant section.

**Device line.** Settings › Writing: Assistant off hides Explain from a block's
menu in an open note at once; Answer Length and Insert As still apply.
Settings › Pro is second in the list.

## 2X5b. Run through `RunFeature` (takes what was left of 2X5a)

**Goal.** The block bar's Run, the edit menu's Run Block and ⌘R stay
general and open a compiler site by default; `RunFeature` replaces that with
the panel or the paywall. NoteEditor, DocumentTextView and CodeFenceDisplay
name nothing in `Pro/Run`.

**Files and call sites.**
- DocumentTextView.swift: `run(_:from:)` :542–562 (`RunRoute.route`,
  `editor?.run.isAvailable`, `editor?.pro?.isPro`, `onRunNeedsPro`,
  `runInApp`); `editor?.run.update(blocks:)` in `restyle` :612.
  `openAtSite` (:569–580) stays general.
- CodeFenceDisplay.swift: `keepInNote` :35–41 and `showLine` :44–54 (both
  use `KeepInNote`), `editor?.run.update(blocks:)` :65, and the three
  `editor?.run.*` closures :78–88.
- NoteEditor.swift: `run` :215, `pro` :219, `onRunNeedsPro` :221,
  `runInApp` :225–231, `connectRun` :235–243, `scroll(toBlock: RunBlock)`
  :1293–1295.
- AppSettings.swift: `AppInfo.runService` :120–123 (what is left of 2X5a);
  its readers are RunSession.swift:311 and a doc comment in RunRouting.swift:26.
- RunPanel.swift: `RunPanelHost.body`'s `.task` :516–529 sets `editor.pro`,
  `onRunNeedsPro`, `connectRun()` and `run.runner`.
- Tests: `RunWiringTests` (`NoteEditor()` ×2, `editor.run.keepInNote`,
  `.showLine`, `.blocks`).

**Do.**
1. *Commit 1, a pure move:* CodeFenceDisplay's Keep in Note and show-line
   functions (:31–54) and NoteEditor's run members (:214–243) to
   `+Run.swift` files.
2. `EditorFeature` gets the hooks Run needs, each a no-op by default:
   `run(_ target:, from:) -> Bool` (handled, or fall through to the site),
   `blocksDidChange(_ targets:)`, and a `connect` that is handed the
   coordinator's general services (open at site, apply an edit, place the
   caret on a line).
3. `Pro/Run/RunFeature.swift` owns the `RunSession`, the gate
   (`RunRoute.route`), `runInApp`, `connectRun`, Keep in Note and show-line.
   `AppInfo.runService` moves to `RunServiceFactory` (or a `RunService`
   enum) in `Pro/Run`.
4. `runBlockAtCaret` (⌘R) stays, and now leads only to general code:
   `Coordinator.run` asks the features, then opens the site. Say so in the
   PR; 2T6 replaces the closure slot itself with `TextCommandTarget`.
5. `scroll(toBlock:)` becomes a general `scroll(toLineAt:)` on NoteEditor, as
   `scroll(toHeading:)` (NoteEditor.swift:1298–1300) already is; `RunBlock`
   stays in Pro.

**Must not.** Gate before the language check (`language.canRun` stays
first, DocumentTextView.swift:543); resign first responder in a different
order (`.inApp` resigns before running, the site path before opening);
change Run Block's place in the edit menu; register Run Block's menu item as
a feature action (it is general).

**Acceptance.** `RunWiringTests`, `RunSessionTests`, `CodeRunnerTests`,
`CodeDestinationTests`, `CodeBlockActionBarTests`, `KeyboardAndMenuTests`
pass. A new test: with no features, Run on a C++ block opens the site path
(a stub for `UIApplication.open`, or the request `openAtSite` builds) and
names no service. Seam count falls by 3 (DocumentTextView, CodeFenceDisplay,
NoteEditor). `grep -rn "runService" NoteCode` finds only `Pro/`.

**Device line.** Pro: Run on a block opens the panel and runs; ⌘R does the
same from the caret; Keep in Note writes the output block; a compile error's
line link moves the caret. Free: Run opens the paywall. Untagged block: no
play button.

## 2X5c. The Run panel through the side-panel slot

**Goal.** PageDetailView names nothing in `Pro/`: the Notes | Run control,
`RunDock` and `RunPanelHost` come from `RunFeature` or the edition.

**Files.** PageDetailView.swift: `@Environment(ProStatus.self)` :61,
`windowWidth` :64 (also read by the toggle :366 and the dock :408, set at
:413), `showsRunIsPro` :65–67, `.modifier(RunPanelHost(...))` :247–252,
`runToggleItem` :358–385, `showRun` :387–395, `runLayout` :400–414 and its
non-UIKit stand-in :788, the toolbar's `runToggleItem` :444.

**Do.** *Commit 1:* the Run header and layout (:356–414) to
`PageDetailView+Run.swift`. Then add to `EditorFeature` (or to
`AppExtensions`; say which and why) two slots:
- a top-bar item placed where `runToggleItem` is (before Share);
- a trailing side panel beside `content`, given the window's width, plus a
  page modifier (today's `RunPanelHost`).
PageDetailView keeps measuring `windowWidth` (general) and passes it in.

**Must not.** Change the top bar's order, the narrow-window switch to a
button (`HomeLayout.regularMinimumWidth`, :366), the `.snappy` animations,
or the compact sheet's detents.

**Acceptance.** `RunWiringTests`, `NotePageChromeTests`, `CompactLayoutTests`
pass. Seam count falls by 1 (PageDetailView). With `.none`, the bar has
Share and ••• only (a test).

**Device line.** Pro, iPad landscape: Notes | Run switches, the dock opens
at the right and the page narrows; narrow the window (Split View or the Duo
upright): the control becomes a Run button. iPhone: the panel is a sheet.
Free: the PRO mark shows and Run opens the paywall.

## 2X6. DebugLaunch: options by group (takes over 1B7)

**Goal.** `-debug-pro`, `-debug-paywall`, `-debug-run-stub` and
`-debug-tip-jar` are registered from `Pro/Debug` and reach `parse`, which is
split by option group. The Welcome lines about Run come from the edition.

**Files.**
- DebugLaunch.swift (728 lines): `DebugLaunchOptions` :92–269 (the four Pro
  fields :125–134, `isActive` :140–143, `current` :145, `parse` :147–268,
  its Pro cases :227–240), the first-launch reset :506–509
  (`RunDisclosure.key`).
- ProStatus.swift: `DebugProStore` :284–310; TipJar.swift: `DebugTipStore`
  :180–194; RunSession.swift: `DebugRunStubKind` and `DebugRunStub`
  :319–353. All `#if DEBUG`.
- NoteCodeScene (2X1): `DebugPaywall`.
- RunPanel.swift:522–527 reads `DebugLaunchOptions.current.runStub`.
- WelcomeNote.swift:93 ("With NoteCode Pro, the run button runs it beside
  the page…") and WelcomeScreen.swift:51 ("NoteCode Pro runs it beside the
  page.").
- Tests: `DebugLaunchTests` (18 `parse` calls), `ProStatusTests` :212–218
  (`parse(...).pro`), `RunWiringTests` :42 (`.current.runStub`),
  `HomeSectionsTests` :298–299 (`WelcomeScreen.features`).

**The smaller change.** update-2.md's `parse(registry:)` keeps one struct
for every option. Instead:
- A `DebugArguments` cursor holds the shared state `parse` has today (the
  index, `value(for:)`, `choice(_:for:)`, the problems list).
- Each group is a type with the flags it owns and a `take(_ flag:, from:)`:
  the general groups (the note, layout, Home) in `Debug/`, the Pro group
  in `Pro/Debug/ProDebugOptions.swift`.
- `DebugLaunchOptions.parse(_:groups:)` walks the arguments once, offers
  each flag to the groups, and reports "unknown argument" only for a flag
  no group owns. The cross-option checks (:250–267) stay in the general
  group.
- The Pro group's values (`pro`, `paywall`, `tipJar`, `runStub`) are read by
  Pro code from the Pro group's result, not from fields on
  `DebugLaunchOptions`. `isActive` asks every group.
- **The registry has to be there at the first read.** `current` stays a
  lazy `static let`, built from a static list of groups that
  `NoteCodeScene.init` sets as its first statement, before `extensions.start()`.
  A DEBUG assertion in `current` fails if it is read before the list is
  set. Tests call `parse(_:groups:)` with the groups they need.
- `AppExtensions.debugResetKeys` lists the keys a first launch clears
  (`RunDisclosure.key`), and `debugRoot` holds the debug paywall.
- `AppExtensions.runLines`: the Welcome note's and screen's sentence about
  Run. `.none` says the run button opens the code on a compiler site; say
  in the PR what the public sentence is, since Marcus reads it.
  `WelcomeNote.content` and `WelcomeScreen.features` become functions of
  it, or take it as an argument.

**Must not.** Change a flag's spelling, value set or error text (the tests
pin the texts); change the order of `parse`'s cross-option checks; move a
`Debug*` type out of `#if DEBUG`; change the App Store edition's Welcome
text.

**Acceptance.** `DebugLaunchTests`, `ProStatusTests`, `TipJarTests`,
`RunWiringTests`, `HomeSectionsTests` pass. New tests: `-debug-pro on` with
the Pro group parses with no problem; without it, it is an unknown
argument. The seam count falls by 1 (DebugLaunch) and NoteCodeScene names
nothing in `Pro/`. One launch with
`-debug-pro off -debug-paywall -debug-report` and a screenshot: the free
paywall, and `problems` empty in the report.

**Device line.** None beyond the launch above (DEBUG only), plus: a first
launch shows the Welcome note's Run line as before.

## 2X7. The public build compiles

**Goal.** `scripts/build-open-source.sh` proves the public build compiles
and its unit tests pass, with no project edit. The seam count is 0.

**Files.**
- New: `scripts/build-open-source.sh`, `OpenSource/Info.plist`,
  `OpenSource/PrivacyInfo.xcprivacy` (2X1 made `OpenSourceEdition.swift`).
- `NoteCodeTests/App/AppStoreReadinessTests.swift`: `privacyManifest`
  (:17–33) asserts tracking and the ad SDK's domains;
  `privacyPolicyPage` (:53–65) asserts the page covers Run and ads. Both
  move to `NoteCodeTests/Pro/`. The CA92.1 reason (:35–46), encryption
  (:48), background modes (:67), launch screen (:73) and icon (:86) stay.
- `scripts/check.sh` runs `check-seam.sh` (2X1) and, with `--full`,
  `build-open-source.sh`.

**What the code says that the design didn't.**
- **The scene manifest isn't in `Info.plist`.** The project generates it
  (`INFOPLIST_KEY_UIApplicationSceneManifest_Generation`, project.pbxproj
  :317–318), as it does the launch screen and orientations. The public
  `Info.plist` keeps `ITSAppUsesNonExemptEncryption` and
  `UTExportedTypeDeclarations` and drops `GADApplicationIdentifier`,
  `NSUserTrackingUsageDescription` and `SKAdNetworkItems` (Info.plist :5–214).
- **The packages stay linked.** Google Mobile Ads and UMP are the target's
  package dependencies, so the public build still links them until the
  split removes them (a project edit, split.md). Only `Pro/` imports them
  (`grep -rl "import GoogleMobileAds\|import UserMessagingPlatform"`), so
  nothing calls them.
- **`ContentView` imports `StoreKit`** for `requestReview`, which is general.
  It stays.

**Do.** The script, using `scripts/lib-xcode.sh` and the simulator lock:
1. A temporary worktree of `HEAD` (`git worktree add` under `$TMPDIR`),
   removed on exit.
2. Delete `NoteCode/Pro/` and `NoteCodeTests/Pro/`; copy
   `OpenSource/OpenSourceEdition.swift` to `NoteCode/App/`, and
   `OpenSource/Info.plist` and `PrivacyInfo.xcprivacy` over `NoteCode/`'s.
3. Build and run the Fast plan there. Print the build result and the
   test totals, nothing else.

The public privacy manifest has `NSPrivacyTracking` false, no tracking
domains, no collected data, and the CA92.1 UserDefaults reason.

**Must not.** Edit `project.pbxproj` or `NoteCode/Info.plist` (stop and ask if
the build needs it); leave the temporary worktree behind; run in the main
working tree.

**Acceptance.** `build-open-source.sh` passes; `check-seam.sh` prints 0 and
the `SEAM` line is 0. The closures and members a name count can't see are
checked by name, and the PR lists each with what it reaches now:
`explainBlockAtCaret` is gone (2X4a); `runBlockAtCaret` reaches
`Coordinator.run` and the site, with no feature registered in the public
build; `AppInfo.runService` is gone from general code (2X5b);
`NoteEditor.pro` is gone (2X2); `grep -rn "\.ai\b\|\.run\.\|onRunNeedsPro"`
finds nothing outside `Pro/`; `check.sh --full` passes. The PR gives the public
build's test count and how many tests `Pro/` took with it. A scratch edit
that names `ProStatus` in a general file makes both scripts fail; put the
output in the PR.

**Device line.** None: the App Store build doesn't change. Marcus's TestFlight
pass covers it.
