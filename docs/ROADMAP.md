# NoteCode roadmap

Source of truth. The published version at
<https://claude.ai/code/artifact/2490317a-7eaf-44ae-9389-f0fb92d7471a>
is a rendering of this file — edit here, ask for the artifact to be regenerated.

Revised 16 October 2026.

| | |
|---|---|
| Drawing layer due | **10 Oct 2026** (hard stop) — done 3 Oct |
| Using it day to day | now — ink is saved as of 23 Sep |
| TestFlight 1 | **Sat 17 Oct 2026**, iPad only |
| App Store submission | Nov 2026, with the iPhone and Duo layouts |
| Second version | AI + feedback, Mar 2027 |

## Where things stand (16 Oct)

v3 is built, and steps 1 and 4 to 9 of the plan below are merged, the last as
#60 on 16 Oct. Next is step 10.

- **Step 10, sized text** (17 Oct, branch `claude/text-size`, on
  `claude/text-colour`): a size menu beside the colour one sets the
  selection or the word at the caret Small, Large or Larger against the text
  around it, in the same span tag as its colour. Step 10 is built. Looked
  at in the simulator; not on the iPad.

- **Step 10, coloured text** (17 Oct, branch `claude/text-colour`, on
  `claude/code-block-room`): a colour menu in the text options row colours
  the selection or the word at the caret in one of six colours, written as
  Obsidian writes it, `<span style="color:#RRGGBB">`. The tags take no room
  and are never drawn, and each colour is made legible for light and dark.
  Search and Get Info leave the tags out. Looked at in the simulator; not
  on the iPad.

- **Step 10, room for code blocks** (16 Oct, branch `claude/code-block-room`,
  off `main`): the panel reaches 14pt into each margin while the code keeps
  the prose column, so nothing re-wraps sideways; a 12pt gap above and below
  every block; a 40pt header holding the language and Run and Copy; code at
  15pt beside a 17pt body on the prose's line height, about 73 columns before
  a wrap instead of 65; a line that still wraps continues two columns past
  its own indentation, after a faint ↳, so it no longer reads as a new
  line. All the vertical room is line height: paragraph spacing let a page
  break fall inside it, and the modes paginated differently. The PDF prints
  the language in the header, and the marks. Looked at in the simulator;
  not on the iPad.

- **Step 1, links not opening on the iPad** (15 Oct, branch
  `claude/link-taps`, off `main`): fixed and seen working on the iPad. Two
  causes. A link that ended its line measured no width, from a TextKit
  behaviour with zero-width characters at a line's end, so a tap on it was
  plain text; the same thing drew the caret at the line's start after a bold
  word ending a line. And the caret's own tap ran alongside every link tap,
  kept off only by a race. Not device-only after all: every link checked in
  the simulator on 13 Oct had words after it.

- **Step 5, the page fills the window** (16 Oct, merged as #60): the page runs edge to edge with no border,
  corner radius or top gap. A bottom bar floats over it and moves nothing; a
  side bar takes one strip from its side, sized for the bar and its options
  row so tools never move the page. Home is a house button beside ☰ in a
  note's header. The list's bottom bar is gone: Settings is in the list's
  ••• and on Home's toolbar, Recently Deleted is the list's last row, and
  Outline moved from the header into the note's •••. See AGENTS.md › The page
  fills the window. Builds for iPad; **not looked at on screen**.

- **Steps 4 and 7** (15 Oct, branch `claude/clear-out-old-notes`, off `main`):
  the model is one plain schema with no versions or migrations, and
  `markdownLayout`, `paperStyle` and Hide Markdown Markers… are gone. The
  coordinator's `rendersMarkdown` flag stays (off by default; the app sets it
  for every note) because the test harnesses are written against it. Deleting a
  folder with its notes puts the folder in Recently Deleted too, and restoring
  it brings those notes back. Builds for iPad; 1,135 unit tests pass except the
  11 known issues in the Code keys suite. Not looked at on screen.

On 3 Oct the drawing layer was done, a week inside its deadline: the TextKit 2 editor
with code blocks, run and copy, Letter-sized pages in three view modes with
pinch zoom, the note page and its hotbar, and a PaperKit canvas that a finger
or the Pencil draws on, with ink undo of its own, saved with the note and
drawn at the screen's density. 25 pull requests by then.

