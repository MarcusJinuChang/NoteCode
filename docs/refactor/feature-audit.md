# Feature audit (4 Nov, `main` 07a5c34)

Each feature group from [features.md](../features.md), read from the code on
`main` after Update 1's moves (1A–1D, T3, T4, F2–F4). It feeds Update 2: what
[update-2.md](update-2.md) already plans is named, not repeated; what it
misses becomes a cleanup (**A*n***) written so it can be a brief.

- **Grades:** *clean* (leave it), *fine* (small things), *needs work* (a real
  problem, planned or not), *tangled* (ownership unclear; the big steps).
- **Kind:** *move* (pure move, `verify-move.sh`), *refactor* (no behaviour
  change), *fix* (behaviour change: a fix PR, failing test first, features.md
  row updated).
- Line numbers are from 07a5c34. Sizes are `wc -l`; tests are `NoteCodeTests/`
  folders that mirror the feature.

## Summary

| Group | Where | Files / lines | Tests (files / lines) | Grade | Why |
|---|---|---|---|---|---|
| Writing and Markdown | `Text/Core`, `Text/Editor`, `Text/Layout`, half of `NoteEditor` | 36 / 10,439 | 34 / 10,293 | needs work | Core is pure and well tested; the Coordinator and the representable around it are the tangle (2T covers most) |
| Code blocks and Run | `Code/`, `Pro/Run` | 25 / 4,377 | 24 / 5,509 | needs work | Blocks are clean; Run reaches the editor through closures, copied Pro state and an unobserved runner |
| Ink | `Ink/`, `PageView` ink section | 22 / 4,840 + ~340 | 14 / 3,188 | needs work | Trap-heavy pipeline inside `PageView`, five copies of tool settings (2P1, 2P5) |
| LaTeX | `Formula/`, `TeXAliases` | 4 / 777 + 106 | 5 / 1,118 | fine | Small, pure where it can be; three hand-rolled caches, an untested editor |
| Pages, view modes, the note page | `NotePage/` | 19 / 6,609 | 17 / 4,702 | tangled | `PageView` 1,611, `NoteEditor` 1,386, `PageDetailView` 820; 2P1–2P3 leave `PageView` near 900 |
| Library, Home, folders, shell | `Library/`, `Model/`, `App/`, `Shared/` | 37 / 8,046 | 25 / 4,482 | needs work | Create/delete twice with different Undo, a rating gate on Pro, misplaced window registry |
| Import and export | `InOut/`, `NoteShareButton` | 5 / 1,524 | 2 / 1,158 | fine | Pure planners, tested; three ways to build a PDF's settings, one wrong title |
| Settings | `Settings/`, `Ink/DrawingSettings` | 12 / 1,391 | 2 / 444 | needs work | Keys and defaults repeated across 22 files (2S2); 2S2's line refs predate 1B5 |
| Pro, ads, tips | `Pro/Store`, `Pro/Ads` | 8 / 1,255 | 5 / 869 | needs work | Fine inside `Pro/`; 13 general files name a Pro type, and the seam script can't see closure coupling |
| Assistant | `Pro/Assistant`, `NoteEditor` :773–877 | 6 / 1,002 + 105 | 3 / 754 | fine | Settings follow `apply(to:)`; the wiring through `NoteEditor` is 2X4's |
| Debug | `Debug/` | 3 / 993 | 1 / 333 | fine | One 728-line file of four types; the probe flags are reported as unknown |

## What update-2.md covers, and what it misses

**Covered, nothing to add:** the extension seam (2X1–2X7), settings tables
(2S2), the snapshot and the Coordinator's types (2T1–2T6), `NoteEditor`'s
split (2T7), long functions (2T8), repeated helpers (2T9), the ink pipeline
(2P1), scroll indicator / keyboard / zoom (2P2), `PageDetailView`'s pieces
(2P3), navigation and `NoteActions` (2P4), `InkToolStore` (2P5), persistence
(2P6), the rest of Core (2C), warnings (2W); with F5–F8 and T5/T6/T8.

**Missing or stale:**

