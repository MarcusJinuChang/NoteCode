# Pages
Notes are Letter-sized pages, Notability-style. The geometry is all in
`PageLayout`, as pure functions.

- **Paper.** US Letter at 96 units to the inch: 816 by 1056 portrait, 1056 by
  816 landscape, with 0.75in margins. At that size 17pt body text prints at
  12.75pt. Orientation belongs to the note (`Page.pageOrientation`), set once
  when it's made; the view mode is a per-device preference (`@AppStorage`),
  chosen from the View section of the header's ••• menu.
- **One pagination, three presentations.** Every page holds a body of the same
  height in every mode, and text flows around a band between one body and the
  next — two margins and a 24pt gap in print layout, a 24pt strip with a dashed
  line in compressed, 1pt in seamless. The bands are the text container's
  exclusion paths. A line that would cross a break is pushed to the next page
  in every mode, so seamless shows up to a line's extra space at each break.
  Because a line's page and its place on the page never depend on the mode,
  neither does ink's.
- **Ink lives in print coordinates** (`PageView.ink`), which is also where it
  prints. The canvas shows it converted to the current mode, and every mode
  change converts from the stored ink, never back from the canvas: a stroke in
  a sheet's margin has no exact place in seamless, and a round trip would move
  it a page. A note's orientation can't change after it's made, so there is
  no re-wrap for ink to fall out of; `PageView` still handles one, because it
  opens every note with portrait pages first.
