# Plan: the 21 Oct testing feedback and the rest of the roadmap

Drawn from Marcus's list of 31 items (tested on NoteCode 1.0, **before the text
overhaul**), `docs/ROADMAP.md` and the design notes. The phases below cover the
feedback; "Structure for implementation" places every ROADMAP to-do too
(release work, known problems, verification debt, LaTeX and the rest). Deadlines
are Marcus's to manage. This file is the plan and the item index for the
feedback; `docs/features.md` is the standing inventory of the app's features
(built, partial, missing), which each item below updates when it lands.

## How the list was read

- **Several items may already be fixed or half there** on `main`, so the first
  step is a retest, not a fix. Found in the source on 21 Oct:
  - *Restore the original palette*: **Reset Colours to Defaults** exists in
    Settings › Drawing (`DrawingSettings.swift`, `InkPalette.resetStoredPalettes`).
    It resets the two ink palettes only. If the ask is the whole app's colours,
    that waits for the colour redesign (phase 4).
  - *"+" makes a note without opening it*: Settings › Notes › New Notes only
    picks the orientation. The tap makes a note and opens it. Not built.
  - *Double tap on the Pencil*: handled in ink mode only (`PageDetailView`
    `onPencilDoubleTap`, `PencilResponse`). Text mode is the gap.
  - *"Plain Text" to "Code"*: `CodeBlockKind.displayName` (`DocumentNode.swift`).
    A one-line change, but `LastCodeLanguage` stores `plainText`, so the stored
    key stays.
  - *Autocorrect off outside code blocks*: prose is autocorrected and code is
    not (`TextRewritingPolicy`). Only the prose half is missing, as a setting.
  - *Sidebar on Home*: by design the app opens on Home with the list away
    (`ContentView.columnVisibility = .detailOnly`).
- **The selection items are one problem, not six.** The stray multi-stroke
  highlight from tapping, the hotbar jumping after a lasso move, the lasso not
  letting go on a tool switch, rectangular select and recolouring text with the
  lasso all come from PaperKit's selection. Marcus chose to build our own object
  system for ink and text (phase 5), so those are **not patched in PaperKit
  first**, apart from stopgaps that cost under an hour.
- **Why before the App Store, if it can be**: the roadmap says the object
  system's storage is the one format change after release. Built before, it
  edits schema version 1 in place and testers reinstall; built after, it needs
  a version 2, a stage and a migration test (AGENTS.md › The model).

## Phases

### 0. Housekeeping and a retest (small)

