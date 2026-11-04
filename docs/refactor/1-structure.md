# 1. Structure: folders, pure moves, dead code

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. Everything here changes no behaviour. The
line numbers are from 2 Nov; find the code by name if they have moved.

## 1A. Feature folders (three PRs, nothing else open)

The project uses synchronized folders, so a file moved inside `NoteCode/`
or `NoteCodeTests/` stays in its target with no project edit. Use `git mv`
so history follows. Needs T1 (the `repoRoot` helper: two tests find the repo
from their own path) and 0D (the baseline is taken before anything moves).

**1A1. The map.** Write `docs/refactor/folders.md`: every file in
`NoteCode/` assigned to one folder, and a count that matches
`ls NoteCode/*.swift | wc -l`. Start from the table in
`git show f552d11:docs/refactoring.md` › Proposed folders, with these
changes:

- **`Text/` is three folders.**
  - `Text/Core`: pure model and parsing, importing neither SwiftUI nor
    UIKit. That is DocumentParser, DocumentNode, InlineParser, InlineTags,
    StyledLine, SpanStyle, TextColour, TypingStyle, MarkdownFormatting and
    its extensions, CodeBlockIdentity, FenceVisibility and TeXAliases.
  - `Text/Editor`: the text view, styler, policy, clipboard, markers and
    caret.
  - `Text/Layout`: MarkdownLayout, ProseBlocks, ProseLayoutFragments and
    BlankLineLayout.
- **`Shared/`** takes Toast, Haptics, BarMaterial and FoldAvoidance.
- **`Pro/`** holds everything the public build leaves out:
  - `Pro/Store`: ProStatus, ProSettings, PaywallView, TipJar, TipJarView.
  - `Pro/Ads`: AdBanner, AdConfig, AdConsent.
  - `Pro/Run`: RunJob, RunPanel, RunServiceClient, RunSession, RunRouting,
    CompilerMessages, JavaMain, ReadsInput.
  - `Pro/Assistant`: AIAssistant, AIFeatures, AIInsertion, AIPrompts,
    AIResultSheet, SystemTextModelClient.
- **`Code/`** keeps `CodeDestination`, which the free build's Run uses, and
  `CodeOutputPanel`, which output blocks use.
- **Ink storage is `Ink/`:** DrawingCodec and DrawingSaveScheduler go with
  the ink.
- **Where a file is unclear,** it goes where its main type's callers are.
  Say which ones you judged.
- **Stays at the top of `NoteCode/`:** `Info.plist`,
  `PrivacyInfo.xcprivacy`, `Assets.xcassets` and `Acknowledgements.txt`.
  `AppStoreReadinessTests` reads them, and the project names `Info.plist`'s
  path.

**Done when.** The map is merged after Marcus has read it.

**1A2. Move the app's files** with a script that reads the map and runs
`git mv`. Then grep for paths that name a moved file:

    grep -rn "NoteCode/[A-Za-z+]*\.swift" scripts docs AGENTS.md README.md .github

Fix the scripts; `scripts/icon-sheet/main.swift`'s build line names
`NoteCode/NoteIconGeometry.swift`. Fix the docs that give a path
(`docs/design/colour.md`); docs that give a bare file name are fine.

**Done when.**
- The build passes, and so do `check.sh` and `verify-move.sh`, which shows
  renames only.
- The moved count equals the map's.
- `lint-traps.sh` rule 6 finds no duplicate basenames.

**1A3. Mirror the tests.** `NoteCodeTests/` takes the same folders. A test
file goes where the type it tests lives, and a test that spans several goes
with its main type.
- `NoteCode.storekit` goes to `NoteCodeTests/Pro/`. `TipJarTests` loads it
  from the test bundle, so it must stay inside the test target.
- Leave `NoteCodeUITests/` as it is.

**Done when.** `check.sh` passes with the same test count as the baseline,
and `verify-move.sh` shows renames only.

## 1B. Pure moves out of the long files (one PR each, two at a time)

**Do.** Move each section in the table into its own file, keeping it the
same type, as `Type+Area.swift` extensions or as a standalone type that
already exists in the file. Change nothing inside the code.
- Stored properties stay in the main declaration.
- Loosening `private` follows README › Rules.
- Run the suites that name the file's types
  (`grep -rl "<TypeName>" NoteCodeTests`).

Leave out NoteEditor, DocumentTextView, PageDetailView and CodeFenceDisplay.
Update 2 rewrites them and splits them inside its own steps, so splitting
them now would be done twice.

| ID | File | What moves out |
|---|---|---|
| 1B1 | `PageView.swift` | `PageDecorationView` (from :1613) and `PageCoverView` (from :1754), to `PageDecorations.swift` |
| 1B2 | `InkToolbar.swift` | `InkToolPersistence` (:101–153), the swatches (:291), the eraser options, and the six hotbar primitives (:555–720), to `HotbarPrimitives.swift` |
| 1B3 | `InkTool.swift` | One file per group of value types; the palette and `InkPaletteSet` (:549–) on their own |
| 1B4 | `Hotbar.swift` | `HotbarMetrics` (the statics four other files use) and the options-row layout (`HotbarTrack`, `BesideBarLayout`, `EdgeFade`) |
| 1B5 | `SettingsView.swift` | One file per section struct; `SettingsCommands`, `AppearanceModifier` and the logo marks on their own |
| 1B6 | `NoteList.swift` | The rows and the menus (its MARK sections). **Deferred to Update 2 (2P4)** |
| 1B7 | `DebugLaunch.swift` | `parse` (:147, 122 lines) by option group. Keep `#if DEBUG` around every file. **Deferred to Update 2 (2X6)** |
| 1B8 | `CodeBlockLayoutFragment.swift` | `DocumentCache` and `String.nativeUTF8` (:556–622), to `Text/Core/DocumentCache.swift` |
| 1B9 | `DocumentStyler.swift` | The pure layout (`BlockLayout`, `InlineLayout`, `BlockSignature`, `layouts`, `changedIndices`, :441–585), to `Text/Core/DocumentLayout.swift`. **Perf** |