- **Ink across page breaks** (9 Oct). The space between one page's text and
  the next is 1pt in seamless, 24 in compressed and 168 in print layout, and
  every element moves between modes whole, by the page its middle is on. A
  stroke drawn across a break sat on its words on one side only: 23pt off
  between seamless and compressed (simulator). So, decided 9 Oct:
  - **Seamless is the reference.** `PageLayout.inkRegion` is each page's
    part of the note in seamless, moved with its page into any mode. Ink
    shows only in those regions. Compressed's strip, print layout's top and
    bottom margins between pages and the gaps between sheets are space
    seamless doesn't have, so they take no ink: a stroke can't start there
    (`takesInk`), and nothing shows there. Side margins are the same in
    every mode.
  - **A stroke is cut into a piece per page** (`InkPages`), however many
    pages it reaches: the same stroke — path, ink, texture seed, PaperKit's
    render state — with a mask of its page's region and a new id. PencilKit
    draws only inside a mask; PaperKit keeps masks through moves, saving and
    its own drawing, and two pieces meeting at a mask's edge join with no
    seam (probe). A masked stroke's frame is its mask's, so the existing
    per-element conversion places each piece by its own page. Whatever lay
    in space no page has is in no piece, so it shows in no mode and can't
    land on another page's words.
  - **Cut in the stored ink, not on the canvas.** `InkCapture` stores a
    changed stroke as its pieces and records which canvas stroke each came
    from (`InkCapture.State.pieceSources`); the canvas keeps the stroke
    whole until ink is next shown — a mode switch or reopening — which
    clears ink undo anyway. Swapping pieces onto the canvas straight away would leave
    PaperKit's undo action for the stroke with nothing to remove. Erasing,
    undoing or moving the stroke takes or re-cuts all its pieces.
  - **Covers hide what the canvas still holds whole** (`PageCoverView`):
    above the canvas, one view per hidden band, drawing what the page draws
    there anyway (the page and its dashed line in compressed; the surround
    and the sheets' edges, borders and shadows in print layout). On a page
    without ink they can't be told from what's beneath
    (`PageViewTests.coversMatchThePage` compares the pixels, and fails if
    the covers are coloured). Text never sits in the bands. The live stroke
    goes under them too.
  - **Measured on the way, so they aren't tried again:** setting
    `renderGroupID` on a stroke from the canvas traps inside PaperKit (its
    strokes are a subclass that can't copy with one); `InkPages`' stroke
    function needs its own name, since `PKStroke` is a `Markup` and a shared
    name recursed until the stack ran out; PaperKit rounds a stroke's frame
    out to whole points, so tests compare masks' bounds; assigning the
    canvas a reordered set doesn't reorder it, so after a mode switch a
    cut stroke's pieces draw above later strokes until the note is reopened
    (stored order is kept); and PaperKit's ink doesn't render through
    `drawHierarchy` in a unit test at all, so ink on screen is checked in
    the simulator, while `InkPagesTests` draws pieces through
    `PaperMarkup.draw`, as the PDF does.
  - Checked in the simulator, light and dark: a stroke across a break sits
    on the same words in all three modes, hidden over the bands while drawn
    and after; undone and switched, nothing comes back. Not checked: the
    Pencil, latency, the lasso and the eraser on pieces.
  - **Pieces, not bending** (10 Oct). A second version bent a stroke across
    a break instead, each point moving with its own page, so it stayed one
    stroke (PR #38's second commit). Marcus had it reverted: it harmed more
    than it helped. The cost of pieces stays in seamless: once ink has been
    shown again, each piece is a stroke of its own there, so erasing a
    stroke across a break takes one object erase per page.
  - **Compressed and print layout stop a stroke at the border** (10 Oct,
    decided by Marcus): a stroke drawn across one shows only on the page
    the pen went down on, nothing in the border or past it. Seamless still
    shows it whole. So the piece on that page keeps the stroke's id, and
    the rest is its *overflow*, marked in the pieces' ids (`InkPages`): the
    stroke's first ten bytes, then `overflowMark`. Stroke ids survive
    saving only when a stroke goes into a markup through `subelements`;
    appending a `PKDrawing` gives every stroke a new one (probe).
    - **Shown:** `showInk` leaves overflow off the canvas outside seamless,
      and the PDF doesn't print it, since print layout is the paper.
    - **When the pen lifts:** the canvas holds the stroke whole, so once
      it's taken in, `PageView.showOwnPieces` updates it in place to its
      own piece, with its id. Assigning the canvas registers no undo
      (probe). Until then it shows past the border; covers hide what's in
      the band. Three things the simulator showed on the way:
      - **Not taken off and put back.** That redraws cleanly, but
        PaperKit's undo then can't find the stroke: two undos did
        nothing, where a stroke on one page undid in one.
      - **A new path** (`InkPages.redrawn`), or PencilKit goes on drawing
        the stroke as it first drew it, whole, though the canvas holds the
        mask.
      - **Specks at the whole stroke's corners** (`InkPages.shown`).
        Updated in place, PaperKit redraws only the tiles the stroke's new
        frame touches, and a masked stroke's frame is its mask's, so ink
        past the border stayed wherever its tiles missed the piece (two
        strokes in four). 0.01pt squares in the mask keep the frame whole;
        points of no area didn't, as PaperKit drops them. A specked
        stroke's frame isn't its piece's, so the next show puts it back
        as stored (`InkCapture.State.specked`): placed by that frame it
        moved half its hidden part off its words.
      Checked in the simulator, compressed: eight strokes, down and up,
      each stopped at the border once the pen lifted; one undo took a
      stroke and its overflow, redo brought both back, still stopped; and
      switched to seamless, both pieces met on their words. Not checked:
      print layout on screen, the Pencil, the lasso and the eraser on a
      stopped stroke.
    - **Erased:** a stroke's overflow the canvas doesn't hold goes with
      it, and is kept aside (`InkCapture.State.buried`) until ink is next
      shown, so undoing the erase brings it back. **Moved by the lasso:**
      the hidden overflow is moved by the same amount, as a translation;
      a lasso's resize or rotation isn't carried exactly.
- **Ink over a code panel shows a colour step at its edge** (21 Oct, a report
  from 1.0). The cause is the highlighter, not a view: PencilKit's marker
  blends with whatever is under it, so its colour changes where the page
  (white / black) becomes the panel (#F2F2F7 / #1C1C1E). Seen in the
  simulator with a stroke across a panel's left edge, cropped 4x: the pen
  (normal blend) shows no step in light; the yellow highlighter is bright on
  the page and duller on the panel, in light, and in dark an olive that
  hides the code beneath it. The canvas is transparent and no cover or mask
  draws there. Not fixed; options, none small: bring the panel's colour
  closer to the page's, give the highlighter a normal blend if PaperKit
  allows it, or draw it under the code text. Not checked: the Pencil, other
  palette colours, the Output panel, print layout.
- **Add Page, and seamless's buffer** (15 Oct, roadmap step 6).
  `Page.minimumPageCount` is the one stored page count: a note has the more of
  it and the pages its text and ink need (`PageLayout.pageCount(…, minimum:)`),
  so it only ever grows. ••• › Add Page raises it by one past the pages the
  note has now, in compressed and print layout (seamless has no page ends to
  add at). In seamless, `PageView.keepPageBelowInk` raises it when ink
  reaches the last page, after the stroke is taken in, so a blank page is
  always below the ink; ink on the new last page makes the next. Compressed
  and print layout add none for ink, since their last page is visible and
  Add Page is there. Like the text size it is no edit (`modifiedAt` stays, no
  undo). Blank added pages print (`NotePDF.Note.minimumPages`, also Export
  All's) and are copied by Duplicate. Erasing never takes pages back.
  - No button on the page itself: print layout and compressed leave no room
    below the last page that the canvas doesn't own, so the menu has it. A
    page-foot button would be its own piece of work.
  - **Adding pages as the reader draws down** (23 Oct, feedback item 8). In
    compressed and print layout, a stroke the reader draws that *ends* in the
    last page's foot (the bottom 15% of its body, `InkPageGrowth.bandShare`;
    `PageLayout.endsInGrowthBand`) adds a page through `raiseMinimum`, the
    path Add Page takes. Seamless already keeps a page below any ink on the
    last page. Settings › Drawing › Add Pages While Drawing, on by default
    (`addPagesWhileDrawing`).
    - **Only strokes drawn now.** `InkCapture.Result.drawnEnds` holds the end
      point of every stroke with no record in `State.shown`; ink that was
      loaded, shown again for a mode switch, moved by the lasso or erased has
      one, so none of it adds a page. An undone erase has none and may count,
      but its page was added when it was first drawn and the count never
      shrinks, so it is no longer the last page's foot.
    - **No ink save of its own.** It runs in `apply(_:)` after `onInkChanged`
      for the stroke, and raising the minimum is the note's page count, not
      ink; the test counts `onInkChanged` and sees one call, not two.
    - Decided: end point, not start (a stroke running from the middle of the
      page into its foot adds one).
  - Not checked on screen or with the Pencil: Add Page from the menu, the
    buffer while drawing.
- **Blank ink after a jump between pages** (23 Oct, feedback item 27; measured,
  not fixed). The canvas covers only the screen (`DrawingCanvas.cover`, so a
  long note never makes a texture past Metal's limit) and each layout pass
  tells PaperKit which part of the note it is over (`contentVisibleFrame`).
  A region PaperKit has not drawn yet is drawn then, asynchronously and in
  tiles: the text, which is views, is there at once and the ink fills in.
  Measured on the iPad Pro 11-inch simulator (Mac GPU) by recording the screen
  while lldb set the text view's offset, and counting ink and text pixels in
  every 30fps frame (`-debug-ink-file`; probe and numbers in the session notes):
  - **3,000 strokes** (150 points each, about 375 a page): jumping to a page
    not yet seen, ink absent for 100 to 200ms (print layout 200, seamless
    130), then filling in over about 300ms. Going back to a page already seen
    showed its ink in the very next frame, so PaperKit keeps what it drew.
  - **400 strokes** (60 points): ink and text changed in the same frame; no
    blank frame.
  - So the gap grows with the strokes in the region exposed, and a device
    GPU with a Pencil's textured strokes is slower than the simulator. "A few
    seconds" is not reproduced here and is not ruled out: it needs the same
    probe on the iPad with Marcus's note. Main-thread work isn't the cost
    (frames kept coming during the fill); nothing in `PageView` redraws ink
    on a scroll except moving `contentVisibleFrame`.
  - **Options, none tried:** (1) cover a window of the note taller than the
    screen, one screen above and below, so the next page is drawn before it
    is reached; the texture limit allows it (3 screens at 1.25x on a 2x
    screen is about 9,000px of 16,384) but the live stroke's buffer follows
    the canvas's size, so Pencil latency has to be measured first. (2) After
    a jump settles, walk `contentVisibleFrame` over the neighbouring pages
    once to warm PaperKit's cache. (3) Nothing, if the iPad's numbers are
    near the simulator's.
- **Print layout** fits its sheets inside a 24pt border of the surround
  (`CanvasGeometry.printGutter`), so they read as paper rather than one slab
  with grey bars across it. Text is a little smaller there than in the
  continuous modes, which fit edge to edge.
- **The page against its surround** (8 Oct, phase 2 of
  `docs/archive/ui-design-v2-implementation.md`). In every mode the page is
  `systemBackground` and whatever isn't the page is `secondarySystemBackground`
  (`PageView.pageColor`, `surroundColor`): `PageView` itself and the SwiftUI
  area behind it (`PageDetailView.content`, so the hotbar's reserved strips
  and the margins show it too) are the surround. In the continuous modes the
  **text view paints the page column**, not a view of its own: the column is
  exactly the text view's bounds, its background sits under the text, the
  break decorations and the canvas (all its subviews). Print layout leaves
  the text view clear, since its sheets carry the page colour and the surround
  has to show between them. `paintPage()` sets all of it, so a mode switch
  can't leave one behind. There is no border or rounded corner (16 Oct; see
  "The page fills the window").
  - **Compressed adds only a dashed line at each page end** (decided 9 Oct).
    Phase 2 also painted its 24pt band in the surround's colour, as the
    design brief asked, which made it read as a gap between pages; Marcus
    wants compressed to be seamless plus the line, so the band went
    (`PageViewTests.compressedBreakIsOnlyALine`).
  - **The surround is a background that ignores the keyboard too**
    (9 Oct). `.background(Color)` ignores the container's safe areas but
    not the keyboard's, and the stack it's on keeps the keyboard's for the
    hotbar, so the grey ended at the keyboard's top and rode up with it, the
    window's white showing around and under the translucent keyboard. Now
    `.background { Color(…).ignoresSafeArea() }`. Measured from simulator
    screenshots, pixels outside the keyboard's rounded corner: white before,
    the surround after, light and dark. No unit test: a keyboard's safe area
    can't be made in one.
  - **Ink over the space seamless doesn't have is hidden, by covers**
    (9 Oct; see "Ink across page breaks" below). The first fix, a
    `CAShapeLayer` mask on the canvas (PR #36), **blanked text**: masked,
    PaperKit's ink tiles painted the page colour over the lines beneath
    them, so around every stroke in print layout whole blocks of words were
    missing. Taking the mask off in the running app (lldb) brought them
    back. The checks at the time looked at the stroke and the gap, not the
    words beside them. Don't put a mask on the canvas.
  The tests render the page and read pixels, in both appearances
  (`PageViewTests.pageAgainstSurround` and neighbours). **Set
  `overrideUserInterfaceStyle` on the page view, not the test's window**: a
  window made outside a scene ignores it when drawing, so the first version
  rendered the simulator's appearance under both labels and its light cases
  "passed" in dark.
- **Whole pages are enforced where TextKit sets the height.**
  `DocumentUITextView` overrides `contentSize` and rounds each height TextKit
  sets up to whole pages, through `PageView.noteHeight(forTextHeight:)`.
  Correcting it afterwards, from a layout observer, didn't work: TextKit can
  set the height after the pass that would correct it. A switch to print
  layout left a five-page note 500pt short, extra layout passes didn't close
  the gap, and a reader near the end was pushed down (`PageSettlingTests`).
- **Blank lines are laid out as zero-width spaces** (`BlankLineLayout`, 23
  Sep). TextKit 2 ignores exclusion paths for an empty paragraph: it asks the
  container, is told "below the band", and places the line where it proposed
  anyway, so a pushing container doesn't help. Blank lines ran through the
  breaks — print layout's band holds about seven, seamless's none — and text
  after a blank run paginated differently by mode, which ink can't survive.
  The content storage's delegate swaps each "\n" paragraph for "\u{200B}", the
  same length, for layout only; the note keeps its newlines. The cost is on
  taps: UIKit snaps a tap's caret to a word boundary, and a run of zero-width
  spaces is one word, so a tap anywhere on a blank run put the caret after it.
  That tap doesn't go through `closestPosition(to:)` (overridden anyway), nor
  the text view's `gestureRecognizerShouldBegin` — its recogniser is on an
  inner view — so `DocumentUITextView` notes the touch in `hitTest` and
  `placeCaretOnTappedBlankLine` moves the caret back when the selection
  changes. Needs a real tap to check; a unit test can't see it. Arrowing up
  and down still visits each blank line. The empty
  last line after a final newline isn't a paragraph and isn't covered: in
  seamless and compressed its caret can still sit in a break.
- **A selection inside a code block is painted by the fragment** (7 Oct,
  `CodeSelectionHighlight`). UIKit's highlight view is the first subview of
  the text canvas, behind every fragment view (measured from the view tree),
  and a block's panel is an opaque fill painted by its fragments, so a
  selection in code showed nothing; prose has no fill and was fine. The
  panel can't go translucent (its seams and overhang assume an opaque fill),
  so `CodeBlockLayoutFragment.drawSelection` fills the selected segments
  right after the panel. Three things tried or found on the way, so they
  aren't tried again: a `.backgroundColor` rendering attribute draws nothing
  in a custom fragment; `invalidateRenderingAttributes` never redraws a
  fragment view, so the coordinator `setNeedsDisplay`s the ones the old and
  new selection touch (drawing only, no layout); and
  `textLayoutManager.textSelections` doesn't hold a selection `UITextView`
  made, so the coordinator hands each fragment the range it tracks
  (`paintedCodeSelection`). Not drawn into the PDF. Checked by rendering the
  text view and comparing the panel's pixels under a selection, light and
  dark; not seen with a real drag. Find's match highlight (`decorate`) may
  hide behind panels the same way; not checked.
- **Position things from lines, never from a fragment's frame.** A line pushed
  past a page break stays inside a fragment whose frame begins above the
  break, so the frame spans it. Code panels (`CodeBlockLayoutFragment.panelRuns`)
  and run/copy buttons (`CodeBlockOverlay`) use the text lines' own bounds;
  from the frame, a panel painted across the gap between two sheets.
  The note's empty last line counts as a line too: after a final newline,
  TextKit puts it in the last paragraph's fragment, so a note ending on a
  closing fence had its caret line shaded as code (25 Sep).
  `CodeBlockLayoutFragment.laidOutPanelRuns` leaves it out after a closing
  fence, and only there: after an unclosed block that line is still code.
- **The reader's place survives a switch.** Switching mode converts the scroll
  position by page, which is exact because every mode paginates the same; a
  top edge in a margin or break shows that page from its top edge
  (`PageLayout.scrollTop(forPage:)`). Switching orientation re-wraps the text,
  so there the line at the top is kept instead — except that a page's first
  line shows that page from its top edge, the same rule, and the note's first
  line means offset 0. Opening a note counts as an orientation change for a
  landscape note (`PageView` starts with default portrait pages), and keeping
  its first line at the top opened every such note 36pt down, its top margin
  out of view.
- **Get the page count right before the bands, on a switch.** The page count
  comes from the text's height, which is still the old layout's until TextKit
  lays it out again. Read against the new layout it gave a nine-page note
  eleven pages, then nine, ten, nine; each change reassigned the bands, which
  relays out the whole note, and TextKit shifted the scroll offset every time
  — the reader landed a line and a half into the page. `PageView` converts the
  old text bottom into the new layout first, which is exact within one
  orientation. Laying out the whole note instead also worked, and cost 500ms
  on a 2,000-line note.
- **Re-anchor TextKit at the note's top on a switch.** TextKit 2 lays text
  out relative to what the viewport showed last, and keeps that anchor when
  the bands change under it. Switching deep in a note, every line on screen
  sat 167pt below its true position — print layout's 168pt break less
  seamless's 1pt, one stale break — so the offset landed on the right page
  edge while the screen showed the previous page's lines, running across
  seamless's breaks. `invalidateLayout(for: documentRange)`, a full
  `ensureLayout`, and relaying out the viewport all left it; scrolling to the
  top and back cleared it. `PageView` now scrolls to 0 after applying the
  bands and before restoring the reader's place, within one update, so
  nothing flickers. `PageSettlingTests.roundTripDeepShowsPagesFirstLine`
  (seamless → print → scroll deep → seamless) failed without it. Tests for
  this check the line actually at the top against a note laid out from
  scratch, never the scroll offset against page geometry — that comparison
  passed the whole time the bug was on screen.
- **Cost.** Once any exclusion path exists, TextKit 2 lays out everything below
  an edit. A keystroke near the top of a note, measured on the simulator: 100
  lines 2.8ms → 13.7ms, 250 lines 5.5ms → 33.8ms, 500 lines 9.7ms → 66ms.
  `PageViewTests.typingCost` bounds it. So anything that edits the text
  storage after a keystroke costs another full layout below the caret —
  including setting attributes that are already there, which is why the
  styler compares before it writes (25 Sep). That one layout is about half
  of what a keystroke costs now. Long notes did stutter on the iPad; the
  alternative is pushing paragraphs with paragraph spacing, computed lazily
  — whole paragraphs rather than lines, and it has to coexist with the
  styler's own paragraph styles.
  - **Held Return and Backspace needing two presses** (21 Oct, a report from
    1.0). Not reproducible through code: twelve contexts (prose, heading,
    after bold, code, after a brace, unclosed code, blank-line runs, and
    Backspace in prose, blank runs, code, bold and a heading), three pacings,
    ten presses each with nothing laid out between: every press changed the
    text and moved the caret (`ReturnAndBackspaceTests.everyPressRegisters`;
    the legitimate no-ops are Return on an empty list item and Backspace at
    the note's start). A burst of 11 real Returns in the simulator all
    registered. The likely cause is this cost against the key repeat, not
    proven: Return near the top of a rendered note takes 14.5ms at 100 lines,
    67ms at 500 (the press itself 39-41ms: edit, restyle, selection
    handlers) and 205ms at 1,500; Backspace 9, 39 and 126ms. A hardware
    repeat is about 30-80ms, so a 500-line note is slower than the repeat.
    Check on the iPad: hold either key in a 5-line note and in a 500-line
    one; if only the long one drops presses, it is cost.
- **Printing goes through a PDF** (4 Oct). The share button in the note's
  header makes one and opens the share sheet, where Print, Save to Files
  and the rest are; there's no print button of its own. A PDF page is a
  sheet of print layout, `PageLayout.sheet(ofPage:)` in page points times
  72/96: US Letter.
- **The PDF is laid out afresh, never read off the screen** (`NotePDF`,
  `PrintedNote`). TextKit only lays out what's on screen, so the page being
  read has nothing to draw for the rest. `PrintedNote` is a second text
  view from `makeConfiguredTextView`, styled by its own
  `DocumentTextView.Coordinator` so code gets its fragments and colours,
  in print layout, forced light: syntax colours come from the light theme,
  and drawing runs under a light trait collection so `.label` and the code
  panels are their light colours on a dark device. It starts from the open
  note's page count and adds page breaks until no text runs past the last.
  Ink is `PageView.ink`, so strokes not yet saved print too.
  - **The light theme is the coordinator's `pinnedAppearance`**, not the
    text view's traits (16 Oct). A view in no window takes its appearance
    from the scene: `overrideUserInterfaceStyle` and `traitOverrides` on it,
    an override on the app's window and `UITraitCollection.current` all
    left it the device's (probed in both appearances). So until then a PDF
    or thumbnail made on a dark device had the dark theme's keywords on the
    light panel. Overriding the *scene's* `traitOverrides` does reach such a
    view, which is how `NotePDFTests.lightSyntaxOnDarkDevice` makes the
    device dark on a light simulator; it fails with the pin removed.
- **A sheet is drawn a line at a time** (`NSTextLineFragment.draw`), with
  code panels through `CodeBlockLayoutFragment.drawPanel`, bottom up so a
  panel's overhang stays behind the line above, as it does on screen. A
  paragraph split by a page break spans both pages, and drawing it whole
  on each, clipped, would put its text in the PDF twice: once off the
  page, where a search or a copy still finds it.
- **Ink prints as a picture, at 288 dots per inch** (`NotePDF.drawInk`).
  `PaperMarkup.draw(in:frame:)` draws only into a bitmap context: handed
  the PDF's, it drew nothing and logged "CGBitmapContextGetColorSpace:
  invalid context" (4 Oct). So each sheet's elements, moved to the sheet's
  origin, are drawn into a bitmap cropped to where the sheet has ink, and
  that goes on the page. Text stays text.
- **What PaperKit's drawing does, measured** (probe, 4 Oct). It draws the
  markup's coordinates straight through the context's transform, so a
  bitmap has to be flipped to UIKit's way up first, and scaled by the
  transform: `frame` doesn't scale anything. And assigning a set to a new
  markup's `subelements` keeps nothing — a markup only updates elements it
  already has from an assigned set — so building one means appending
  through its `subelements`, in one `append(contentsOf:)`, as
  `NotePDF.drawInk` does.