| Gap | Evidence | Goes to |
|---|---|---|
| 2X3 doesn't list the rating prompt's ad gate | ContentView.swift:563 `AdConsent.shared.trackingAnswered` | A1 |
| 2X2 makes one paywall but not one "is Pro" | read three ways: RunPanel.swift:518, SystemTextModelClient.swift:87, PageDetailView.swift:378/390 | A1 |
| `check-seam.sh` counts type names only | Pro behaviour through closures: TextOptionsRow.swift:356 (`explainBlockAtCaret`), NoteCommands.swift:247 (`runBlockAtCaret`), AppSettings.swift:123 (`runService`) | A1 |
| folders.md › Seams is out of date | `ProStatus` is now named by AboutSettings, not SettingsView (1B5); `AIAssistant`/`AIFeatureSettings` by WritingSettings. Count today: 13 files (list in A1) | A1 |
| 2S2's and 2X4b's SettingsView line refs | SettingsView is 143 lines since 1B5 (d542802); the 14 duplicates are now in WritingSettings, CodeSettings, GeneralSettings, NotesSettings, DrawingSettings | note for the 2S2 / 2X4b briefs |
| 1B9 isn't on `main` | `BlockLayout`, `layouts`, `changedIndices` still at DocumentStyler.swift:468–598 | the 2T1 brief should say whether 1B9 landed |
| No step brings `PageView` under 600 lines | after 2P1 (~340) and 2P2 (~260) it is ~1,000; Release QA › 2 wants a reason over 600 | A9 |
| 2C's list misses `FormulaEditing` | Foundation only (FormulaEditing.swift:15) | A12 |
| No step for the page half of `DocumentTextView` | 11 of its 20 properties are `PageView`'s (DocumentTextView.swift:17–40); 2S2d covers the editor half | A10 |
| Nothing unifies the "fence longer than the text" rule | AIInsertion.swift:42/65, RunRouting.swift:93–100 | A6 |

## 1. Writing and Markdown

**Where.** `Text/Core` 17 files / 4,729 (parser, inline parser, nodes,
`MarkdownFormatting` + 4 extensions = 1,704, `StyledLine`, `SpanStyle`,
`TypingStyle`, `DocumentCache`); `Text/Editor` 15 / 4,907
(`DocumentTextView` 1,457, `DocumentStyler` 901, `DocumentUITextView` 506,
`RichPaste` 388, `MarkerTaps` 284, `RichCopy` 257); `Text/Layout` 4 / 803;
`NoteEditor.swift:480–1280` (formatting, typing style, sizes);
`TextOptionsRow` 415.

**Shape.** The text is `Page.content`, bound into `DocumentTextView`
(`@Binding var text`). The Coordinator owns parsing (`DocumentCache`),
styling, highlighting, markers and fence display. `NoteEditor` is the
SwiftUI side: the hotbar and options row call it; it reaches the text view
through a weak ref and 12 closure slots the Coordinator fills
(NoteEditor.swift:31–260, 749–757, 1194, 1252). Core imports only
Foundation (checked) and is tested by 321 `@Test`s. Depends on: HighlightSwift
(via `SyntaxHighlighter`), SwiftMath (formulas). Depended on by: code blocks,
LaTeX, PDF, thumbnails, search, titles.

| Problem | Where | Covered by |
|---|---|---|
| Syntax colours are told apart by colour value: "not `.label`, not the output text colour, not `markerColor`, not `.clear`"; the output colours are "a hair off `.label` on purpose" so this works | DocumentStyler.swift:601, 616–617, 851; CodeOutputPanel.swift:17–18 | **A11** |
| Five whole-document copies and four UTF-16 passes per keystroke | DocumentTextView.swift, CodeSelectionHighlight.swift:63 | 2T1 |
| Coordinator is 1,457 lines with five re-entrancy flags | DocumentTextView.swift:213–1366 | 2T2–2T6 |
| Seven copies of the tag split | DocumentNode.swift:126/132, DocumentParser.swift:398, DocumentCache.swift:77, DocumentTextView.swift:338/646, CodeBlockAction.swift:136 | 2T9 |
| Three hand-rolled caches with three policies (unbounded static; clear at 500; lock and clear at 2,000) | DocumentStyler.swift:119, FormulaAttachment.swift:48–61, FormulaValidity.swift:67–90 | **A13** |
| `DocumentTextView` is the representable of a `PageView` (makes one at :94), lives in `Text/Editor`, and carries ink/page props (`inkSaver`, `onScrolled`, `addsPagesWhileDrawing`…) | DocumentTextView.swift:15–40 | **A10** |

