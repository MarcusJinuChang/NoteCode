# 2P. Page, ink and shell

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. The design is [update-2.md](update-2.md) ›
2P; this file is the briefs. Line numbers were checked on `main` at
`07a5c34` (4 Nov), before 2X and 2S2 changed PageDetailView; find the code
by name.

**When.** Wave 9, alongside 2T (different files). 2P1 and 2P2 are
`PageView` (1,611 lines), one at a time; 2P3 (PageDetailView) and 2P4
(ContentView, NoteList) can run beside them. Ink work is the most
trap-heavy in the plan: before touching it, read AGENTS.md's lines on
`InkCapture`, `onInkChanged`, `commitInk()`, `MarkupOrderedSet` and
`PKInk.inkType`, all of which apply.

**No device testing until the refactor is finished** (README › Marcus's
part). The Pencil lines each brief gives go on Marcus's list for his one
pass; they are the acceptance a simulator can't give.

## T5 tests for this track (each before its step, in its own PR)

| Before | Pin today's behaviour of | Notes |
|---|---|---|
| 2P4 | navigation: open a note, Home, the list in a compact width and back (`CompactScreen.path`, `SidebarPlan`); create from "+", from a template and from ⌘N; delete with Undo from the note (ContentView.swift:615–631) and from the list (NoteList.swift:772–793), and what each Undo reopens | No test names the toast's "Moved to Recently Deleted" today. `CompactLayoutTests` and `SidebarOnHomeTests` cover parts of navigation; extend, don't duplicate |
| 2P5 | the ink tool's settings round trip: pen and highlighter width and colour, eraser mode and size, finger draws, return to previous tool, selection kind, written by the hotbar and read back by Settings › Drawing and a new note | `SettingsTests` pins the keys; nothing tests `InkToolPersistence` (Ink/HotbarPrimitives.swift:22) by name. Use `TestDefaults` |

## 2P1. `PageInkPipeline` out of `PageView` (three PRs; perf; Pencil after each)

**Files.** PageView.swift: the ink state :152–175 (`inkState`,
`newestSnapshot`, `snapshotSerial`, `isCapturing`, `inkGeneration`,
`inkBottom`), the MARK "Ink" section :1016–1352 (`showInk` :1034,
`captureInk` :1175, `commitInk` :1211, `frames(of:)` :1299,
`withoutOverflow` :1314, `convert(_:from:to:)` :1337). Ink/InkCapture.swift
(372 lines) is the detached work `captureInk` hands to.

**The PRs**, each two commits (move, then the type):
1. `InkMarkupTransforms`: the static `frames`, `withoutOverflow` and
   `convert` as a caseless enum in `Ink/`. `PageView` keeps forwarding
   statics for `PageViewTests`.
2. `PageInkPipeline` holds the state and its generation; `PageView` owns
   one.
3. `showInk`, `captureInk` and `commitInk` move onto it; `PageView.commitInk()`
   forwards, since `NoteEditor.commitInk` and `PageDetailView` call it.

**Must not.** Walk a `MarkupOrderedSet` other than with `for … in`; build
one other than with one `append(contentsOf:)`; save ink from anywhere but
`onInkChanged`; read `PageView.ink` without `commitInk()` first; turn the
run loop in a test that waits for a capture (`await`, `waitFor` in TestSupport/InkHarness.swift:53);
drop the `inkGeneration` check that discards a stale result.

**Acceptance.** *Perf*: `PageViewTests/openingCost.open` and `.switch`,
`NotePDFTests/printingCost` within 10% of baseline.md:143–146.
`PageViewTests`, `InkPagesTests`, `InkSelectionTests`, `DrawingCanvasTests`,
`InkInsertTests`, `PaperKitSelectionRemovalTests`, `EditorLeakTests` pass.

**Pencil lines** (each PR). Draw quickly across a page break; erase with the
pixel eraser (it must not crash as the pen lifts); lasso and move strokes;
switch view mode with ink on the page; leave the note and reopen it: every
stroke is where it was. On a note with thousands of strokes
(`-debug-ink-file`), writing keeps up.

## 2P2. Scroll indicator, keyboard inset and zoom

**Files.** PageView.swift: "Keyboard" :309–342 and "Moving with the hotbar"
:343–459 (`applyKeyboardInset` :427) → `PageKeyboardInset`; "Zoom"
:1353–1408 (`zoomAtPinchStart` :186) → `PageZoom`; "The scroll indicator"
:1500–1576 → `PageScrollIndicator`. Two commits each, one PR for all three
or one per type (say which).