- **UI design v3, phase 8: settings, toasts, polish** (14 Oct, branch
  `claude/v3-phase-8-settings-polish-ship`, off `main`, merged as #55): Settings ›
  Notes has Recently Deleted; Show Markdown's footer says what it covers; Copy
  Block says "Copied"; empty states draw the mark; Reduce Motion skips the dock
  snap and palette reorder; privacy and support pages are drafted in
  `docs/site/` for Marcus to host. The ship steps in `project.pbxproj` (iPad
  only, build number) wait for Marcus's go-ahead. Builds for iPad and Mac;
  unit tests pass except 11 issues in one suite that also fail on `main` here.
  Not looked at on screen.
- **UI design v3, phase 7: getting notes in and out, and windows** (14 Oct,
  branch `claude/v3-phase-7-notes-in-and-out`, off phase 6's branch, merged
  as #54): Share is a menu (tap for the PDF; hold for PDF, Markdown, Copy as
  Markdown, Print…); Export All Notes… (the list's ••• and Settings › Notes)
  writes a folder with a subfolder per folder and a `.md` per note, plus a PDF
  beside each note with ink, with progress and Cancel, through Files; Import…
  (Home and the list's •••) brings in `.md`/`.txt` as written and source files
  as one tagged code block; a second window that selects a note the first has
  open shows "Open in Another Window" instead of a second editor. Builds for
  iPad and Mac; 1,134 unit tests pass. **Not looked at on screen**, and the
  folder export through Files is untried.
- **UI design v3, phase 6: navigation, and the text options row** (14 Oct,
  branch `claude/v3-phase-6-navigation-text-row`, off `main`, merged as #53): an
  Outline button in the header (and ⌃⌘O) lists the note's headings and jumps
  to one, its line at the top of the page; a "2 / 5" badge shows while the note
  scrolls and fades a second after. Text mode gets a second row beside the
  hotbar, as ink mode has: a text size stepper (`+ 17 −`, seven sizes from 14 to
  23, kept per note, ⌘+ and ⌘−) and then controls for what the caret is in:
  Body, H1 to H3 and Link; the list kinds and indent; a code block's
  language, indent and + Output. Changing a size re-wraps the note, keeps the
  reader on their line, and asks first on a note with ink; the PDF and
  thumbnails are made at the note's own size. Builds for iPad and Mac; 1,100
  unit tests pass; looked at in the simulator (the row, the stepper, the
  outline), not with a hardware keyboard, the Pencil or on a note with ink.
- **UI design v3, phase 5: insert and templates** (13 Oct, branch
  `claude/v3-phase-5-ink-paper-templates`, off `main`, merged as #52): ink mode's
  hotbar has Insert, PaperKit's own popover of shapes, arrows and a text box
  plus Photo… (downscaled to 2 pixels a point of page width), placed at the
  middle of the page on screen and kept like any ink (saved, undone, moved with
  its page between modes, printed); edits to a shape or text box that don't move
  it are now saved too, which `InkCapture` missed. Lecture, Problem and Lab
  templates from + › From Template and Home, their code block in the folder's
  usual language. **Paper (dots and grid) was dropped from this phase and
  postponed until after v3.** Builds for iPad and Mac.
- **UI design v3, phase 4: code** (13 Oct, branch `claude/v3-phase-4-code`,
  off phase 3's branch, merged as #50): C, JavaScript, Rust, Go and SQL join C++,
  Java and Python (SQL keeps Copy only; Compiler Explorer runs C, Rust and Go
  from a link, checked on the live site, but **not JavaScript**, which it can't
  execute); ```` ```output ```` blocks are a dark console with Copy and no Run;
  Return in code keeps the indent, goes deeper after `{ ( [` or a Python colon
  and opens a pair of braces onto their own lines; ⇥ and ⇧⇥ indent lines;
  a row of code keys sits above the on-screen keyboard while the caret is in
  code (not with a hardware keyboard); line numbers go in the page's margin,
  and print. Settings › Code has Code Keys, Indent Width and Line Numbers.
  Also fixed: a language retag never re-coloured the code. Builds for iPad and
  Mac, and 1,000 unit tests pass; looked at in the simulator (the row, Return after a Python colon, ⇥,
  the language menu and an Output block, line numbers, light and dark); not
  with a hardware keyboard or the Pencil.
- **UI design v3, phase 3: writing, with Markdown markers hidden** (12 Oct,
  branch `claude/v3-phase-3-writing`, off phase 2, merged as #49): in a note made
  from now on, `#`, `**`, backticks, `~~` and link syntax take no room on the
  page (a word-joiner swap in layout, so nothing re-wraps and ink stays put);
  a heading's `#` is drawn in the margin while the caret is on it, and the
  hotbar lights up what the caret is in. Backspace, arrow keys and Return
  know about the hidden markers. Return continues lists and checklists, Tab
  and ⇧Tab nest them, List ▾ has Numbered and Checklist, boxes tick with a
  tap, and `[text](url)` and bare addresses are links (tap to open, hold for
  Open Link / Copy Link). Notes with ink keep visible markers until the title
  menu's Hide Markdown Markers…. Builds for iPad and Mac; looked at in the
  simulator (the margin hash, boxes, links, Return in a list, with real taps
  on a box and the heading); not with a real keyboard or the Pencil.
- **UI design v3, phase 2: title screen, Home, thumbnails, reopening** (12 Oct,
  branch `claude/v3-phase-2-home`, off phase 1, merged as #48): the app opens on
  Home, in the page area, with the list behind ☰: the note to continue (with
  "page 3 of 5"), the eight most recent, folder tiles, New Note, and an empty
  state. A Home row tops the list (⇧⌘H). A first launch opens a title screen
  (Settings › Help and About shows it again). Rows and cards show a picture of
  the note's first page, made one at a time and cached. A note reopens at the
  page it was left at. Builds for iPad and Mac; looked at in the simulator
  (Home light and dark, the title screen light, a note reopening at page 3),
  not with the Pencil or a real keyboard.
- **UI design v3, phase 1: model v7, Recently Deleted, folder identity,
  Duplicate** (12 Oct, branch `claude/v3-phase-1-recently-deleted`, off
  `main`, merged as #46): deleting a note now moves it to Recently Deleted for 30
  days, with a toast and Undo and nothing asking first; the list's foot shows
  a Recently Deleted row, only when it holds something, which opens a sheet to
  Restore, Delete Now or Delete All…. Notes are purged at launch once they are
  past 30 days. Folders have a colour and a symbol, set in a new editor sheet
  in place of the name alert. Duplicate is in the note menu. Model v7 adds the
  fields v3 needs (only some used so far); notes without ink migrate as
  `rendered`, notes with ink keep their layout. Builds for iPad and Mac, and
  784 unit tests pass; three `HotbarUITests` reach tests fail the same way on
  `main` (they look for a "Red" swatch). Looked at in the simulator, dark only:
  the folder editor, the toast, the list foot and the sheet; not light mode,
  Restore, Undo, hold menus, Delete All or the Pencil.
- **UI design v2, phase 1: colour** (7 Oct, branch `claude/ui-phase-1-colour`,
  merged as #31): the orange accent, with its Increase Contrast variants, and the
  design's syntax colours for code in light and dark. Run is orange. Builds
  for iPad and Mac, and 537 tests pass; not yet checked in the simulator or on
  the iPad. Phases 2 to 9 are in `docs/ui-design-v2-implementation.md`.
- **Ink across page breaks** (9 Oct, branch `claude/ink-split-pages`,
  merged as #38): a stroke drawn across a page break now stays on its words on both
  pages in every view mode. It's stored as one piece per page, each moving
  with its own page. Seamless is the reference: compressed's strip and print
  layout's top and bottom margins and gaps take no ink, and anything drawn
  across them is hidden. Also fixes print layout blanking the text around
  ink, which PR #36's fix had caused. Builds for iPad and Mac, 589 tests
  pass; checked in the simulator, not yet with the Pencil on the iPad.
- **UI design v2, phase 2: the page against its surround** (8 Oct, PR #34,
  merged): seamless and compressed now show a white (black) page column on a
  grey surround, as print layout already did, with the hotbar's strips on the
  surround too. Fixed 9 Oct (branch `claude/page-gap-ink-keyboard`,
  merged as #36): compressed is back to only a dashed line at each page end, its
  grey band gone; in print layout a stroke run off one sheet no longer shows
  over the grey between sheets; and the grey no longer rides up with the
  keyboard, which had left white around and under it. Checked in the
  simulator, light and dark; not yet on the iPad with the Pencil.
- **UI design v2, phase 3: the note header** (8 Oct, branch
  `claude/ui-phase-3-header`, merged as #35): the custom header and its large
  title field are the system navigation bar now. The title is a menu (Rename,
  Pin, Move to Folder, Lock Text, Get Info, Delete) and renames in place;
  Share and ••• sit on the right, and ••• holds the view mode, Run Code In and
  Find in Note. The Account placeholder is gone. Builds for iPad and Mac;
  looked at in the simulator, not tapped through, and the new-note rename isn't
  checked, and the lock icon sits before Share, not after the title.
- **UI design v2, phase 4: the hotbar** (10 Oct, branch
  `claude/ui-phase-4-hotbar`, merged as #39): the text tools are Style, Bold,
  Italic, Inline Code, List and Code Block, the last three menus. In ink mode
  the bar is just the tools and Finger Draws, and what the selected tool can
  be set to (colours and three widths for the pen and highlighter, mode and
  size for the eraser) is in a thinner row that floats beside the bar, on the
  page's side, and reserves no room, so the page never moves. The pen and
  highlighter each have a palette of the design's colours, and each remembers
  its own colour and width; a palette a device had saved is kept. The squeeze
  palette shows the same two rows in one panel. Builds for iPad and Mac, and
  611 tests pass, plus seven UI tests for where the row sits and what it
  reaches; looked at in the simulator in light and dark, on all three edges,
  not tried with the Pencil or the squeeze palette.
- **UI design v2, phase 5: code-block fences** (10 Oct, branch
  `claude/ui-phase-5-fences`, merged as #40): a code block shows its backticks
  only while the caret or a selection is in it. Away, the opening line shows the
  language's name (a menu: C++, Java, Python, Plain Text, which rewrites the
  fence's tag and can be undone) with Copy and Run on the right; editing, it
  shows "```cpp" in the marker colour. Ink mode and the PDF
  show no fences. Nothing moves when a block switches: the lines keep their
  height, and nothing is laid out or edited (a caret move costs 1.5ms, a
  keystroke 35ms on a 500-line note). The brief's first choice, a clear
  rendering attribute, does hide the glyphs but un-hides text edited inside
  its range, so the fragment draws the fences itself. Show Markdown (While
  Editing or Always) is read from `showMarkdown`; its row comes with phase 6.
  Also: undo and redo are no longer turned away by the keyboard-rewrite guard.
  Builds for iPad and Mac, 661 tests pass; looked at in the simulator
  (rendered, light and dark), not tapped through or tried on the iPad.
- **UI design v2, phase 6: settings** (10 Oct, branch
  `claude/ui-phase-6-settings`, merged as #42): a gear at the foot of the note
  list, or ⌘, with a keyboard, opens Settings as a form sheet: General
  (Appearance, Toolbar Position, Haptic on Snap), Notes (View, Sort By), Writing
  (Show Markdown), Code (Run Code In), Drawing (Finger Draws, pen and highlighter
  palettes, Eraser, Reset Colours) and Help and About (Acknowledgements,
  Version). Each row reads and writes the setting the rest of the app already
  uses. Appearance changes every window as it is picked. Settings changed while
  a note is open reach that note. Left out until they work: App Icon (it came
  with phase 7), New Notes and Welcome Note (phase 8), and Send Feedback and Privacy Policy,
  which wait for an address and a page. Builds for iPad and Mac, 687 tests pass; looked at in the
  simulator only as far as the opened sheet's list of sections, in dark; no
  page was tapped through.
- **UI design v2, phase 7: the app icon** (10 Oct, branch
  `claude/ui-phase-7-icon`, merged as #43): the icon set has images, which an
  upload needs. `scripts/make-icons.swift` draws them (the Logo board's
  geometry, Core Graphics) into three icon sets: the Default, with a Dark
  variant on a transparent ground, a greyscale Tinted variant and the macOS
  sizes, and two alternates, Paper and Orange. Settings › General › App Icon
  (iPad and iPhone) shows the three as choices and switches with
  `setAlternateIconName`; iOS shows its own "icon changed" alert. Opaque
  everywhere but Dark, since the App Store rejects an alpha channel. Looked
  at in the simulator: the row, the switch from Paper back to the Default
  and the tick following it; builds for iPad and Mac, 694 tests pass; not seen on a Home Screen, in Dark or Tinted, on
  the Mac, or on the iPad. **TestFlight is no longer waiting on the icon.**
- **UI design v2, phase 8: note list and first run** (12 Oct, branch
  `claude/ui-phase-8-list-first-run`, off `origin/main`, merged as #44): tapping
  + makes a note in Settings › Notes › New Notes' orientation, in the open
  note's folder; holding it offers Portrait Pages, Landscape Pages and New
  Folder. The list's note menu is the title menu, Rename included. The
  selected row is an accent tint. An empty list offers New Note and Open
  Welcome Note, and an empty folder says so. A first launch on an empty store
  makes a "Welcome to NoteCode" note, once; Settings › Help and About › Welcome
  Note makes another on request. The launch screen was already the plain system
  background, now pinned by a test. Builds for iPad and Mac, 700 tests pass;
  checked in a fresh simulator: the first-launch note, the tint on the selected
  row and the + tap. Not checked: the hold menu, Rename from the list, the empty
  states, dark mode, the Mac.
- **UI design v2, phase 9: finishing** (12 Oct, branch
  `claude/ui-phase-9-finishing`, off the phase 8 branch, merged as #45): every
  shortcut in the brief is in the menu bar, so holding ⌘ lists them (Bold,
  Italic, headings, bullets, code block in the last language, Run and Copy
  Block, text/draw, the ink tools on bare keys, thinner and thicker, the view
  modes, Find, Print, New Note and Folder, Search Notes, the note list). The
  edit menu offers Bold, Italic, Code and Format on prose, and Run Block and
  Copy Block in code. Copy Block gives a light tap; the pointer lifts the
  hotbar and the run, copy and language buttons. The note body now ignores
  the system's text size, which had been re-wrapping notes under their ink;
  the list and Settings scale with it. Builds for iPad and Mac, 735 tests
  pass; looked at in the simulator only at the largest text size. No
  shortcut was tried with a real keyboard.
- **Note search** (4 Oct, PR #27, merged 8 Oct): a search field at the top of the note
  list finds notes by every word typed, in the title or the text, ignoring
  case and accents. Results show the line that matched, with the words in
  bold, title matches first. Opening one scrolls the note to its first match
  and highlights every match until you type. The magnifying glass in an open
  note's header, or ⌘F with a keyboard, finds and replaces within the note.
  Ink isn't searched. Builds for iPad and Mac, and 493 tests pass; not yet
  checked in the simulator or on the iPad.
- **Printing and PDF export** (4 Oct, PR #29, merged 8 Oct): the share button in an
  open note's header makes a PDF of the note, a page for each of its pages
  exactly as print layout shows them, ink, code panels and syntax colours
  included, and opens the share sheet to print it, save it to Files or send
  it. Always light, on white paper, whatever the device's appearance. Text
  stays text, so it can be searched and selected in the PDF; ink goes on as
  a picture at 288 dots per inch, since PaperKit draws only into bitmaps.
  Builds for iPad and Mac, and 486 tests pass; not yet checked in the
  simulator or on the iPad.
- **Text lock** (4 Oct, PR #30, merged 8 Oct): the lock in an open note's header, or
  Lock Text in its long-press menu in the list, makes the note's text and
  title read-only until it's unlocked. Tapping it brings up no keyboard,
  the formatting buttons grey out and undo stands down, but text can still
  be selected and copied, code blocks still run and copy, and ink can still
  be drawn. The note remembers it: a new model version, 6, with migration
  tests from version 5. Locked notes show a small lock in the list. Locking
  isn't an edit, so the date stays. Not the Face ID kind, which is under
  "Not in the order". Builds for iPad and Mac, and 486 tests pass; not yet
  checked in the simulator or on the iPad.
- **Autocorrect for prose** (3 Oct, PR #26, merged 8 Oct): prose gets the keyboard's
  autocorrect, capitals, smart quotes and dashes, and inline predictions
  back; code keeps them off, on a block's lines and fences and in inline
  code, an unclosed fence or backtick included, and on the word just after
  inline code until a space ends it. The keyboard switches as the caret
  crosses from one to the other, and is set up as typing begins. Spell
  checking stays off everywhere, since it would mark identifiers typed in
  code. Typed through on the iPad simulator's keyboard and checked in light
  and dark. That found a new note's first letter left lowercase, fixed and
  checked, and autocorrect rewriting inline code's last word and eating its
  backtick, either as the space after it was typed or when the keyboard went
  back over it from the next word. Both inline code fixes are unit-tested
  but not typed through again: the simulator's keyboard checks were stopped
  as too slow.
- **Note info** (3 Oct, merged 3 Oct, PR #25): Get Info, in a note's long-press menu
  in the list, or the info button in an open note's header, shows when the
  note was made and last changed, its folder and orientation, its words,
  and its code blocks by language with their lines. Opened from the note,
  it adds the page count, which only a laid-out note knows. Worked out from
  the text through `DocumentParser` each time it opens, so nothing is
  stored. 476 tests; checked in the iPad simulator in light and dark.
  The sheet is the standard one, holding every row for code in up to
  three languages; a fourth scrolls.
- **Pinning and sorting** (3 Oct, merged 3 Oct, PR #24): a long press pins a note or
  a folder to a Pinned section at the top of the list, and Sort By, in
  the list's ••• menu, orders notes by date modified, date created or
  title, either way round.
  The sort is a per-device setting; folders stay in name order. No model
  change: the pins came with folders. 468 tests; checked in the iPad
  simulator in light and dark, where the first build's Sort button pushed
  the list's title out, so Edit and Sort By now share a ••• menu.
- **Folders** (3 Oct, merged 3 Oct, PR #23): notes file into folders that open and
  close in the list, each with its own run destination between the note's
  and the app's. The model is versioned from here on, and this first
  migration also carries the pins for pinning, so sorting and note info need
  no model change. Its versions include every shape earlier builds wrote:
  with only the latest, stores from before 23 Sep wouldn't open. 459 tests;
  copies of four simulators' stores, from 12 Sep to 25 Sep, open with every
  note intact.
- **The device pass is closed** (3 Oct). Marcus has used the app on the iPad
  and reports it works, so latency, palm rejection and Pencil-versus-finger
  routing are taken as passed rather than measured.
- **Ink is saved** (23 Sep, merged 25 Sep): half a second after
  drawing pauses, and at once when the note closes or the app leaves the
  screen. It survived a force-quit on the simulator. 410 tests.
- **The iPad pass has started.** First findings (25 Sep): ink and the line
  being typed were drawn at a lower density than the screen, and typing
  stuttered now and then. Both density bugs are fixed and measured on the
  simulator, and a keystroke costs about a third less (merged 25 Sep).
  Typing near the top of a long note still costs
  about two frames; the rest of that is pagination by exclusion paths.
  Two smaller bugs found on the way are fixed too: a deleted
  note came back if the app was killed within a few seconds, and the empty
  line after a note's closing fence was shaded as code.
  The simulator's share of the device checklist is done (26 Sep, branch
  `device-pass`): dragging a lasso selection and scrolling with two fingers
  while a finger draws are fixed (merged 26 Sep). Rotation and Split View passed
  on the iPad.
- **Pencil changes** (26 Sep, PR #21, merged 2 Oct): the eraser erases whole
  strokes or only what it passes over, at three sizes or a custom one; "+"
  adds a colour from Apple's colour picker, and a colour can be removed or
  moved; the Pencil's double tap and squeeze do what Settings says; the
  surround around the page scrolls with one finger and zooms; and undo,
  redo and the mode toggle no longer scroll away with the hotbar's tools.
  All but the Pencil checked on the simulator. 448 tests.
- **Ship prep** (4 Oct, PR #28, merged 8 Oct): the app carries the privacy manifest
  App Store Connect requires, saying it tracks and collects nothing and
  reads UserDefaults only for its own settings. It says it uses no
  encryption of its own, so uploads skip the export question, and it no
  longer declares a push background mode or iCloud and push entitlements,
  left over from Xcode's template and never used. The app icon, the other
  thing missing before an upload, came with Phase 7 of the UI design.
- **Signing on the paid team** (9 Oct): Marcus re-obtained the paid
  Developer Program membership, which hadn't been showing on the account
  since 11 Sep. Builds had been signing with the free Personal Team, whose
  profiles last seven days, so the app stopped opening on the iPad about
  weekly. The team kept its ID, `N454V8HV9J`, and Xcode now lists it as
  paid; the app's provisioning profile, made 8 Oct, lasts a year, to
  8 Oct 2027. TestFlight is no longer waiting on the account or the icon. Not yet seen on the iPad: whether a build installed from now on
  keeps opening past a week.

## Plan

Revised 15 Oct, once v3 was built. The steps are in order of
implementation, grouped by the three dates: TestFlight on 17 Oct, the App
Store submission in November, and the AI version in March. They are
Marcus's list of 15 Oct, plus the postponed items marked as such.

**Decided 15 Oct: no old notes are kept working until the release.** Nothing
important is stored in the app yet. So nothing is built to keep notes from
earlier builds working: no migrations, no layout-version gates, no legacy
paths. That holds until other people have notes. TestFlight testers reinstall
after step 4. After the release everyone's notes count, so anything that
changes how notes are stored lands before it.

### Before the TestFlight upload (Sat 17 Oct)

1. **Links not opening on the iPad** (postponed 13 Oct until v3 was done).
   Fixed 15 Oct, branch `claude/link-taps`; see "Where things stand".

### Before the App Store submission (November)

2. **Ads or a tip jar: decide now, build at step 12.**
   - Ads mean an ad SDK, a tracking prompt, and a privacy label that no
     longer says nothing is collected.
   - Proposed: a tip jar through StoreKit, which passes review everywhere.
   - A plain Buy Me a Coffee link is thought to be allowed only on the US
     storefront. Check guideline 3.1 before building.
3. **Notability and Obsidian deep dive**, timeboxed. Moved up from last: it
   is the only item that can add to or reorder this list, and it feeds step
   10's format decision.
4. **Clear out what only old notes needed** (done 15 Oct):
   - the visible-marker layout (`markdownLayout` nil) and the title menu's
     Hide Markdown Markers…;
   - the handling of ink saved before the 9 and 10 Oct cutting;
   - the frozen model versions 1–7 and the v7 custom stage;
   - the unused `paperStyle`.

   From here to step 13 the model is edited in place, and a store that won't
   open is deleted with the app. AGENTS.md's model section changes with this
   step.
5. **The page fills the window**, Notability-style, rather than sitting
   inside a frame. (Built 16 Oct, branch `claude/page-fills-window`; see
   AGENTS.md. The options row's room is reserved whenever the bar is at a
   side, as proposed.) Three more go with it:
   - the page moves with the hotbar, centred or pushed aside, and a bar at
     the bottom moves nothing;
   - Home moves to the top left;
   - the iPad layout loses clutter.

   It is one piece of work, since all four are the page area's geometry and
   its chrome. Only the display scale changes, so ink stays on its words. It
   reverses "moving the bar never resizes the page", which was a choice, not
   a constraint.

   Open: if the page also moves for the options row, it jumps at every tool
   or mode change. Proposed: reserve the row's room whenever the bar is at a
   side.
6. **Add page** in compressed and print layout, **and a buffer in
   seamless**, as Apple's Notes has. One stored page count serves both: the
   button adds to it, and seamless adds a page when ink reaches the last one.
   (Built 15 Oct, branch `claude/accent-colour`; see AGENTS.md › Pages. Add Page is
   in the ••• menu, not on the page.)
7. **Folders go to Recently Deleted** too (done 15 Oct).
8. **Hold and drag** notes and folders. (Built 16 Oct, branch
   `claude/drag-folders`, on top of step 9's branch; see AGENTS.md ›
   Organising notes. Folders now nest and are arranged by hand, with an arrow on
   the left of each to show its contents. **The drops themselves are untried**:
   the simulator never delivered one. Moves also work from the folder menu.)
9. **Editable accent colour**, with a reset to orange. Before step 11, so
   the colour is wired up once for both layouts. (Done 15 Oct, branch
   `claude/accent-colour`; see AGENTS.md › Colour.)
10. **Text restructure: colour and size anywhere, and more room for code
    blocks.** Room for code blocks first (16 Oct, branch
    `claude/code-block-room`): Marcus found the run and copy buttons had no
    room and the block looked cramped; see AGENTS.md › Code blocks: room
    around and inside. Colour second (17 Oct, branch `claude/text-colour`):
    `<span style="color:#RRGGBB">`, as step 3's research recommended, from a
    menu in the text options row. Size third (17 Oct, branch
    `claude/text-size`): the same span with `font-size`, Small, Large and
    Larger against the text around it, asking first on a note with ink. See
    AGENTS.md › Coloured and sized text.
    - **Why before the release:** changing how text is stored costs nothing
      now, and means migrating everyone's notes after.
    - **Why before step 11:** it changes the text options row, which the
      iPhone gets too.
    - **Proposed format:** extend the Markdown rather than store rich text
      (Obsidian uses HTML spans for colour). The styler, the formatting
      buttons, lists, hidden markers, search and export are all built on
      Markdown in the note.
    - **Order:** room for code blocks, then colour, since it moves no
      lines, then size. (Colour was first until 16 Oct; code blocks went
      ahead because they need no format decision.)
    - **Room is line height, never paragraph spacing:** spacing let a page
      break fall inside it and the modes paginated differently (probe,
      16 Oct). Size anywhere has to follow the same rule.
    - **Until step 17,** resizing text above ink moves lines out from under
      it, as typing a line already does.
11. **iPhone and Duo layouts**, on the chrome from step 5. The Duo is out
    23 Oct and needs Xcode 27.1 (see Deferred work).
    (Built 17 Oct, branches `claude/iphone-layout` and
    `claude/iphone-layout-2`: in a compact width, a stack of Home, the list
    and a note; the page fitted by its text column; the hotbar fixed at the
    bottom; Home in two columns; options rows that scroll on a narrow phone;
    the sheets checked on a phone. On the Duo, the hotbar keeps off the fold
    while it is partly folded. Left: the board's open question, column or
    whole page, and a device. See AGENTS.md › iPhone and the Duo.)
12. **The list's foot: the mark, Feature Request, the tip jar**, and the
    postponed Send Feedback and Privacy Policy rows. Last before submitting,
    since all of them wait on the pages in `docs/site/` being hosted.
13. **Freeze the model as version 1**, the last change before submitting.
    Versioning starts with what ships.

If November gets tight, steps 7–9 can slip past the release. Step 10
shouldn't.

### After the submission

14. **iCloud sync** (postponed). Once there's an iPhone app, a phone without
    sync is a second, empty notebook. The model is shaped for CloudKit
    already. Sync needs Signing & Capabilities, so `project.pbxproj` changes.
15. **Paper styles** (postponed 14 Oct). They broke on page geometry in
    compressed and print layout, which steps 5 and 6 settle.
16. **LaTeX.**
    - Maths is always shown rendered.
    - It never switches to source under the caret, as Obsidian's does, since
      layout can't depend on the caret.
    - SwiftMath (native) fits better than KaTeX in a web view.
17. **Text-anchored ink** (postponed; see Deferred work). After steps 10 and
    16, which move text under ink the most. Before step 19, so objects are
    anchored from the start.
18. **AI, for March.** One or two features tied to the use case (explain this
    code block, summarise this page), built on TestFlight usage. Apple's
    on-device Foundation Models would keep the app collecting nothing.
19. **Our own object system**, tap- and pen-first like tldraw, in place of
    PaperKit's shapes.
    - It brings rectangular selection and an options row for the lasso.
      Rectangular selection waits for it because PencilKit's lasso is
      freeform only.
    - It comes after step 18 because March is a fixed date.
    - Its storage is the one format change after the release. Shapes made
      with Insert before then will need converting, unless Insert is hidden
      until this lands.
20. **More shapes**, logic gates among them.

### Not in the order

None of the steps above depend on these:

- infinite canvas;
- side-by-side pages (a scrolling direction);
- A4;
- the macOS editor;
- sign-in and group notes;
- note locking with Face ID;
- note combination or sealing;
- code sort and code syntax.

### Done — the drawing layer on PaperKit (to 10 Oct)
See [phase-drawing-layer.md](phase-drawing-layer.md) for the build plan.

| Step | Planned | Status |
|---|---|---|
| 1. Spike | 6–7 Sep | Done |
| 2. Geometry | 8–14 Sep | Done, and grew into pages and view modes |
| 3. The toggle | 15–21 Sep | Done; the code-block buttons' overlap with the canvas fixed 25 Sep |
| 4. Saving ink | 22–28 Sep | Done 23 Sep; gate passed on the simulator |
| 5. Device pass | 29 Sep – 10 Oct | Done 3 Oct: rendering density fixed, typing cost cut; the simulator's share of the checks done, and the lasso and two-finger scrolling fixed; Pencil changes merged 2 Oct (PR #21); Marcus reports it works on the iPad |

**Fallback if it runs long:** the phase doc's cut list — stop adding pages for
ink, then PencilKit's canvas instead of PaperKit's. Saving is never cut.

### The before-November candidates (3 Oct)

Folders were merged on 3 Oct. Text locking, note search, pinning, sorting,
note info and printing were merged by 8 Oct. UI polish became the v2 and v3
designs. TestFlight is the 17 Oct upload, and the submission follows step 13.
Scrolling direction, infinite canvas and sign-in are under "Not in the order".

The old Later list went the same way:

- templates came with v3;
- theme and colour selection is step 9;
- iCloud sync is step 14;
- AI is step 18.

## Done so far

**Foundations (Jul–Aug).** Swift and SwiftUI basics before touching NoteCode.

**Walking skeleton (Aug).** The `Page` model, a page list, a page editor, and
`Storage` — which degrades to an in-memory store and says so, rather than
crashing on launch when the disk store fails.

**Custom text engine (Aug – early Sep).** Built before the drawing layer, out
of the original order, because it was the phase most likely to sink the
schedule.

- A real `UITextView` on TextKit 2 (`DocumentTextView`)
- Pure, unit-tested fence parsing (`DocumentParser`)
- Fragment-level code panels (`CodeBlockLayoutFragment`) — `.backgroundColor`
  paints per glyph and leaves a ragged right edge
- Async syntax colouring via HighlightSwift, restyling only the changed block
- Debounce went from a guessed 200ms to a measured 20ms

**Run and copy (11 Sep).** In-app execution was cut: every option needed a
paid API, a VPS sandbox, or a multi-megabyte WASM runtime with a four-second
cold start, for a feature nobody uses during a lecture. It came back as a
redirect. Every code block carries run and copy in its top-right corner, and
run opens a free online compiler.

- `CodeDestination` — where a block goes, and how. Compiler Explorer takes the
  whole program in the URL, so the student lands on a finished run; Programiz
  and OnlineGDB can't be prefilled, so the code goes on the pasteboard.
- Per-note choice, app-wide default behind it. Folders slot in between when
  they exist — `RunDestinationPreference.resolve` walks the levels in order.
- The buttons are TextKit 2 viewport-positioned overlays (`CodeBlockOverlay`),
  not attachments, and the text view has to be stopped from eating their taps.

**The note page and pages (12–23 Sep).** Laid out from the 12 September
mockup: a title header with the note list behind ☰, and one hotbar docked
left, bottom or right carrying undo, redo, the text/draw toggle and the current
mode's tools. It replaced `PKToolPicker`. Notes are Letter-sized pages,
portrait or landscape, chosen when the note is made; a view menu shows them
seamless, compressed or as print layout; pinch zoom is a transform on the
scrolling text view, which measured 40 times cheaper per keystroke than a zoom
container.

**The drawing layer, steps 1–3 (19–23 Sep).** PaperKit's canvas inside the
text view's content, so both layers share one scroll position. Ink is stored in
print coordinates and shown on the same words in every mode. A finger draws
unless the canvas is locked to the Pencil, and ink has an undo stack separate
from the text's.

## Deferred work

Referenced by name from the code.

| Where | What |
|---|---|
| `PageLayout.swift` | **A4.** Notes print on US Letter only. A4 is one more paper size here, but a different width re-wraps the text, so it would be a property of the note, chosen when it's made, like orientation. |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are exclusion paths, and TextKit 2 then lays out everything below an edit: 34ms a keystroke near the top of a 250-line note on the simulator. If it lags on the iPad, push whole paragraphs with paragraph spacing instead, computed lazily. |
| `PageView.swift` | **Diagonal panning when zoomed in.** The text view scrolls vertically and `PageView` sideways, so a pan picks one. |
| `Page.swift` | **Text-anchored ink.** Wanted for its own sake, not just as a drift fix. Anchor each stroke to an `NSTextLocation` plus an offset, translate the group on relayout. Its own phase. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** `g142` and `python313`, chosen because the site has 1,197 compilers and no "latest" alias. A retired id still shows the code with the compiler pane complaining, so this is a maintenance item, not a risk. |
| `PageDetailView.swift` | **The macOS editor.** Still a plain `TextEditor` — no fences, no highlighting, no ink. |
| `Storage.swift` | **iCloud sync.** CloudKit via SwiftData, deferred past MVP by design. The model is shaped for CloudKit since 3 Oct (optional relationships, defaults, nothing unique), so turning it on needs no migration of its own. |
| Layout | **iPhone Duo.** Apple's foldable, out 23 Oct 2026, runs standard iOS 27.1, so it's covered by the iPhone target. Apple asks apps to resize with the scene rather than the screen, keep controls out of the fold (`reservedRegions`), and let bars run vertically down the side. Testing needs Xcode 27.1, which carries the Duo simulator. It takes the USB-C Apple Pencil (one report says not until after launch), so ink on any iPhone relies on a finger drawing, which works on PaperKit as of 23 Sep. Checked 2 Oct on the Xcode 27.1 beta (27A9269): main builds with no new warnings, and all 448 tests pass on the Duo simulator once the ink placement test allows a screen pixel, since a 3x screen puts PaperKit's shapes on its own pixels. The beta's iOS 27.1 runtime runs only the Duo, so iPads are still tested on 27.0. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms. Ink got the same treatment: 1,000 strokes read back in 29ms, so
  reading as a note opens is fine.
- **Isolate risk.** Spike the hard part standalone. A failed spike costs an
  afternoon; a failed integration costs a week.
- **Settings travel together.** `TextRewritingPolicy` groups six traits into
  one type with one `apply(to:)` so they cannot drift. `EditorMode` does the
  same for the drawing toggle.
- **Degrade, don't crash.** `Storage` falls back to an in-memory store and says
  so. Unreadable ink gives an empty canvas and a warning, and is never written
  over.
- **Check what's on screen, not what the code computed.** The view-switch bug
  of 13 Sep passed a test comparing the scroll offset to page geometry while
  the screen showed the wrong page. The debug launch options report where
  TextKit actually put the lines.