**Grade: needs work.** Core is clean; everything around the Coordinator is
2T's job, plus the colour-identity trick nobody plans to remove.

## 2. Code blocks and Run

**Where.** `Code/` 17 / 2,898 (`CodeBlockLayoutFragment` 549,
`CodeIndent` 261, `CodeBlockOverlay` 254, `CodeFenceDisplay` 253,
`CodeDestination` 229); `Pro/Run` 8 / 1,479 (`RunPanel` 544, `RunSession`
353).

**Shape.** Blocks come from the parse (`CodeBlockAction.targets`); the
overlay places bars from TextKit's viewport. Run state is a `RunSession`
owned by `NoteEditor` (NoteEditor.swift:215), filled by the Coordinator
(CodeFenceDisplay.swift:65–98) and by `RunPanelHost`'s `.task`
(RunPanel.swift:517–528), which copies `pro` onto the editor and sets the
runner. The gate is `RunRoute.route` in the Coordinator
(DocumentTextView.swift:546). `SyntaxHighlighter` is a clean protocol seam.

| Problem | Where | Covered by |
|---|---|---|
| `runner` is `@ObservationIgnored`, but `isAvailable` (reads it) decides whether the Notes \| Run switch exists; it is set in a `.task` after the first render, so the switch shows only because `windowWidth` changes later | RunSession.swift:59, 85; PageDetailView.swift:364, 413; RunPanel.swift:521 | **A3** |
| Pro is copied onto the editor (`editor.pro = pro`) and the signed transaction is passed twice to the same host | RunPanel.swift:518; PageDetailView.swift:250 | A1 (2X2) |
| `showsRunIsPro` says "P2's paywall replaces this alert"; it is the paywall sheet now | PageDetailView.swift:65–67 | A1 (2X2) |
| "Fence longer than any backtick run" written twice | RunRouting.swift:93–100, AIInsertion.swift:42, 65 | **A6** |
| Run wiring lives in `CodeFenceDisplay.swift` (the editor connection), not with fences | CodeFenceDisplay.swift:58–98 | 2X5b, 2T6 |
| `RunRoute`, `KeepInNote` named from general code | DocumentTextView.swift:546, CodeFenceDisplay.swift | 2X5a |

**Grade: needs work.** The block side is fine; Run's wiring is three hops
(view task → editor → Coordinator closures) with one unobserved input.

## 3. Ink

**Where.** `Ink/` 22 / 4,840 (`DrawingCanvas` 595, `HotbarPrimitives` 505,
`InkCapture` 372, `InkInsert` 330, `InkSelection` 323); `PageView.swift:1016–1352`;
`NoteEditor.swift:23–167` (tool, Pencil, finger).

**Shape.** `PageView` owns the canvas, the capture state and its
generation; saving is `DrawingSaveScheduler` from `onInkChanged`, owned by
`PageDetailView` (`@State inkSaver`). The tool is `NoteEditor.inkTool`, whose
`didSet` pushes to canvas and selection (NoteEditor.swift:35–53). Tool
settings are read in five places. Depends on PaperKit; depended on by PDF,
thumbnails, debug report.

| Problem | Where | Covered by |
|---|---|---|
| Capture, show and commit inside a 1,611-line scroll view | PageView.swift:145–183, 1016–1352 | 2P1 |
| Five copies of pen / highlighter / eraser / finger settings | NoteEditor.inkTool, `InkToolPersistence`, `InkSwatches`, `DrawingSettings`, `SelectionOptions` | 2P5 |
| `HotbarPrimitives.swift` (in `Ink/`) is persistence + swatches + eraser options + hotbar pieces under a hotbar name | Ink/HotbarPrimitives.swift (1B2) | 2P5 dissolves it |
| Ink extensions live in Settings | AppSettings.swift:177–204 (`EraserSettings.summary`, `InkPalette.resetStoredPalettes`) | **A12** |
| `InkObjectTable` is read and written back but nothing in the app adds an entry | DrawingSaveScheduler.swift:43 | none: a stored format reserved for anchored ink; keep |

