# Features

What NoteCode contains, how each part works, and what is missing, by type of
feature. For Marcus and for agents: read this to learn what exists before
reading code, and to find the design note that has the detail. What is still to
be seen on a real iPad is one ordered list: [ipad-test-checklist.md](ipad-test-checklist.md).

- **Status:** *built* (merged to `main`), *partial* (built, with a named gap),
  *missing* (wanted, not built), *planned* (not in 1.0; see `docs/ROADMAP.md` › After 1.0),
  *idea* (not decided), *stalled* (decided to wait).
- **Built does not mean checked on a real iPad.** What is unchecked on the iPad
  is in `docs/ROADMAP.md` › Verification debt.
- **Feedback #n** is the item's number in Marcus's 21 Oct testing list, kept in
  `docs/archive/feedback-plan.md` with its stream and order.
- **Keep it current:** a PR that adds, changes or removes a feature updates its
  row here (same PR). A new feature gets a row in the right section. The "how
  it works" column stays one line; the reasoning goes in `docs/design/`.
- Not here: why something was decided, measurements, bug history (the design
  notes) and schedule (ROADMAP).

## 1. Notes and library

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Home | App opens here, with the list beside it in a regular width; Continue card for the last note, sections of recent notes with thumbnails, folders, Import and From Template; title screen on first launch; under 700pt wide (beside the list on a portrait 11-inch) it takes the phone layout (#117); toolbar is Settings only (plus Search in a compact stack) since the list's field and + are beside it; "Edited … ago" and "Today" tick each minute; thumbnails show dark in dark mode; folder tiles go 2 to 4 across by width and may wrap names; the ad is an opaque strip below the page (31 Oct) | built | `home-the-title-screen-thumbnails-reopening.md`, `iphone-and-the-duo.md` |
| Note list | Sidebar list over the page, no glass (opaque bar, Home's grey; icons: ellipsis.circle, checkmark.circle for Edit, square.and.arrow.up for Export); pinned first; folders and notes are sorted together; sort and order per device; a note's edited date is written when typing pauses (about 2s) and when the note closes or the app leaves the screen, so the list reorders after a pause, not per keystroke (F6); the list and Home fetch only the notes outside Recently Deleted, and the foot counts the deleted ones in the store (F8); search; swipe actions | built | `organising-notes.md` |
| Notes and folders as one list | One list holds folders and notes, sorted together | built (feedback #13) | |
| Sidebar on Home | The list sits beside Home in a regular width | built (feedback #3) | `ContentView` |
| Folders | One folder per note, nested, drag to arrange (the arrangement is kept but hidden by the sort), colour and symbol, pin, delete asks about contents | built | `organising-notes.md`, `recently-deleted-and-folder-faces.md` |
| Drag and drop of notes and folders | The list takes the drop as a whole (`ListDropBridge`), by rules plus the menu route; a note or folder onto the Recently Deleted row deletes it; the lift is held 0.25s; a note onto a folder and onto Library is tested on the iPad (`ListDragUITests`), the simulator delivers no drop | built; hover indicator, arranging, edge scroll, Recently Deleted drop and the shorter hold unchecked | `organising-notes.md` |
| New note "+" | Tap makes a note and, per the Open Note After Creating setting (default on since 31 Oct), opens it, or with the setting off shows a toast with Open instead; hold picks orientation; files in the open note's folder | built (feedback #12) | `WelcomeNote.swift` |
| Templates | Lecture, Problem and Lab; text only | built | `insert-and-templates.md` |
| Welcome note | First launch note | built | `organising-notes.md` |
| Recently Deleted | Delete moves a note there with an Undo toast; restore; purged after a period; folders go with their notes | built | `recently-deleted-and-folder-faces.md` |
| Note menu | Rename, Pin, Move to Folder (with Top Level), Get Info, Manage (Lock Text, Duplicate), Delete | built | `the-note-page.md` |
| Text lock | Read-only text, ink still works | built | `the-note-page.md` |
| Get Info | Counts and dates | built | `NoteInfoView.swift` |
| Thumbnails and reopening | Cards draw the note; a note reopens at its last page; a note's ink is read and decoded off the main actor, through a context of its own, for the thumbnail and for Home's Ink fact (F7); a note with unsaved changes (ink drawn moments ago) is saved first, so its thumbnail has that ink (list-x1) | built | `home-…md` |
| Search | By title (a note's first line until it is renamed) and text; a result shows the line it matched as the page draws it (no `#`, `**`, backticks, a link's address; code as typed); Find in Note inside a note; an empty search reads no note's text, so the list's cost doesn't grow with the notes (F4a) | built | `organising-notes.md` |
| Note titles | A note is "Untitled" in storage until renamed; what shows (list, Home, search, top bar, PDF and file names, Duplicate) is its first non-empty line with the Markdown markers left out, cut to 60 characters, and "Untitled" only for an empty note. Renaming stores the name; clearing it goes back to the first line | built | `organising-notes.md` |
| iCloud sync | Model is shaped for CloudKit; nothing syncs | planned (After 1.0) | ROADMAP |
| Face ID locking, note combining | | idea | ROADMAP |

## 2. Writing (text)

| Feature | How it works | Status | Detail |
|---|---|---|---|
| One continuous document | A note is one flowing text with Markdown as the source; markers are hidden unless the caret is in the line; typing or deleting over a selection that takes some of a span's hidden markers keeps them, so the span stays | built | `writing-hidden-markdown-markers-lists-checklists.md` |
| Headings | H1 to H6 from Aa (the hotbar's Style menu, headings only) or the hotkeys (H1 to H3) | built; a default size on the hotkey stalled (feedback #10) | `the-note-page.md` |
| Inline marks | Bold, italic, underline, strikethrough in the text options row (after the size control), inline code on the hotbar, highlight (six colours); applied per character; the bars light the state at the caret | built | `formatting-per-character.md`, `obsidian-s-other-marks-and-blocks.md` |
| Typing style | A press with a caret sets what the next characters will be | built | `typing-style.md` |
| Nested formatting | A real parser, not spans; bold inside colour inside italic | built | `inline-nesting.md` |
| Text colour | Row of swatches (and a Default ring) in the text options row, written as an Obsidian-compatible span | built | `coloured-and-sized-text.md` |
| Text size | Seven steps (14 to 23) plus any size per run with `+` and `−` | built | `coloured-and-sized-text.md`, `navigation-and-the-text-options-row.md` |
| Line spacing presets (pt) | Under More in the text row: Default, +2, +4, +6, +8, +12 pt; line height only; stored per note (`Page.lineSpacing`, so ModelFreezeTests' hash changed) | built (feedback #2) | `navigation-and-the-text-options-row.md` |
| Lists | Bulleted, numbered, checklist; Return continues, Tab and Shift-Tab indent, Backspace unwinds | built | `writing-hidden-…md` |
| Checklists | `- [ ]` boxes you tap | built | `MarkerTaps.swift` |
| Links | Markdown links, tappable | built | `writing-hidden-…md` |
| Quotes, rules | `>` quotes up to a depth, `---` rules | built | `obsidian-s-other-marks-and-blocks.md` |
| Paste and copy with formatting | Rich paste becomes Markdown with colours, sizes, code and lists; copy writes RTF and HTML as well | built | `paste-and-copy-with-formatting.md` |
| Autocorrect | On in prose, off in code; Settings › Writing › Autocorrect turns prose off, in a note that is already open too. Smart dashes make a typed `--` between words a dash while on; at a line's start the hyphens stay, so `---` is a rule or a front-matter fence. Where nothing rewrites (code, or prose with it off), two quick spaces stay two: the keyboard's "." shortcut is put back (`PeriodShortcut`) | built (feedback #19) | `the-note-page.md` |
| Marker dimming | Settings › Writing › Markers: heading marks, list bullets, checkboxes, code fences each Off / Dim (default) / Full | built (feedback #9) | `settings.md` |
| Caret on empty space | A tap below the last line adds the blank lines needed and puts the caret there, one undo step; gaps between sheets in print and compressed are not handled | built (feedback #7) | |
| Outline and page badge | Headings list (exactly as tall as its rows) jumps to a heading; "2 / 5" shows the page | built | `navigation-and-the-text-options-row.md` |
| Find in note | System find | built | `the-note-page.md` |
| Summarise Note | Pro. ••• › Summarise Note: an on-device summary in a sheet (long notes in up to 4 pieces); Copy or Insert Below | built; unverified on device | `ai-features.md` |
| LaTeX | Inline `$…$` (and `$$…$$` mid-line, display style) draws as a formula in the line, in the text's colour and size; a formula SwiftMath can't draw keeps its dollars and shows dimmed. A `$$` block (`$$`…`$$` over lines, or one line) draws as one centred formula on a line of its own, scaled down to fit the column, its source lines taking no room; an undrawable block shows as typed, dimmed. A drawn formula is one place for the caret; Backspace after it deletes all of it (one undo step); a selection never ends inside one. Tap opens an editor popover (sheet when narrow) with the source in monospace and a live preview — Done writes back as one undo step, Remove deletes it, read-only in a locked note. Inline Formula and Display Formula buttons on the hotbar (and the edit menu, ⇧⌘M / ⌥⌘M) insert a new inline or display formula over the selection. The PDF and thumbnails draw each formula as vectors in black on the sheet, and don't print its source. Copy puts the source in Menlo (`$…$`, and every line of a `$$` block) in the RTF, the plain text unchanged; a rich paste escapes a `$` as `\$` when it would otherwise make a formula. Get Info doesn't count words inside a formula, and an outline title shows a formula's TeX without its dollars | inline layout (L3), display blocks (L4), editing (L5), PDF/thumbnails (L6) and info/outline/copy/paste (L7) built; unverified on device | `latex.md` |
| Free text boxes | PaperKit has one through Insert; a text-box tool is not designed | idea (feedback #18) | |

## 3. Code blocks

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Fenced blocks | Triple backticks anywhere become a block; detected while typing, before the closing fence. A bare fence typed inside a block closes it only once its line is left, so typing ```swift there doesn't flash the rest of the note | built | `code-block-fences.md` |
| Languages | C++, Java, Python, C, JavaScript, Rust, Go, SQL; chosen from the hotbar or the block's name button | built | `code-languages-and-keys.md` |
| Unmarked blocks | Shown as "Code" (stored key unchanged); plain styling | built (feedback #15) | |
| Output blocks | An `output` fence for a program's result, on the code panel's own light/dark colours | built | `code-languages-and-keys.md` |
| Syntax highlighting | HighlightSwift with a custom theme; each role 4.5:1; the theme's weight and italic (keywords bold, comments italic) drawn in the code font at its size, so a line keeps its height | built | `colour.md` |
| Block header | Name, Run and Copy buttons in the block's corner | built | `code-blocks-room-around-and-inside.md` |
| Run | Pro runs in the app (below); free opens the paywall. No choice of where code runs (removed 30 Oct). A site is only the panel's way out (*Open on a Site Instead*) and Run in a build without a service: Compiler Explorer (code in the link) or Programiz (code copied) for Java, JavaScript and a block too long for a link | built | `AGENTS.md`, `CodeDestination.swift`, `scripts/refresh-ce-ids.sh` (the pinned compiler ids; 6 Nov: Python 3.15) |
| Run panel | Notes \| Run control in the top bar opens a pane at the page's right (360pt, dragged 280pt to half the window, collapses to an edge tab; a bottom sheet in a compact width): block strip, Run, Output and Input tabs, per-block input and last result (dimmed when the code changed). `RunSession`; `-debug-run-stub`. `RunServiceFactory.runService` (Pro/Run/RunSession.swift) supplies the runner; with `nil` none of it is visible | built (R3, R4) | `code-languages-and-keys.md`, `RunPanel.swift`, `RunSession.swift` |
| Run in the app | A free reader's ▷, ⌘R and the edit menu's Run open the paywall (`PaywallView`, "Run in the app is part of NoteCode Pro.") and do nothing else; the Run segment of the top bar carries a small PRO mark for them; Pro's run in the panel, every runnable language (C++, C, Java, Python, JavaScript, Rust, Go). The first run in the app is held while the panel says where the code goes (`RunDisclosure`: our run service and Judge0, with the Privacy Policy link); Run sends it and is remembered, Not Now sends nothing and asks again next time. Each run sends `ProStatus.signedTransaction`; a 402 refreshes `ProStatus` and opens the paywall. Offline, capped, service down or too large: the panel says which, and except offline offers *Open on a Site Instead*. **Keep in Note** writes or replaces the ```` ```output ```` block under the code (one undo step); a compile error's `file:line` is a link that puts the caret on that line. `RunRoute`, `KeepInNote` | built (R4) | `RunRouting.swift`, `CodeDestination.swift`, `RunPanel.swift` |
| Copy block | Copies the code with a Copied toast | built | `keyboard-edit-menu-…md` |
| Code keys row | ⇥ ⇤ and brackets above the keyboard | built | `code-languages-and-keys.md` |
| Indentation | Return keeps indent and opens a level after `{`; Tab and Backspace move a level; width is a setting | built | `code-languages-and-keys.md` |
| Line numbers | Setting, off by default | built | `code-languages-and-keys.md` |
| Wrapped lines | Continue past their indentation, with a mark | built | `code-blocks-room-around-and-inside.md` |
| Return in a block | A thin extra gap after Return was reported on 1.0 | not reproduced on `main` (feedback #14, #31); retest on the iPad | `code-blocks-room-around-and-inside.md` |
| Explain Code | Pro. Edit menu › Explain Block, or the Explain chip in the text row, on a block: Apple's on-device model explains it in a sheet; Copy, or Insert Below as a quote or output block (undoable) | built; unverified on device | `ai-features.md` |
| Running code in the app | Pro. Runner layer (R1), proxy (R2), panel (R3) and wiring (R4); see "Run panel" and "Run in the app" above. Contract: `docs/design/run-proxy-contract.md` | built (R1–R4); unverified on device | `RunServiceClient.swift`, `JavaMain.swift`, `CompilerMessages.swift`, `ReadsInput.swift` |

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
| Rectangular selection | Select tool, Rectangle or Lasso: move, scale from a corner, recolour, duplicate, delete; touching, not containing. A drag or scale shows the selection as a picture moved by a layer transform, so its cost doesn't grow with the note (O2) | built (24 Oct), unverified on the iPad (feedback #6) | `object-system.md` |
| Recolour text with the lasso | The shape also covers text, a range per line (never code); one colour control recolours ink and text | built (24 Oct), unverified on the iPad (feedback #26) | `object-system.md` |
| Add pages while drawing down | In compressed and print layout a stroke ending in the last page's bottom 15% adds a page; Settings › Drawing › Add Pages While Drawing | built (feedback #8) | |
| Selection behaviour | Selection clears on a tool or mode switch; PaperKit's own selection is let go of (one shape or image can be handed to it to Edit) | built (24 Oct); tap-to-highlight and the hotbar displacement not located, needs the probe log on the iPad (feedback #24, #29, #30) | `object-system.md` |
| Return to previous tool after a selection | Settings › Drawing › Return to Previous Tool, off by default; after Delete or a tap on empty space | built (24 Oct) (feedback #16) | `object-system.md` |
| Ink storage | `drawingData` is plain PaperKit bytes or an `NCOB` container with an object table (anchors, groups); empty table writes the plain bytes | built (24 Oct) | `object-system.md` |
| Hover mark follows the tool | The Pencil hover mark lags a tool or property change; the app draws no mark, PaperKit does | measured, PaperKit's; options in `pages.md` (feedback #17) | |
| Text-anchored ink, more shapes, logic gates | | planned (After 1.0) | ROADMAP |

## 5. Pages and layout

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Letter pages | US Letter, 96 units per inch; portrait or landscape per note | built | `pages.md`, `page-geometry-orientation-and-zoom.md` |
| View modes | Seamless, compressed (dashed breaks), print layout (separate sheets) | built | `pages.md` |
| Page breaks | A paragraph that would cross a page's end starts the next page whole (paragraph spacing, not exclusion paths), the same page in every mode; a paragraph taller than a page is broken by line. A keystroke near the top of a 40-page note costs about what it does unpaged (F5) | built; moves breaks against 1.1.0, where single lines were pushed; typing feel on the iPad unchecked | `pages.md` |
| Zoom | Pinch to zoom; zoom does not re-wrap text | built | `page-geometry-orientation-and-zoom.md` |
| Add Page | Appends a page | built | `pages.md` |
| The page fills the window | The hotbar floats over the page or takes a strip at a side | built, with a 10pt edge buffer (feedback #1) | `the-page-fills-the-window.md` |
| Scrolling | The text view scrolls and its pan lives on the page: a drag anywhere (background included) scrolls, diagonally when zoomed, with sideways momentum; no give at the top; own indicator at the window edge (the text view's inside-the-page one is off); hairline under the top bar; page edge and shadow (W2) | built; feel on the iPad unchecked | `who-owns-scrolling.md` |
| A4, side-by-side pages, infinite canvas | | idea | ROADMAP |
| Paper styles | Removed for the full release (31 Oct, Marcus): every note shows plain paper, with no menu, setting, template or debug argument for it. The drawing code is gone; `Page.paperStyle` stays in the model, unused, so version 1's hashes hold | removed | `paper-styles.md` |
| Text alignment | A text alignment system (left, centre, right, justified) to come in place of paper styles | idea | ROADMAP |
| Typing in a long note | Typing near the top of a 40-page note costs about 97ms a keystroke; the text view's exclusion paths for the pages are the cost (98.8 to 111.1 ms with them, 0.8 without) and no safe fix exists | measured, not fixed (F5) | `baseline.md` › Release QA 4A |
| Blank pages after moving between pages | Ink is absent about 130 to 200ms after a jump with 3,000 strokes while PaperKit draws the new region; not reproduced at "a few seconds" | measured, options in `pages.md` (feedback #27) | |

## 6. Interface

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Header | One joined pill at the top left (list and Home, drawn icons), editable title with menu, then the Notes \| Run switch (when Run is offered), Share, •••; the note shrinks into its Home card on the way home (cross-fade with Reduce Motion) | built (W3) | `the-note-page.md` |
| Hotbar | Docks left, bottom or right; undo, redo, text/draw toggle (on a light grey disc in both modes, so it reads as the thing to try), then the mode's tools; on a phone a B I U button after the toggle brings out the text options row, which otherwise stays in, and a scrolling bar or row fades at an end with more past it | built | `the-note-page.md` |
| Options rows | Text row (B/I/U/S, colour swatches, highlight, size, More; opaque, no glass) and ink row (palette, widths, eraser mode) beside the bar | built | `navigation-and-the-text-options-row.md` |
| Settings inside a note | Settings at the foot of the note's ••• menu | built (feedback #11) | |
| Keyboard shortcuts | One table: formatting, headings, tools, view modes, run and copy block, find, print, new note and folder, home, settings | built; unchecked with a real keyboard | `keyboard-edit-menu-…md` |
| Edit menu | Cut, Copy and Paste first, then Format entries on selection | built | `keyboard-edit-menu-…md` |
| Pointer | Hover effects on controls | built | `keyboard-edit-menu-…md` |
| Toasts, empty states | One toast at a time with Undo; empty states use the mark | built | `recently-deleted-…md`, `settings-toasts-polish-v3-phase-8.md` |
| Accessibility | VoiceOver labels, Reduce Motion, Increase Contrast; the note body ignores Dynamic Type | built; sweeps unchecked | `settings-toasts-polish-…md` |
| iPhone and Duo | Compact stack, fold avoidance; in the 1.0.1 release (31 Oct) | built; simulator only, no physical Duo | `iphone-and-the-duo.md` |
| Colour and icons | Accent editable; Settings › Drawing › Colour Set picks Refined or Original highlighters; highlighter swatches are marker chips, vivid on dark bars; Settings › General › Toolbar Icons picks NoteCode's drawn icons or the system's, with an Icon Weight | built (feedback #4, #5, #28) | `colour.md` |
| macOS | Not a platform of the app target since 1.2.0 (debt D14); the old Mac editor was a plain `TextEditor` with no fences or ink | planned | NOW.md queue 6 |

## 7. Sharing, import and export

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Share | Menu with a primary action; PDF and Markdown; the sheet points at the button (the top right when the button is in no window, which a short inkless note gave); the PDF's title and file name are the note's title (its first line if blank) | built | `notes-in-and-out-and-one-editor-per-note.md` |
| PDF | Laid out afresh, text a line at a time, ink as a picture. Trailing pages with no text and no ink (margin ink counts) are left out, so pages added automatically while writing near the end do not print; blank pages between content stay, and an empty note prints one page. The note and its page count are untouched | built | `pages.md` |
| Print | System print of the PDF | built | `keyboard-edit-menu-…md` |
| Export All and Import | A folder of Markdown files and back; each note's PDF, if any, titled with the note's shown title, as its file name is, and without trailing blank pages (as PDF above) | built; unchecked on the iPad | `notes-in-and-out-…md` |
| Several windows | One editor per note; Open in Another Window | built | `notes-in-and-out-…md` |

## 8. Settings

Sheet with General, Pro, Notes, Writing, Code, Drawing and Help and About
(`SettingsView.swift`, `DrawingSettings.swift`); design in `settings.md`.

| Page | Contains | Missing |
|---|---|---|
| General | Appearance, Accent Colour, Toolbar Position, Haptic on Snap, App Icon, Toolbar Icons and Icon Weight | whole-app palette reset |
| Notes | New Notes orientation, Open Note After Creating, View, Sort By and Order, Recently Deleted, Export All | |
| Writing | Show Markdown, Autocorrect, Markers (four rows), On-Device Assistant (switch, Answer Length, Insert As) | |
| Code | Code Keys, Indent Width, Line Numbers | |
| Drawing | Finger Draws, Erases, Size, Colour Set, Pens and Highlighters palettes, Pencil actions, Add Pages While Drawing, Return to Previous Tool, Reset Colours | |
| Pro | Status (Pro or Free), renewal, Manage, Restore, See NoteCode Pro (`ProSettings.swift`) | |
| Help and About | Welcome note and screen, version, licences, tip jar, privacy row (always) and feedback and feature-request rows, mailing `notecodesupport@gmail.com` (`AppInfo.feedbackAddress`, set 31 Oct) | |

## 9. Shell and release

| Feature | How it works | Status | Detail |
|---|---|---|---|
| Tip jar | Three consumable tips; unlocks nothing | built; needs App Store Connect | `the-list-s-foot-and-the-tip-jar.md` |
| App icon | Drawn by a script; Default, Dark, Tinted plus two alternates | built | `AGENTS.md` › Shipping |
| Privacy | Notes never leave the device. Run (Pro) sends a block's code and input to our proxy and Judge0; ads (free) send what Google's SDK collects, unlinked. Manifest declares the ad data and UserDefaults. Policy rewritten for both (`docs/site/privacy.md`) | policy drafted; Marcus publishes it to `gh-pages` | `docs/design/shipping.md` › Privacy, Run and ads |
| Storage | SwiftData, schema version 1 frozen by hashes; falls back to memory with a warning | built | `AGENTS.md` › The model |
| Pro status | `ProStatus`: whether the reader has Pro (`com.marcus.NoteCode.pro.monthly`, $4.99 a month), its expiry and the signed transaction for the Run proxy; purchase, Restore, Manage; `-debug-pro on\|off`. The AI actions read it (P2); ads (P3) and Run (R4) read it too | built (P1) | `the-list-s-foot-and-the-tip-jar.md`, `ProStatus.swift` |
| Paywall and AI gate | `PaywallView`: what Pro gives, this iPad's AI availability, price and period, Subscribe, Restore, Terms of Use, Privacy Policy (always: `AppInfo.privacyPolicy` is set), and the renewal terms with Apple's cancel-24-hours line. If the store doesn't answer or has no product, "Couldn't reach the App Store." with Try Again instead of a price that never loads (`ProStatus.productFailed`). A free reader's Explain or Summarise opens it instead of the sheet and starts no model session (`AIAssistant.needsPro`). Settings › Pro: status, renewal, Manage, Restore. Run opens it too ("Run in the app is part of NoteCode Pro."), and so does Remove ads (P3) | built (P2); unverified on device | `ai-features.md`, `PaywallView.swift`, `ProSettings.swift` |
| Ads | Banner (standard anchored adaptive, at most 90pt) for readers without Pro, in an opaque strip below Home's page and in the list's foot, with Remove ads under it opening the paywall; sized from the width of its slot, so it stays inside the column (#117). UMP consent form first (EEA/UK), then the Mobile Ads SDK starts; the app's ATT prompt waits for a second Home visit, never launch, but while the AdMob console publishes its IDFA explainer, readers outside the EEA/UK get Google's explainer and then ATT on the first visit (`shipping.md` › Ads, open choice). Refused or unasked tracking: non-personalised (`npa`). Where UMP requires it, Help and About › **Ad Privacy Options** reopens Google's form to change the answer; on a launch that skipped Home it asks UMP when that page opens, showing nothing. Test ids in Debug, real ids in Release (`AdConfig`) | built (P3); unverified on device | `shipping.md`, `AdConfig.swift`, `AdConsent.swift`, `AdBanner.swift` |
| Rating prompt | iOS's App Store rating sheet (`requestReview`), a second after a note closes back to Home, once notes were opened on three different days; once a version and 120 days apart, and iOS may still show nothing (`ReviewPrompt`). Never for a note just deleted, in a debug launch, or while a free reader's tracking prompt is still to come. A build from Xcode always shows it; TestFlight never does | built; unverified on device | `ReviewPrompt.swift` |
| Group notes, sign-in | Needs a server; nothing else in the app does | idea | ROADMAP |

## 10. Editions and tooling

What the app is built as, and what guards it. For a feature's place in the
code, see AGENTS.md › How a feature plugs in.

| Feature | How it works | Status | Detail |
|---|---|---|---|
| App Store edition | `Pro/AppStoreEdition.swift` is the `@main`; it hands `NoteCodeScene` `AppExtensions.appStore` (Pro, Run, assistant, ads, tip jar) | built | `AGENTS.md`, `refactor/2X-seam.md` |
| Open-source edition | `OpenSource/OpenSourceEdition.swift` is the `@main` with `AppExtensions.none`; the build is `NoteCode/` minus `Pro/`. Run opens a compiler site. Proved by `scripts/build-open-source.sh`; not yet published. `scripts/export-public.sh` copies what `scripts/public-paths.txt` allows into a folder and scans it; draft public docs in `OpenSource/docs-draft/` | built; the public repo is planned | `refactor/split.md` |
| The seam | No file outside `Pro/` names a `Pro/` type; `check-seam.sh` counts breaches (0) | built | `AGENTS.md` |
| Editor features | `EditorFeature` adds actions, a top-bar item, a side panel and Run to a note's editor; Run and the assistant are the two | built | `NotePage/EditorFeature.swift` |
| Pure core | `Text/Core` compiles alone with `swift test` (`Package.swift`, `scripts/core-test.sh`) | built | `refactor/T11-core-package.md` |
| Checks | `check.sh` (lint, seam, core tests, build, tests, warning ratchet), `lint-traps.sh`, `perf.sh`, `verify-move.sh` | built | `AGENTS.md` › Scripts |
