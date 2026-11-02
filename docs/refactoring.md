# Refactoring NoteCode: preparation

Written 2 Nov 2026 at `8b34576`, after 1.0 was submitted. This is the
groundwork for a refactor, not the refactor: what the codebase looks like,
what must not change, what the project allows, and a proposed order. How the
code got this shape is in `docs/timeline.md`.

## Ground rules

- **Behaviour-preserving.** A refactor PR changes no feature, no stored
  attribute and no on-screen result. A behaviour change found along the way
  is its own PR. `docs/features.md` should need no edit.
- **One step per PR off `main`**, small enough to review as moves and
  renames. Run the unit tests before and after each (command below).
- **The model stays frozen.** No change to `NoteSchemaV1` or anything
  `ModelFreezeTests` hashes. See `docs/design/the-model.md`.
- **The implementation requirements in AGENTS.md are load-bearing.** Each
  one is a bug that shipped once. The ones a refactor is most likely to
  break are under "Traps" below.
- **Don't touch `project.pbxproj` or `Info.plist`.** If a step needs either,
  stop and ask Marcus. Most steps don't (next section).

## What the project allows

The three targets use Xcode's **synchronized folders**
(`PBXFileSystemSynchronizedRootGroup` for `NoteCode/`, `NoteCodeTests/`,
`NoteCodeUITests/`). Every file under a target's folder is compiled into it,
so:

- **Moving a Swift file into a subfolder of `NoteCode/` needs no project
  edit.** Use `git mv` so history follows.
- `NoteCode/Info.plist` must stay where it is: `INFOPLIST_FILE` and the
  folder's one membership exception both name that path.
- `PrivacyInfo.xcprivacy`, `Assets.xcassets` and `Acknowledgements.txt` are
  resources; moving them is safe for the build but checked by
  `AppStoreReadinessTests`. Leave them at the top.
- A new Swift package or framework target **does** need a project edit: ask.

Paths named outside the code that a move would break:

| Path | Named in |
|---|---|
| `NoteCode/NoteIconGeometry.swift` | `scripts/icon-sheet/main.swift` (build line), `docs/design/colour.md` |

Docs otherwise name types and files by bare name, which survives a move.

## Baseline

| | |
|---|---|
| App sources | 156 Swift files, 40,655 lines, all flat in `NoteCode/` |
| Tests | 132 files in `NoteCodeTests/` (Swift Testing), plus `NoteCodeUITests/`; 33,713 lines together |
| Last green run | 1,848 tests in 211 suites, 31 Oct at `fb7428e` (ROADMAP) |
| Run proxy | `server/run-proxy`, its own npm project: 31 tests and a typecheck |

Re-take the baseline before step 1, and record the count and time:

    xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
      -only-testing:NoteCodeTests -parallel-testing-enabled NO