**Grade: needs work**, all of it planned. Don't add to 2P1.

## 4. LaTeX

**Where.** `Formula/` 4 / 777; `TeXAliases` (Core, 106); math in
`DocumentParser`, `MarkdownLayout`, `NotePDF.swift:388–415`.

**Shape.** Parse finds `$…$` and `$$` blocks; the styler swaps them for
attachments (`FormulaAttachment`, cached); `FormulaEditing` is the pure caret
and edit rules; `FormulaEditor` presents from the Coordinator. Only
`FormulaAttachment` and `FormulaValidity` import SwiftMath.

| Problem | Where | Covered by |
|---|---|---|
| `FormulaEditing` is pure but sits outside Core | FormulaEditing.swift:15 | **A12** |
| Attachment cache is a static dictionary cleared at 500; validity cache a locked class cleared at 2,000 | FormulaAttachment.swift:48–61; FormulaValidity.swift:67–90 | **A13** |
| `FormulaEditorModel` and the popover have no test | FormulaEditor.swift:21–230 | T5 |

**Grade: fine.**

## 5. Pages, view modes, the note page

**Where.** `NotePage/` 19 / 6,609: `PageView` 1,611, `NoteEditor` 1,386,
`PageDetailView` 820, `Hotbar` 452, `TextOptionsRow` 415, `PageLayout` 310,
`CanvasGeometry` 291.

**Shape.** `PageDetailView` owns the note's `NoteEditor` and ink saver as
`@State`, reads 16 `@AppStorage`s, and passes them to `DocumentTextView`,
which configures `PageView`. `PageLayout`/`CanvasGeometry` are pure and
tested (48 `@Test`s). `PageView` reports back through four closures
(`onReadingPlaceChanged`, `onScrolled`, `onMinimumPageCountChanged`,
`onInkChanged`).

| Problem | Where | Covered by |
|---|---|---|
| Page layout application, bands, furniture, restore and reveal stay in `PageView` after 2P1/2P2 (~360 lines) | PageView.swift:622–750, 783–1015 | **A9** |
| Editor bridges set in `onAppear` (`commitTextSize`, `commitLineSpacing`, `onBlockCopied`) | PageDetailView.swift:284–288 | 2P3 |
| `@State NoteEditor()` / `DrawingSaveScheduler` made on every `init` | PageDetailView.swift:51, 202 | 2P3 |
| `modifiedAt` on every keystroke | PageDetailView.swift:273–274 | F6 |
| A general `UIResponder.currentFirstResponder` lives at the end of NoteEditor.swift | NoteEditor.swift:1367–1384 | **A12** |
| `DebugSession.shared` called from `PageView` | PageView.swift:305, 589 | none: `#if DEBUG`, general debug; keep |

**Grade: tangled.** The three biggest files in the app; 2P1–2P3 and 2T7 are
the right steps, and A9 finishes `PageView`.

## 6. Library, Home, folders, shell

**Where.** `Library/` 14 / 4,473 (`NoteList` 829, `HomeView` 567,
`NoteListDrop` 520, `NoteIconGeometry` 508, `NoteThumbnail` 442); `Model/`
8 / 1,190; `App/` 10 / 2,032 (`ContentView` 656); `Shared/` 5 / 351.

**Shape.** `ContentView` owns selection, column visibility and the compact
path; `HomeView` and `NoteList` each `@Query` every page. Notes are made
through `Page.create` (good: one path), deleted through
`Page.moveToRecentlyDeleted` from three places. `OpenNoteRegistry.shared`
keeps one editor per note. Pure parts (`HomeSections`, `NoteListSections`,
`NoteSort`, `NoteTitle`) are tested.

| Problem | Where | Covered by |
|---|---|---|
| Delete with Undo twice, and the Undos differ: ContentView's reopens the note, NoteList's doesn't | ContentView.swift:615–632; NoteList.swift:772–793 | 2P4 (`NoteActions`): the brief must say which Undo wins (a fix if they change) |
| The rating prompt (general) waits on `AdConsent` (Pro) | ContentView.swift:563 | **A1** |
| `OpenNoteRegistry` and `WindowToken` are in the import/export file | NoteInterchange.swift:322–378 | **A12** |
| Rename writes `modifiedAt` here and `PageDetailView` writes it again on `title` change | NoteList.swift:768; PageDetailView.swift:273 | F6 |
| Every list loads every note; thumbnails read `drawingData` on main | NoteList.swift:76, HomeView.swift:55, 361 | F7, F8 |
| `ContentView`, `HomeView`, `ListFoot` have no tests | — | T5 (navigation, create/delete) |

