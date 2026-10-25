# Features

What NoteCode contains, how each part works, and what is missing, by type of
feature. For Marcus and for agents: read this to learn what exists before
reading code, and to find the design note that has the detail. What is still to
be seen on a real iPad is one ordered list: [ipad-test-checklist.md](ipad-test-checklist.md).

- **Status:** *built* (merged to `main`), *partial* (built, with a named gap),
  *missing* (wanted, not built), *planned* (scheduled in `docs/feedback-plan.md`),
  *idea* (not decided), *stalled* (decided to wait).
- **Built does not mean checked on a real iPad.** What is unchecked on the iPad
  is in `docs/ROADMAP.md` › Verification debt.
- **Feedback #n** is the item's number in Marcus's 21 Oct testing list, kept in
  `docs/feedback-plan.md` with its stream and order.
- **Keep it current:** a PR that adds, changes or removes a feature updates its
  row here (same PR). A new feature gets a row in the right section. The "how
  it works" column stays one line; the reasoning goes in `docs/design/`.
- Not here: why something was decided, measurements, bug history (the design
  notes) and schedule (ROADMAP).

## 1. Notes and library

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Home | App opens here, with the list beside it in a regular width; Continue card for the last note, sections of recent notes with thumbnails, folders, Import and From Template; title screen on first launch | built | `home-the-title-screen-thumbnails-reopening.md` |
| Note list | Sidebar list over the page; pinned first; folders and notes are sorted together; sort and order per device; search; swipe actions | built | `organising-notes.md` |
| Notes and folders as one list | One list holds folders and notes, sorted together | built (feedback #13) | |
| Sidebar on Home | The list sits beside Home in a regular width | built (feedback #3) | `ContentView` |
| Folders | One folder per note, nested, drag to arrange (the arrangement is kept but hidden by the sort), colour and symbol, pin, delete asks about contents | built | `organising-notes.md`, `recently-deleted-and-folder-faces.md` |
| Drag and drop of notes and folders | The list takes the drop as a whole (`ListDropBridge`), by rules plus the menu route; a note onto a folder and onto Library is tested on the iPad (`ListDragUITests`), the simulator delivers no drop | built; hover indicator, arranging and edge scroll unchecked | `organising-notes.md` |
| New note "+" | Tap makes a note and, per the Open Note After Creating setting (default off), shows a toast with Open instead of opening it; hold picks orientation; files in the open note's folder | built (feedback #12) | `WelcomeNote.swift` |
| Templates | Lecture, Problem and Lab; text only | built | `insert-and-templates.md` |
| Welcome note | First launch note | built | `organising-notes.md` |
| Recently Deleted | Delete moves a note there with an Undo toast; restore; purged after a period; folders go with their notes | built | `recently-deleted-and-folder-faces.md` |
| Note menu | Rename, Pin, Move to Folder, Remove from Folder, Lock Text, Duplicate, Get Info, Delete | built | `the-note-page.md` |
| Text lock | Read-only text, ink still works | built | `the-note-page.md` |
| Get Info | Counts and dates | built | `NoteInfoView.swift` |
| Thumbnails and reopening | Cards draw the note; a note reopens at its last page | built | `home-…md` |
| Search | By title and text; Find in Note inside a note | built | `organising-notes.md` |
| iCloud sync | Model is shaped for CloudKit; nothing syncs | planned (stream L) | ROADMAP |
| Face ID locking, note combining | | idea | ROADMAP |

## 2. Writing (text)

| Feature | How it works | Status | Detail |
|---|---|---|---|
| One continuous document | A note is one flowing text with Markdown as the source; markers are hidden unless the caret is in the line | built | `writing-hidden-markdown-markers-lists-checklists.md` |
| Headings | H1 to H6 from Style ▾ or the hotkeys (H1 to H3) | built; a default size on the hotkey stalled (feedback #10) | `the-note-page.md` |
| Inline marks | Bold, italic, strikethrough, underline, inline code, highlight (six colours); applied per character; the bar lights the state at the caret | built | `formatting-per-character.md`, `obsidian-s-other-marks-and-blocks.md` |
| Typing style | A press with a caret sets what the next characters will be | built | `typing-style.md` |
| Nested formatting | A real parser, not spans; bold inside colour inside italic | built | `inline-nesting.md` |
| Text colour | Colour menu in the text options row, written as an Obsidian-compatible span | built | `coloured-and-sized-text.md` |
| Text size | Seven steps (14 to 23) plus any size per run with `+` and `−` | built | `coloured-and-sized-text.md`, `navigation-and-the-text-options-row.md` |
| Line spacing presets (pt) | Menu in the text row: Default, +2, +4, +6, +8, +12 pt; line height only; stored per note (`Page.lineSpacing`, so ModelFreezeTests' hash changed) | built (feedback #2) | `navigation-and-the-text-options-row.md` |
| Lists | Bulleted, numbered, checklist; Return continues, Tab and Shift-Tab indent, Backspace unwinds | built | `writing-hidden-…md` |
| Checklists | `- [ ]` boxes you tap | built | `MarkerTaps.swift` |
| Links | Markdown links, tappable | built | `writing-hidden-…md` |
| Quotes, rules | `>` quotes up to a depth, `---` rules | built | `obsidian-s-other-marks-and-blocks.md` |
| Paste and copy with formatting | Rich paste becomes Markdown with colours, sizes, code and lists; copy writes RTF and HTML as well | built | `paste-and-copy-with-formatting.md` |
| Autocorrect | On in prose, off in code; Settings › Writing › Autocorrect turns prose off. Smart dashes turn `---` into "—-" while on | built (feedback #19) | `the-note-page.md` |
| Marker dimming | Settings › Writing › Markers: heading marks, list bullets, checkboxes, code fences each Off / Dim (default) / Full | built (feedback #9) | `settings.md` |
| Caret on empty space | A tap below the last line adds the blank lines needed and puts the caret there, one undo step; gaps between sheets in print and compressed are not handled | built (feedback #7) | |
| Outline and page badge | Headings list jumps to a heading; "2 / 5" shows the page | built | `navigation-and-the-text-options-row.md` |
| Find in note | System find | built | `the-note-page.md` |
| Summarise Note | ••• › Summarise Note: an on-device summary in a sheet (long notes in up to 4 pieces); Copy or Insert Below | built; unverified on device | `ai-features.md` |
| LaTeX | | planned, design note done (`docs/design/latex.md`), needs SwiftMath package added by Marcus | `latex.md` |
| Free text boxes | PaperKit has one through Insert; a text-box tool is not designed | idea (feedback #18) | |

## 3. Code blocks

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Fenced blocks | Triple backticks anywhere become a block; detected while typing, before the closing fence | built | `code-block-fences.md` |
| Languages | C++, Java, Python, C, JavaScript, Rust, Go, SQL; chosen from the hotbar or the block's name button | built | `code-languages-and-keys.md` |
| Unmarked blocks | Shown as "Code" (stored key unchanged); plain styling | built (feedback #15) | |
| Output blocks | An `output` fence for a program's result | built | `code-languages-and-keys.md` |
| Syntax highlighting | HighlightSwift with a custom theme; each role 4.5:1 | built | `colour.md` |
| Block header | Name, Run and Copy buttons in the block's corner | built | `code-blocks-room-around-and-inside.md` |
| Run | Redirect to a free compiler: Compiler Explorer (code in the link) or Programiz or OnlineGDB or a custom site (code copied); chosen per note, folder or app | built | `AGENTS.md`, `CodeDestination.swift` |
| Copy block | Copies the code with a Copied toast | built | `keyboard-edit-menu-…md` |
| Code keys row | ⇥ ⇤ and brackets above the keyboard | built | `code-languages-and-keys.md` |
| Indentation | Return keeps indent and opens a level after `{`; Tab and Backspace move a level; width is a setting | built | `code-languages-and-keys.md` |
| Line numbers | Setting, off by default | built | `code-languages-and-keys.md` |
| Wrapped lines | Continue past their indentation, with a mark | built | `code-blocks-room-around-and-inside.md` |
| Return in a block | A thin extra gap after Return was reported on 1.0 | not reproduced on `main` (feedback #14, #31); retest on the iPad | `code-blocks-room-around-and-inside.md` |
| Explain Code | Edit menu › Explain Block, or the Explain chip in the text row, on a block: Apple's on-device model explains it in a sheet; Copy, or Insert Below as a quote or output block (undoable) | built; unverified on device | `ai-features.md` |
| Running code in the app | Out of scope on purpose | not planned | `AGENTS.md` |

## 4. Drawing and ink

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Ink layer | PaperKit canvas over the page; the toggle gives touch ownership to text or ink | built | `AGENTS.md`, `archive/phase-drawing-layer.md` |
| Tools | Pen, highlighter, eraser (pixel or object), Select (lasso or rectangle; the button is still the lasso's) | built; Select, with its options row (shape, then commands once something is selected), unverified on the iPad | `object-system.md` |
| Palettes | Seven pen colours and five highlighters; editable; per-tool width (fine, medium, bold) and colour remembered | built | `the-note-page.md`, `settings.md` |
| Finger Draws | Finger draws or is ignored, per device | built | `the-note-page.md` |
| Ink undo | Separate from text undo | built | `the-note-page.md` |
| Insert | Photo, shapes, text box through PaperKit's popover | built; dragging them unchecked on the iPad | `insert-and-templates.md` |
| Pencil double tap and squeeze | Swap to eraser, swap to previous tool, or show the ink tools; in text mode they switch to ink first | built; unchecked with a Pencil (feedback #23) | `the-note-page.md` |
| Ink across pages | Ink cut cleanly at page breaks | built | `pages.md` |
| Ink in the PDF | Printed as a picture at 288 dpi | built | `pages.md` |
| Rectangular selection | Select tool, Rectangle or Lasso: move, scale from a corner, recolour, duplicate, delete; touching, not containing | built (24 Oct), unverified on the iPad (feedback #6) | `object-system.md` |
| Recolour text with the lasso | The shape also covers text, a range per line (never code); one colour control recolours ink and text | built (24 Oct), unverified on the iPad (feedback #26) | `object-system.md` |
| Add pages while drawing down | In compressed and print layout a stroke ending in the last page's bottom 15% adds a page; Settings › Drawing › Add Pages While Drawing | built (feedback #8) | |
| Selection behaviour | Selection clears on a tool or mode switch; PaperKit's own selection is let go of (one shape or image can be handed to it to Edit) | built (24 Oct); tap-to-highlight and the hotbar displacement not located, needs the probe log on the iPad (feedback #24, #29, #30) | `object-system.md` |
| Return to previous tool after a selection | Settings › Drawing › Return to Previous Tool, off by default; after Delete or a tap on empty space | built (24 Oct) (feedback #16) | `object-system.md` |
| Ink storage | `drawingData` is plain PaperKit bytes or an `NCOB` container with an object table (anchors, groups); empty table writes the plain bytes | built (24 Oct) | `object-system.md` |
| Hover mark follows the tool | The Pencil hover mark lags a tool or property change; the app draws no mark, PaperKit does | measured, PaperKit's; options in `pages.md` (feedback #17) | |
| Text-anchored ink, more shapes, logic gates | | planned (stream L) | ROADMAP |

## 5. Pages and layout

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Letter pages | US Letter, 96 units per inch; portrait or landscape per note | built | `pages.md`, `page-geometry-orientation-and-zoom.md` |
| View modes | Seamless, compressed (dashed breaks), print layout (separate sheets) | built | `pages.md` |
| Zoom | Pinch to zoom; zoom does not re-wrap text | built | `page-geometry-orientation-and-zoom.md` |
| Add Page | Appends a page | built | `pages.md` |
| The page fills the window | The hotbar floats over the page or takes a strip at a side | built, with a 10pt edge buffer (feedback #1) | `the-page-fills-the-window.md` |
| Scrolling | The text view scrolls; the page handles zoom and pan | built | `who-owns-scrolling.md` |
| A4, side-by-side pages, infinite canvas | | idea | ROADMAP |
| Paper styles | Blank, dots, grid, lined per note; spacing (Fine, Standard, Wide) and strength (Light, Standard, Strong) too; vector shape layers behind text and ink in each page body, so nothing is laid out and it stays on its points at every zoom and mode; printed and in thumbnails (0.75 alpha); ••• › Paper per note, Settings › Notes › Paper for new notes (default blank); Duplicate copies it, templates and Import take the default | built; not seen on a real iPad, the menu and the Settings rows not looked at | `paper-styles.md` |
| Blank pages after moving between pages | Ink is absent about 130 to 200ms after a jump with 3,000 strokes while PaperKit draws the new region; not reproduced at "a few seconds" | measured, options in `pages.md` (feedback #27) | |

## 6. Interface

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Header | Home, list, editable title with menu, Share, ••• | built | `the-note-page.md` |
| Hotbar | Docks left, bottom or right; undo, redo, text/draw toggle, then the mode's tools | built | `the-note-page.md` |
| Options rows | Text row (size, colour, and so on) and ink row (palette, widths, eraser mode) beside the bar | built | `navigation-and-the-text-options-row.md` |
| Settings inside a note | Settings at the foot of the note's ••• menu | built (feedback #11) | |
| Keyboard shortcuts | One table: formatting, headings, tools, view modes, run and copy block, find, print, new note and folder, home, settings | built; unchecked with a real keyboard | `keyboard-edit-menu-…md` |
| Edit menu | Format entries on selection | built | `keyboard-edit-menu-…md` |
| Pointer | Hover effects on controls | built | `keyboard-edit-menu-…md` |
| Toasts, empty states | One toast at a time with Undo; empty states use the mark | built | `recently-deleted-…md`, `settings-toasts-polish-v3-phase-8.md` |
| Accessibility | VoiceOver labels, Reduce Motion, Increase Contrast; the note body ignores Dynamic Type | built; sweeps unchecked | `settings-toasts-polish-…md` |
| iPhone and Duo | Compact stack, fold avoidance; the target is still iPad-only | partial: not turned on | `iphone-and-the-duo.md` |
| Colour and icons | Accent editable; Settings › Drawing › Colour Set picks Refined or Original highlighters; highlighter swatches are marker chips, vivid on dark bars; Settings › General › Toolbar Icons picks NoteCode's drawn icons or the system's, with an Icon Weight | built (feedback #4, #5, #28) | `colour.md` |
| macOS | Builds; the editor is a plain `TextEditor` with no fences or ink | partial | ROADMAP |

## 7. Sharing, import and export

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Share | Menu with a primary action; PDF and Markdown | built | `notes-in-and-out-and-one-editor-per-note.md` |
| PDF | Laid out afresh, text a line at a time, ink as a picture | built | `pages.md` |
| Print | System print of the PDF | built | `keyboard-edit-menu-…md` |
| Export All and Import | A folder of Markdown files and back | built; unchecked on the iPad | `notes-in-and-out-…md` |
| Several windows | One editor per note; Open in Another Window | built | `notes-in-and-out-…md` |

## 8. Settings

Sheet with General, Notes, Writing, Code, Drawing and About
(`SettingsView.swift`, `DrawingSettings.swift`); design in `settings.md`.

| Page | Contains | Missing |
|---|---|---|
| General | Appearance, Accent Colour, Toolbar Position, Haptic on Snap, App Icon, Toolbar Icons and Icon Weight | whole-app palette reset |
| Notes | New Notes orientation, Open Note After Creating, View, Sort By and Order, Recently Deleted, Export All | |
| Writing | Show Markdown, Autocorrect, Markers (four rows), On-Device Assistant (switch, Answer Length, Insert As) | |
| Code | Run Code In, Code Keys, Indent Width, Line Numbers | |
| Drawing | Finger Draws, Erases, Size, Colour Set, Pens and Highlighters palettes, Pencil actions, Add Pages While Drawing, Return to Previous Tool, Reset Colours | |
| About | Version, licences, tip jar, privacy and feedback rows once set | |

## 9. Shell and release

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Tip jar | Three consumable tips; unlocks nothing | built; needs App Store Connect | `the-list-s-foot-and-the-tip-jar.md` |
| App icon | Drawn by a script; Default, Dark, Tinted plus two alternates | built | `AGENTS.md` › Shipping |
| Privacy | Nothing collected; manifest lists UserDefaults only | built; pages not hosted | `AGENTS.md` › Shipping |
| Storage | SwiftData, schema version 1 frozen by hashes; falls back to memory with a warning | built | `AGENTS.md` › The model |
| Ads and Pro, group notes | | planned or idea (stream L) | ROADMAP |