**Must not.** Change who owns scrolling (docs/design/who-owns-scrolling.md):
the text view doesn't scroll, the page does. Change the inset's animation
curve (it follows the keyboard's).

**Acceptance.** `KeyboardInsetTests`, `PageMotionTests`, `PageSettlingTests`,
`PageViewTests`, `CanvasGeometryTests` pass. Device line: pinch to zoom and
back, with the keyboard up and down; drag the scroll indicator on a long
note; dock the hotbar left and right and type.

## 2P2b. `PageView` under 600 lines (feature-audit.md › A9; after 2P2)

After 2P1 (about 340 lines out) and 2P2 (about 260) `PageView` is still
about 1,000 lines, and the release QA wants a reason for anything over 600.
**Two commits each:**
- `PageBands`: "Pages" :783–1015 (applying the layout, the bands between
  pages, the furniture, `addPage`).
- `PageReading`: "Reopening where the reader left off" :622–674, "Search"
  :675–711 and "Outline" :712–749.

**Must not.** Change the debug report's fields (DebugLaunch.swift's
`DebugStateReport` reads the page), where a note reopens, or where bands sit
in any view mode.

**Acceptance.** `PageViewTests`, `ReopenTests`, `PageSettlingTests`,
`PageLayoutTests`, `DebugLaunchTests` pass; `wc -l PageView.swift` under
600, or the PR says what is left and why. One launch with
`-debug-note pages -debug-mode print -debug-page 4 -debug-then-mode seamless -debug-report`:
the report matches one taken on `main` before the PR (both in the PR).

## 2P3. PageDetailView into its parts

PageDetailView.swift is 820 lines. After 2X and 2S2b it has lost Run, the
assistant and its `@AppStorage`s; what is left:

| Type | Today |
|---|---|
| `NoteHeader` | `headerItems` :422–471 (with what 2X5c left of the Run item) |
| `NoteMoreMenu` | `moreMenu` :472–556 |
| `PencilGestureRouter` | `respond(to:at:)` :737–761, `drop` :762–780, the Pencil environment :154–155 |
| `PageBadgeModel` | `badge`, `badgeVisible`, `badgeTimer` :166–168, `noteScrolled(to:)` :711–725, the fade timings :702–707 |

**Allocation.** `@State private var editor = NoteEditor()` (:51) and
`_inkSaver = State(initialValue: DrawingSaveScheduler(page:))` (:202) build
a new object on every `init`, which SwiftUI runs far more often than it
keeps the state. Make both lazy (an `@State` optional filled in `.task` or
`onAppear`, or a small holder), so `init` allocates nothing. A test counts
`NoteEditor` allocations across repeated inits.

**Must not.** Change the toolbar order or the menu's items; save ink or
bump `modifiedAt` while opening; F6 (`modifiedAt` on every keystroke,
:274) is a fix PR, not this.

**Acceptance.** `NotePageChromeTests`, `PageOverlayTests`, `EditorModeTests`,
`DrawingSaveSchedulerTests`, `CompactLayoutTests`, `EditorLeakTests` pass;
PageDetailView under 400 lines. Device line: double-tap and squeeze the
Pencil (each action in Settings); the page badge shows while scrolling and
fades.

## 2P4. ContentView and NoteList (takes over 1B6)

**Files.** ContentView.swift (656 lines): navigation :219–362 (`compactPath`
:30, the split view :225–236), "One editor per note" :363, import/export
:385, `newNote` :436 and :448, `delete(_:)` :615–631. NoteList.swift (829
lines): Rows :346–535, Menus :536–663, Bindings :664–714, Changes :715–820
(`deletePages` :772, `announceMoved` :784, `delete(_ folder:)` :795).

**Do.**
- `NavigationModel` (`@Observable`): selection, `compactPath`,
  `columnVisibility`, the opened search. `LaunchCoordinator`: the launch
  delay, the title screen, the Welcome note, `opensDebugNote`.
- **One `NoteActions`** for create and move-to-Recently-Deleted with Undo,
  used by ContentView and NoteList. **Which Undo wins: neither changes.**
  Today they differ: ContentView's (a note deleted from its own ••• menu)
  clears the selection, goes back to the list and, on Undo, reopens the
  note if nothing else was opened since; NoteList's (deleted from the list,
  one or many, the open note possibly among them) clears the selection and
  on Undo only restores. `NoteActions.moveToRecentlyDeleted(_:reopening:)`
  keeps both: ContentView passes the page to reopen, NoteList passes `nil`.
  Whether the list's Undo should also reopen an open note it deleted is a
  behaviour change: write it in the PR as a finding for Marcus, and it
  becomes a feature cleanup.
