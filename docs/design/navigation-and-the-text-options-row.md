# Navigation and the text options row
v3 phase 6 (14 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **The outline** (`NoteOutline`, `NoteOutlineView`) lists the headings the
  parser finds (`DocumentParser`, so a `#` line in code isn't one and
  `#hashtag` isn't), computed when the popover opens and never stored. Outline
  in the note's ••• menu (it was a header button until 16 Oct; the popover now
  hangs off the ••• button) and ⌃⌘O (View menu, through `OpenNote.showOutline`)
  open it; each row is `NoteOutlineView.rowHeight` and the popover is exactly
  as tall as its rows (it had 24pt extra, which showed as an empty row at the
  bottom); rows are indented by level from the note's highest, the heading
  the reader is under is ticked (the last at or above the line at the top),
  and an empty heading reads "Untitled". Offsets are UTF-16, accumulated in
  one pass as `DocumentStyler.layouts` does.
  - **A tap is `PageView.scroll(toLineAt:)`**, which shares `reveal`'s way of
    getting there (`layOut(downTo:)`, then the offset) but puts the line at
    the top rather than a quarter down. A page's first line shows that page
    from its top edge, as a mode switch does; a heading too near the end to
    reach the top lands as far up as the note scrolls.
  - **The offset is rounded up to a whole pixel** (`pixelCeiling`). A scroll
    offset snaps to the screen's pixels, and one that snapped down from a
    line's top left the line above showing by a fraction of a point, which is
    then the first line the reader sees: a size change landed one line early
    in five of six cases until this.
- **The page badge** ("2 / 5", `PageBadge`): `PageView.onScrolled` fires
  after any layout pass that moved the offset, hopped to the next turn of the
  main queue (a pass can be inside a SwiftUI update, and the callback sets
  state); `PageDetailView` shows it 18pt under the header and fades it a second
  after the last move. Not while the app is positioning the note
  (`pendingRestore`, `pendingReveal`); the first move after a restore does
  show it once, which reads right ("page 3 of 5") and was not looked at.
- **Text size is `NoteTypography`** (a value, `NoteTypography.swift`), seven
  steps: 14, 15, 16, 17 (default), 19, 21, 23, each the system's body at one
  Dynamic Type step (xSmall to xxxLarge), so every size keeps that step's
  leading. `bodySize` snaps a stored value that isn't a step to the nearest;
  `storedSize` is `nil` at 17, so a note nobody resized keeps today's model
  and today's thumbnail name.
  - **Everything that reads a note's fonts takes it:** the styler
    (`DocumentStyler`'s attributes, `applyStyling`, `applyTypingAttributes` and
    `listParagraphStyle` all take a `typography`, defaulting to `.standard`,
    so a caller that never asks gets exactly today's fonts), the list-marker
    width cache (keyed by size), line numbers (sized by the code beside them,
    `NoteTypography.lineNumberFont(forCodeSize:)`), the hanging heading marker
    and the checkbox (both already took the paragraph's own font),
    `PrintedNote`/`NotePDF.Note.typography`, `NoteThumbnail.Source.typography`,
    and `-debug-text-size` with `topLinePoints` in the report.
  - **A coordinator owns it** (`Coordinator.typography`, `setTypography`), not
    a global, so a PDF or a thumbnail made while another note is open has its
    own note's size (`notesDontShareASize`). `UITextView.font` is not set on a
    change: that replaces every run's font and the restyle would undo it with
    a second layout.
  - **A thumbnail's cache name has `-t<size>`** when the size isn't the
    default, since a size isn't an edit and leaves `modifiedAt` alone, and its
    row's task restarts on the size as well as the date.
  - **Applying a size re-wraps**, so `PageView.reflow` keeps the reader on the
    line they were on, as an orientation switch does: it takes the top line,
    runs the change, lays out, re-anchors TextKit at the note's top, lays out
    down to the line and settles the offset on it, again while it moves (the
    page count, and so the bands, can still change). The test checks the line
    at the top against the same note laid out from scratch at the new size.
  - **Picked from ••• › Text Size** since 18 Oct (text overhaul, phase 1):
    the row's stepper became the selection's size (see "Coloured and sized
    text"). A pick isn't a change yet: `NoteEditor.textSize` is what the menu
    shows, and the note catches up after `settleDelay` (300ms). A note with
    ink asks first, in the board's wording, **once each time the note is
    opened** (the editor is made per note): Cancel puts the menu back. The
    size is written through `commitTextSize` into `Page.textSize` and nothing
    else: `modifiedAt` stays, nothing goes on the text undo stack. Off in ink
    mode and for a locked note, as the stepper was.
  - **⌘+ and ⌘−** (Bigger Text, Smaller Text, in Format) step the
    selection's size since 18 Oct, as Pages' do; the system left both free.
    Not tried with a real keyboard (the key is "+", which on a US layout is
    ⇧⌘=).
  - **Measured while writing the tests:** TextKit 2 sets a line taller than
    the font's own `lineHeight` (19.0pt a line at 14, 22.0 at 17; the font
    says 16.7 and 20.3), so a Letter page holds 48 lines at 14 and 41 at 17.
    A test of page counts at two sizes needs enough lines for that to show:
    200 lines were five pages at 14, 15, 16 and 17 alike.
  - **A test harness whose caret is at the note's end scrolls there** after a
    restyle (`PageSettlingTests.openNote` leaves it there on purpose): the
    size-change tests started at the end and "jumped" there, which looked
    like a `reflow` bug for an hour. They use `ReopenTests.open`, whose caret
    is untouched.
- **The text options row** (`TextOptionsRow`) is text mode's counterpart of
  the ink options row: the same `BesideBar` overlay 8pt from the bar on its
  page side, in `OptionsRowStyle` (40pt to the eye, 44pt reach, glass), so it
  reserves nothing. `HotbarLayoutTests` passes with it. It is out in text
  mode, for a note that isn't locked, with no sheet over the page
  (`Hotbar.textRowHidden`: the info sheet and the folder editor); it slides
  in with the bar's own transition and cross-fades under Reduce Motion.
  Docked at a side it is vertical.
  - **With the keyboard up**, docked at the bottom, `keyboardClearance` adds the
    row's gap and reach (8 + 44) while it is showing, so the caret's line
    stays above it (`PageDetailView.keyboardClearance`).
  - **The size control comes first**, `+ 17 −` across and `+` over `17` over
    `−` down, with the size on a `secondarySystemFill` pill. Since 18 Oct it
    is the size of the text at the caret or the selection, not the note's
    (see "Coloured and sized text").
  - **The rest follows the caret** (`CaretFormatting.block`, from the parse
    of one line, and for code from the `CodeRange` list, which now carries the
    fence's tag): a paragraph or heading shows Body, H1, H2, H3 (the current
    one tinted) and Link; a list item the three kinds and ⇤ ⇥; a code block
    its language (the block's own button's list, `CodeBlockKind.menu`), ⇤ ⇥
    and + Output (not on an output block, and off for an unclosed one, which
    has no place after it).
  - **Every control does what a menu already did**, through
    `replace(_:withText:)`, so it undoes like typing: Body and H1 to H3 are
    `setHeading`, the lists `toggleList`, ⇥ and ⇤ the coordinator's
    `indentEdit(outdent:)` (code lines' rule in a block, the list item's
    elsewhere: Tab, ⇧Tab and the row ask the same function), the language
    the block's retag (`setKind`), + Output `MarkdownFormatting.insertOutputBlock`
    and Link `linkTarget`/`link` (pure, `MarkdownFormatting+TextRow.swift`).
  - **Link wraps the selection, or the word at the caret, or a placeholder**,
    as `[text](address)`, and asks for the address in an alert on the page
    (an alert can't hang off the row). It does nothing in code, across lines,
    over brackets or in a link that is already there. An address is trimmed
    and its spaces and parentheses escaped (`linkAddress`); no scheme still
    means https at tap time (`LinkTarget`). The caret ends after the link.
  - **Tests undo in separate turns.** UIKit closes an undo group at the end
    of a run-loop turn, and a test makes its chips' edits back to back, so one
    `undo()` takes them all: `TextRowEditorTests` waits between taps.
- **Checked in the simulator** (iPad Pro 13-inch, dark, a 21pt debug note):
  the row's look and order, with the keyboard up above the bar and clear of the
  caret, `+` to 23 re-flowing the note with its heading kept at the top and
  `+` going dim at the end, and the outline popover and a jump to a heading
  (it landed at the top of the page). **Not checked:** the page badge on
  screen, any dock but the bottom, an 11-inch iPad, portrait, the ink question
  on a note with ink, Link's alert, the language menu and + Output by a tap,
  ⌘+ and ⌘− and ⌃⌘O with a real keyboard, Reduce Motion, light mode and the
  Pencil. `HotbarUITests` (seven tests, the reach and the ink row beside the
  bar on every edge) ran with the text row in place and pass.

- **Line spacing** (23 Oct, feedback item 2; `LineSpacingTests`). A menu after Highlight
  in the text row's prose and list controls: Default, +2, +4, +6, +8, +12 points
  (`NoteTypography.lineSpacings`), added to the height of every prose line.
  - **Line height only, never paragraph spacing**, so the three view modes
    still paginate alike: a line is pushed across a page break whole, space
    between paragraphs isn't (the rule in "Code blocks: room around and inside").
    `paginatesAlike` sweeps a block across the first page break at 6 and 12pt
    in all three modes, and fails with the same points as
    `paragraphSpacingBefore` (checked).
  - **How:** `NoteTypography.lineStyle(for:)`, a paragraph style whose
    `minimumLineHeight` is the block's font's line height plus the spacing.
    TextKit adds the font's leading to a minimum on top (measured: a minimum of
    28 gave a 29.7pt line), so the minimum leaves the leading out and a 17pt
    paragraph is 22 + n. It is a *floor* under the block's own font: a heading
    grows by n too, a line holding larger sized text is as tall as that text
    makes it. Applied in `proseAttributes`, `headingAttributes`,
    `listParagraphStyle` and `quoteParagraphStyle`, so blank lines, typing
    attributes and the PDF follow; at 0 the styles are as they were (no
    attribute written, the restyle stays no edit). Code lines and fences keep
    their fixed heights (`CodeBlockRoom`), the output panel too.
  - **Per note, not per device** (decided here): it moves every line under the
    ink drawn on it, as the text size does, and a per-device value would lay one
    note out differently on two iPads. So it is stored: `Page.lineSpacing`
    (`Int?`, `nil` for none), part of `NoteTypography` with the size, which
    reaches the styler, the PDF, thumbnails (`-s<n>` in the cache name) and
    Export All through `Page.typography`. **This changed the model's hash**:
    `ModelFreezeTests.versionOneHashes` has a new `Page` entry (`Folder` is
    unchanged), as the notes on the model allow before the release. A device
    that already has a store from a build before it (TestFlight 1.0) may not
    open it, and the testers reinstall.
  - **Asks first on a note with ink**, as the text size does, once each time
    the note is opened, and shares its answer (`NoteEditor.setLineSpacing`,
    `spacingAwaitingConfirmation`). A pick applies at once: it is one action,
    with no run of taps to wait out. Off in ink mode and for a locked note.
    Not an edit: `modifiedAt` and the undo stack stay as they are.
  - **Not checked:** the Pencil, ink on a note whose spacing changed, print
    and compressed layout on screen, the menu's look in dark mode, a note
    with sized text at a large spacing, the PDF in the share sheet.

- **Rearranged for 1.0 (T2, 28 Oct).** In prose and lists the row reads Bold,
  Italic, Underline, Strikethrough | Default ring + the six `TextColour`
  swatches, highlight | size `+ 17 −` | More. **More** holds what moved: Body and
  H1–H3 (prose only), Quote, Link (disabled inside a link), the three lists,
  Outdent, Indent and a Line Spacing submenu. Code blocks keep size, language,
  indent, + Output and Explain. The row's face is an opaque `systemBackground`
  capsule with a hairline, no glass (the ink row's is W4's). Not checked on a
  device or at 11-inch portrait; the row scrolls along the bar if it is too long.

- **Hotbar layout (31 Oct, review; `TextBarLayoutTests`).**
  - **The row reads Size, Bold/Italic/Underline/Strikethrough, colour and
    highlight, More** (`TextRowSection.prose`). Size is at the top or left,
    where code blocks already had it.
  - **The row is never longer than the bar** (`RowLimit`): `BesideBar` offers
    the text row the smaller of the page's length and the bar's, and it scrolls
    past that. It always scrolled (`OptionsRowTrack`, 17 Oct, for a 390pt
    phone), but it was offered the page's whole length, so on an iPad it stood
    out past both ends of the bar. The scroll view is the same one: the freeze
    that `HotbarTrack` records came from a `ViewThatFits` swapping a plain
    row for a scrolling one, and nothing here branches. The pen's row still
    gets the page's length.
  - **Aa is headings only** (Heading 1 to 6, Body). Bold and Italic left the
    bar for the row (⌘B, ⌘I stay); Underline and Strikethrough left Aa for the
    row (⌘U and the edit menu stay); Quote, Horizontal Rule, Inline Formula and
    Display Formula are buttons on the bar, after Inline Code. In a code block
    the row has no Bold to Strikethrough, as before; the edit menu still does
    not offer them there either.
  - **The bars keep three lines clear below the caret** when the keyboard is
    up and the bar is at the bottom (`Hotbar.linesBelowCaret`, 66pt on top of
    the bar and row): the clearance had stopped at the caret's own line, so
    the lines under it sat behind the bars.
  - **The bars dim behind Settings and Export All** (`coveredBySheet`,
    `dimsWhenCovered`). Seen on the iPad Pro 13-inch simulator (iOS 27.0): the
    page and the top bar went grey and the hotbar and both rows stayed at full
    brightness. Cause not found (the hotbar is in the same hierarchy as the
    page, so the system's dimming should reach it); the bars paint a black 0.2
    over themselves, the page's measured dimming, while `ContentView` says a
    sheet is up. The Info sheet and folder editor dim the main bar the same way
    (`textRowHidden`). The code keys row is a keyboard accessory and is not
    covered. Not checked in dark mode or on a device; if iOS dims them there,
    this doubles it.
  - **Not fixed: two format menus overlapping.** The only two "format" menus
    are Aa on the bar and the text view's edit menu (Format ▸, in
    `DocumentTextView.proseMenu`), and the edit menu is another change's.
    Aa no longer repeats Underline, Strikethrough or the formulas as Format
    does, so what they offer differs; where they sit on screen when both are
    open was not reproduced.
