# The folder map (1A1)

Which folder each file in `NoteCode/` goes to in 1A2, and the tests' mirror in
1A3. Nothing moves in this PR. Starts from the table in
`git show f552d11:docs/refactoring.md` › Proposed folders, with the changes
[1-structure.md](1-structure.md) › 1A1 lists. Every one of the **156**
`NoteCode/*.swift` files is in exactly one row below
(`ls NoteCode/*.swift | wc -l` = 156). `Info.plist`, `PrivacyInfo.xcprivacy`,
`Assets.xcassets` and `Acknowledgements.txt` stay at the top of `NoteCode/`.

## Judgement calls

Each is a file the brief did not place, or one the old table placed
differently. The rule used: a file goes where its main type's callers are.

| File | Goes to | Why |
|---|---|---|
| `EditMenuOrder` | `Text/Editor` | Old table: `App/`. Its only caller is `DocumentTextView`. |
| `ReviewPrompt` | `App` | Old table: `Store/`. Callers are `ContentView` and `AdConsent`; it is not a Pro feature, so it stays out of `Pro/` and the public build keeps it. |
| `ReadsInput` | `Pro/Run` | Old table: `NotePage/`. The brief lists it under Run; its only caller is `RunPanel`. |
| `LastCodeLanguage` | `Code` | Old table: `Model/`. Not a model type: a per-device setting that ⇧⌘K reads, called only by `NoteEditor`. Sits with `CodeEditorSettings`. |
| `SelectionOptions` | `Ink` | Old table: `NotePage/`. It declares `SelectOptions`, called only by `InkToolbar`. |
| `SelectionShape` | `Ink` | Three of its four callers are ink files; the fourth is `TextRegionSelection`, which stays in `Text/Editor`. |
| `NoteTypography` | `Text/Editor` | Imports UIKit, so not `Text/Core`. Twelve callers across editor, page, PDF and thumbnails; the editor owns it. |
| `CodeSelectionHighlight` | `Text/Editor` | Callers are `DocumentTextView` and `CodeBlockLayoutFragment`, one each. Kept with the text view that draws it. |
| `CodeBlockLayoutFragment` | `Code` | Its name says layout, but it draws a code block, and the action bars and overlay are its neighbours. Not `Text/Layout`. |
| `CodeFenceDisplay` | `Code` | Callers are `DocumentTextView`, `CodeBlockLayoutFragment` and `HeadingMarkerDisplay`; UIKit, so not `Text/Core`. |
| `NoteSearch` | `Library` | Four callers: `ContentView`, `NoteList`, `PageDetailView`, `DocumentTextView`. The search over notes belongs to the list. |
| `NoteInfo` | `Model` | Pure value (Foundation only). Callers are `HomeView` and `NoteInfoView`, so it could be `Library`; kept with the other note-derived values, `NoteSort` and `NoteTitle`. |
| `NoteMemory` | `Model` | Imports SwiftData; ten callers across the app. |
| `FormulaValidity` | `Formula` | Imports SwiftMath, so not `Text/Core`, though `DocumentStyler` and `MarkdownLayout` call it. |
| `TeXAliases` | `Text/Core` | Old table: `Formula/`. The brief puts it in Core; it imports only Foundation. |
| `NoteTemplates` | `Library` | An extension on `Page`; callers are the list, home and the formula and text option rows. The templates are the "new note" menu. |
| `CanvasGeometry` | `NotePage` | CoreGraphics only; callers are `Hotbar`, `PageDetailView`, `PageView`. |
| `PencilResponse` | `NotePage` | SwiftUI; callers are `NoteEditor` and `PageDetailView`. |
| `DrawingCodec`, `DrawingSaveScheduler` | `Ink` | Old table: `Model/`. The brief moves ink storage to `Ink/`. |
| `ProSettings` | `Pro/Store` | Per the brief. Its only caller is `SettingsView`, so the public build needs a stand-in or a guard there; that is for the Pro split, not this map. |

## The map