- `docs/features.md` is made (item 25): the inventory of what the app has,
  how it works and what is missing, by type. It is not this plan's tracker;
  the item index at the end of this file is. Rows in features.md that say
  *planned (feedback #n)* point back here.
- Retest the 31 items on `main` on the iPad and mark each *fixed*, *still
  there* or *not reproducible*. Anything fixed by the text overhaul comes off
  the plan.

### 1. Quick wins (each an afternoon or less)

| Item | Change |
|---|---|
| "Plain Text" to "Code" | `displayName` for `.plain`; keep the stored key |
| "+" doesn't open the note | New setting beside New Notes: *Open Note After Creating*, default off. The tap inserts, shows the note in the list and a toast |
| Settings inside a note | A Settings entry in the note's ••• menu, same sheet as Home's gear (`ContentView` owns the sheet) |
| Autocorrect off in prose | Settings › Notes (or Text) toggle; `TextRewritingPolicy` gains the prose case, so it stays one `apply(to:)` |
| Don't dull bullets and markers | Per-element dimming settings for heading markers, list bullets, checkboxes and fence lines (`HeadingMarkerDisplay`, the styler); see Answered 5 |
| Line spacing presets (pt) | Options in the text options row; line height only (Answered 2). After the Return line-space bug is understood |
| Return to previous tool after selection | Setting plus a small `NoteEditor` rule: after a lasso is dismissed, restore the tool before it |
| Pencil double tap in text mode | Switch to ink mode, then run the double-tap action. Check the SwiftUI `onPencilDoubleTap` fires with the text view first responder |

### 2. Text bugs (probe first)

These follow the debugging approach in memory: probe against ground truth with
several interventions in one run before fixing, and prove the fix with content
that can show the bug.

1. **Return in a code block grows a thin gap, and "the line space bug happens
   outside text too"** (items 14 and 31). Probably one cause: the line
   height or blank-line layout (`BlankLineLayout`, `CodeBlockRoom`,
   `CodeBlockLayoutFragment`) when an empty line is created by Return. First
   learn whether outside a block it is the same fragment or a different one.
2. **Enter and Backspace need two presses while repeating** (item 20). Likely
   the highlight/restyle pass or the marker-hiding caret adjustment swallowing
   a key while the text storage is mid-edit. Reproduce with a held key on the
   iPad first, since the simulator may not repeat the same way.
3. **Awkward border where ink crosses a code block** (item 22, and the same
   family as "non-base background"): look at the code panel's edge against ink
   composited over it in light and dark.
4. **Caret anywhere** (item 7, decided): tapping empty space below the last
   line, or in a blank gap, extends the document with newlines and places the
   caret there. Needs the `DocumentUITextView` tap path and a guard so a tap
   beside an action bar still reaches the bar (AGENTS.md › Implementation
   requirements).

### 3. Navigation

- **No separation of notes and folders in the sidebar** (item 13): one list in
  which a folder is a row you expand, sorted with the notes by the chosen sort.
  `NoteListSections` / `FolderSection` / `NoteListDrop` all assume sections, so
  this is a real change, with drag and drop rules (`organising-notes.md`) to
  carry over. Drop on the iPad is already on the verification-debt list: check
  that first, because it decides the drop implementation.
- **Sidebar always shown on Home** (item 3): Home becomes a split view with the
  list visible in landscape (and the same compact-stack rules on iPhone/Duo).
  Touches the choice in `ContentView` that Home is the list's absence.
- **A buffer between the page and the screen edge** (item 1, Answered 1) on
  every side the hotbar doesn't take, top included.
- **Hotbar displaced after a lasso move** (item 24): waits for phase 6, since
  it comes from PaperKit's selection.

### 4. Ink behaviour that stays in PaperKit (small)

- **Add pages as I draw down** (item 8, decided): when a stroke ends in the last
  page's bottom band, append a page. Must go through the same path as Add Page,
  must not call `onInkChanged` for its own re-layout, and must not fire on a
  stroke that began somewhere else (AGENTS.md: ink saving is only for changes
  the reader made).
- **Tool or property changes show instantly on the hover mark** (item 17): the
  Pencil hover indicator reading the tool state; check whether PaperKit redraws
  the mark when `PKTool` changes while hovering.
- **Pages go blank for a few seconds after moving between them** (item 27):
  measure first (this looks like render tiles being rebuilt). A repro on the
  iPad with a note of a few hundred strokes; compare with the print mode path.

### 5. Colour and icons

- One design pass for item 28 and 5: dark-mode colours too dull, light mode a
  little uncanny; icons and colour display in the hotbar and options row.
- Write `docs/design/colour.md` first: the palette for ink, accent defaults,
  syntax and Home, light, dark and Increase Contrast. `InkShadeTests` and
  `SyntaxThemeTests` pin the values today, so the redesign changes them in one
  commit with the tests.
- **Restore original palette** then covers the whole set, not just the two ink
  palettes. Keep Reset Colours as is.
- The marker-dimming settings (phase 1) use these colours.
- Custom icons for the hotbar, options row and menus (Answered 3).

### 6. Our own object system (a phase, not a step)

Replaces PaperKit's selection and shapes. In scope: rectangular selection of ink
and text, recolouring selected text, selection letting go on tool switch, no
tap-to-highlight cluster, and the hotbar staying put. Out of scope for now: the
free text box tool (Marcus isn't sure he wants it), and logic gates and more
shapes.

This needs its own design note before code: what an object is (stroke, image,
shape, text range), where it is stored (a format change in schema version 1),
how selection and move work, what happens to PaperKit's markup data, and
whether PaperKit stays as the ink renderer. The first deliverable is that note
and a spike, per "Isolate risk".

### 7. Later, not now

- **Type on the Mac, draw on the iPad at the same time.** Needs the macOS
  editor (a plain `TextEditor` today) and iCloud sync or a live link between
  two devices. After the submission, behind iCloud sync and the macOS editor in
  the roadmap. Not a mirroring problem as the list suggests.
- **Free text box tool**: decide once the object system exists.

Stalled: default heading size on the heading hotkey (Answered 4).

## Structure for implementation

Deadlines are Marcus's to manage, so this orders by dependency and by which
files each piece touches, not by size. **Decided (21 Oct): the goal is to land
everything above and most of stream L before the submission next week.** So
the object system, and every later change to stored data, edits schema version 1
in place and no version 2 is needed; anything in L that doesn't make it
(likely the Pro tier, group notes and the Mac+iPad link) ships after. Treat
the stream split as the way to run them in parallel: S, T, N, P, O, C and R
are file-disjoint on purpose. The submission blockers in ROADMAP (iPhone target,
hosted pages, App Store Connect) stay a separate track and don't gate any of
this, but they do gate shipping, so R's blockers start in wave 1.

### Workstreams

Each owns a set of files, so two can run at once without touching the same ones.
Within a stream the PRs are sequential; one PR is one reviewable change (a
setting, a fix), never a phase.

| Stream | Phases it carries | Main files | Depends on |
|---|---|---|---|
| **S. Settings and small behaviours** | 1 (Code label, "+" opens or not, Settings in a note, prose autocorrect, double tap in text mode) | `SettingsView`, `AppSettings`, `WelcomeNote`, `NoteList`, `PageDetailView` menu, `TextRewritingPolicy` | nothing |
| **T. Text editor** | 2 (bugs), then caret-anywhere, line-spacing presets, marker dimming | `DocumentUITextView`, `BlankLineLayout`, `CodeBlock*`, `DocumentStyler`, `HeadingMarkerDisplay` | the probe comes first; features after it |
| **N. Navigation** | 3 (one list, sidebar on Home) | `ContentView`, `NoteList*`, `HomeView`, `FolderSection` | the iPad drop check |
| **P. Page and pages** | page buffer, add pages as I draw down, blank-page lag, hover mark | `PageDetailView`, `Hotbar` layout, `PageView`, `PageLayout`, `InkPages` | nothing |
| **O. Object system** | 6, and with it the whole selection family | `DrawingCanvas`, `InkTool`, `InkInsert`, `NoteEditor`, storage | design note and spike first |
| **C. Colour and icons** | 5 | `InkTool` shades, `SyntaxTheme`, `AccentPalette`, then `Hotbar`, `InkToolbar` | palettes any time; icons after O's tool changes |
| **R. Release** | ROADMAP's blockers, verification debt and known problems (below) | `project.pbxproj` (by hand), `docs/site/`, `AppSettings.AppInfo`, test files | nothing for the first three; the on-device checks follow the streams they cover |
| **L. After submission** | iCloud, paper styles, LaTeX, text-anchored ink, AI, shapes, Pro (below) | see each | the submission, except where noted |

Conflict to watch: S, P and O all touch `PageDetailView`; S's changes there are
the ••• menu and the double-tap hook, kept to one small PR each and merged
first.

### Waves

1. **Wave 0 (before anything):** Marcus retests the 31 items on `main` on the
   iPad (the index and checklist are at the end of this file), so items
   already fixed drop out. Nothing in wave 1 waits for the result
   except T's bug list and S's items marked "may already exist".
2. **Wave 1 (parallel):** S in full; T's probe (no fix yet, a Mac CLI probe
   for the parser pieces, per the debugging notes); N after the iPad drop
   check; O's design note and a spike of the selection and storage; C's
   palette note.
3. **Wave 2:** T's fixes, then its features; P; O's build, in steps (storage
   and a reader for it, then rectangular select for ink, then text, then
   the tool-switch and previous-tool rules); C's palette values.
4. **Wave 3:** C's icons (after O's tool set is final, since the lasso and
   rectangle icons are in it); the leftover selection items; a full retest;
   `features.md` and ROADMAP brought up to date (each PR updates its own
   feature rows as it lands; this is the final pass for what slipped).

