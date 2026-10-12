# Implementing NoteCode v3: brief for an agent

Written 12 Oct 2026, against `claude/ui-phase-9-finishing` at `561b87a`, with
v2's phases 7–9 treated as merged. Hand this whole file to the agent as its
task, one phase at a time.

v3 is **v2 finished**, not a new direction. It adds a home screen and a title
screen, fills the holes a TestFlight tester would hit first, and reworks what
v2 left thin. The goal is one TestFlight build on Sat 17 Oct, iPad only, with
iPhone and the Duo to follow by the November submission.

## Run settings

| | |
|---|---|
| Model | Sonnet 5.5 (`claude-sonnet-5-5`), every phase |
| Effort | **high** |
| Sessions | One new chat per phase. No subagents, no multi-agent workflows |
| Branches | One branch and one PR per phase (`claude/v3-phase-N-<topic>`). Branch from `main` if the previous phase has merged, else from the previous phase's branch |

**Why high.** The design is settled, so open-ended research would be wasted.
But phases 3, 4, 5 and 6 touch the code AGENTS.md is most careful about:
TextKit 2's lazy layout, ink that has to stay on its words, taps inside a
`UITextView`, and the note's fonts. If a phase's first approach fails twice,
stop and report rather than trying a third. Phase 3's probe and Phase 6's
size refactor are where that's most likely.

### Starting a phase's chat

Paste this, with N and the base branch filled in:

> Implement Phase N of `docs/ui-design-v3-implementation.md` in the NoteCode
> repo. Read the brief's sections before "Phases", then Phase N, then
> AGENTS.md in full. Branch `claude/v3-phase-N-<topic>` from `<base>`. Read the
> canvas boards Phase N names. Stop at Phase N's "Done when": open the PR, but
> don't merge.

Each chat starts cold, so everything a phase needs is in this file, AGENTS.md
and the code. Nothing relies on another chat's memory.

---

## The design

**Canvas:** <https://claude.ai/artifact/QR1E8Fm6YU8a7YBFLvh7nc>. It is built
on v2's canvas (<https://claude.ai/artifact/8R5rgZmdLaW4kH1CjUiX8i>), whose
tokens still hold. Read the boards with the Artifact tool (`read`,
`path: "project/<Board>.dc.html"`). **Where the canvas and this brief
disagree, this brief wins.**