**Grade: needs work.**

## 7. Import and export

**Where.** `InOut/` 4 / 1,335 (`NotePDF` 483, `ExportAll` 393,
`NoteInterchange` 378, `ImportFiles` 81); `NoteShareButton` 189.

**Shape.** `NoteExport.plan` / `NoteImport.note` are pure and tested (45
`@Test`s). `NotePDF.render` takes a `NotePDF.Note`; the open note builds it
from the editor (NoteEditor.swift:347–360), Export All from the stored page
(ExportAll.swift:221–236). `PrintedNote` (NotePDF.swift:252) builds a whole
Coordinator and is also the thumbnails' ink drawer (NoteThumbnail.swift:182–184).

| Problem | Where | Covered by |
|---|---|---|
| Export All's PDFs carry the stored title ("Untitled" until renamed) as their PDF title; the file name and Share use `displayTitle` | ExportAll.swift:228 vs :203, NoteShareButton.swift:86 | **A2** (fix) |
| A third way to read settings for a PDF: `UserDefaults.standard` by hand, `rendersMarkdown: true` hard-coded | ExportAll.swift:225–233 | **A8** |
| `SharePopover.documentTitle` is dead in effect: its one caller passes `displayTitle`, never empty (NoteTitle.swift:31–35); it repeats `NoteTitle`'s rules more loosely | NoteShareButton.swift:153–162; PageDetailView.swift:447 | **A7** |
| `PrintedNote` builds a full Coordinator to style text | NotePDF.swift:272 | 2T2 |

**Grade: fine.**

## 8. Settings

**Where.** `Settings/` 11 / 1,177 (split by 1B5: `SettingsView` 143 +
`GeneralSettings`, `NotesSettings`, `WritingSettings`, `CodeSettings`,
`AboutSettings`); `Ink/DrawingSettings` 214; `Pro/Store/ProSettings` 40.

**Shape.** Each page reads its keys with `@AppStorage`; the note page reads
the same keys again (PageDetailView.swift:72–144). 2S1 pinned every key and
default. `AccentPalette.defaultsKey` is read by five views with `""`.
`AppInfo` holds constants plus a `nonisolated(unsafe) static var deviceName`
(AppSettings.swift:118).

| Problem | Where | Covered by |
|---|---|---|
| 68 `@AppStorage` declarations across 22 files, keys and defaults repeated (e.g. the three AI settings in WritingSettings.swift:18–20 and PageDetailView.swift:130–132) | `grep -c @AppStorage` | 2S2a–c |
| 2S2's refs (SettingsView :278–569) and 2X4b's (SettingsView.swift:494, 526–551) predate 1B5 | update-2.md › 2S2, 2X4b | note for those briefs |
| `SettingsView` names `ProSettings`; `AboutSettings` holds `AdConsent.shared` | SettingsView.swift, AboutSettings.swift:14 | 2X3, 2X4b (A1 adds ProSettings) |
| `AppInfo.runService` is a Pro constant in general settings | AppSettings.swift:123 | 2X5a |

**Grade: needs work**, planned.

## 9. Pro, ads, tips

**Where.** `Pro/Store` 5 / 833 (`ProStatus` 310, `TipJar` 194, `PaywallView`
174); `Pro/Ads` 3 / 422 (`AdConsent` 220).

**Shape.** `ProStatus.shared` and `TipJar.shared` start in `NoteCodeApp`
and go into the environment; `AdConsent.shared` is read directly by five
files. Debug stores live inside the real types (2X6). Inside `Pro/` the
code is tidy and tested (`ProStatusTests`, `TipJarTests`, `AdTests`).