### Roadmap items folded in

The rest of `docs/ROADMAP.md`, placed in the same structure.

**R. Release (alongside everything, in this order)**

1. *Blockers (Marcus by hand or with him):* turn on iPhone (`TARGETED_DEVICE_FAMILY`,
   in `project.pbxproj`, so Marcus edits it); host `docs/site/privacy.md` and
   `support.md` and fill `DATE` and `EMAIL ADDRESS`, then set
   `AppInfo.privacyPolicy` and `.feedbackAddress`; App Store Connect (Paid
   Applications, the three tip products, Small Business Program, screenshots,
   description, privacy label, review notes); bump the build number per
   upload.
2. *Known problems, cheap and file-disjoint, so any time:* inject the
   keyboard check in `Code keys and indentation in the editor` so it doesn't
   depend on the Mac's `GCKeyboard`; clear the Swift 6 isolation warnings
   (`SyntaxTheme`, `CaretTarget: Equatable`) and the 94 `UIWindow(frame:)`
   deprecations before Swift 6 mode makes them errors; replace the deprecated
   `FileDocument` (`ExportFolderDocument`); try typing three hyphens by hand
   (smart punctuation may make an em dash first), which belongs to T since
   it is `TextRewritingPolicy`; weight and italic in syntax colours
   (`ColorRun` carries colour only), which belongs with C or T once the
   cost in "Pages › Cost" is understood; re-check the pinned Compiler
   Explorer ids.