- **One layout-class value.** "Compact" is worked out five ways:
  ContentView.swift:34 and PageDetailView.swift:80 (`sizeClass == .compact`),
  HomeView.swift:78 (`HomeLayout.isCompact`, which adds a width),
  PageView.swift:505 (`traitCollection.horizontalSizeClass`) and
  CompactNavigation.swift:88. One `LayoutClass` in the environment, set
  once at the root, replaces the size-class reads; Home's width rule stays
  Home's, expressed on top of it; PageView's UIKit read stays (it can't see
  the environment) unless it can be handed the value.
- **NoteList's rows and menus become types** (1B6: as extensions they
  needed about 24 members loosened): `NoteRow`, `FolderRow`, `NoteMenu`,
  `FolderMenu`, each taking what it reads as `let`s and what it does as
  `NoteActions`.

**Leave the split view's `.balanced` / `.prominentDetail` `if/else`
(ContentView.swift:225–236) exactly as it is.** It depends on view
identity.

**Must not.** Change what any Undo restores or reopens; change the list's
drag and drop (`NoteListDrop`, `ListDragUITests` on the iPad only); delete
anything without saving at once (AGENTS.md: `moveToRecentlyDeleted` saves).

**Acceptance.** The T5 navigation and delete tests, `NoteListTests`,
`NoteListFirstRunTests`, `RecentlyDeletedTests`, `NestedFolderTests`,
`CompactLayoutTests`, `SidebarOnHomeTests`, `HomeSectionsTests` pass;
ContentView and NoteList each under 600 lines. Device line: delete a note
from its ••• menu and Undo (it reopens); delete it from the list and Undo
(it comes back, closed); fold and unfold the Duo with a note open; drag a
note into a folder.

## 2P5. One `InkToolStore` (after its T5 test)

The pen, highlighter, eraser and finger settings live in five places:
`NoteEditor.inkTool` (NoteEditor.swift:35), `InkToolPersistence`
(HotbarPrimitives.swift:22, six `@AppStorage`s :25–40), `InkSwatches`
(:81, `@AppStorage` palette :87), `DrawingSettings` (Ink/DrawingSettings.swift:15–21,
:120, :181) and `SelectOptions` (Ink/SelectionOptions.swift:13). One
`@Observable InkToolStore` reads and writes the keys (from 2S2a's tables),
and the five read it.

**Must not.** Change any key or encoding (`InkingSettings`' and
`EraserSettings`' text forms); change when the canvas gets a new tool.

**Acceptance.** The T5 round-trip test, `InkToolHandoverTests`,
`InkWidthStepTests`, `InkPaletteTests`, `FingerDrawsPersistenceTests`,
`SettingsTests` pass. Pencil lines: change width and colour in the hotbar,
then in Settings › Drawing, then open another note: each tool is as left;
finger draws on and off; the eraser's mode survives a relaunch.

## 2P6. Persistence

- **`Storage.save(_:reason:)`** logs a failed save with `os.Logger` in place
  of the swallowed `try?`s. Today 19 calls drop a persistence error
  (`grep -rnE "try\? .*(save|moveToRecentlyDeleted|delete|purge|restore)\(" NoteCode`):
  ContentView :606, :623, :626; NoteListDrop :152, :154; RecentlyDeletedView
  :196, :200, :204, :209, :218, :219; PageDetailView :350; NoteMemory :146;
  NoteList :703, :779, :791, :804, :811 (and WelcomeNote :145–146,
  `fetchCount`, which may stay). Behaviour stays: a failure still leaves the
  change pending for autosave.
- **`Page.settledID`** (NoteMemory.swift:144) is a getter that saves; it
  becomes `settledID()` or `settle() -> PersistentIdentifier?`. Four
  callers: ContentView:375, PageDetailView:580, NoteThumbnail:267,
  NoteMemory:131.
- **The model's extensions leave the frozen class files**: Page.swift
  :108–end and Folder.swift :80–end to `Page+….swift` and `Folder+….swift`.
  `ModelFreezeTests` proves the hashes don't change.

**Must not.** Change a stored attribute (the model is frozen); read
`drawingData` from a page whose deletion has been saved; make a deletion
stop saving at once.

**Acceptance.** `StorageTests`, `ModelFreezeTests`, `RecentlyDeletedTests`,
`NoteMemoryTests`, `FolderTests`, `NestedFolderTests` pass. A test that a
save failing (a stand-in context) is logged and doesn't throw.