| Board | Shows |
|---|---|
| `Main` | Title screen, first launch |
| `Home`, `HomeEmpty` | Home in the page area, and Home with no notes |
| `Library` | List rows with thumbnails, the Home row, folder identity, the folder editor, Recently Deleted, the toast |
| `NotePage` | The hanging heading marker, the outline, the page badge, hotbar state, a checklist, a link |
| `Markers` | How Markdown markers are hidden, and why |
| `TextRow` | The text options row: text size, and the paragraph at the caret |
| `Writing` | List ▾, Return, checklists, links |
| `Code` | The keys row, auto-indent, languages, line numbers, output blocks |
| `Ink` | Insert, grid paper, ••• › Paper |
| `InAndOut` | Templates, Share ▾, Import, Export All, toasts |
| `Settings` | New rows (the `v3` tags on the board aren't in the app) |
| `iPhone` | A sketch for November. Not built this week |

## Before writing code

1. **Read AGENTS.md in full.** At minimum, take in these sections: "Who owns
   scrolling", "Pages" (all of it), "The note page", "Code-block fences",
   "Implementation requirements", "The model and its versions", "Shipping",
   "Build/test" and "Debug launch options".
   - Reading `.layoutManager` silently downgrades the text view to TextKit 1.
   - Anything that edits the text storage after a keystroke costs a full
     layout below the caret.
   - Ink lives in page coordinates.
2. Read `docs/ROADMAP.md` "Where things stand" for what has merged.
3. Read the files each phase names before changing them. The comments in this
   codebase explain *why*; keep that style.

## Working with Marcus

- **He is learning iOS while building this.** In each PR description, explain
  the mechanics of what you did and why, not just what changed.
- **He tests on-screen behaviour himself.** Keep any simulator check under
  about ten minutes. Past that, stop and put a checklist in the PR: what to do
  on the iPad, what should happen, and what would count as a bug.
- **Never say something is verified on screen when it wasn't.** Say plainly
  what you didn't check.
- **Prove regression tests.** Revert the fix and confirm the test fails; a
  test that passes both ways isn't a test.
- **Check drawing properly.** Look at anything that draws in light and dark,
  with content that could show the bug: descenders, long lines, a block at a
  page break, a stroke over formatted text.
- **Leave merging to him.** Don't merge. Don't run an older branch on his
  iPad.

## Build and test

```bash
xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -parallel-testing-enabled NO
```

- Also build the macOS destination. The target must keep compiling there,
  even where a feature is iPad-only (`#if canImport(UIKit)`, as elsewhere).
- Tests use Swift Testing.
- For a quick screenshot, `scripts/debug-launch.sh` puts the app in a known
  state. Phase 2 adds `-debug-first-launch` and `-debug-home`.

---

## Reconciliations: canvas vs code

| On the canvas | Do this |
|---|---|
| Outline is a header button, left of Share | Build it there, plus ⌃⌘O |
| The Insert popover | It is PaperKit's `MarkupEditViewController`. Present it; don't redraw it. Add Photo… through its `additionalActions` |
| Thumbnails in list rows, 30 × 39 | The first page, as `NoteThumbnail` draws it, at that size |
| The toast | Above the hotbar when a note is open; at the list's foot otherwise. Gone after 4s; VoiceOver announces it |
| Home's folder tiles: three, then New Folder | The grid wraps as folders are added, four per row |
| `v3` tags in Settings | Not in the app |
| A bare URL in a note | Shown exactly as typed. Only `[text](url)` hides syntax |
| The "1 / 5" badge | Top centre of the page area, 18pt under the header. Shown while scrolling, fades 1s after the scroll stops |
| `HomeEmpty` | What Home shows when the store has no live notes |
| `TextRow`: the stepper reads `+ 17 −` across, and `+` over `17` over `−` down | Marcus's order. Keep it, even though `−` usually comes first |
| AGENTS.md and the v2 brief: "never settings, on purpose: note text size" | Decided 12 Oct (Marcus): text size becomes a property of each note, set from the text options row, and a note with ink asks first. It is still never an app-wide setting, and still never follows Dynamic Type. Record this in AGENTS.md beside Phase 9's "The note body does not follow Dynamic Type" |

---

## Model v7

The store is at version 6. **v7 is v3's only model change**; if you find you
need another, stop and ask.

| Field | Type | Meaning |
|---|---|---|
| `Page.deletedAt` | `Date?` | Set means the note is in Recently Deleted |
| `Page.paperStyle` | `String?` | `plain`, `dots` or `grid`; nil means plain |
| `Page.markdownLayout` | `String?` | `rendered` (markers collapse), or nil, the legacy layout with visible markers |
| `Page.textSize` | `Int?` | The body size in points: 14, 15, 16, 17, 19, 21 or 23. Nil means 17, today's size |
| `Folder.colorName` | `String?` | One of the eight folder colours; nil means orange |
| `Folder.symbolName` | `String?` | An SF Symbol from the folder editor's set; nil means `folder` |

- **Freezing v6.** Freeze v6's classes in `NoteSchema.swift`, as v5 was frozen
  for v6. The live classes in `Page.swift` and `Folder.swift` become v7's, and
  a lightweight stage v6 → v7 joins `NoteMigrationPlan`.
- **CloudKit shape.** Everything optional, nothing unique.
- **`markdownLayout` on migration.** A note whose `drawingData` is empty
  becomes `rendered`. A note with ink stays nil (see "Hiding Markdown
  markers"), and every new note is `rendered`.
  - This can't be a lightweight mapping, so either use a custom stage, or set
    it on first launch after migration from a pass over the store.
  - Whichever you choose, it must not touch `modifiedAt`.
- **Tests:** `SchemaMigrationTests` writes a v6 store and opens it through
  `Storage` (never a container built some other way). Assert notes, folders,
  pins, locks, ink bytes and the `markdownLayout` rule.

---

## Design tokens added in v3

v2's tokens (accent, page, surround, code panel, syntax, ink palettes, logo)
are unchanged, and already in the code:

- `AccentColor.colorset`
- `SyntaxTheme`
- `InkColor`
- `PageView.pageColor` and `surroundColor`
- `NoteCodeMark`

AGENTS.md "Colour" describes them.

**Folder colours.** The tint sits behind the symbol. Symbol on tint must be at
least 3:1 in both appearances; a test computes it, as `SyntaxThemeTests`
does.

| Name | Base | Light tint | Light symbol | Dark tint | Dark symbol |
|---|---|---|---|---|---|
| Orange (default) | `#FA8500` | `#FFE9CF` | `#B85900` | `#3D2400` | `#FFAA33` |
| Red | `#DA101E` | `#FBE0E2` | `#B00D18` | `#3D0A0E` | `#FF6B74` |
| Yellow | `#EBB000` | `#FBF1CC` | `#8A6700` | `#3A2E00` | `#FFD54D` |
| Green | `#27A551` | `#DDF2E4` | `#1C7A3B` | `#0E3019` | `#5AD884` |
| Blue | `#066EE5` | `#DCEBFC` | `#0A5BBF` | `#0A2340` | `#6CB6FF` |
| Teal | `#00727A` | `#D6EDEE` | `#00727A` | `#00282B` | `#5ED0D6` |
| Purple | `#8E22C3` | `#F1E4F9` | `#7A1CA8` | `#2C0E3D` | `#C39BFF` |
| Graphite | `#6C6C70` | `#E9E9EB` | `#55555B` | `#2C2C2E` | `#AEAEB2` |

**Folder symbols**, 16, in this order:

- `chevron.left.forwardslash.chevron.right`, `terminal`, `cpu`, `sum`
- `point.3.connected.trianglepath.dotted`, `cylinder`, `book.closed`, `flask`
- `globe`, `graduationcap`, `lightbulb`, `number`
- `chart.xyaxis.line`, `function`, `curlybraces`, `folder`

The canvas draws stand-ins for some of these; use the SF Symbols.

**Other new tokens**

| Token | Light | Dark |
|---|---|---|
| Hanging heading marker | `secondaryLabel` | `secondaryLabel` |
| Checkbox, unchecked | 2pt `tertiaryLabel` stroke, 6pt radius | same |
| Checkbox, checked | accent fill, white tick | same |
| Checked item text | `secondaryLabel`, struck through | same |
| Link text | `#B85900`, underlined | `#FFAA33`, underlined |
| Output panel | `#141416` fill, `#E5E5EA` text, label `#A1A1A6` | `#2C2C2E` fill, `#F2F2F7` text, label `#8E8E93` |
| Paper lines and dots | `#E6E9EF` | `#2A2C31` |
| Paper spacing | 24pt in page units, from the page's top-left margin corner. Grid lines 0.5pt; dots 1.2pt radius | same |
| Toast | white at 94% (`.regularMaterial` is fine), 1px separator, 40pt tall, 15pt text | material in dark |
| Text options row | The ink options row's look (`OptionsRowStyle`): 40pt to the eye, 44pt reach, glass. The size number sits on a `secondarySystemFill` pill. The current choice is tinted the way a selected tool is | same |

---

## Phases

Each phase lists what to build, then **Done when**. Write the tests named, and
add others wherever the logic is pure.

### Phase 1: model v7, Recently Deleted, folder identity, Duplicate

- **Model v7**, as above.
- **Recently Deleted**
  - **Soft deletes.** Every delete sets `deletedAt` instead of deleting:
    the list's swipe, the title menu's Delete, and a folder deleted along
    with its notes. Deleting no longer asks; a toast with Undo follows.
    `Page.delete(_:from:)` stays, for purging.
  - **One predicate.** A single helper (`Page.isLive`, or a `#Predicate`
    factory) filters every view of notes:
    - `NoteList` and `NoteListSections`, `NoteSearch`, Home, folder counts;
    - `NewNotes.folder(whileViewing:)` and Export All.
    The first-launch Welcome check counts deleted notes too, so a store
    holding only deleted notes isn't a first launch.
  - **The view.** A Recently Deleted row sits at the list's foot, shown only
    when it has notes. It opens a view whose rows offer Restore and Delete
    Now; Delete All… asks first.
  - **Restoring.** A restored note whose folder is gone goes to the top
    level. Deleting and restoring keep `modifiedAt`.
  - **Purging.** At launch, notes deleted more than 30 days ago go through
    `Page.delete(_:from:)`. Never read `drawingData` from a page whose
    deletion has been saved (AGENTS.md).
- **Folder identity.** A folder editor sheet (name, colour, symbol, live
  preview) replaces the name alert for New Folder and a folder's Rename. Rows
  and Home tiles show the symbol on its tint.
- **Duplicate** in `NoteTitleMenu`, so it reaches both the list and the title.
  - Copies `content`, `drawingData`, `pageOrientation`, `paperStyle`,
    `markdownLayout`, `textSize`, the folder and `runDestination`.
  - Leaves out the pin and the lock. Dates are new. The title becomes
    "<title> copy".
- **Done when:**
  - The migration test passes.
  - Each view filters deleted notes, with a test per view that fails when its
    filter is removed.
  - Purge age, restore to the top level, and Duplicate's ink bytes are
    tested.
  - The macOS build compiles.
  - Marcus's checklist covers: delete, Undo, delete again, restore; delete a
    folder with notes; the editor sheet in both appearances.

### Phase 2: title screen, Home, thumbnails, reopen at the last page

- **Title screen** (`WelcomeScreen`).
  - A full-screen cover on first launch, under flag `welcomeScreenShown`. Set
    the flag either way, as `WelcomeNote.madeKey` is.
  - Shows the mark (`NoteCodeMark`), the wordmark, a tagline, three feature
    rows and Get Started, which leads to Home.
  - Settings › Help and About › Welcome Screen shows it again. Under Reduce
    Motion it fades.
  - The launch screen stays plain (`AppStoreReadinessTests.launchScreenIsPlain`).
- **Home** (`HomeView`).
  - Replaces the `ContentUnavailableView` in `ContentView`'s detail. The app
    opens on Home with the list hidden; ☰ brings the list.
  - Sections come from a pure `HomeSections`, like `NoteListSections`:
    - **Continue:** the note last opened on this device, with "page N of M".
    - **Recent:** about 8 notes by `modifiedAt`, excluding Continue's.
    - **Folders:** tiles. A tap opens the list with that folder expanded.
    - **Actions:** New Note, From Template, Import. Phase 5 builds From
      Template and phase 7 builds Import; until then their buttons don't
      exist.
  - `HomeEmpty` is shown when no live notes exist.
- **A Home row** sits at the top of the list and clears the selection. Bind
  ⇧⌘H only if the system leaves it free; check that, don't assume it.
- **Thumbnails** (`NoteThumbnail`).
  - The first page only, drawn the way the PDF draws a sheet (`PrintedNote`,
    `NotePDF.drawInk`), in light appearance.
  - **Never lay out the whole note.** Feed the printed text view a prefix of
    the text long enough for one page, and only the ink that touches page 1.
  - Cached in Caches as `<persistentID>-<modifiedAt>.png`. That naming needs
    no file-timestamp API, so no privacy-manifest entry.
  - Made lazily for cards on screen, one per turn of the main actor, and
    refreshed when a note closes.
- **Reopen at the last page.**
  - Per device, the last page each note was read at, keyed by its persistent
    ID (UserDefaults).
  - Restored with `PageLayout.scrollTop(forPage:)` after the first layout, the
    way `PageView.reveal` waits for it.
  - Test the line at the top against a note laid out from scratch, never the
    scroll offset against page geometry (AGENTS.md).
- **Debug launch:** `-debug-first-launch` (a fresh in-memory store with the
  flags cleared) and `-debug-home`.
- **Done when:**
  - Tests cover the flag, `HomeSections`, a thumbnail of a 2,000-line note
    made within a measured budget without laying out past page 1, the cache
    key changing with `modifiedAt`, and the reopen.
  - Marcus's checklist covers a fresh install, Home light and dark, and
    thumbnails updating.

### Phase 3: writing, starting with hiding Markdown markers

#### Hiding Markdown markers (the `Markers` board)

**The constraint.**

- A marker that appears or disappears as the caret moves shifts the words
  after it, and can re-wrap the lines below. Ink stays where it was drawn.
- Any layout change also lays out the rest of the note again (66ms on a
  500-line note).
- So whether a marker takes space must never depend on the caret.

**Collapse, in layout only.**

- `BlankLineLayout` already swaps a blank line for a zero-width space in the
  paragraph TextKit lays out (`NSTextContentStorageDelegate`). Extend it, or
  wrap it in a `MarkdownLayout`, so that in `rendered` notes it also swaps
  marker characters for U+2060 WORD JOINER. That's zero width with no line
  break, and the same length, so offsets map straight through.
- Collapse:
  - heading markers: the `#`s and the space after them;
  - the markers of complete inline spans: `**`, `*` or `_`, backticks, `~~`;
  - link syntax: `[` and `](url)`.
- Bullets `-`, `*` and `+` lay out as `•`. A checkbox's `[ ]` or `[x]` lays
  out as an em space plus two joiners, and the box is drawn in the em space.
- Take the ranges from `DocumentStyler.layouts` (`blockMarkers` and each
  inline's `markers`), so layout and styling can't disagree. Nothing inside a
  code block collapses; inline code collapses only its backticks.
- The swap is state-independent: same output whatever the caret, mode or
  setting.
- A joiner keeps its run's font, so line heights and caret heights don't
  change.
- Legacy notes (`markdownLayout` nil) keep today's layout. In them, swap only
  blank lines.

**Reveal, by drawing only.**

- **Headings.**
  - A `HeadingLayoutFragment`, returned by the layout manager delegate as
    `CodeBlockLayoutFragment` is, widens `renderingSurfaceBounds` into the
    left margin (the container is inset by `PageLayout.margin`).
  - It draws `#`, `##` or `###` in `secondaryLabel`, right-aligned 8pt left
    of the text, on the first line's baseline.
  - Shown while the caret is on that heading (Show Markdown › While Editing),
    or always (Always). Hidden in ink mode, and never printed.
  - Redraw on caret moves the way fences do: ask the coordinator at draw time
    and `setNeedsDisplay` only the fragment views whose state changed. No
    layout.
- **Inline formatting.** The hotbar's Bold, Italic, Inline Code and
  Strikethrough, and Style ▾'s heading level, show the state at the caret
  (`NoteEditor` publishes it on selection change). Inline markers are never
  drawn in place.

**Editing collapsed markers.** The rules are pure functions in
`MarkdownFormatting`; the hooks go in `DocumentUITextView` and the
coordinator.

- **Caret stops.**
  - A collapsed run is one caret stop. For inline runs the stop is the run's
    left edge, so typing at the end of a bold word stays bold and typing at
    its start doesn't.
  - For a heading marker the stop is after it.
  - Apply in `closestPosition(to:)` (as `blankLine(before:tappedAt:)` does),
    on selection change in the direction of travel, and on arrow keys. Only
    for zero-length selections; a selection may span markers.
- **Backspace.**
  - Into a closing run, it deletes the last visible character inside the
    span. An emptied span loses its markers.
  - At the start of a heading's text, it removes the marker.
  - Both go through `replace(_:withText:)`.
- **⌘B, ⌘I, ⌘E, ⇧⌘X** recognise markers just outside the selection, since a
  double-tap selects the word without them.
- **The title menu** gains Hide Markdown Markers… for legacy notes. It asks
  first, with the `Markers` board's wording, then sets `rendered`.

**The probe comes first, at most 1 hour, written as tests.** With the
word-joiner swap:

1. Line frames of a heading, and of a paragraph with bold, code and a link,
   equal those of the same text with the markers deleted.
2. Caret rects next to a run are full height.
3. Where `closestPosition` and a double-tap land.
4. A marker drawn at negative x is unclipped, in seamless and on a
   print-layout sheet.
5. A keystroke in such a paragraph costs no more (`typingCost`), and a caret
   move into a heading lays nothing out (count at the layout delegate, as
   `CodeFenceCostTests` does).
6. The delegate sees the current parse during the edit that changes it.

**If word joiners misbehave in text input**, fall back to a tiny clear font
set by the styler, with `caretRect(for:)` overridden to the line's height.
Report before switching.

#### The rest of Phase 3

- **Return.**
  - Return in a list item continues it: bullet, next number, or empty box.
  - Return on an empty item ends the list. Tab and ⇧Tab nest and un-nest
    items.
  - Built as pure `TextEdit`s in `MarkdownFormatting`, applied from
    `shouldChangeTextIn` (`DocumentTextView.swift:601`, returning false)
    through `replace(_:withText:)`. Never during marked text. Undo is one
    step.
- **List ▾** gains Numbered and Checklist.
- **Checklists.**
  - `- [ ]` and `- [x]` become a `ListMarker` case in `DocumentParser`.
  - In text mode a tap on the box toggles it through
    `replace(_:withText:)`, without moving the caret. Hook it the way
    `placeCaretOnTappedBlankLine` is hooked.
  - Checked items are struck through in `secondaryLabel`.
  - In legacy notes the box is drawn over the `[ ]` glyphs.
- **Links.**
  - `[text](url)` and bare `http(s)://` URLs, in `InlineParser`.
  - A tap opens Safari. Holding shows the address with Open Link and Copy
    Link.
  - Spike first, 30 minutes at most: does
    `textView(_:primaryActionForTextItem:defaultAction:)` fire in this
    editable TextKit 2 view? If not, use the checkbox tap path.
- **Done when:**
  - The probe's tests stay as regression tests, and the line-frame equality
    test fails if the swap is removed.
  - Caret-stop and backspace rules are tested as tables.
  - The list-continuation table, and parser cases for checkboxes and links,
    are tested.
  - `typingCost` is no worse.
  - Marcus's checklist covers the `Markers` board's iPad steps and real taps
    on boxes and links (AGENTS.md: a button inside a `UITextView` is not
    simply a button).

### Phase 4: code

- **Code-keys row.**
  - An `inputAccessoryView` while the caret is in code
    (`TextRewritingPolicy.at`), swapped with the input-view reload that
    already happens on crossing.
  - Keys: ⇥, ⇤, `{ } ( ) [ ] < > ; = " ' : / \ | & * #`, ← and →, inserted
    through `replace(_:withText:)`.
  - Hidden with a hardware keyboard. Check how to detect one (`GCKeyboard`);
    don't assume.
  - Looks like the ink options row. Settings › Code › Code Keys turns it off.
  - `CanvasGeometry.keyboardInset` must include the row.
- **Auto-indent.**
  - Return in code keeps the line's indent, and adds a level after `{`, `(`,
    `[` or a Python `:`. Between `{` and `}` it splits the braces onto their
    own lines.
  - ⇥ and ⇧⇥ indent or outdent the selected lines (hardware Tab through
    `keyCommands`).
  - Settings › Code › Indent Width: 2 or 4, default 4.
- **Languages.**
  - C, JavaScript, Rust, Go and SQL join `CodeLanguage`.
  - Each needs tags, display name, highlight.js name, `SyntaxThemeTests`
    contrast, and run mapping in `CodeDestination`.
  - Pin and check Compiler Explorer ids on the live site, as `g142` and
    `python313` were. SQL gets Copy only.
  - Code Block ▾ and the language button list them.
- **Line numbers** (Settings › Code › Line Numbers, off by default).
  - `CodeBlockLayoutFragment` draws them in the left margin, right-aligned
    beside each code line (not fence lines), in `secondaryLabel` monospaced
    digits.
  - Never a gutter inside the panel; that would re-wrap code and move ink.
  - Printed when on.
- **Output blocks.** ` ```output ` uses the output panel tokens, with the
  label "Output", Copy and no Run. It's in Code Block ▾.
- **Done when:**
  - Indent tables for C++, Java and Python pass.
  - The row's key set by region is tested.
  - New languages parse, highlight and give run URLs.
  - A line-number pixel test passes, and a line-frame test shows nothing
    moves with numbers on.
  - `keyboardInset` is tested with the row.
  - `typingCost` is no worse.

### Phase 5: insert into ink, paper, templates

- **Insert**, a tool after Lasso.
  - Present `MarkupEditViewController(supportedFeatureSet: .latest,
    additionalActions: [Photo…])` as a popover. The canvas is already
    `.latest` (`DrawingCanvas.swift:119`).
  - Photo…: `PhotosPicker`, then `PaperMarkup.insertNewImage`. Downscale to
    at most 2× the page width, and place at the visible page's centre.
  - Check elements that aren't strokes through `InkCapture`, `InkPages`
    (they move whole, by their middle's page), undo, saving
    (`onInkChanged`) and the PDF.
- **Paper.**
  - Per note (`Page.paperStyle`). The default is Settings › Notes › Paper; a
    note changes it from ••• › Paper.
  - Drawn beneath text and ink, only in each page's region, never in the
    bands. No layout effect.
  - `PageViewTests.coversMatchThePage` must still pass, so covers draw
    nothing extra.
  - Printed faintly.
- **Templates** (`NoteTemplates`, text only, like `WelcomeNote`).
  - Lecture, Problem and Lab, with their contents as on the `InAndOut`
    board. Bracketed words are placeholders.
  - Offered from + › From Template › and Home.
  - The code block's tag is the folder's most common language, else C++.
- **Done when:**
  - A shape, a text box and a photo survive saving, reopening, a mode switch
    and the PDF.
  - Paper has pixel tests in both appearances, and a line-frame test shows
    nothing moves.
  - Templates parse with their headings and code block.

### Phase 6: navigation, and the text options row

- **Outline.**
  - A header button and ⌃⌘O open a popover of the note's headings
    (`DocumentParser`), indented by level, with the current one marked.
  - A tap scrolls there through `PageView.reveal`'s path.
- **Page badge**, as in the reconciliations above, from `PageView.pageCount`
  and the page at the top.

#### The text options row (the `TextRow` board)

- **Placement.**
  - Text mode's counterpart of the ink options row. It uses the same
    `BesideBar` layout: 8pt from the bar on its page side, centred along it,
    in `OptionsRowStyle`.
  - It reserves nothing: `HotbarLayoutTests`' page-frame test still passes in
    both modes and on every dock.
  - Slides in with text mode; cross-fades under Reduce Motion.
  - Hidden in ink mode, on a locked note, and while a sheet covers the page.
  - Vertical when docked left or right.
- **With the keyboard up**, docked at the bottom, `keyboardClearance` adds
  the row's height, so the caret's line stays above it.
- **The text size stepper** comes first: `+`, the size, `−` (vertically, `+`
  over the size over `−`).
  - **Steps:** 14, 15, 16, 17 (the default), 19, 21 and 23. These are the
    system's body size at the content size categories xS, S, M, L, xL, xxL
    and xxxL.
  - **Fonts.** Built by `DocumentStyler.fixedFont(for:)`'s mechanism, with the
    note's category in place of `.large`, so every style keeps the system's
    leading at that size. Phase 9 measured what `systemFont(ofSize:)` without
    leading does to page breaks. Headings use their own text styles at that
    category; code is monospaced at the body's size.
  - **Controls.** Tapping the number shows the list; `+` and `−` are disabled
    at the ends. ⌘+ and ⌘− (Bigger, Smaller), if the system leaves them free.
  - **Not an edit.** Stored in `Page.textSize`; `modifiedAt` stays, and
    nothing goes on the text undo stack.
  - **Applying a size** restyles and re-lays out the whole note. Treat it as
    a re-wrap: keep the reader's place by line, as an orientation switch does
    (AGENTS.md, "The reader's place survives a switch" and "Get the page
    count right before the bands"). Steps settle after 300ms, so a run of
    taps lays out once.
  - **Ink.** A note with ink asks first, in the board's wording, once each
    time the note is opened. A note without ink changes at once.
  - **Everything that reads the note's fonts takes its size:**
    - the styler: `proseFont`, `codeFont`, `headingFont`, the attribute sets
      and typing attributes;
    - the list marker width cache, keyed by size;
    - the hanging heading marker;
    - `PrintedNote` and `NotePDF`, and `NoteThumbnail`;
    - the debug report.
  - **A value, not a global.** Hold the size as a value the coordinator owns
    (a `NoteTypography`), so a PDF or thumbnail made while another note is
    open uses its own note's size.
- **The rest of the row follows the caret,** from the parse at the caret:
  - **Paragraph or heading:** Body, H1, H2, H3 (the current one tinted), then
    Link.
  - **List item:** bullet, numbered, checklist (the current one tinted), then
    ⇤ and ⇥.
  - **Code block:** the language (a menu, the language button's list), ⇤ and
    ⇥, then + Output.
  - **How they edit.** Each does what Style ▾, List ▾, the language button
    and the indent edits from Phases 3–4 already do, through
    `replace(_:withText:)`. Nothing edits text another way.
    - Link wraps the selection, or the word at the caret, as `[text](url)`,
      asking for the address in an alert.
    - + Output inserts an empty ` ```output ` block after the code block.

**Done when:**

- The outline matches the parser, and a tap puts that heading's line at the
  top. Test the line at the top, not the offset.
- **Text size:**
  - Fonts at each size match `preferredFont(forTextStyle:compatibleWith:)`
    at that category, and nil gives exactly today's fonts: today's line
    frames don't move.
  - A size change keeps the top line, tested against a note laid out from
    scratch.
  - The ink question appears only for a note with ink.
  - The PDF and a thumbnail use the note's size.
- **The row:** `HotbarLayoutTests` passes with it, and each contextual
  control's edit is tested.
- `typingCost` at 17 is no worse.
- **Marcus's checklist:**
  - each dock edge in text mode;
  - the keyboard up on an 11-inch iPad in landscape;
  - a size change on a note with ink and on one without;
  - undo after a style chip.

### Phase 7: getting notes in and out, and windows

- **Share ▾** (`NoteShareButton`). A tap shares the PDF, as now. Holding
  offers Markdown (`.md`, text only), Copy as Markdown and Print… (⌘P).
- **Export All** (Settings › Notes and the list's •••).
  - `fileExporter` of a folder: a subfolder per folder, an `.md` per note,
    and optional PDFs with ink.
  - Progress is shown, the export can be cancelled, and deleted notes are
    left out.
- **Import** (Home and the list's •••).
  - `fileImporter` for `.md`, `.txt` and source files (`.cpp .cc .h .hpp .c
    .java .py .js .rs .go .sql`).
  - Markdown and text come in as written. A source file becomes one fenced
    block tagged from its extension, titled from the file name.
  - New notes go into the open folder, using security-scoped access.
- **Two windows.** A note already open in one window shows "Open in another
  window" in a second, so two editors never write one note. The fallback, if
  short on time, is `UIApplicationSupportsMultipleScenes = NO` for
  TestFlight 1.
- **Done when:**
  - Markdown export equals `content`.
  - Export All's folder layout is tested.
  - Import's tagging and titles are tested.
  - The same-note guard is tested.

### Phase 8: settings, toasts, polish, ship prep

- **Settings,** as on the `Settings` board. Pin every key in
  `SettingsTests.keysAreStable`.
  - Notes: Paper, Recently Deleted, Export All Notes….
  - Writing: Show Markdown, with the new footer.
  - Code: Code Keys, Indent Width, Line Numbers.
  - Help and About: Welcome Screen, plus Send Feedback and Privacy Policy
    once `AppInfo.feedbackAddress` and `.privacyPolicy` are set.
- **Toasts.** One component, used for: Copied (Copy Block), Moved to Recently
  Deleted · Undo, Exported N notes, Imported N notes.
- **Polish sweep.**
  - Empty states use the mark.
  - Spacing and symbol weights match v2.
  - Transitions honour Reduce Motion.
  - Every new control has a VoiceOver label.
  - Dynamic Type applies in the chrome, not the note body.
- **Ship prep.**
  - Set `TARGETED_DEVICE_FAMILY = 2` and bump the build number.
  - Draft the privacy and support pages for Marcus to host. The privacy page
    says nothing is collected, notes stay on the device, and Run sends a
    block's code to the compiler site the reader picked.
  - Update AGENTS.md "Shipping".
- **Done when:** settings keys are pinned, and the macOS build compiles. The
  PR carries the full iPad QA path from the plan (fresh install through
  relaunch).

---

## Cut line

If Thursday night shows the week won't hold, these move to TestFlight build
2, in this order:

1. Insert into ink
2. Line numbers
3. Text size (the text options row ships with its paragraph controls)
4. Hiding inline markers (headings keep theirs)
5. Links (and the row's Link button)
6. Languages beyond C
7. Import
8. The two-window guard (fall back to multiple windows off)
9. Thumbnails (fall back to text previews)

**Never cut:** model v7 and Recently Deleted; Home and the title screen;
hidden heading markers; list continuation; auto-indent; the code-keys row;
Export; the ship steps.

## After each phase

- Update AGENTS.md where behaviour or structure changed, in its style: dated,
  specific, with the reason and anything measured.
- Update `docs/ROADMAP.md` "Where things stand".
- The PR covers:
  - what changed, with the mechanics explained;
  - the tests;
  - what was and wasn't checked on screen;
  - Marcus's checklist.

## Out of scope

Ask before starting any of these:

- Sign in with Apple
- iCloud sync
- AI features
- The iPhone layout (designed, not built, this week)
- A real Mac editor
- Text-anchored ink
- A4 paper
- Infinite canvas
- Pages side by side
- Face ID note locking
- Drawing inline markers in place
- Syntax theme choice
- A camera or document scanner
- Seeded ink
- Icon Composer glass