3. *Verification debt, on the iPad, after the stream that changes each:*
   folder and note drag and drop (this gates N); the text overhaul's six
   checks, including `.md` in Obsidian and a mixed-size PDF (after T);
   page-fills-window chrome and Reduce Motion (after P); Pencil latency,
   palm rejection, squeeze and double tap, lasso on cut strokes, Insert and
   dragging inserted objects (after O, which replaces the lasso); hardware
   keyboard shortcuts and Tab (after T); Export and Import, a second window;
   the tip jar with a sandbox purchase in TestFlight; a physical Duo after
   23 Oct; light/dark, Increase Contrast, 11-inch and portrait sweeps (last,
   after C).

**L. After the submission (ROADMAP's order, with the dependencies that matter)**

1. **iCloud sync.** Signing & Capabilities; the model is already shaped for
   CloudKit. Matters most once the iPhone app exists. It is also the first
   half of "type on the Mac, draw on the iPad": that needs the macOS editor
   (today a plain `TextEditor`) too, so those two belong together.
2. **Paper styles** (dots, grid), postponed after breaking page geometry. Its
   own design note first; reuse the page-geometry tests.
3. **LaTeX** (SwiftMath, always rendered, never caret-dependent). Touches the
   parser, styler and layout, so it runs after T is settled and with the hidden
   markers' rules in mind (`writing-hidden-markdown-markers…`). Paste, copy and
   PDF export have to handle it, so add them to the "done means" list.
4. **Text-anchored ink**, "before our own object system" in the roadmap, but
   the object system now comes first. So **O's design note decides how an
   object is anchored** (page coordinates now, an `NSTextLocation` plus an
   offset later) so that anchoring is added without the second format
   change.
5. **AI for March:** explain this code block and summarise this page on
   Apple's on-device Foundation Models, so the app still collects nothing.
   Needs the code block parser (done) and a place in the UI; independent of
   the others.
6. **More shapes**, logic gates among them, on O's object system.
7. **Ads and a Pro subscription:** ad SDK, tracking prompt, a new privacy
   label and `privacy.md`; lands with Pro, last.

**Unordered, kept visible:** infinite canvas, side-by-side pages, A4, the macOS
editor, sign-in and group notes (these need a server), Face ID note locking,
note combining, code sort. **Deferred performance work** from ROADMAP's table
(typing cost on long paged notes, diagonal panning when zoomed) waits for
evidence on the iPad, so wave 0's retest should note any lag.

### Verification

- Each fix carries a test that fails without it (memory: verification
  discipline); anything on screen is checked on the iPad, Pencil items on the
  hardware.
- A PR touching stored data updates the pinned hashes in `ModelFreezeTests`
  and says so.
- Stage files by name; `project.pbxproj` stays out (AGENTS.md › Shipping).

## Answered (21 Oct)

1. **Hotbar and the page edge.** The hotbar shifting the page is right. What
   is wrong is that the page edge touches the screen edge: keep a small buffer
   between the page and the screen edge on every side the bar doesn't occupy,
   top included (the "top section border"). Phase 3. Constraint: Room is
   taken by `Hotbar.footprint` / `the-page-fills-the-window.md`, and a buffer
   mustn't re-wrap text (width) or change pagination between the three view
   modes; check `HotbarLayoutTests`.
2. **Text spacing is line spacing**, with presets in points in the text options
   row. The standing decision stands: room is line height, never paragraph
   spacing. Phase 1 or 2, after the line-space bug (a spacing option would
   hide the bug it's supposed to ride on).
3. **Colour and icons:** hotbar swatches first. Also the icons: the SF Symbol
   look reads as basic, so phase 5 includes a custom icon set for the hotbar,
   options row and menus. The decision (draw our own, or restyle SF Symbols
   with weight and layering) is part of that design note.
4. **Default heading size on the heading hotkey: stalled.** Not planned until
   Marcus returns to it.
5. **Greyed markers need settings.** Heading markers, list bullets, checkboxes
   and fence lines each get their own control for how dim they are (off, dim,
   full). **Highly customizable is a standing aim:** where a visual choice
   exists, expose it as a setting through one type with one `apply(to:)`
   (AGENTS.md › Conventions), and group them in Settings so the page doesn't
   grow into a wall of rows.
6. **PaperKit's tap-to-highlight waits for the object system** (phase 6). No
   stopgap.

## Still open

Nothing from this list. Other questions will come out of the object system's
design note and the wave 0 retest.

## Item index and retest (the 21 Oct list)

Numbers are the order of Marcus's list. Stream letters are the table above.
Marcus fills the Retest column on the iPad against current `main`: *fixed*,
*still there*, *n/a*. Status: planned, building (a wave 1 session is on it),
stalled, idea.

| # | Item | Stream | Status | Retest |
|---|---|---|---|---|
| 1 | Page edge shouldn't touch the screen edge (buffer on sides the hotbar doesn't take, top included) | P | built (branch) | |
| 2 | Line spacing presets in pt | T | built (branch) | |
| 3 | Sidebar always shown on Home | N | planned | |
| 4 | Setting to restore the original palette | C | built (branch) | |
| 5 | Refine colour display and icons | C | swatches built (branch); icons planned | |
| 6 | Rectangular selection | O | planned | |
| 7 | Tap empty space puts the caret there | T | built (branch) | |
| 8 | Add pages as I draw down | P | built (branch) | |
| 9 | Settings to not dim bullets and other markers | T | built (branch) | |
| 10 | Default heading size on the header hotkey | | stalled | |
| 11 | Settings reachable from inside a note | S | built (branch) | |
| 12 | "+" makes a note without opening it | S | built (branch) | |
| 13 | One list for notes and folders | N | planned | |
| 14 | Return in a code block gets the border's thin space | T | not reproduced on main | |
| 15 | "Plain Text" becomes "Code" | S | built (branch) | |
| 16 | Back to the previous tool after a selection (setting) | O | planned | |
| 17 | Tool change shows instantly on the hover mark | P | PaperKit's; options written | |
| 18 | Text box tool, type anywhere | | idea | |
| 19 | Setting to turn off autocorrect outside code | S | built (branch) | |
| 20 | Enter/Backspace held needs two presses | T | not reproduced; likely cost on long notes | |
| 21 | Type on Mac and draw on iPad together | L | idea | |
| 22 | Awkward border where ink is over a code block | T | cause found: highlighter blend; fix open | |
| 23 | Pencil double tap in text mode swaps to the pencil | S | built (branch), unchecked with a Pencil | |
| 24 | Hotbar displaced after moving objects with the lasso | O | planned | |
| 25 | Create the features doc | | done | |
| 26 | Recolour text with the lasso | O | planned | |
| 27 | Pages blank for a moment after moving between pages | P | measured; options written | |
| 28 | Redesign the colour palettes | C | highlighters built (branch); pens unchanged | |
| 29 | Remove PaperKit's tap-to-highlight of a cluster | O | planned | |
| 30 | Lasso lets go on a tool switch | O | planned | |
| 31 | The line-space bug also happens outside code | T | not reproduced on main | |

**Retest first,** since these decide what the streams do: 14, 31 and 20 (Return
gap in and out of code; held Return and Backspace); 22; 27 and any typing lag
on a long note; 24 and 29; 11, 12, 15, 19 and 23 (say if they already work on
this build); and folder and note drag and drop (decides how the single list is
built).