General files that name a Pro type today (13): ContentView, NoteCodeApp,
CodeFenceDisplay, DebugLaunch, HomeView, ListFoot, NoteList, NoteEditor,
PageDetailView, AboutSettings, SettingsView, WritingSettings,
DocumentTextView. No test file outside `NoteCodeTests/Pro/` does.

| Problem | Where | Covered by |
|---|---|---|
| Paywall presented from five places | AdBanner.swift:48, ProSettings.swift:38, RunPanel.swift:539, PageDetailView.swift:264, NoteCodeApp.swift:107 | 2X2 |
| "Is Pro" read three ways (env, copy on the editor, `ProStatus.shared` in a closure) | PageDetailView.swift:378; RunPanel.swift:518; SystemTextModelClient.swift:87 | **A1** |
| `AdConsent.shared` hard-wired | ContentView, HomeView, ListFoot, AdBanner, AboutSettings | 2X3 (+ A1 for ContentView:563) |
| Pro behaviour reached by closures the seam count can't see | TextOptionsRow.swift:356; NoteCommands.swift:247; WelcomeNote.swift:93 | **A1** |

**Grade: needs work** at the seam; *fine* inside `Pro/`.

## 10. Assistant

**Where.** `Pro/Assistant` 6 / 1,002 (`AIPrompts` 283, `AIFeatures` 209,
`AIAssistant` 192); `NoteEditor.swift:773–877`; result sheet and paywall
sheet in PageDetailView.swift:257–268.

**Shape.** `NoteEditor.ai = AIAssistant.system()` (NoteEditor.swift:252),
one per note; settings arrive by `AIFeatureSettings.apply(to:)` (the
convention). `TextModelClient` is a clean seam over Apple's model.
`AIInsertion` is pure and tested.

| Problem | Where | Covered by |
|---|---|---|
| `ai`, `explain`, `summariseNote`, `insertAnswer` on `NoteEditor` | NoteEditor.swift:249–256, 773–877 | 2X4a |
| `AIAssistant(client:)` defaults `isPro` to `{ true }`: a new caller is Pro unless it says otherwise | AIAssistant.swift:92 | **A1** (2X4a brief: make it required) |
| `AIResultSheet` has no test | AIResultSheet.swift | none; small, sheet only |

**Grade: fine.**

## 11. Debug

**Where.** `Debug/` 3 / 993 (`DebugLaunch` 728, `SelectionProbe` 144,
`DebugProbe` 121).

**Shape.** `DebugLaunchOptions.current` parses once; `DebugSession.shared`
seeds storage and writes the report; the two probes read
`ProcessInfo.arguments` themselves. `DebugLaunchTests` covers parse and the
report.

| Problem | Where | Covered by |
|---|---|---|
| `-debug-probe`, `-debug-probe-snapshot`, `-debug-probe-watch` and `-debug-selection-probe` work but land in the report's `problems` as "unknown argument" | DebugLaunch.swift:241–244; DebugProbe.swift:19–20, 52; SelectionProbe.swift:22 | **A4** (fix) |
| One file holds options (:92–278), report (:280–426), seeding with inline sample notes (:427–597) and the session (:629–728) | DebugLaunch.swift | **A5** |
| `DebugProbe.swift` declares `DeviceProbe` | DebugProbe.swift:17 | A5 (rename the file) |
| Pro options in `parse` | DebugLaunch.swift:227–240 | 2X6 |

**Grade: fine.**

## Cleanups

Each is one PR off `main`.