Also build the macOS destination: `#if os(macOS)` and iOS-only API have
broken it before (#76).

## Hotspots

The six largest files hold a quarter of the app. Each already has `// MARK:`
sections that are natural seams.

| File | Lines | Used by | Seams |
|---|---|---|---|
| `PageView.swift` | 1,826 | 16 files | Keyboard, hotbar motion, layout, reopening, search, outline, re-wrapping, pages, **ink** (340 lines), zoom, touches, the one pan, scroll indicator, rendering; plus `PageDecorationView` and `PageCoverView` |
| `DocumentTextView.swift` | 1,435 | 14 | The representable; a ~1,100-line `Coordinator` (hidden markers, code-keys row, line numbers); fragment selection |
| `NoteEditor.swift` | 1,395 | 16 | Insert, find, formatting, typing style, text options row, assistant, size at the caret (310 lines), note text size, line spacing, outline, undo |
| `DocumentStyler.swift` | 894 | 11 | Attributes, applying, colour and size, incremental restyling, offsets (385 lines) |
| `NoteList.swift` | 829 | — | Empty states, rows, menus, bindings, changes |
| `PageDetailView.swift` | 813 | 6 | Header, page |

Most-shared types, which make the widest blast radius for a rename:
`MarkdownFormatting` (19 files), `DocumentParser` (18), `ProStatus` (18).

Splitting these into `Type+Area.swift` extensions, as `MarkdownFormatting`
already is, keeps every call site unchanged. Stored properties can't move
into an extension, so a section that owns state (PageView's ink, the
Coordinator's markers) is a candidate for its own type instead; that is a
design change, not a move, and wants its own PR and a look at the traps.

## The pure core

60 files import neither SwiftUI nor UIKit: the parsers, the model, code
keys and indentation, the run client and session, formula validity, sort,
search, titles, templates and more. AGENTS.md asks for parsing to be pure
and testable without SwiftUI; these are what that rule produced.

Two ways to make it stick, for Marcus to choose:

1. **A folder** (`NoteCode/Core/`) and a convention. No project edit.
2. **A local Swift package** that the app depends on, so UIKit can't creep
   in by accident and the core builds and tests on the Mac in seconds.
   Needs a project edit, and the frozen model would have to stay in the app
   (SwiftData `@Model` types in a package are fine, but `ModelFreezeTests`
   and `Storage` move with them).

List them with:

    grep -L 'import SwiftUI\|import UIKit' NoteCode/*.swift

## Proposed folders

A grouping by area, for step 1. It is a proposal: check that every file is
assigned (`ls NoteCode/*.swift | wc -l` against the moved count) and adjust
where a file's imports say otherwise.

| Folder | Files |
|---|---|
| `App/` | NoteCodeApp, ContentView, CompactNavigation, NoteWindowControl, PageWindowChrome, BarMaterial, Haptics, Toast, FoldAvoidance, WelcomeScreen, WelcomeNote, NoteShortcut, NoteCommands, EditMenuOrder |
| `Model/` | Page, Folder, NoteSchema, Storage, NoteMemory, DrawingCodec, DrawingSaveScheduler, NoteSort, NoteTitle, NoteInfo, LastCodeLanguage |
| `Library/` | HomeView, HomeSections, NoteList, NoteListDrop, NoteListSections, RecentlyDeletedView, FolderEditor, FolderAppearance, NoteIconGeometry, NoteIconView, NoteThumbnail, ListFoot, NoteSearch, NoteTemplates |
| `NotePage/` | PageDetailView, PageView, PageLayout, PageViewMenu, CanvasGeometry, EditorMode, NoteEditor, Hotbar, HotbarDock, TextOptionsRow, NoteTitleMenu, NoteInfoView, NoteOutline, NoteOutlineView, NoteShareButton, SelectionOptions, PencilResponse, ReadsInput |
| `Text/Parsing/` | DocumentParser, DocumentNode, InlineParser, InlineTags, StyledLine, SpanStyle, TextColour, TypingStyle, MarkdownFormatting and its four extensions, CodeBlockIdentity, FenceVisibility |
| `Text/Editor/` | DocumentTextView, DocumentTextView+Clipboard, DocumentUITextView, DocumentStyler, MarkdownLayout, ProseBlocks, ProseLayoutFragments, BlankLineLayout, CaretAnywhere, HeadingMarkerDisplay, MarkerDimming, MarkerTaps, TextRegionSelection, TextRewritingPolicy, NoteTypography, RichCopy, RichPaste, CodeSelectionHighlight |
| `Code/` | CodeBlockAction, CodeBlockActionBar, CodeBlockLanguageButton, CodeBlockLayoutFragment, CodeBlockOverlay, CodeBlockRoom, CodeFenceDisplay, CodeIndent, CodeKeys, CodeKeysRow, CodeEditorSettings, CodeOutputPanel, SyntaxHighlighter, HighlightSwiftHighlighter, SyntaxTheme |
| `Run/` | RunJob, RunPanel, RunRouting, RunServiceClient, RunSession, CodeDestination, CompilerMessages, JavaMain |
| `Formula/` | FormulaAttachment, FormulaEditing, FormulaEditor, FormulaValidity, TeXAliases |
| `Ink/` | DrawingCanvas, DrawingSettings, InkCapture, InkColorPicker, InkInsert, InkObjectTable, InkObjects, InkPages, InkSelection, InkSelectionOverlay, InkTool, InkToolbar, SelectionShape |
| `InOut/` | NotePDF, ExportAll, ImportFiles, NoteInterchange |
| `Assistant/` | AIAssistant, AIFeatures, AIInsertion, AIPrompts, AIResultSheet, SystemTextModelClient |
| `Store/` | ProStatus, ProSettings, PaywallView, AdBanner, AdConfig, AdConsent, TipJar, TipJarView, ReviewPrompt |
| `Settings/` | SettingsView, AppSettings, AccentPalette |
| `Debug/` | DebugLaunch, DebugProbe, SelectionProbe |

Tests can mirror it later; a test file's folder doesn't affect what it can
see (`@testable import NoteCode`).

## Traps

From AGENTS.md › Implementation requirements, the ones a refactor touches
most easily. Read the full list before a step that goes near them.

- **`.layoutManager`** read anywhere on the text view drops it to TextKit 1,
  silently. A helper that "just reads the layout" can do it.
- **Action bars** are placed from TextKit 2's viewport, never the whole
  document, and `DocumentUITextView` refuses its recognisers on a bar. Moving
  either needs a real tap test, not `sendActions`.
- **`MarkupOrderedSet`**: walk with `for … in`; build with one
  `append(contentsOf:)`. A tidier `map` is a 100× regression at 2,000
  strokes (`PageViewTests.openingCost`, `NotePDFTests.printingCost`).
- **Ink saves** only from `PageView.onInkChanged` for the reader's own
  changes; capture runs off the main thread, and code that needs every
  stroke calls `commitInk()` first. Tests that wait for it `await`.
- **Parse `nativeUTF8`**, never `textView.text` a character at a time.
- **`Page.drawingData`** must not be read from a page whose deletion was
  saved; deletion paths (`moveToRecentlyDeleted`, `Page.delete`) save at
  once.
- **`PKInk.inkType`** traps on the eraser's ink; use
  `InkContent.inkIdentifier`.
- **Settings that move together** live in one type with one `apply(to:)`
  (`TextRewritingPolicy`). Don't scatter them while splitting a file.
- **Performance tests** (`StylingPerformanceTests`, `CodeFenceCostTests`,
  `TextSizeCostTests`, the `openingCost`/`printingCost` pairs) guard costs
  that a refactor can quietly multiply. Compare their numbers to the
  baseline, not just pass/fail.

## Proposed order

1. **Re-baseline** tests (iOS) and build (macOS); record both here.
2. **Folders**: the moves above with `git mv`, one PR, no code changes; fix
   the icon-sheet build line and `colour.md`.
3. **Split the hotspots into extensions**, one file per PR, largest first
   (`PageView`, `DocumentTextView`'s Coordinator, `NoteEditor`,
   `DocumentStyler`). No logic changes.
4. **Decide the pure core** (folder or package; see above).
5. **Types out of the hotspots** where a section owns state, one per PR,
   each checked against the traps and on the iPad where it touches ink or
   taps.

Steps 2 and 3 are mechanical and safe to hand to an agent with this file;
4 and 5 are design decisions.

## Open questions for Marcus

- **Package or folder** for the pure core (above).
- **`Page.paperStyle`** is still a stored attribute after paper styles were
  removed (31 Oct). Removing it changes the frozen hash; whether that is
  still allowed depends on whether 1.0 is live. Until decided, leave it.
- **Tests' layout**: mirror the app's folders now, or leave them flat.
- **Scope**: does the refactor include `server/run-proxy`, or the app only?