| Folder | Files | # |
|---|---|---|
| `App/` | `NoteCodeApp`, `ContentView`, `CompactNavigation`, `NoteWindowControl`, `PageWindowChrome`, `WelcomeScreen`, `WelcomeNote`, `NoteShortcut`, `NoteCommands`, `ReviewPrompt` | 10 |
| `Shared/` | `Toast`, `Haptics`, `BarMaterial`, `FoldAvoidance` | 4 |
| `Model/` | `Page`, `Folder`, `NoteSchema`, `Storage`, `NoteMemory`, `NoteSort`, `NoteTitle`, `NoteInfo` | 8 |
| `Library/` | `HomeView`, `HomeSections`, `NoteList`, `NoteListDrop`, `NoteListSections`, `RecentlyDeletedView`, `FolderEditor`, `FolderAppearance`, `NoteIconGeometry`, `NoteIconView`, `NoteThumbnail`, `ListFoot`, `NoteSearch`, `NoteTemplates` | 14 |
| `NotePage/` | `PageDetailView`, `PageView`, `PageLayout`, `PageViewMenu`, `CanvasGeometry`, `EditorMode`, `NoteEditor`, `Hotbar`, `HotbarDock`, `TextOptionsRow`, `NoteTitleMenu`, `NoteInfoView`, `NoteOutline`, `NoteOutlineView`, `NoteShareButton`, `PencilResponse` | 16 |
| `Text/Core/` | `DocumentParser`, `DocumentNode`, `InlineParser`, `InlineTags`, `StyledLine`, `SpanStyle`, `TextColour`, `TypingStyle`, `MarkdownFormatting`, `MarkdownFormatting+Markers`, `MarkdownFormatting+Style`, `MarkdownFormatting+TextRow`, `MarkdownFormatting+Typing`, `CodeBlockIdentity`, `FenceVisibility`, `TeXAliases` | 16 |
| `Text/Editor/` | `DocumentTextView`, `DocumentTextView+Clipboard`, `DocumentUITextView`, `DocumentStyler`, `TextRewritingPolicy`, `RichCopy`, `RichPaste`, `CaretAnywhere`, `HeadingMarkerDisplay`, `MarkerDimming`, `MarkerTaps`, `TextRegionSelection`, `NoteTypography`, `CodeSelectionHighlight`, `EditMenuOrder` | 15 |
| `Text/Layout/` | `MarkdownLayout`, `ProseBlocks`, `ProseLayoutFragments`, `BlankLineLayout` | 4 |
| `Code/` | `CodeBlockAction`, `CodeBlockActionBar`, `CodeBlockLanguageButton`, `CodeBlockLayoutFragment`, `CodeBlockOverlay`, `CodeBlockRoom`, `CodeFenceDisplay`, `CodeIndent`, `CodeKeys`, `CodeKeysRow`, `CodeEditorSettings`, `CodeOutputPanel`, `CodeDestination`, `SyntaxHighlighter`, `HighlightSwiftHighlighter`, `SyntaxTheme`, `LastCodeLanguage` | 17 |
| `Formula/` | `FormulaAttachment`, `FormulaEditing`, `FormulaEditor`, `FormulaValidity` | 4 |
| `Ink/` | `DrawingCanvas`, `DrawingCodec`, `DrawingSaveScheduler`, `DrawingSettings`, `InkCapture`, `InkColorPicker`, `InkInsert`, `InkObjectTable`, `InkObjects`, `InkPages`, `InkSelection`, `InkSelectionOverlay`, `InkTool`, `InkToolbar`, `SelectionShape`, `SelectionOptions` | 16 |
| `InOut/` | `NotePDF`, `ExportAll`, `ImportFiles`, `NoteInterchange` | 4 |
| `Settings/` | `SettingsView`, `AppSettings`, `AccentPalette` | 3 |
| `Debug/` | `DebugLaunch`, `DebugProbe`, `SelectionProbe` | 3 |
| `Pro/Store/` | `ProStatus`, `ProSettings`, `PaywallView`, `TipJar`, `TipJarView` | 5 |
| `Pro/Ads/` | `AdBanner`, `AdConfig`, `AdConsent` | 3 |
| `Pro/Run/` | `RunJob`, `RunPanel`, `RunServiceClient`, `RunSession`, `RunRouting`, `CompilerMessages`, `JavaMain`, `ReadsInput` | 8 |
| `Pro/Assistant/` | `AIAssistant`, `AIFeatures`, `AIInsertion`, `AIPrompts`, `AIResultSheet`, `SystemTextModelClient` | 6 |
| **Total** | | **156** |

`Text/Core` imports only Foundation, checked from each file's `import` lines
(the other `Text` files, `NoteTypography` and `CodeFenceDisplay` among them,
import UIKit). `Pro/` is everything the public open-source build leaves
out; `CodeDestination` and `CodeOutputPanel` stay in `Code/`.