**1B6 and 1B7 stopped, as the Rules require, and moved to Update 2.**
- **1B6:** splitting NoteList needs about 24 members loosened, so its parts
  are types, not extensions. 2P4 rewrites NoteList's actions and takes it
  over.
- **1B7:** `parse` is one loop and one switch sharing a cursor and an
  accumulator, so it can't be split as a pure move. 2X6 takes it over.

For 1B8 and 1B9, check that the moved code imports neither SwiftUI nor
UIKit; `lint-traps.sh` rule 4 will check it from then on. If it needs one,
it stays out of `Core/`: say so and put it in `Text/Editor`.

**Done when.** `verify-move.sh` passes, apart from the access loosening
listed in the PR. The build and the named suites pass, and the file is
shorter by what moved.

## 1C. Dead code and doc rot

**Do.**

- **Before deleting anything,** confirm it has no callers, with swift-lsp
  find-references or a grep for the name.
- **Remove what nothing uses:** `NoteEditor.canLink` (:1154),
  `InlineMarkup.isStyled` (DocumentNode.swift:255) and
  `DrawingSaveScheduler.setObjects` (:91).
- **Code that only tests use.** That is `BlockResultStore`
  (CodeBlockIdentity.swift:58), `CodeBlockAction.code(atCaret:)`,
  `DocumentStyler.applyStyling(to:rendered:)`, `DocumentStyler.headingFont`,
  `NoteTypography.isStandard`, `FormulaValidity.clearCache` and
  `InkSelectionOverlay.beginsDrawingForTest`. For each one, decide whether
  it is a test seam or dead. A seam goes behind `#if DEBUG` (the tests build
  Debug). A dead one goes, along with its tests. List each decision in the
  PR.
- **`ContentView.opensDebugNote` and `openedPage`** are always false or
  nil in Release; put them behind `#if DEBUG`.
- **Stale comments:**
  - DocumentStyler.swift:5 names a "FenceParser" that doesn't exist.
  - DocumentStyler.swift:159–168 says "deliberately not incremental" above
    code that is incremental.
  - CodeBlockAction.swift:102 says in-app Run is out of scope.
  - DocumentTextView.swift:187–190 repeats the same comment lines.
- **`docs/ROADMAP.md` › Known problems.**
  - "~400 Swift 6 isolation warnings" and "94 `UIWindow(frame:)`" are out
    of date: tests use `makeTestWindow`, and `SyntaxTheme` and `CaretTarget`
    are fixed. Replace those two with 0D's warning count.
  - "`FileDocument` is deprecated" is fixed: `ExportFolderDocument` is a
    `WritableDocument`. Remove it.

**Done when.** The build passes, and so does `check.sh` with the test count
changed only by the tests of what was removed. The PR lists each removal.

## 1D. Named constants for repeated numbers

**Do.** Give each repeated number one named constant **per meaning**, with
the value unchanged. Two 44s that mean different things get two names.

- **`44 * 0.2237`:** the icon corner radius (HomeView.swift:214,
  SettingsView.swift:370, 372).
- **A literal `44`:** where it means the hotbar button, use
  `Hotbar.buttonSide`. Where it is a tap target or an icon tile, give it its
  own name. Sites: FolderEditor:186, HomeView:213, 318, 408, NoteList:482.
- **The three 24pt gaps:** `printSheetGap`, `compressedGap` (PageLayout.swift
  :88, :91) and `printGutter` (CanvasGeometry.swift:94). Merge them only if
  they must stay equal; otherwise make each a named constant that says why
  it is 24.
- **Fade and badge timings** written inline, and the 0.5s tap-recency
  window (DocumentUITextView.swift:223, :278).

**Done when.** The build passes and so do the suites for the files touched.
The PR has a table of every constant, its value and its sites.

## 2S1. Pin every stored setting and id

Needs T1 (`SettingsTests` stops writing `UserDefaults.standard`).

**Do.**
- **Find every UserDefaults key.** Each is a `static let` on the type that
  owns it. Grep for `forKey:`, `AppStorage(` and `static let .*[Kk]ey`.
  There are about 38, and `SettingsTests.keysAreStable` (:18) pins 23 of
  them.
- **Pin each general key's string and its default value** as literals in
  `SettingsTests`. That includes these unpinned ones: `penSettings`,
  `highlighterSettings`, `inkPaletteSet`, `addPagesWhileDrawing`,
  `lastCodeLanguage`, `welcomeNoteMade`, `welcomeScreenShown`, `notePlaces`
  and `lastOpenedNote`.
- **Pin the Pro ones in `NoteCodeTests/Pro/ProKeysTests.swift`:**
  - the settings keys: the `ai*` keys, `adHomeVisits`, `runPanelWidth` and
    `runDisclosureAccepted`;
  - the bundle id;
  - the product ids (ProStatus.swift:67, TipJar.swift:53–55). The run
    proxy's `wrangler.toml` checks the same ones (`PRO_PRODUCT_IDS`,
    `BUNDLE_ID`).

**Done when.**
- Every key the app reads or writes is pinned with its default.
- Renaming any one fails a test. Check one by hand and say which in the PR.
