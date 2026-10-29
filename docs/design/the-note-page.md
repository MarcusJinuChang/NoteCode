# The note page
Laid out from the 12 September mockup.

- **Header** (8 Oct, phase 3 of `docs/archive/ui-design-v2-implementation.md`). The
  system navigation bar, not a custom view: `PageDetailView` sets
  `navigationTitle($page.title)` (the binding is what makes it editable),
  `toolbarRole(.editor)` for a leading title with a chevron, and
  `toolbarTitleMenu` for the title's menu. The custom header said it existed
  so the bar wouldn't be "a second, empty title bar", which stops being true
  once the bar is the header.
  - **Left:** the system's sidebar button, which opens the list over the page
    (`.prominentDetail`) so opening it never re-wraps the note. The design
    draws ☰; `.toolbar(removing: .sidebarToggle)` didn't remove the system's
    button on iPad, on the split view or on the detail, so a custom ☰ sat
    beside it and was dropped rather than kept as a duplicate.
  - **Title menu** (`NoteTitleMenu`): Rename (the system's `RenameButton`,
    disabled while the text is locked), Pin, Move to Folder (its submenu
    has Top Level), Get Info, Manage (Lock Text, Duplicate), Delete — six, since
    S2 (28 Oct). Delete asked once, in an
    alert, until v3 phase 1; now it asks nothing and moves the note to
    Recently Deleted, and a toast offers Undo (see "Recently Deleted").
    `ContentView.delete` clears the selection first, as the list does, and
    brings the list back, since the ☰ went with the page.
  - **Right:** Share (`NoteShareButton`) and •••: a View section (the
    mode's `title` and `systemImage` from PageViewMenu.swift), Run Code In
    (`RunDestinationMenu`, now a submenu) and Find in Note. All in the label
    colour (`.tint(.primary)` on each item), not the accent.
  - **Alerts can't hang off menu content.** It's gone the moment an item is
    chosen. The custom-site alert (`runDestinationSiteAlert`) and New Folder's
    name alert are attached to the page's own view, and the menu raises a
    binding.
  - **A new note opens with Rename active** (`RenameOnAppear`, from
    `ContentView.newPage`, set by `NoteList.onNewPage`), through the
    environment's `rename` action, which only a view under the
    `navigationTitle` can see. Not checked on screen.
  - **A locked note shows `lock.fill`** (small, secondary) in the trailing
    group, before Share. The design puts it after the title, but a system
    title is a string: it takes no icon, and a principal-placement view would
    replace the title and its menu.
  - Gone from the header: Find's own button, the lock button, the info
    button, the disabled Account placeholder.

- **Hotbar.** One bar, dragged by its grip to the left, bottom or right edge,
  snapping to whichever is nearest (`HotbarDock.nearest`). Undo, redo and the
  text/draw toggle never move; after the divider come the current mode's tools.
  Only the tools scroll when the bar is too short for them; the arrows and the
  toggle sit outside the scroll view.
  A bar at the bottom floats over the page and moves nothing; one at a side
  takes a strip from that side only. See "The page fills the window".
  It replaces `PKToolPicker` — see docs/archive/phase-drawing-layer.md.
  The bar is one accessibility container (identifier `hotbar`), so VoiceOver
  hears a toolbar and tests can find its frame.
- **Text tools** (10 Oct, phase 4 of `docs/archive/ui-design-v2-implementation.md`):
  Style ▾ (Heading 1 to 3, Body, then Strikethrough), Bold, Italic, Inline
  Code, List ▾ (Bulleted only for now) and Code Block ▾ (C++, Java, Python,
  Plain Text). The separate strikethrough button went into Style. The menus
  show no ▾: the design draws plain icons. (Since 19 Oct Style ▾ has Heading 1
  to 6, then Underline, Strikethrough, Quote and Horizontal Rule; see
  "Obsidian's other marks and blocks".)
- **Ink mode is two rows** (10 Oct). The bar holds the grip, undo, redo, the
  toggle, Pen, Highlighter, Eraser, Lasso and **Finger Draws** (the old
  Pencil-only lock, said the other way round: `NoteEditor.fingerDraws`). What
  the selected tool can be set to is in a thinner **options row** that floats
  beside the bar, on the page's side:
  - **Pen and highlighter:** their palette, Add Colour, a divider and three
    widths. **Eraser:** pixel or object, then its sizes. **Lasso:** no row.
  - **It reserves nothing.** It is the bar's overlay, so the bar's size is the
    same in text and ink mode and the page never moves
    (`HotbarLayoutTests` hosts the real note page and compares its frame and
    scale across modes, tools and docks, and the bar's size).
  - **Placed by a `Layout`, not an alignment guide** (`BesideBar`). The first
    version was an overlay alignment with an `alignmentGuide` on the row, and
    the guide was ignored on every attempt: the row sat on the bar, 48pt from
    where it belonged, which the UI tests measured as -40 against 8
    (simulator, 9 Oct). A layout that places its one child from its own
    bounds, 8pt outside them and centred along them, doesn't depend on a guide
    being read.
  - **The 44pt touch target is layout, not a hit shape.** The row looks 40pt
    thick; each control is 44pt thick with its face at the bar's end, and the
    glass is drawn on the 40. A `contentShape` grown past the view's bounds
    took no touches in the extra 4pt (a sweep down a control's centre line:
    nothing past the page edge of the frame, and 5pt past the bar's).
    Along the row a control is 34pt, the design's 391pt for the pen's seven
    colours, Add Colour and three widths (`OptionsRowStyle`, which the
    control faces read from the environment, so the same buttons are 44pt
    squares on the bar and 34 by 40 in the row).
  - **Slides out from the bar**, a cross-fade under Reduce Motion, when the
    mode is ink and the tool has options. The bar itself never moves.
  - **Checked** by `HotbarUITests` (XCUITest, since a SwiftUI hit test and the
    accessibility tree need a real app): the 8pt gap and the centring on each
    edge, and a tap 1.5pt into the reach selects its control while a tap 2pt
    into the gap doesn't. The launch arguments pass empty values for the
    stored palettes and settings, which aren't valid, so the app reads its
    defaults and a simulator's saved palette can't decide what's on screen.
  - **Testing SwiftUI that changes state needs a window in a scene.** A
    `UIWindow(frame:)` made outside the test host's scene gets no display
    link, and SwiftUI never re-rendered after the editor's mode changed: the
    first version of `HotbarLayoutTests` passed with the page's insets made to
    depend on the mode. `HotbarLayoutTests.makeWindow` uses the host's
    `UIWindowScene`; both tests then failed under a mutation (insets by mode;
    the bar growing with the row) and pass without it.
- **Ink tools** (`InkToolbar.swift`), shared by the hotbar and the palette
  the Pencil's squeeze brings up (`InkToolPopover`: the tools, then the selected
  tool's options under them), so the two can't disagree.
  - **Two palettes** (10 Oct): the pen keeps `InkPalette.defaultsKey`
    (`inkPalette`), so a palette a device saved before stays its pen's, and the
    highlighter has `highlighterPalette`. The defaults are the design's: seven
    pen inks (Ink, Red, Orange, Yellow, Green, Blue, Purple) and five
    highlighters (Graphite, Orange, Yellow, Green, Pink), as hex in
    `InkColor.penShades` and `.highlighterShades`. A device that has saved a
    palette keeps it, since `@AppStorage` reads the default only where
    nothing is stored. Only the light value is ever stored; the design's dark
    column is what PencilKit shows for each, and `InkShadeTests` checks all
    twelve within 1/255 on the iOS simulator.
  - **Each tool remembers its colour and width** per device
    (`InkingSettings`, keys `penSettings` and `highlighterSettings`, applied
    by `InkToolPersistence`). Widths are fine, medium and bold, as multiples of
    the ink type's `defaultWidth` kept inside its `validWidthRange`: pen 0.5,
    1, 2 and highlighter 0.6, 1, 1.6. The highlighter starts on yellow, not
    graphite, which heads its palette. A swatch removed from a palette
    while it's selected is replaced by the palette's first colour when the row
    appears.
  - "+" opens Apple's `UIColorPickerViewController` from UIKit
    (`InkColorPicker`), not from a SwiftUI popover, where it's a child
    controller and its eyedropper and close button expect to be the presented
    one. Hold a colour to remove it; hold and drag to move it. A colour picked
    on a dark page is stored as the light ink that shows as it
    (`InkColor(chosen:on:)`). The palette (`InkPalette`) and the eraser
    (`EraserSettings`) are stored per device, like the dock.
  - **Finger Draws is per device too** (10 Oct, key `fingerDraws`, through
    `InkToolPersistence`). Each note gets a new `NoteEditor`, so it used to
    reset to on with every note opened and every launch.
  - The model is pure and portable (`InkTool.swift`); only the PencilKit tool
    and the UIColor conversions are behind `canImport(UIKit)`. Declaring
    `init(hex:)` inside `InkColor` removed its memberwise initialiser, so it is
    in an extension.
- **The hover mark and a tool change** (23 Oct, feedback item 17; nothing
  changed, measured only). The app draws no hover mark: there is no hover
  recogniser or view of ours, and in the canvas's view tree (probe, simulator)
  none of PaperKit's views is a preview, and none appears or changes when the
  tool is set. The mark is PaperKit's, drawn from `drawingTool`. Ours is
  synchronous: `NoteEditor.inkTool`'s `didSet` assigns `canvas.tool` before the
  change returns, for a kind, a colour, a width and the Pencil's double tap
  (`InkToolHandoverTests`), so no turn of the run loop and no SwiftUI render
  sits between a tap and PaperKit holding the new tool. If the mark still
  shows the old tool until the Pencil moves, PaperKit redraws it on the next
  hover event, not on a tool change. The simulator has no hover, so this is
  not seen on a device. Options if it is: nudge the tool again on the first
  hover after a change (needs our own hover recogniser alongside PaperKit's),
  or hand tool changes to a `PKToolPicker`, which the app dropped (see
  docs/archive/phase-drawing-layer.md).
- **Pencil double tap and squeeze** do what the reader set in Settings ›
  Apple Pencil (`PencilResponse`), in ink mode only: swap to the eraser and
  back, swap to the previous tool, or show the ink tools beside the Pencil.
  Hardware only — the simulator has no Pencil.
  - **From text mode** (21 Oct) a double tap or squeeze first switches to ink
    mode (`NoteEditor.enterInkForPencil`), then does the same action, so the
    first tap lands on the eraser or the palette. Not when the reader's setting
    is off or a system shortcut (`PencilResponse.nothing`): switching mode for
    a gesture that then does nothing would only surprise. **Unverified:**
    whether SwiftUI's `onPencilDoubleTap` is delivered while the text view is
    first responder. The simulator can't send a Pencil event and no iPad
    Pencil was to hand, so only the mode switch is tested
    (`NoteEditorTests.pencilFromText`). If a double tap in text mode does
    nothing on the iPad, the fallback is a `UIPencilInteraction` on the text
    view itself, with the same `respond` behind it.
- **Formatting is markdown in the source.** A button computes a `TextEdit` in
  `MarkdownFormatting`, which is pure and defers to the parsers, so a button
  never writes markers the styler won't draw. `NoteEditor` applies the edit
  with `replace(_:withText:)`, the path typing takes, so it is undoable and
  restyles like typed text. Assigning `.text` loses undo, the selection, and
  the delegate callback that writes the change back to the page.
- **Prose is autocorrected, code isn't** (3 Oct). The keyboard's rewriting
  traits (autocorrect, capitals, smart quotes and dashes, smart
  insert/delete, inline predictions) are on in prose and off on a code
  block's lines and fences and in inline code, where they'd silently turn
  `int lo` into `In too`. An unclosed fence or backtick counts as code,
  since the closing one is typed last (`TextRewritingPolicy.at`). So does
  the word just after a closing backtick, until a space ends it: the
  keyboard corrects the word a space ends, and its word runs through the
  backtick, so a space after `` `int lo` `` turned it into `` `int lot ``,
  the closing backtick eaten. The keyboard also goes back over words behind
  the caret, which no trait stops: a space after the next word turned
  `` lo` now `` into `log now`. So the coordinator turns away any edit that
  replaces text other than the selection and changes code
  (`TextRewritingPolicy.rewriteChangesCode`), which is what the keyboard's
  corrections look like; typing, pasting, deleting, composition and the
  formatting buttons (`NoteEditor.isFormatting`) all pass. The coordinator
  switches on each caret move, but only when the caret crosses from one to
  the other, since `reloadInputViews()` redraws the suggestion bar, and
  never while text is being composed (marked text), where a reload could
  disturb the character. It also picks as editing begins, since a tap into
  an empty note moves no caret, and the note's first letter stayed
  lowercase. XCUITest's `typeText` skips autocorrect entirely, so a typing
  check has to tap the keyboard's keys. Spell checking stays off everywhere:
  on in prose, it marks every word typed this session anywhere in the note,
  so an identifier typed in a code block turned red as soon as the caret
  moved back to prose.
- **`NoteEditor` is the bridge.** SwiftUI owns the hotbar and UIKit owns the
  text view, and neither can reach the other. The hotbar talks to `NoteEditor`,
  and the text view registers with it.
- **Text and ink have separate undo stacks** (decided and built 19 Sep). Left
  alone, ink landed on the text view's stack, since the canvas's
  `undoManager` walks the responder chain through it. PaperKit's controller
  can't be subclassed, so `DrawingCanvas` is the view between them and vends
  its own; `NoteEditor` routes the hotbar's arrows to the stack the mode uses.
  Ink's stack is cleared whenever the page re-places ink for a mode switch.
- **Text lock** (4 Oct). Lock Text in the title menu, or in the list's note
  menu, sets `Page.isTextLocked`: the text and title
  can be read, selected and copied, but not changed. Read-only rather than
  hidden behind Face ID, which is "Note locking" in Later. It belongs to the
  note, so it lasts until unlocked, and like pinning it isn't an edit.
  - It is one more input to `EditorMode.apply`, which already sets
    `isEditable` and `isSelectable` per mode. Set anywhere else, the next
    switch back to text would undo it. Text mode, locked: selectable, not
    editable, keyboard away, and no keyboard back from ink either. Ink
    mode is the same locked or not, so a locked note can still be drawn on.
  - `NoteEditor` keeps a copy (`setTextLocked`) and applies it in `attach`,
    so a lock set before the page exists still lands. Formatting does
    nothing while locked, and text mode's undo arrows stand down, since
    undoing typing would change locked text. Ink keeps its undo.
  - Unlocking doesn't raise the keyboard: the reader was reading.
  - The title is shown as plain text while locked, not a disabled field,
    which would grey it. The Mac's stand-in editor is simply disabled.

- **Caret anywhere** (23 Oct, feedback item 7; `CaretAnywhere.swift`). A tap in
  the empty space below the note's last line adds the blank lines it takes to
  reach that line and puts the caret on it, so a note can be continued from
  anywhere on its last page, as on paper. The lines are the note's own
  newlines, one undo step (`Coordinator.apply`), added at the end; nothing above
  moves, so ink isn't touched.
  - **Its own recogniser** (`MarkerGestures.emptySpaceTap`), beside the link
    and box taps, `cancelsTouchesInView` off and recognising with the caret's
    tap, which puts the caret at the end anyway. It begins only where
    `Coordinator.isEmptySpace(at:)` says: text mode, an editable note (not
    locked, not in ink mode, no composition), not on a code block's buttons
    (`containsInteractiveElement`), and below the last line. A tap on or
    beside the text is the text view's own.
  - **The count** is `CaretAnywhere.newlines`: `ceil((tapY - lineBottom) /
    lineHeight)`, at most 200. `lineBottom` is the end of the note's caret line
    (`DocumentUITextView.lastLineBottom`). A note ending in a newline has an
    empty last line that TextKit sets at 22pt with the caret at the end and
    about 14pt without it (its extra line fragment takes the typing attributes
    only then), so that line is a blank line's height (`typography.codeLineHeight`),
    never measured. A page break can outrun the count (a line that would cross
    one is pushed to the next page), so the edit loops up to four times, looking
    at the caret's line after each.
  - **Asked cheaply.** The end of the note is only measured when the viewport
    reaches it (`viewportReachesEnd`): a tap in the text of a long note never
    lays the rest out.
  - **Tested** (`CaretAnywhereTests`): the caret's line contains the tap for
    seven endings (prose with and without a newline, blank lines, a heading, a
    closed block, with and without a newline after it, an unclosed block) at 1,
    2.5 and 6 lines below; taps on the text and beside it add nothing; ink mode
    and a locked note add nothing; one undo. Fails with the count rounded down or
    the mode and lock checks removed (both checked).
  - **Not covered by a unit test:** the overlay guard is defensive. A code
    block's buttons are always above the note's last line, so no point can be both
    on a bar and below the text; the real tap was checked in the simulator
    (a tap on the last block's Copy button reached it and added nothing; a tap
    below the block added lines and raised the keyboard with the caret on a body
    line). Not checked: the Pencil, print and compressed layout (taps in the
    gap between sheets), a note on an iPhone, taps below an unclosed block with
    the keyboard up.

## Joined list and Home control, and the way home (W3)

`NoteWindowControl`: the list and Home as one pill at the top left, in the
`sidebar` and `home` icons of `NoteIconGeometry` (an opaque `.quaternary` fill,
no glass). Home is the detail column's other branch, not a navigation
destination, so `.navigationTransition(.zoom)` doesn't apply. Instead Home
records each card's frame (`HomeLaunch`: anchor and scale against Home) when
a card is tapped, and the note's removal transition scales toward that
anchor and fades (`AnyTransition.noteToHome`); a note opened from the list
shrinks to the middle, Reduce Motion cross-fades. Ink is committed by
`PageDetailView.onDisappear` as before.
The system's sidebar toggle is removed with `.toolbar(removing: .sidebarToggle)`
on the **sidebar column's** content (`noteList` inside the split view), not on
the note or the detail column, where it did nothing on iPad.