| ID | Kind | What changes | Must not change | Step |
|---|---|---|---|---|
| A1 | docs | Amend the Update 2 briefs when they are expanded: 2X3 adds the rating gate (ContentView.swift:563) as an edition hook; 2X2's `ProGate` is the only "is Pro" (editor copy at RunPanel.swift:518 and `ProStatus.shared` at SystemTextModelClient.swift:87 go), renames `showsRunIsPro`, passes the transaction once; 2X4a makes `AIAssistant`'s `isPro` required; 2X1's `check-seam.sh` also counts `runBlockAtCaret`, `explainBlockAtCaret`, `ai.`, `runService`; folders.md › Seams gets today's 13 files | nothing in code | before 2X1 (the plan PR between waves) |
| A2 | fix | Export All's PDF title is `displayTitle` (ExportAll.swift:228). Test: export a note never renamed, read the PDF's title | file names, the Markdown, which notes get a PDF | beside 2X, any time |
| A3 | fix | `RunSession.runner` observed (drop `@ObservationIgnored`, RunSession.swift:59), or set before the first render. Test first: the header's Run switch appears with no width change | the Run switch's look, PRO mark, compact button | before 2X5c |
| A4 | fix | `parse` knows the four probe flags (and skips them), so they leave `problems`. Test: `parse(["-debug-probe"]).problems` is empty | the probes' own behaviour; every other flag | before 2X6 |
| A5 | move | DebugLaunch.swift → `DebugLaunchOptions.swift` (options and `parse`, untouched), `DebugStateReport.swift`, `DebugSeed.swift`, `DebugSession.swift`; DebugProbe.swift → DeviceProbe.swift. All `#if DEBUG` | `parse`'s body; the report's fields | before 2X6 (it then edits one file) |
| A6 | refactor | `CodeFence.wrapping(_:tag:)` in Text/Core, used by `KeepInNote.fenced` and `AIInsertion.edit(.output)`. Leave NoteImport's line-start rule (NoteInterchange.swift:293), which differs | the text written; `OutputBlockTests`, `AIFeaturesTests` | beside 2T9 |
| A7 | refactor | Delete `SharePopover.documentTitle`; Share uses `displayTitle` as Print does | PDF and `.md` names and titles (same strings today) | any time |
| A8 | refactor | One `NotePDF.Note(page:settings:)` used by `NoteEditor.pdf` and Export All; Export All reads the 2S2a table, not `UserDefaults` by hand | what either PDF looks like (Export All keeps `rendersMarkdown: true`) | after 2S2a |
| A9 | refactor, two commits | `PageView`'s pages section to `PageBands` (layout application, bands, furniture, `addPage`, :783–1015) and reopen/reveal to `PageReading` (:622–750) | debug report fields, restore-to-page, band positions in every mode; `PageViewTests`, `ReopenTests`, `PageSettlingTests` | 2P2b, after 2P2 |
| A10 | refactor | The page-only properties of `DocumentTextView` (DocumentTextView.swift:17–40: layout, clearances, area, ink saver, reveal, resume, page count, page growth, callbacks) become one `PageConfiguration` with `apply(to: PageView)` | `DocumentTextView.Coordinator`'s name (34 test files use it); what `updateUIView` sets and in what order | beside 2S2d |
| A11 | refactor | A custom attribute (`.noteCodeSyntax`) marks highlighted runs; `codeColors` and `inheritedCodeColor` read it instead of comparing colours (DocumentStyler.swift:601–622, 844–856) | every colour on screen, including the output tokens; highlight timing; `StylingPerformanceTests` within 10% | inside 2T3 |
| A12 | move | Small homes: `OpenNoteRegistry`/`WindowToken` → App/NoteWindowControl; `UIResponder.currentFirstResponder` → Shared; AppSettings.swift:177–204 → Ink; `FormulaEditing` → Text/Core (add to 2C) | everything; access levels unchanged | 2C, or any wave |
| A13 | refactor | One `BoundedCache<Key, Value>` for marker widths, formula attachments, formula validity (and `TextColourCache`, DocumentStyler.swift:885) | limits (500, 2,000; marker widths stays unbounded or gets a limit stated in the PR); perf | beside 2T2 |

## Ranked by value per effort

1. **A1**: an hour of plan edits; without it the public build breaks at
   ContentView:563 and "is Pro" stays split after 2X2.
2. **A4**: a few lines and a test; the report stops lying about real flags.
3. **A2**: one argument and a test; a wrong title in every exported PDF.
4. **A3**: small, test first; the Run switch shows today by accident.
5. **A5**: a pure move that makes 2X6 smaller and reviewable.
6. **A7**: deletes dead code.
7. **A6**: one helper, two callers.
8. **A12**: four tiny moves, any time.
9. **A8**: one factory, after 2S2a.
10. **A11**: removes the colour-identity trick; medium, inside 2T3.
11. **A10**: the page half of the representable's settings, beside 2S2d.
12. **A9**: the largest, but `PageView` can't meet the 600-line bar without it.
13. **A13**: tidy, low risk, low value.
