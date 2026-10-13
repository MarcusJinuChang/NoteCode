# AGENTS.md

## Project overview

An iPad note-taking app for computer science coursework. A single continuous,
scrollable document (Obsidian-style) where:

- Regular text is typed and formatted like a normal markdown note.
- Triple-backtick fences (` ``` `) anywhere in the flow become syntax-highlighted
  code blocks — not separate files, just inline sections of the same page. Each
  block carries a run and a copy button in its top-right corner, and run hands
  the block to a free online compiler rather than executing anything locally.
- A drawing layer (Notability-style) sits over the same page and can be toggled on
  to draw handwritten notes/diagrams with Apple Pencil, then toggled back to
  text/code editing without losing scroll position or leaving the page.

Primary use case: CS133 (C++) and general algorithm practice (Java/Python), so
code blocks need to support at least C++, Java, and Python.

Running code in-app is deliberately out of scope. Every option needed either a
paid API, a self-hosted sandbox on a VPS, or a multi-megabyte WebAssembly
runtime with a four-second cold start — all for a feature whose value is lowest
exactly when the app is being used, since nobody runs code during a lecture.

The run button is a redirect, not an execution: `CodeDestination` opens a free
online compiler, and nothing in the app ever runs a program. Two ways the code
gets there, and the difference decides how the button behaves:

- **In the link.** Compiler Explorer encodes a whole session in the URL path, so
  the student lands on a finished run. Verified against the live site; the
  compiler ids are pinned and are a maintenance item, since the site has no
  "latest" alias and 1,197 compilers.
- **On the pasteboard.** Programiz and OnlineGDB keep the editor's contents in
  the browser, with no way to be handed a program, so the code is copied and the
  student pastes on arrival. This is the fallback for every other site, which is
  what makes an arbitrary custom URL a usable destination.

Compiler Explorer does not get Java: its executor compiles into a fixed
filename, so `public class Main` fails there with an error about the file name.
It does not get JavaScript either, whose only compilers there are V8 builds that
cannot execute (see "Code: languages, the keys row…").
A destination that can't take a language hands the block to one that can rather
than failing, which is why `RunRequest` reports where it actually went.

The destination resolves through levels, most specific first — page, then
its folder, then app-wide (`Page.runDestinationLevels`). The folder is one
more element of the array `resolve` walks, not another branch.

## Tech stack

- **Swift + SwiftUI** — app shell, navigation, state management.
- **TextKit 2** (`NSTextLayoutManager`) — custom text editor that detects code
  fences as you type and renders that span as a distinct, non-plain-text region.
- **PaperKit** (`PaperMarkupViewController`, `PaperMarkup`) — transparent
  overlay canvas for ink, sharing scroll position with the text layer. It is
  PencilKit's canvas plus shapes, images and text boxes; PencilKit's tools still
  drive it. Only one of (text layer, drawing layer) should own touch input at a
  time, controlled by the toggle. Chosen over a bare `PKCanvasView` on 19 Sep;
  see docs/phase-drawing-layer.md.
- **SwiftData** — persistence for documents (text content + serialized
  `PaperMarkup` data per page). iCloud sync is a later-stage concern, not MVP.
- **Platforms** — iOS and macOS, each at the latest release (27.0). iPhone Duo
  runs the same iOS; see docs/ROADMAP.md.

## Conventions

- Prefer SwiftUI-native state (`@State`, `@Observable`) over introducing
  Combine unless a specific async stream genuinely needs it.
- Keep the text/code parsing logic (fence detection, language tagging)
  separate from rendering — parsing should be pure and testable without
  SwiftUI in the loop.
- Drawing data (`PaperMarkup`) is serialized independently per page and should
  never be re-encoded on every keystroke of the text layer — only on drawing
  layer changes.
- When several settings have to move together, they live in one type with one
  `apply(to:)` rather than being set individually at the call site, so they
  cannot drift apart. `TextRewritingPolicy` is the reference example.

## Architecture notes

- A "page" is the persistence unit: text content + an array of drawing
  strokes anchored to scroll position, not a list of discrete blocks.
- The toggle switches *input ownership*, not *view visibility* — both layers
  are always rendered/visible; only one accepts touches at a time.
- Code fence detection should be resilient to incomplete fences while typing
  (i.e. don't require the closing ``` to exist before showing highlighting).

## Colour

The UI redesign's palette (7 Oct, phase 1 of `docs/ui-design-v2-implementation.md`).

- **Accent** is `AccentColor.colorset`, `#FA8500` in light and dark, with
  `#B85900` and `#FFAA33` in the Increase Contrast slots. The target's
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` was already set, so the
  asset alone reaches SwiftUI's `.tint` and UIKit's `tintColor` (the caret,
  the selection); no root `.tint` was needed. The colorset was empty before,
  which is why everything was system blue. Checked in the built `Assets.car`
  with `xcrun assetutil --info`, all four variants.
- **Syntax colours are `SyntaxTheme`**, highlight.js CSS handed to
  HighlightSwift through `HighlightColors.custom(css:)`, replacing the stock
  Xcode theme. Pure strings, so tests read them without the JavaScript
  round trip. Measured on C++, Java and Python: the importer honours plain
  class selectors and the compound and descendant forms
  (`.hljs-title.class_`, `.hljs-class .hljs-title`), and `SyntaxThemeTests`
  checks which colour lands on which token. Each role is 4.5:1 or better on
  the code panel; a test computes the ratios.
- **Plain text is `.label`, which CSS can't say.** The HTML importer paints
  anything unstyled `#000000`, and the styler applies every run it's given, so
  without a rule plain code was black on the dark panel. The theme gives
  `.hljs` a sentinel colour (`SyntaxTheme.plainHex`) and the adapter drops runs
  in it. Revert that filter and `plainIsLeftAlone` fails.
- **Weight and italic aren't drawn.** The CSS asks for semibold keywords and
  italic comments, but `ColorRun` carries only colour. Carrying a font trait
  would mean the styler writing fonts after a highlight pass, which is another
  layout below the caret (see "Pages › Cost").
- **Run is the accent**, not green: `CodeBlockActionBar` tints it
  `UIColor.tintColor`. The copy button's green tick stays.

## Page geometry, orientation, and zoom

The document should lay out at a fixed page width, not at the device width.
Ink is stored in page coordinates, so anything that reflows the text while
leaving strokes where they are — rotation, Split View, a different device —
points annotations at the wrong words, and there is no repairing it after the
fact. A fixed column means rotation changes the margins, not the line breaks.

Wanted, and now built (see "Pages" for how):

- **A base width per orientation** — portrait narrower, landscape wider, so
  neither orientation wastes the screen.
- **Pinch to zoom in and out**, the way Notability does it.

Those two requirements pull against ink stability in different amounts, and
the difference decides how much work they are:

- If "a base width per orientation" means two *display scales* over one
  canonical layout width, nothing re-wraps, ink never drifts, and it is the
  same mechanism as pinch zoom — essentially free once zoom exists.
- If it means two *layout widths*, the text re-wraps on every rotation and ink
  drift stops being an edge case. That version is only safe on top of
  text-anchored strokes: anchor each stroke to an `NSTextLocation` plus an
  offset from that paragraph's fragment origin, then translate the stroke group
  on relayout (every PaperKit element has an ID and `applyTransform`).

**Decided, then reversed on measurement:** the zoom container was to be built
before the drawing layer. Measured first, on 12 Sep, it cost TextKit 2 its lazy
layout — see "Who owns scrolling".

**Decided 2026-09-11:** "a base width per orientation" means two *display
scales* over one canonical layout width — not two layout widths. Line breaks
are a function of that one width, so every iPad size, both orientations, Split
View and Stage Manager all wrap identically, a note authored on one device
opens the same on another, and ink stays on the words it was drawn over. It is
also the same mechanism as pinch zoom, so it costs almost nothing once the zoom
container exists.

What that buys is paid for in one place: landscape shows the same text larger
rather than showing more of it. Filling the extra width is then a choice
between raising the display scale and letting the margins grow, and both are
safe for ink, so "neither orientation wastes the screen" becomes a preference
rather than a risk. Below some width — a narrow Split View — scaling down to
fit stops being readable, so the scale wants a floor with horizontal scrolling
past it rather than shrinking indefinitely.

**Built 12 Sep, and made page-based the same evening** (`PageLayout`,
`CanvasGeometry`, `PageView`). A note lays out at its pages' text width — 672pt
for portrait pages, 912pt for landscape — and is drawn at the area's width over
the page's, up to 1.25x, times the reader's pinch zoom (0.5x to 4x). There is no
floor on fitting after all: a landscape page in a portrait iPad fits at about
0.65x, and zoom is how it gets larger. The hotbar reserves room on both sides
whichever edge it is on, so moving the bar never resizes the text.

The page's orientation is the note's, not the device's: rotating the iPad still
changes only the scale. It's chosen when the note is made, from the "+" menu,
and fixed after that (23 Sep): changing it would re-wrap the text and move every
line out from under its ink.

`GeometrySpike` (branch `spike/page-geometry`) answered this and the question is
now closed. Keep the branch for the drift demonstration it also gives.

**Also decided:** text-anchored ink is wanted for its own sake, not only as a
mitigation. That changes the calculus — once strokes are anchored to text, two
layout widths stop being dangerous, so the orientation question becomes a
preference rather than a risk. Sequencing still matters: anchoring is its own
phase and does not fit before the App Store submission.

## Who owns scrolling

The `UITextView` scrolls itself, and the canvas is a subview of its content, so
both layers share one `contentOffset` with no synchronisation code at all.

That was going to change for pinch zoom: an outer scroll view owning scroll and
zoom, with a non-scrolling text view and the canvas in one shared container.
Measured on 12 Sep before building it, a text view with scrolling disabled has
the whole document as its TextKit 2 viewport — 477ms per keystroke on a 500-line
note against 11ms scrolling, and 5.5 seconds at 2000 lines. So instead:

- The display scale is a transform on the scrolling text view, which leaves the
  viewport alone (9ms per keystroke on the same note).
- `PageView`, around it, scrolls only sideways, when the page is wider than its
  area.
- The text container's width is pinned, never tracked. A text view first sized
  while scaled below 1x takes its line width from the shrunken frame, and
  portrait and landscape then break lines differently.
- Text is drawn at the density it is shown at, by raising `contentScaleFactor`
  through the text view's subviews, capped at 3x the drawn scale. It runs
  after each layout pass of the text view *and* after each TextKit viewport
  layout (`textViewportLayoutControllerDidLayout`, public from iOS 27): an
  edit redraws its paragraph in a new view with no layout pass of the text
  view, and the line being typed stayed soft (25 Sep). During a pinch it
  waits for the gesture to end.
- Ink is drawn at that density too, by zooming PaperKit rather than scaling
  its views: `DrawingCanvas.renderScale` zooms it by the page's scale and
  shrinks the canvas by the same factor. PaperKit then sizes its content as
  the markup's bounds divided by the zoom, so the canvas's copy of the
  markup has the note's size *times* the zoom; with the note's own size,
  every element sat 81.6pt right of its words at 1.25x. The zoom never goes
  below 1 (`CanvasGeometry.inkRenderScale`): PaperKit takes input only
  inside the markup's bounds, and below 1 they were narrower than the note.
- Pinch zoom is a user factor on the same transform (`PageView.setZoom`), which
  keeps the page point between the fingers still.
- Zoomed in, a pan goes sideways or up and down, not diagonally: the text view
  scrolls vertically and `PageView` sideways. The text view can't do both —
  measured, `UITextView` forces its content width back to its own width.
- In ink mode the Pencil never scrolls, and while a finger draws, two fingers
  do (`EditorMode.scrolling(fingerDraws:)`, which `NoteEditor` applies to
  both pans). Left at one touch, the text view's pan raced PaperKit's
  gestures and a dragged lasso selection stayed put. PaperKit's own scroll
  view has a two-finger pan too, which it switches back on after a
  selection is dragged; it took every two-finger drag with nowhere to
  scroll, so `DrawingCanvas` allows it no touches at all (25 Sep).
- Off the canvas, one finger always scrolls, and a pinch zooms (26 Sep):
  beside the page, between print layout's sheets, below a short note's
  end. Beside the page is `PageView`'s own space, which scrolls only
  sideways, so its hit test hands those touches to the text view; in space
  seamless doesn't have — between print layout's sheets, its top and bottom
  margins, compressed's strip — `DrawingCanvas.takesTouch` turns them away
  (`PageLayout.takesInk`). How many fingers a
  scroll needs is set as each first finger lands (`PageView.touchWillLand`),
  so `NoteEditor` hands the mode's rule to the page, not to the pans.

- **The keyboard covers the page; it doesn't resize it** (7 Oct). SwiftUI
  used to shrink the detail for the keyboard's safe area, which gave the page
  a shorter area and cut its outline off at the keyboard, and shrank the note
  list when its search field was focused. Now the page layer
  (`PageDetailView.content`, the text view and canvas) and the list column
  both `.ignoresSafeArea(.keyboard)`. The hotbar is the page layer's sibling
  and keeps the keyboard's safe area, so it still rides above the keyboard.
  Nothing then kept the caret in view, since `PageView` turns
  `contentInsetAdjustmentBehavior` off, so `PageView` listens for
  `keyboardWillChangeFrame` and insets the text view's bottom by what the
  keyboard covers (`CanvasGeometry.keyboardInset`, pure). Three details
  that matter: the inset is in the text view's own points, so it is divided
  by the display scale; a floating keyboard insets nothing, since only a
  keyboard as wide as the screen says where the bottom is; and a bar docked
  at the bottom rides up with the keyboard over the page, so
  `keyboardClearance` adds its height, and the inset updates when the bar
  is docked elsewhere. `PageView.windowFrameForScreenFrame` exists because a
  window made outside a scene (every test) answers a screen-space conversion
  with a zero rect. Checked in the simulator on a ten-page note: the page
  stays full size and the caret line sits above the hotbar. The list change
  is checked by build only.

## Pages

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
  - **Ink saved before 9 Oct isn't cut.** Rewriting ink nobody touched on
    opening would change saved notes for being looked at; an old stroke is
    cut the first time it's moved or erased.
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
    - Ink cut on 9 Oct, before overflow existed, has random ids, so all of
      its pieces show in every mode, and a stroke saved whole before then
      shows whole, until either is moved or erased.
- **Print layout** fits its sheets inside a 24pt border of the surround
  (`CanvasGeometry.printGutter`), so they read as paper rather than one slab
  with grey bars across it. Text is a little smaller there than in the
  continuous modes, which fit edge to edge.
- **The page against its surround** (8 Oct, phase 2 of
  `docs/ui-design-v2-implementation.md`). In every mode the page is
  `systemBackground` and whatever isn't the page is `secondarySystemBackground`
  (`PageView.pageColor`, `surroundColor`): `PageView` itself and the SwiftUI
  area behind it (`PageDetailView.content`, so the hotbar's reserved strips
  and the margins show it too) are the surround. In the continuous modes the
  **text view paints the page column**, not a view of its own: the column is
  exactly the text view's bounds, its background sits under the text, the
  break decorations and the canvas (all its subviews), and it follows the
  corner radius `placeOutline()` already sets. Print layout leaves the text
  view clear, since its sheets carry the page colour and the surround has to
  show between them. `placeOutline()` sets all of it, so a mode switch can't
  leave one behind.
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

## The note page

Laid out from the 12 September mockup.

- **Header** (8 Oct, phase 3 of `docs/ui-design-v2-implementation.md`). The
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
    disabled while the text is locked), Pin, Move to Folder, Remove from
    Folder, Lock Text, Duplicate, Get Info, Delete. Delete asked once, in an
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
  The page keeps both side edges clear, whichever one the bar is on, so moving
  it never resizes or shifts the page.
  It replaces `PKToolPicker` — see docs/phase-drawing-layer.md.
  The bar is one accessibility container (identifier `hotbar`), so VoiceOver
  hears a toolbar and tests can find its frame.
- **Text tools** (10 Oct, phase 4 of `docs/ui-design-v2-implementation.md`):
  Style ▾ (Heading 1 to 3, Body, then Strikethrough), Bold, Italic, Inline
  Code, List ▾ (Bulleted only for now) and Code Block ▾ (C++, Java, Python,
  Plain Text). The separate strikethrough button went into Style. The menus
  show no ▾: the design draws plain icons.
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
- **Pencil double tap and squeeze** do what the reader set in Settings ›
  Apple Pencil (`PencilResponse`), in ink mode only: swap to the eraser and
  back, swap to the previous tool, or show the ink tools beside the Pencil.
  Hardware only — the simulator has no Pencil.
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

## Keyboard, edit menu, pointer, Dynamic Type

Phase 9 of `docs/ui-design-v2-implementation.md` (12 Oct).

- **One table of shortcuts** (`NoteShortcut`): title, key and modifiers for
  every shortcut in the brief, read by the menu bar and by the two places
  that already owned one (⌘F in the header's ••• menu, ⌘, in
  `SettingsCommands`). `NoteShortcutTests.noTwoShareKeys` is where a collision
  is ruled out, and `matchesTheBrief` compares each against the brief's table
  written out by hand.
- **They are menu-bar buttons** (`NoteCommands`), not `UIKeyCommand`s, so the
  ⌘ overlay and the menu bar both list them, titled. The window in front
  hands the menu its state through scene values, since a command can't see a
  window's: `WindowActions` from `ContentView` (new note, new folder, search,
  the note list) and `OpenNote` from `PageDetailView` (the editor, the view
  mode, print). ⌘N replaces New Window (`.newItem`), ⌃⌘S replaces the system's
  sidebar toggle (`.sidebar`: the list slides over the page and only
  `ContentView` knows its state), ⌘P replaces Print, and Format's group
  replaces the system's, whose Bold and Italic act on rich text this view
  doesn't allow.
- **Bare keys (P, H, E, L, [ and ]) are typing whenever a field has the
  keyboard.** The menu turns them off unless the note is in ink mode, no field
  is being edited and no sheet is over the window. "No field is being edited" is
  `TextInputActivity`, which watches the begin and end notifications every
  `UITextField` and `UITextView` posts, by identity (a tap from one field to
  another begins the second before the first ends). It covers the list's
  search field, a title being renamed, alerts and Settings without any of
  them knowing. Nothing on the page is first responder in ink mode, so
  nothing else competes for the keys.
- **⌘Z and ⇧⌘Z are replaced** (`.undoRedo`). The system's Undo reaches only a
  first responder that has an undo manager, and in ink mode there is none, so
  it would have been dead exactly when ink has the page. They go to
  `NoteEditor.undoFromKeyboard`: the note's own stack for the mode, unless some
  other text input has the keyboard, in which case that field's undo manager
  (`UIResponder.currentFirstResponder`, found by sending an action to no one).
- **Run Block (⌘R) and Copy Block (⇧⌘C)** act on the block the caret is in, in
  text mode (`CodeBlockAction.target(atCaret:)`); the coordinator registers
  them on the editor in `connect`. Run, Copy and the edit menu share the
  coordinator's `run` and `copy`, so there is one path for each.
- **Code Block, last language (⇧⌘K)**: `LastCodeLanguage`, per device
  (`lastCodeLanguage`), written by every code-block insert including the
  hotbar's menu, C++ until one is made, Plain Text remembered as `plain`.
- **[ and ]** step the selected tool's width (`InkToolState.stepWidth`): the
  pen's and the highlighter's three, the eraser's three sizes (from a custom
  size, the nearest preset that way), nothing for the lasso.
- **The edit menu** (`textView(_:editMenuForTextInRanges:)`): on prose, Bold,
  Italic, Code, then Format › (Strikethrough, Heading 1–3, Body); none when
  the note is locked or in ink mode. In a code block, Run Block (not for a
  block with no language the app knows), Copy Block, then Share Block, which
  was there before and wasn't asked to go.
- **Copy Block taps** (`Haptics.copyBlock`, a light impact), from the button,
  the edit menu and ⇧⌘C; a seam so a test can see it. The dock's snap tap
  was already there and is behind its setting; this one isn't.
- **Pointer:** `.hoverEffect(.highlight)` on the options-row controls and the
  bar's menus, and `isPointerInteractionEnabled` on the run, copy and language
  buttons. **Not on `HotbarButton`** (12 Oct): with it, a touch in the 8pt gap
  between the options row and the bar ran the Text button, 18pt away, and the
  three `HotbarUITests` reach tests failed from Phase 9 on (bisected: they pass
  at the Phase 8 merge, and with only that effect removed). Moving the effect
  onto the icon, or pinning it with `contentShape(.hoverEffect, .rect)`, didn't
  help. The bar's undo, redo, mode and tool buttons therefore have no pointer
  highlight; an `onHover` highlight would be the way to give them one. Seen
  with the simulator's synthesized taps, not a finger or the Pencil.
- **Print (⌘P)** opens the system's print dialog on the note's PDF
  (`NoteEditor.printNote`), the same PDF the share button makes.
- **The note body no longer follows Dynamic Type.** It did: the text view's
  font was `preferredFont(.body)` with `adjustsFontForContentSizeCategory`
  on, so a reader who raised the system's text size re-wrapped every note and
  moved every line from under its ink, which "Page geometry" says must not
  happen. Now fonts come from `preferredFont(forTextStyle:compatibleWith:)`
  at the default (`.large`) category, so they are the same 17pt body and
  34/28/22/20/17/15 headings, and the text view's adjusting is off. The list,
  Settings and menus use semantic fonts and scale (checked at the largest
  accessibility size: the list wraps and stays usable).
  - **Don't use `UIFont.systemFont(ofSize:)` for these.** First version did,
    and every line came out 1.7pt shorter: the system's body font has
    *leading* (1.71pt) that a plain system font of the same size doesn't,
    though `lineHeight` is identical (20.29 either way). Existing notes would
    have re-paginated away from their ink. `PageViewTests.orientationKeepsTopText`
    failed on it; that is the only thing that noticed. Headings kept their
    old weights too (title3 and below are semibold + bold trait, not bold).
  - `KeyboardAndMenuTests.bodyIgnoresTextSize` puts an accessibility size on
    the text view and window and checks the font, the styled text and the
    content height didn't move; it fails with the old two lines back.
- **Not checked:** any shortcut with a real keyboard (the simulator tools
  can't send modifier chords: the ⌘ overlay, the menu bar, the bare keys
  being off in a field, ⌘Z in ink mode), ⌘P's dialog on the iPad, the list
  taking ⇧⌘N and ⇧⌘F after it slides in (it waits 350ms for the slide), the
  pointer effects, the haptic, the edit menu on the iPad.

## Recently Deleted and folder faces

v3 phase 1 (12 Oct, `docs/ui-design-v3-implementation.md`).

- **Deleting moves a note to Recently Deleted** (`Page.deletedAt`), from the
  list's swipe and menu, the title menu, and a folder deleted with its notes.
  Nothing asks first; a toast offers Undo for four seconds. `modifiedAt` is left
  alone, so deleting and restoring don't reorder anything, and a note deleted
  twice keeps its first date, so its 30 days don't restart.
- **One rule decides what the reader sees: `Page.isLive`**, or `.live` on a
  collection. The list's sections (`NoteListSections`), search
  (`NoteSearch.results`), `Folder.livePages`, `NewNotes.folder(whileViewing:)`
  and the list's empty state use it; Home and Export All will. The pure types
  filter themselves, so the list can be handed every note and
  `RecentlyDeletedTests` has a test per view that fails when its `.live` is
  removed (each was removed in turn, 12 Oct, and the matching test failed).
  `NoteList` keeps its one unfiltered `@Query`; `RecentlyDeletedView` runs its
  own with `Page.deletedPredicate`, so a note it deletes for good leaves its
  rows in the same update.
- **A folder isn't soft-deleted.** `Folder.delete(_:_:from:)` removes the folder
  and, with `.withNotes`, marks its *visible* notes deleted. The folder's
  `nullify` rule then clears each note's `folder`, so a restored note lands at
  the top of the list, and Undo on that toast does too. A note already in
  Recently Deleted keeps its first date.
- **Restoring** just clears `deletedAt`: back to its folder if the folder is
  still there, else the top level, which the nullify rule already did.
- **Purging** is `Page.purgeExpired`, once per launch from `ContentView.task`,
  *after* the Welcome note's check. A store holding only deleted notes has been
  used, so that check counts them too. It goes through `Page.delete`, which
  reads nothing from a note. Notes older than 30 days (`Page.retention`) go.
  The row's "days left" is `elapsed / 86,400` floored, so 30 on the day.
- **The view** is a sheet from a row at the list's foot, shown only when it has
  notes (`RecentlyDeletedView`): Restore and Delete Now by hold or swipe, and
  Delete All… asking first. Delete Now doesn't ask, as on the `Library` board.
- **The toast** (`ToastCenter`, `ToastView`, `ToastOverlay`): one at a time, a
  new one replaces the last and restarts the clock. The list draws it at its
  foot when the list is showing, and the open note's page draws it above the
  hotbar when the list is away (`pageToastInset`; the hotbar's thickness plus
  12pt around it when docked at the bottom). Phase 8 reuses it for Copied,
  Exported and Imported. VoiceOver is told when it appears. The Undo pill looks
  28pt and is 40pt tall to a finger.
  - Undo from the title menu's Delete reopens the note, but only if no other
    note has been opened since.
- **Folder identity.** `Folder.colorName` and `symbolName` are names, not
  colours, so one folder reads right in both appearances. `FolderColor` holds the
  eight colours' tint and symbol per appearance (the brief's table);
  `FolderAppearanceTests` computes the contrast of all 16 pairs, needs 3:1, and
  checks the calculation can fail. An unknown stored name falls back to orange
  and `folder` instead of failing.
  - **The editor** (`FolderEditor`) replaces the name alert for New Folder, a
    folder's Rename and the title menu's Move to Folder › New Folder…: preview,
    name, eight colours, sixteen symbols. Its rules are a pure `FolderDraft`
    (`apply(to:moving:in:)`). Renaming a note from the list is still an alert.
  - `FolderBadge` is the symbol on its tint, 26pt in the list's rows.
- **Duplicate** (`Page.duplicated(in:)`) copies text, ink, orientation, paper,
  Markdown layout, text size, folder and run destination, and leaves the pin and
  lock behind. A copy of a note with the old layout keeps it, since its ink
  depends on the layout it was drawn on.

## Home, the title screen, thumbnails, reopening

v3 phase 2 (12 Oct, `docs/ui-design-v3-implementation.md`).

- **The title screen is an overlay on `ContentView`**, not a `fullScreenCover`
  (`WelcomeScreen`, the `Main` board): a cover's slide can't be told to fade,
  and Reduce Motion has to. Normal motion slides it up; Reduce Motion fades.
  Flag `welcomeScreenShown`, set when `claimFirstLaunch` is asked, shown or
  not. Not tied to an empty store, as the Welcome note is: a build that updates
  over notes shows it once, as the new home's introduction. Skipped, without
  spending the turn, when storage is in memory or a debug launch opened a note.
  Settings › Help and About › Welcome Screen shows it again, dismissing
  Settings first.
- **The app opens on Home** (`HomeView`): `ContentView`'s detail is Home
  whenever `selection` is nil, with the list away (`.detailOnly`); ☰ brings
  it over, as over a note. With storage failed the list starts open, since
  its warning is the list's. The Home row at the top of the list and ⇧⌘H
  (`goHome`) clear the selection and send the list away.
  - **Sections are `HomeSections`**, pure, handed every note. Continue is the
    note opened last; with none recorded, or it gone (deleted), the note edited
    last, so Home always has a way back in. Recent is the next 8 by
    `modifiedAt`. Folders are tiles in name order with live counts. `hasNoNotes`
    shows the empty state: no *live* notes, so a store of folders alone, or of
    deleted notes, is empty. The test that a deleted note is in none of it
    fails with `.live` removed (checked 12 Oct).
  - **"Page 3 of 5" is remembered, not computed.** Only a laid-out note knows
    its page count, and laying out a closed note costs what opening it does
    (see Note info). So `NoteMemory.Place` keeps `[page, of]` as of the last
    time the note was read.
  - **The Ink chip is on Continue only.** `Page.drawingData` is external
    storage; reading `isEmpty` loads the file, and Recent has up to 8 cards.
  - **Colours are the grouped pair** (`HomePalette`): light grey with white
    cards, black with dark grey ones, so cards stand out in both. Not the
    page's surround, which is darker than its page in dark.
  - **A card's shadow goes on its shape, in `.background { … .shadow }`.**
    On the stack it shaded the text too (seen in the simulator, light).
  - A tap on a folder tile is `ListRequest.showFolder`: the list opens over
    Home with that folder open and scrolled to.
  - From Template (phase 5) and Import (phase 7) are not on Home until they
    exist.
  - **⇧⌘H is bound but not tried with a real keyboard**: the simulator tools
    can't send chords. Nothing else in `NoteShortcut` uses it, and neither the
    iPad's global shortcuts (⌘H is the Home Screen, ⌘Space, ⌘Tab, ⇧⌘3/4/5) nor
    the Mac menu bar's (⌘H Hide, ⌥⌘H Hide Others) include it. If a device
    shows the system taking it, change `NoteShortcut.home`.
- **`NoteMemory` is per device and keyed by persistent ID**, in `UserDefaults`:
  the note opened last (`lastOpenedNote`) and every note's place
  (`notePlaces`, one dictionary). Not in the model: where someone was reading
  is not an edit, and must not move `modifiedAt`.
  - **Keys must be made with `.sortedKeys`.** `JSONEncoder` writes an object's
    keys in no fixed order, so the same `PersistentIdentifier` gave different
    strings on different calls: places were never found again, and a
    thumbnail's cache name changed between asking and storing, so every
    thumbnail came back blank. Found by `NoteMemoryTests`, after the simulator
    showed it.
  - **Find a note by its key, never by decoding a key into an ID.** A decoded
    ID passed `==` but a `Set` of IDs didn't find it, so pruning forgot every
    place at each launch. `HomeSections` compares `key(for:)`; `prune` builds a
    set of keys.
  - **A new note's ID is temporary until the context saves it**, and a key
    made from one never matches again. `Page.settledID` saves first, then
    answers; `key(for:)` refuses a temporary ID.
  - Pruned once a launch, with every note's ID (deleted ones too).
- **Reopening at the last page.** `PageDetailView` reads the note's place once
  as it opens and hands `DocumentTextView.resumingAtPage`; `PageView.restore`
  waits for the first layout, as `reveal` does (a search's match wins), lays
  out down to that page as scrolling there would (`DebugLaunch.scroll`'s
  technique, not the whole note) and scrolls to `scrollTop(forPage:)`.
  - **The page reports its own place** through `onReadingPlaceChanged`,
    whenever the page at the top or the page count changes, held back until
    the restore has run: otherwise opening at page 4 first wrote page 1 over
    it. The place is the page at the top edge plus 1pt, since exactly on a
    page's scroll-top the edge is mid-band and rounding could name the page
    before. Written as the reader scrolls, not on closing, so an app killed
    mid-read keeps where it was.
  - A place past a shortened note's end opens at the end, scrolled as far as it
    goes: the last page's top can lie beyond the furthest the view scrolls.
  - Tests check the line at the top against a note laid out from scratch, in
    every mode and orientation, and that the first report is the restored
    page. Layout in those tests is forced a few passes at a time: a window made
    outside the test host's scene has no display link, and the report hooks
    run from layout passes.
- **Thumbnails** (`NoteThumbnail`, `ThumbnailStore`, `NoteThumbnailView`): the
  first page, drawn as the PDF draws a sheet (`PrintedNote`, `NotePDF.drawInk`),
  light, at 0.55 pixels to the page point (449 by 581 for Letter).
  - **Never the whole note.** The printed text view is fed `prefix(of:)`: 80
    paragraphs or 8,000 characters, whichever comes first, clear of what one
    page holds. Measured on the simulator, a 2,000-line note: 9ms with the
    prefix, 333ms without; 40 lines is 4ms. The cost test fails without it.
  - **Ink is drawn at the thumbnail's resolution**, not the PDF's:
    `NotePDF.drawInk` takes `pixelsPerPagePoint`. A sheet's crop at 288 dots
    per inch is 31MB. Only elements touching page 1 are drawn.
  - **Cached in Caches** as `NoteThumbnails-v1/<hash of the ID>-<modifiedAt in
    ms>.png`. A new date is a new name, so no timestamp is read (the privacy
    manifest needs a reason for file timestamps), and the note's older files are
    removed as a new one is written. Bump `NoteThumbnail.version` when a note
    starts looking different for another reason: phase 3's hidden markers
    will, since a thumbnail made now shows `##` and `**`.
  - **One per turn of the main actor** (`ThumbnailStore.Gate`, a class: a
    struct held across the gate's suspension was an exclusive-access trap),
    each yielding before it starts; a request cancelled while it waits draws
    nothing. A row that is being edited shows its last picture and waits 600ms
    of quiet before asking for the next.
  - A note whose deletion has been saved is never read (AGENTS.md, drawing
    data): the store checks `modelContext` and `isDeleted` before touching it.
  - macOS draws a placeholder; `PrintedNote` is UIKit.
- **Debug launch:** `-debug-first-launch` and `-debug-home` (see the table).
- **Not checked:** the Pencil; Reduce Motion's fade; the title screen in dark;
  the Home row, a folder tile, Show All and the toolbar's search and + by a
  tap; ⇧⌘H; Home on an 11-inch iPad or in portrait; a thumbnail updating after
  an edit on screen; thumbnails of a note with ink on the iPad; the macOS
  Home (it builds).

## Writing: hidden Markdown markers, lists, checklists, links

v3 phase 3 (12 Oct, `docs/ui-design-v3-implementation.md`).

- **Markers take no room in a `rendered` note** (`Page.markdownLayout`,
  `MarkdownLayout`). `BlankLineLayout`'s content-storage delegate swaps each
  marker for U+2060 WORD JOINER in the paragraph TextKit lays out: same
  length, so offsets map straight through, and the text storage still holds
  the Markdown. The ranges are `DocumentStyler.layouts`' own (`blockMarkers`,
  each inline's `markers`), so styling and layout can't disagree. Collapsed:
  a heading's `# `, the markers of complete inline spans (inline code only its
  backticks), a link's `[` and `](url)`, and a checkbox item's `- `. A bullet
  `-`/`*`/`+` lays out as `•`; `[ ]` or `[x]` as an em space plus two joiners,
  and the box is drawn in the em space. Nothing in a code block. A legacy note
  (`markdownLayout` nil) swaps blank lines only, as before.
  - **State-independent**: the swap is a function of the text alone. The caret,
    the mode and Show Markdown never change it.
  - **Probe, as tests** (`MarkdownLayoutTests`). Every line frame (fragments
    and lines) of a note with bold, code, strike, a link, a heading, bullets
    and boxes equals that of the same styled text with the markers physically
    deleted, in seamless, print and landscape. A control test and a mutation
    (swap off) both fail it. Carets beside a run are full height. A closing
    marker typed, a span broken, and a fence opened or closed above all lay
    out the same as a fresh note, *in the edit that makes them*: the styler's
    attribute edit regenerates the paragraphs whose parse changed, so nothing
    stale survives. A keystroke in a 500-line rendered note: 37.2ms against
    37.0ms legacy (`MarkdownLayoutCostTests`); the runs are computed once per
    edit (`layoutMarkerRuns`), not per paragraph, and a layout parses nothing.
  - **Measured, so it isn't tried again**: a joiner is zero width in the body
    font, next to an em space too (CoreText); `closestPosition` over a bold
    word returned offsets on both sides of each marker and never inside one;
    a test's ground truth has to keep the em space and `•` the swap puts in,
    or the checkbox and bullet lines look 10pt off.
  - **`PrintedNote` takes `rendersMarkdown`** (PDF and thumbnails), or the
    paper breaks lines where the screen doesn't. `NoteEditor.rendersMarkdown`
    carries it from the coordinator. A thumbnail's cache name has `-r` for a
    rendered note, since hiding markers isn't an edit and leaves `modifiedAt`
    alone, and `NoteThumbnail.version` is 2.
  - **The parser got stricter on the way** (`InlineParser`): an emphasis span
    can't start with a space or end after one, and `_` can't open or close
    inside a word. `2 * 3 * 4`, `int *p and *q` and `snake_case_name` were
    spans, which was a dimmed-asterisk quirk before and a vanished character
    once markers are hidden.
- **Reveal is drawing only.** `HeadingLayoutFragment` widens
  `renderingSurfaceBounds` into the left margin and draws the hashes in
  `secondaryLabel`, right-aligned 8pt left of the text on the first line's
  baseline: while the caret or a selection is on that heading (Show Markdown ›
  While Editing) or always (Always); never in ink mode, never printed (the
  PDF draws lines, not fragments). Redrawn the way fences are
  (`HeadingMarkerDisplay.swift`, state in `HeadingMarkerVisibility`, asked at
  draw time, `setNeedsDisplay` on the changed fragment views): a caret move
  makes no fragment and edits no storage (tested, as `CodeFenceCostTests`
  does). **A unit test can't see the crop**: `layer.render` doesn't apply the
  fragment view's bounds, so the pixel test passed with the reach removed. The
  contract is tested instead (the area reaches past the hashes at every level;
  fails without the union), and the real crop was looked at in the simulator.
  A fragment's default area reaches only 11pt left of its text.
- **Inline formatting shows in the hotbar** (`NoteEditor.caretFormatting`,
  `MarkdownFormatting.formatting`): Bold, Italic and Code light up, Style ▾
  and List ▾ show checkmarks. A caret is in a span from just after its first
  marker character to the end of its text, which is what typing there makes.
- **Caret stops** (`MarkdownFormatting.caretStop`, pure, on the one line,
  parsed with the styling's parsers). Every offset in a hidden stretch is one
  place on the page; the stop is its left edge for inline markers (the end of
  a bold word is inside it, the start isn't) and after it for a heading's
  marker or a checkbox's `- [x] `. Touching markers are one stretch.
  Applied in `closestPosition(to:)` and in `textViewDidChangeSelection`
  (`normalizeCaret`).
  - **Never after an edit.** Typing the closing `**` leaves the caret after
    it; normalising would put it back inside the bold and the next letter
    with it (`typingIsLeftAlone`). An edit is told by `editCount`.
  - **An arrow is a caret that moved one place with no finger down**
    (`wasTouchedRecently`, from `hitTest`); a tap, or any other landing, goes
    to the stop. An arrow leaves a stretch the way it came in: right from an
    inline stop goes one visible place on, except at a line's end, where it
    goes just past the markers, the only way out of bold there (invisible,
    and the hotbar's Bold shows it). Left from a heading's stop goes to the
    line above.
  - **A tap past a line's end goes after its markers** (13 Oct). A line that
    ends in a bold word or a link has two places at its end, either side of
    the hidden markers, and the stop rule put every tap on the one inside
    the span, so tapping in the empty space after such a line left the caret
    short of the end. `DocumentUITextView.isBeyondLineEnd` asks whether the
    touch is more than 8pt right of the line's last glyph; if so
    `closestPosition` and `normalizeCaret` leave the caret at the line's end
    (`CodeEditingFixesTests.tapAfterBold`, `.tapAfterLink`). A tap *on* the
    last letter still stands inside the span. Not tried with a real
    finger.
- **Backspace** (`MarkdownFormatting.backspace`, applied in `shouldChangeTextIn`
  through `Coordinator.apply`, which is `replace(_:withText:)`, so undoable and
  restyled): at the start of a heading's or list item's text it removes the
  marker (keeping indentation); in front of, inside or just past a closing
  marker it deletes the last visible character of the span by grapheme, and an
  emptied span goes with its markers. Elsewhere the ordinary Backspace.
- **Return, Tab, ⇧Tab.** Return in a list item continues it (same bullet, next
  number keeping `.` or `)`, an empty box); on an empty item it ends the list;
  text after the caret moves to the new item; one undo step. In a rendered note
  Return at the end of a line that ends in closing markers puts the newline
  *after* them (the caret stands in front, and a plain newline split `**` from
  its word). Tab nests two spaces, ⇧Tab takes them back, only on list items
  (otherwise the key is given back). Tab arrives as `shouldChangeTextIn` with
  `"\t"`; ⇧Tab is a `UIKeyCommand` on `DocumentUITextView` with priority,
  not a menu button, since a bare Tab in the menu bar would take it from every
  field. Numbers after an inserted item aren't renumbered.
- **List ▾** has Bulleted, Numbered and Checklist (`toggleList`): another kind
  converts, the same kind takes the list off, numbers count written lines.
- **Checklists**: `- [ ]` / `- [x]` (any bullet char; `[ ]` then a space or the
  line's end) is `ListMarker.checkbox`. `ChecklistLayoutFragment` draws the box
  (2pt `tertiaryLabel` outline, 6pt radius; checked: accent fill and a white
  tick) in the em space, or over the `[ ]` glyphs in a legacy note, and the PDF
  draws it with its line (accent by name: paper has no tint). A ticked item is
  struck through in `secondaryLabel`.
- **Taps on boxes and links** (`MarkerTaps.swift`). **Decided without the
  spike**: `textView(_:primaryActionFor:)` wasn't tried; the brief's fallback is
  what a box needs anyway and one path serves both. The text view answers
  `hitTest` with itself for a touch on a box or a link, so the text
  interaction's recognisers (on an inner view; refusing them in
  `gestureRecognizerShouldBegin` doesn't work) never see it and the caret
  doesn't move or the keyboard rise; recognisers on the text view take the tap
  and the hold. They live on a separate delegate object (`MarkerGestures`): a
  scroll view is the delegate of its own pan and pinch. A box needs an
  editable view; a link opens in a locked note too. Link text: `[text](url)`
  and a bare `http(s)://` address shown exactly as typed, `#B85900` / `#FFAA33`
  underlined (`DocumentStyler.linkColor`); inline code isn't a link. Only
  http, https and mailto open (`LinkTarget`); no scheme means https. A hold
  shows the address with Open Link and Copy Link (`UIEditMenuInteraction`).
- **Hide Markdown Markers…** is in the title menu for a legacy note (not the
  list's note menu), asks first with the board's wording, and sets `rendered`.
  Not an edit. The words re-wrap once, so ink drawn before may need moving.
- **Not checked** (see the PR's checklist): the Pencil; a real keyboard (⇧Tab,
  Tab, arrows past markers, ⌘B on a double-tapped word); the link tap and hold
  (a tap opens Safari, which the simulator tools weren't driven to); Return and
  Backspace by the hardware keyboard; the margin hash in light mode on screen
  (dark was looked at; light is covered by the pixel test); fast
  typing and pasting into a rendered note; the title menu's conversion on a
  note with ink; the macOS app running (it builds); `closestPosition` for a
  selection drag handle.

## Code: languages, the keys row, indentation, line numbers, output

v3 phase 4 (13 Oct, `docs/ui-design-v3-implementation.md`).

- **Eight languages** (`CodeLanguage`): C++, Java, Python, then C, JavaScript,
  Rust, Go and SQL, in that order in every menu (`CodeBlockKind.menu`: the
  languages, a divider, Output, Plain Text). Each has its tags (`js`, `golang`,
  `rs`, `postgres`, …), `displayName`, `canonicalName` (Compiler Explorer's own
  language id), `highlightName` (what highlight.js is asked for, so `golang` and
  `js` colour without depending on its aliases) and `canRun`. The raw value is
  what `insertCodeBlock` writes after the fence, and reads back as itself.
  - **SQL is Copy only** (`canRun` false): the sites that take it run it against
    a database of their own, so a Run would only open a page. No destination
    lists it; the menu says "Copy only" under it.
  - **Run mapping, checked on the live sites on 13 Oct.** Compiler Explorer
    ids are pinned: C `cg152` (`-O2 -std=c17`), Rust `r1990` (`-O`), Go `gl1260`,
    beside `g142` and `python313`. Each was compiled and run through
    `/api/compiler/<id>/compile` with `execute` on, and a `clientstate` link
    for each of C, Rust and Go was opened in a browser and landed on "Program
    returned: 0" with the program's output (Go's first compile took 17s cold).
    **The brief and canvas say JavaScript runs on Compiler Explorer. It can't:**
    its only JavaScript compilers are two V8 builds with `supportsExecute` false,
    so JavaScript is Programiz by paste, like Java. OnlineGDB has no JavaScript
    or SQL page either (404), so its `supportedLanguages` drops JavaScript too.
    The ids are a maintenance item: retired ones still show the code, with the
    compiler pane complaining.
  - Tags other than these are unknown, so a block tagged `ruby` still has no
    Run and keeps its tag as the language button's label.
- **Output blocks** (```` ```output ````, `CodeBlockKind.output`,
  `CodeBlock.isOutput`): a console. Dark panel in both appearances
  (`CodeOutputPanel`: `#141416`/`#E5E5EA`/`#A1A1A6` light, `#2C2C2E`/`#F2F2F7`/
  `#8E8E93` dark), the label "Output", Copy and no Run, no highlighting, no
  auto-indent, no line numbers. Measured contrast: text 14.7:1 light, 12.5:1
  dark; the design's label colour is 7.2:1 light and **4.3:1 dark**, under 4.5
  for 13pt text, kept as the design has it and tested at 4:1.
  - **Three things the retag between a language and Output taught**, so they
    aren't found again. (1) Python and output are both six letters, so the
    styler's block signature didn't change and the text kept its old colour;
    `styleDetail` now includes `isOutput`. (2) A highlighting pass handed an
    output block resets its text to `.label` (`applyColors(clearing:)`), so
    output is left out of the jobs, and `codeColors` doesn't carry the
    console's text colour into a block just turned into code. (3) **A retag
    between languages never re-coloured anything**, which predates v3:
    `highlightedBlocks` was keyed by `CodeBlockID`, which is the block's
    ordinal and code and not its tag, so python → sql left python's colours on
    the text. It is keyed by the id and the tag now (`HighlightKey`).
    `OutputBlockTests.retagRecolours` fails with the tag taken out of the key.
    **That test restyles once before its first check**: the harness's window
    applies its appearance after the first restyle, a change of appearance
    forgets everything highlighted, and until then the mutation looked
    harmless.
  - The fragment's `isOutput` is set when it is made. A retag restyles the whole
    block, which lays every paragraph of it out again, so none keeps the old
    answer (`retagTurnsEveryLine`).
- **Return in code** (`CodeIndent.returnEdit`, pure, applied from
  `shouldChangeTextIn` through `Coordinator.apply`, so one undo step): keeps the
  line's indent as far as the caret is in it; one level deeper after `{`, `(` or
  `[` and, in Python only, a colon (not in a `#` comment; `case 1:` in C++ is a
  plain newline); between a bracket and its own closer the closer goes to its
  own line and the caret lands between; a line the caret leaves blank has its
  indent moved down, not copied, so a blank line stays blank. Not on a fence
  line, not in output, not for a selection that leaves the block. One level is
  Settings › Code › Indent Width (2 or 4, default 4), or a tab if the line is
  indented with one.
- **Backspace in an indent takes back a level** (`CodeIndent.backspaceEdit`,
  13 Oct): with a collapsed caret in a code line's leading spaces, one press
  deletes back to the previous multiple of the indent width, so four spaces
  typed by ⇥ go in one press and six go to four. One space over a level, a
  tab indent (already one level a character), a caret after text and a
  caret outside a block's own lines are the ordinary delete. Applied from
  `shouldChangeTextIn` like Return, so one undo step.
- **A block with no language is plain** (13 Oct). The styler carries syntax
  colours across a restyle, since highlighting is async; it carried them
  for a block whose tag had just been deleted too, and no highlight pass
  comes for a bare fence, so the old language's colours stayed on the text
  (`DocumentStyler.codeColors` now skips blocks with no tag,
  `CodeBlock.hasLanguageTag`). A tag the app doesn't know (`ruby`) still keeps
  what highlight.js makes of it.
- **⇥ and ⇧⇥** (`CodeIndent.indentEdit`; the hardware Tab arrives as a `"\t"`
  in `shouldChangeTextIn`, ⇧Tab is the existing `UIKeyCommand`, which now
  answers for code too): one level in or out on **every line the selection
  touches, which with a caret is its line, wherever the caret is in it**, not
  an insert at the caret. That is the brief's wording ("indent or outdent the
  selected lines"), chosen over VS Code's tab-at-the-caret since on a tablet a
  line is what is wanted. Blank lines in a multi-line selection are left alone;
  a single blank line takes the indent, or ⇥ there would do nothing. ⇧⇥ with
  nothing to take off hands the key back. Code lines only: a selection running
  into a fence or prose isn't Tab's. Lists keep their own Tab.
- **The code-keys row** (`CodeKeysRow`, `CodeKeys`): ⇥ ⇤ `{ } ( ) [ ] < > ; = " '
  : / \ | & * #` ← →, on a glass capsule, 40pt keys in a 52pt row, an
  `inputAccessoryView` set while `TextRewritingPolicy` says the caret is in
  code, and swapped **before the one `reloadInputViews()`** that crossing
  already does (`applyRewritingPolicy`), so the traits and the row change in a
  single redraw. The first tap into a note that opens on code crosses nothing,
  so the unchanged-policy path refreshes it too
  (`refreshedWithoutCrossing` fails without that). The symbols scroll in a narrow Split
  View; the indent and arrow keys stay at the ends. Each key goes through the
  same paths as typing (`replace(_:withText:)`, `apply`), so it undoes like
  typing; ← and → collapse a selection to its edge.
  - **Not with a hardware keyboard** (`HardwareKeyboard`): `GCKeyboard.coalesced`
    non-nil, with a refresh on `GCKeyboardDidConnect`/`DidDisconnect`. Not the
    on-screen keyboard's visibility, which says nothing about whether a
    hardware one is attached. Asked last (an autoclosure), since the row is
    decided on every caret move. **Not checked with a real keyboard**, or in the
    simulator with "Connect Hardware Keyboard" on.
  - **`CanvasGeometry.keyboardInset` needed no change, measured.** UIKit's
    `keyboardFrameEnd` includes the accessory: on the iPad Pro 13-inch
    simulator in landscape it was `(0, 534, 1376, 498)` in prose and
    `(0, 482, 1376, 550)` in code, 52pt taller and higher, and the move from one
    to the other posts a new frame, so the text view re-insets as the caret
    crosses. The hotbar, docked at the bottom, rides above the row.
    `KeyboardInsetTests.codeKeysRow` and `PageViewTests` pin the arithmetic
    with those numbers.
- **Line numbers** (Settings › Code, off by default): `CodeBlockLayoutFragment`
  draws each code line's number, right-aligned 16pt left of the panel, in the
  page's margin, on the paragraph's first line's baseline (a wrapped line has
  one), `secondaryLabel`, monospaced digits at 85% of the code's size. **Never a
  gutter inside the panel**, which would shift the code, re-wrap it and move
  ink. It's the way a heading's hash is drawn: the fragment's rendering surface
  always reaches `PageLayout.margin + 5` to the left (on or off, so the setting
  is a redraw and no layout), the number is asked for at draw time
  (`lineNumber`), and the coordinator `setNeedsDisplay`s the on-screen fragment
  views of every block when the setting changes. The number is the count of
  newlines from the block's start, so an edit above renumbers nothing. Not on
  fence lines or output. Printed when on (`NoteEditor.showsLineNumbers` →
  `NotePDF.Note.lineNumbers`, once, on the page a split paragraph's first line
  is on); thumbnails never show them. Measured: a keystroke in a 500-line note
  30.9ms off, 30.7ms on; a rendered-note keystroke 34.4ms against legacy 35.3ms,
  and the fence cost test 36ms — no worse than before. **A pixel test does see a
  crop here**: with the surface's margin union removed, the digits vanished
  from the render (`rightAligned`, `surfaceReach`), unlike the heading hash's.
- **Settings › Code** has Code Keys, Indent Width and Line Numbers beside Run
  Code In. `CodeEditorSettings` carries the three to the editor with one
  `apply(to:in:)` (the repo's one-type rule), from `PageDetailView`'s
  `@AppStorage`. Keys: `codeKeys`, `indentWidth`, `lineNumbers`, pinned in
  `SettingsTests.keysAreStable`. A width the picker can't have made reads as 4.
- **Not checked:** the Pencil; a real hardware keyboard (⇥, ⇧⇥, the row
  disappearing); a floating keyboard; the row in a narrow Split View; VoiceOver
  on the keys; Return in the Korean layout the simulator started with was the
  only keyboard used; the Output panel's selection highlight (orange at 30% on
  a near-black panel) beyond looking at it; line numbers at 4+ digits on
  screen (the area is tested for five); the macOS app running (it builds).

## Settings

A form sheet with a `NavigationStack`: a list of sections, each a page
(10 Oct, phase 6 of `docs/ui-design-v2-implementation.md`). `SettingsView.swift`
holds the list and every page but Drawing, which is iPad-only
(`DrawingSettings.swift`); the pure parts (appearance, the snap haptic's key,
the version string, the licence text, the palette reset) are `AppSettings.swift`.

- **A row exists only if it works.** Left out on purpose, and where each
  comes back (App Icon came with phase 7, see "Shipping"): New Notes and
  Welcome Note (both came with phase 8; New Notes is the "+" button's tap, so
  a row before then would have changed nothing), Send Feedback and Privacy
  Policy (`AppInfo.feedbackAddress` and
  `.privacyPolicy` are `nil` until Marcus gives one; each row appears when its
  value does). Not built, per the brief: Account, iCloud, Templates, Recently
  Deleted, Export All, Storage, Rate, What's New, code keys, indent, line
  numbers.
- **Every row binds the key its owner already uses**, through the owner's
  constant (`HotbarDock.defaultsKey`, `NoteSort.defaultsKey`,
  `RunDestinationPreference.appDefaultKey`, `NoteEditor.fingerDrawsKey`, …),
  never a second spelling. `SettingsTests.keysAreStable` pins the stored
  names, since renaming one orphans what a device saved. Finger Draws needed
  no new key: `fingerDraws` was already per device (10 Oct, before this phase),
  so the row and the hotbar's hand button are one setting.
- **Opening it.** The gear is an inset at the foot of the list
  (`NoteList.safeAreaInset`), not a `.bottomBar` toolbar item: in the
  simulator that placement put the gear at the centre of the screen with the
  list hidden, and it wasn't there in portrait. ⌘, is a `CommandGroup(replacing:
  .appSettings)` in the app's menu (`SettingsCommands`), which can't see a
  window's state, so the window in front hands it its sheet's binding through
  `focusedSceneValue`. The sheet is owned by `ContentView`, above the list,
  so ⌘, works with the list slid away over a note.
- **Appearance is applied at the root of the scene** (`AppearanceModifier`,
  `preferredColorScheme`, on both the note view and the storage-unavailable
  view), so every window, the sheet and UIKit controllers presented from it
  follow it live. `AppearanceSettingTests` hosts a view in a window and
  changes the stored value light → dark → light → system, and fails without
  the modifier. The PDF stays light by its own means (`NotePDF`).
- **Settings changes reach an open note.** The sheet sits over the page, whose
  editor was set from the device's values as it appeared, so
  `InkToolPersistence` also follows the stored eraser and Finger Draws
  (guarded by equality, so the editor's own writes aren't echoed back). Without
  it the next hand-button tap would have written the stale value over the
  Settings one. The palettes need nothing: every swatch row reads the same key.
- **Haptic on Snap** is `.sensoryFeedback(.alignment)` on the hotbar, triggered
  by a counter `drop` bumps, with the setting as its condition. It fires on
  every drop, including one that lands back on the same edge, and not on
  Toolbar Position or the "Dock …" accessibility actions, which aren't snaps.
- **Palettes** are edited in a `List` (swipe to remove, Edit to reorder, Add
  Colour from Apple's picker through `InkColorPicker`, as the hotbar does).
  Reset Colours asks first, and only rewrites the two palettes
  (`InkPalette.resetStoredPalettes`): the colour each tool is drawing in is
  left, and falls back to the palette's first on its own if the reset took it.
- **Acknowledgements** is `Acknowledgements.txt`, bundled: HighlightSwift's
  MIT licence, and highlight.js's BSD-3, which HighlightSwift carries and the
  app ships. It's copied from the package checkout, so a package update that
  changes either licence means copying again; a test checks both are present.
- **The mark** in About's header is `NoteCodeMark`, drawn in SwiftUI on the
  logo's 120-unit grid (the brief's geometry), in the colours of whichever
  `AppIconChoice` it is given: About shows the Default, and General › App Icon
  draws all three as previews. `scripts/make-icons.swift` draws the same
  shapes into the real icon; this view isn't the icon.
- **Not checked on screen:** most pages (only the section list was seen, in
  dark, in the simulator), the Mac's sheet and ⌘, (the Mac builds; it was not
  run), the haptic, Add Colour from a sheet, Reset Colours, and Appearance
  with a note open.

## Code-block fences

A code block shows its backticks only while it is being edited (10 Oct,
phase 5 of `docs/ui-design-v2-implementation.md`). Pure rules are in
`FenceVisibility`; drawing is `CodeBlockLayoutFragment`; wiring is
`CodeFenceDisplay.swift`.

- **Editing** is the caret or a selection in the block, from the opening
  fence's line to the end of the closing fence's line (before its newline: the
  line after is prose). An unclosed block holds the caret to the end of the
  note. A selection counts if it overlaps the block by a character. In ink
  mode nothing is being edited. Settings › Writing › Show Markdown is
  `ShowMarkdown` (`showMarkdown`, While Editing or Always); Always draws every
  fence. Its row is in Settings › Writing
  (see "Settings"); `PageDetailView` reads the key. Always keeps fences
  in ink mode too, which the brief didn't say either way.
- **Hide glyphs, never lines.** An away block's fence lines keep their
  height and place and the fragment skips drawing their text, so nothing
  below moves and ink stays on its words. No text-storage edit is made to
  show or hide them. The fragment asks the coordinator at *draw* time
  (`fenceDisplay`), finding its block from its own offset, as
  `selectedRanges` does; a state change marks the on-screen fragment views
  of the blocks that changed for display (`setNeedsDisplay`, no layout), the
  way the selection highlight does.
- **Not a rendering attribute** (the brief's first choice). Measured:
  `setRenderingAttributes([.foregroundColor: .clear])` hides the glyphs and
  lays nothing out (same fragments, no viewport layout), and follows an edit
  above its range. It does not follow one inside it: the language menu
  replacing a tag, or typing at the range's end, drew the new text again, so
  it would be set again after every edit. `CodeFenceDisplayTests.renderingAttribute`
  records this. A first spike concluded it drew nothing different; its
  measuring rect began outside the panel's rounded corner, so its first
  pixel was the page's and every panel pixel counted as ink. **Measure
  pixels inside the panel** (`Harness.interior`).
- **Cost, measured** on the simulator, 500-line note, seamless layout: a
  caret move into or out of a block 1.5ms; a keystroke at the same place
  35ms. Over the moves, zero fragments made (counted at the layout
  delegate) and zero text-storage edits. TextKit's viewport-layout callback
  still fires about once per in-and-out; nothing is laid out.
- **The opening fence, away** has the language's name (`CodeBlockLanguageButton`,
  C++, Java, Python, or the tag as typed, Plain Text for a bare fence) where
  the glyphs were, and a menu that retags through `replace(_:withText:)`
  (`FenceTag.retag`, pure): undoable, Run follows. It is an action-bar
  control: the overlay keeps it beneath the canvas, in `containsInteractiveElement`,
  and a locked note shows it dimmed with nothing behind it. Editing shows
  the fence in the marker colour instead, and no button. There was an accent
  ring round the block being edited until 13 Oct; Marcus found it ugly and it
  went (`CodeFenceDisplayTests.noRing` pixel-checks the edge). The PDF never
  prints fence lines (`NotePDF` skips `isFence`).
- **Undo and redo pass the keyboard-rewrite guard.** Undoing a retag puts text
  back by replacing it inside a code line, which is what a keyboard
  correction looks like, so `shouldChangeTextIn` turned it away and spent
  the undo step. Found by the retag's undo test.
- The panel starts at the fragment's x, 5pt in from the container, and
  code text starts at that edge too: the first glyph touches the panel's edge.
- **Not checked:** a real tap on the name, the menu on the iPad, fast typing
  into a new block, a paste, a block scrolled out of view while its state
  changes (it draws its state when it returns, since it asks at draw time),
  find highlights on a hidden fence, or the Pencil.

## Organising notes

A flat, date-sorted list of pages does not survive a semester of coursework,
so notes file into folders by class — CS133, algorithm practice (built 3 Oct).

- **One folder per note, or none** (decided 3 Oct). `Folder.pages` is
  to-many with a nullable inverse, `Page.folder`, so a note can sit at the top
  of the list. Several folders per note would make "move" and deleting a
  folder with its notes ambiguous, and grouping by class doesn't need it.
  Folders don't nest.
- **Folders open and close in place** in the list (`NoteList`), rather than
  leading to a column of their own: the list slides over the page, and a
  second column would cover more of it. Open state is per launch.
- **Deleting a folder asks** whether its notes go too, or move to the top.
  `Folder.delete` saves at once, like `Page.delete`. "Go too" means Recently
  Deleted now, not gone for good (see "Recently Deleted").
- **Moving a note isn't an edit.** It keeps its date modified, or filing a
  week of notes would make them all look written today.
- The list's grouping and order are pure (`NoteListSections`): folders sort
  by name with numbers compared as numbers, and notes by the reader's sort.

- **Pinned goes to the top** (3 Oct). Pinned folders and pinned notes, from
  any folder, sit in a Pinned section above the folders. A pinned note is
  listed there and not again in its folder, so no note has two rows (a
  selectable list would highlight both), and a folder's count is the notes
  under its own row; a pinned note's row names its folder instead. Pinning,
  like moving, isn't an edit and keeps the date.
- **Sorting is per device** (`NoteSort`, `@AppStorage`, 3 Oct): date
  modified, date created or title, either way round, and picking a key picks
  the way round that reads naturally — newest first, A to Z. It orders notes
  in every section; folders stay in name order. Rows show the date the list
  is sorted by. Ties fall back to title, then creation, so the order never
  shuffles between launches.
- **The list's toolbar holds two items**, ••• and +. Edit and Sort By share
  the ••• menu on iPad, and Done takes its place while editing: with Edit,
  Sort and New side by side, the sidebar had no room left for its title.
- **The + is a `Menu` with a primary action** (12 Oct, phase 8 of
  `docs/ui-design-v2-implementation.md`). A tap makes a note in Settings ›
  Notes › New Notes' orientation (`NewNotes`, key `newNoteOrientation`,
  portrait until chosen); holding it shows Portrait Pages, Landscape Pages and
  New Folder. A note made from either goes in **the open note's folder**
  (`NewNotes.folder(whileViewing:)`), or the top of the list with no note open:
  the list has several folders open at once, so "the open folder" had to mean
  something, and this is where a student working through a class's notes is.
  All creation goes through `Page.create`, so the tap, the menu and the folder
  menu can't disagree about what a new note is.
- **The note menu is the title menu**: `NoteTitleMenu` is used by both, and the
  list passes `onRename` where the title uses the system's `RenameButton`, so
  rows and order can't drift. The list's Rename asks in the name alert
  (`FolderNaming.renamePage`) and moves the date, as renaming from the title
  does. Delete still doesn't ask in the list, as before.
- **The selected row is the accent tint** (`RowSelectionTint`, 18% light, 22%
  dark) set with `listRowBackground`, label-coloured text. Seen in the
  simulator: it replaces the system's solid highlight rather than sitting
  under it. Light only; dark not looked at.
- **Empty states.** No notes and no folders: `ContentUnavailableView` with New
  Note and Open Welcome Note. A folder with nothing in it shows a "No Notes"
  row that can't be selected. No search results was already
  `ContentUnavailableView.search`.
- **The Welcome note** (`WelcomeNote`) is plain text, no seeded ink. It is made
  on first launch (`ContentView.task`, flag `welcomeNoteMade`), **only when the
  store has no notes and no folders**: the brief said "first launch", and a
  build that updates over a semester of notes isn't one. The flag is set
  either way and never cleared, so deleting the note doesn't bring it back. Not
  made when storage is in-memory (the flag would claim a first launch happened)
  or under a debug launch's note. Settings › Help and About › Welcome Note, and
  the empty list's Open Welcome Note, make a **new** note each time and open
  it. Making one writes nothing to any other note
  (`NoteListFirstRunTests.otherNotesKeepTheirDates`).
- **The launch screen is the system background and nothing else**:
  `INFOPLIST_KEY_UILaunchScreen_Generation` writes an empty `UILaunchScreen`,
  already the case; `AppStoreReadinessTests.launchScreenIsPlain` pins it.
- **Note info is derived, never stored** (3 Oct). `NoteInfo` works out
  words and code blocks by language from the text, through
  `DocumentParser`, each time the sheet opens: nothing to keep in step
  with typing, and no model change. Code isn't words, and markdown markers
  around prose aren't either. Get Info in the list's note menu leaves out
  the page count, since only a laid-out note knows it (`PageView.pageCount`)
  and laying out a closed note costs what opening it does; the info button
  in an open note's header adds it. The sheet is a standard form sheet with
  two closely spaced sections, which holds every row for code in up to
  three languages. Page size left most of the sheet empty, and
  `.presentationSizing(.form.fitted(...))` collapsed it to its title bar,
  since a Form reports no height of its own (measured 3 Oct).

- **Search is every word, anywhere** (4 Oct, `NoteSearch`): each word
  typed has to be in the title or the text, in any order, ignoring case and
  accents and word boundaries. Results replace the sections while the field
  holds words, as one flat list: title matches first, then the reader's
  sort, since a search is for one note and sections of one row each read
  slower. Each row shows the line of its first match. Ink isn't searched.
- **A note opened from a result shows where it matched.** `ContentView`
  takes the search as the selection changes, not live, so typing in the
  field doesn't redraw the note under the list; `PageView.reveal` waits for
  the first layout, lays out down to the first match (as scrolling there
  would), scrolls it a quarter of the way down, and highlights every match
  through the text view's own find decorations (`decorate(foundTextRange:)`),
  which sit on the text at any zoom. The highlights go at the first edit.
- **Find within a note is UIKit's** (`isFindInteractionEnabled`): ⌘F, or
  Find in Note in the header's ••• menu, which switches to text mode first, since
  the text takes no selection while ink has the page.

Pinning, sorting, note info and search needed no model change: the pins
(`Page.isPinned`, `Folder.isPinned`) came in with folders.

## The model and its versions

The store's model is versioned (`NoteSchema.swift`, since 3 Oct). Everything
else says `Page` and `Folder`, which are typealiases for the current version.

- **Never edit a version that has shipped.** A model change is a new
  `VersionedSchema` with its own copies of the classes, the old one stays
  frozen, and a stage joins `NoteMigrationPlan`. SwiftData matches a store to
  its version by the shape of its entities, so a frozen copy that drifts —
  a renamed attribute, a dropped `.externalStorage` — stops old stores
  opening.
- **A failed migration looks like lost notes.** `Storage` falls back to an
  in-memory store with a warning; the file is untouched, but the app can't see
  it. `SchemaMigrationTests` writes a store with the previous version and
  opens it through `Storage`, never a container built some other way.
- **Shaped for CloudKit**, so iCloud sync later needs no migration of its own:
  every relationship optional, every attribute optional or with a default,
  nothing `.unique`.
- **Versions 1 to 4 are every shape a build wrote before versions** (15 Aug,
  11 Sep, 13 Sep, 23 Sep), recovered from the history of Page.swift; version
  5 adds folders, and version 6 the text lock (4 Oct). With only the 23 Sep
  shape, stores last opened by a build from before 23 Sep failed —
  `.externalStorage` changes the entity's shape without changing a column
  (measured 3 Oct on copies of the simulators' stores). `SchemaMigrationTests`
  writes a store in each shape, version 5 included.
- **Version 5 is frozen in NoteSchema.swift** (4 Oct), like 1 to 4, and the
  live classes in Page.swift and Folder.swift are version 6's. `Folder` didn't
  change, but a version lists its own classes, so it moved up with `Page`.
- **Version 7 (12 Oct, v3 phase 1)** is v3's only model change, and version 6
  is frozen beside 5. It adds `Page.deletedAt`, `paperStyle`, `markdownLayout`
  and `textSize`, and `Folder.colorName` and `symbolName`, all optional with
  `nil` meaning the old behaviour. Only `deletedAt`, `markdownLayout` and the
  folder pair are used so far; the rest wait for their phases.
  - **The one custom stage** (`NoteMigrationPlan.migrateToVersionSeven`): a
    lightweight stage can give a column only one value, and `markdownLayout`
    depends on the note: `rendered` where `drawingData` is empty, `nil` (visible
    markers, as drawn) where there is any ink at all. It runs inside the
    migration, once, and writes nothing else, so `modifiedAt` doesn't move
    (`SchemaMigrationTests` checks the dates). The cost is reading every note's
    ink once, since an external-storage column can't be tested in the store.
  - **Every new note is `rendered`**, set in `Page.init`, so the + button, the
    Welcome note, templates and imports can't forget.
- **Older builds don't know the newest version.** A build from before 3 Oct
  opens the store without versions and would likely migrate it back to its
  own shape, dropping folders and pins. A build with version 5 but not 6
  may drop text locks the same way, or fail to open the store and show no
  notes, with the file left as it was; neither is measured. Don't run an
  older branch on a device whose notes use what it doesn't know.

## Shipping

What an upload checks before a person sees the app (4 Oct).
`AppStoreReadinessTests` checks each of these in the built app.

- **The privacy manifest** (`PrivacyInfo.xcprivacy`) has to list a reason
  for every required-reason API the app calls, or the upload is rejected.
  Today that's only UserDefaults, through `@AppStorage`, for the app's own
  settings (`CA92.1`). Calling one from another category — file
  timestamps, system boot time, disk space, active keyboards — means adding
  its reason. `CACurrentMediaTime` isn't on Apple's list. Notes never leave
  the device, so nothing is collected or tracked; a server would change
  that.
- **Exempt encryption.** `ITSAppUsesNonExemptEncryption` is `NO` in
  Info.plist: the only network traffic is the system opening a compiler's
  page over HTTPS. Encryption of the app's own would change the answer.
- **No background modes or entitlements it doesn't use.** Xcode's template
  declared push as a background mode and had an unused entitlements file
  for iCloud and push; both went on 4 Oct, since a mode the app never uses
  is a question in review. iCloud sync brings them back, through Signing &
  Capabilities.
- **Signing is the paid team** (9 Oct). Automatic signing, team
  `N454V8HV9J`. That ID was the free Personal Team, whose device profiles
  last seven days, and it can't sign push or CloudKit; Marcus re-obtained
  the paid Developer Program membership, and the same ID is now a paid
  Individual team, so the project's team setting didn't need to change.
  Read from Xcode's team list (`defaults read com.apple.dt.Xcode
  IDEProvisioningTeamByIdentifier`: `isFreeProvisioningTeam = 0`, team name
  "Marcus Chang" with no "(Personal Team)"), a new "Apple Development:
  Marcus Chang" certificate issued 8 Oct to 8 Oct 2027, and the app's
  team provisioning profile, made 8 Oct and valid a year. When an on-device
  build misbehaves, check which team signed it before reading any Swift.
  - **Marcus's working tree carries an uncommitted `project.pbxproj` edit**,
    and has since 8 Oct: Xcode set `CODE_SIGN_IDENTITY = "Apple Development"`
    for every SDK, in place of ad-hoc `-` for macOS (`"CODE_SIGN_IDENTITY
    [sdk=macosx*]" = "-"`), and added an empty `PROVISIONING_PROFILE_SPECIFIER`,
    when the paid account came back. It is his local state: **leave it
    unstaged, never commit or revert it, and don't mention it in summaries or
    PRs** (he knows). Stage files by name, never `git add -A` or `-a`. If a
    change needs `project.pbxproj` itself, stop and ask first.
- **The app icon** (10 Oct, phase 7 of `docs/ui-design-v2-implementation.md`):
  the set had no images, which fails an upload; it has them now. They are
  **drawn by `scripts/make-icons.swift`** (Core Graphics, the Logo board's
  120-unit geometry), which rewrites the three icon sets and their
  `Contents.json` outright: `swift scripts/make-icons.swift` from the
  repository root. Edit the script, never the PNGs.
  - **`AppIcon`**: Default (opaque), Dark (brackets and pencil on a
    transparent ground: the system supplies the background) and Tinted
    (greyscale, with the pencil at the orange's luma so it stays darker than
    the brackets once tinted), plus the ten macOS slots. Each macOS size is
    drawn at its own pixel size, not scaled from the 1024.
  - **Opaque except Dark.** The App Store rejects a marketing icon with an
    alpha channel, so the Default, both alternates and the Tinted image are
    written with none (`sips -g hasAlpha`); `AppIconTests.alpha` checks it.
  - **Alternates** `AppIcon-Paper` and `AppIcon-Orange`, named in
    `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, **scoped to the iPhone
    and iPad SDKs** (`[sdk=iphone*]`): they have no macOS art, so unscoped
    the Mac build warned "No applicable app icon found" for both. macOS has
    no `setAlternateIconName` either. One image each, with no Dark or Tinted
    variant, so they look the same in every Home Screen style.
  - **Full-bleed squares**, as the design says. The macOS slots are the same
    art, unmasked: not seen on a Mac, so check the Dock before shipping there.
  - **The colours live twice**, in the script and in `AppIconChoice`
    (AppSettings.swift), which Settings draws its previews from, since an
    icon set can't be loaded as an image by name. `AppIconTests` samples the
    background, a bracket and the pencil in each PNG against the model, so a
    change to one side fails until the other follows.
  - **Settings › General › App Icon** (iOS only) reads
    `UIApplication.alternateIconName` as it appears and after each change,
    and stores nothing: iOS keeps the choice, so a copy in `UserDefaults`
    could only disagree with the Home Screen. iOS puts up its own "You have
    changed the icon" alert on a change; it can't be turned off without
    private API. The Mac has no row.
  - **Not done:** Icon Composer's glass look (out of scope; Marcus can rebuild
    from the script's geometry), and the icon on a real Home Screen with
    Increase Contrast or a tint colour (the system composes both).

## Build/test

Scheme `NoteCode`; targets `NoteCode`, `NoteCodeTests`, `NoteCodeUITests`.
One SwiftPM dependency: HighlightSwift 1.1.0.

    xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

Tests use Swift Testing (`@Suite` / `@Test`), not XCTest. Suites that touch
UIKit are wrapped in `#if canImport(UIKit)` and marked `@MainActor`.

Since 13 September, runs fail to launch on Xcode's cloned simulators ("Busy
… failed preflight checks"). Add `-parallel-testing-enabled NO`.

Run on a physical iPad with Apple Pencil for anything involving ink — latency
and palm rejection in the simulator are not representative.

## Debug launch options

Debug builds only (`DebugLaunch.swift`, all behind `#if DEBUG`). They put the
app in a known state in one command and report what's on screen, so a check
doesn't take twenty gestures, a pasteboard that syncs with the Mac, or a
rebuilt copy of the app with logging.

| Argument | Does |
|---|---|
| `-debug-note pages\|code\|empty` | Opens a built-in note, in an in-memory store — the simulator's notes are untouched |
| `-debug-note-file <path>` | Opens a note read from a file on the Mac |
| `-debug-orientation portrait\|landscape` | The seeded note's pages |
| `-debug-mode seamless\|compressed\|print` | Sets the view mode, in the saved setting the menu uses |
| `-debug-page <n>` | Scrolls to page n's top edge, counted from 1 |
| `-debug-then-mode <mode>` | Switches mode once the page has settled |
| `-debug-then-delay <seconds>` | Wait before that switch; default 1 |
| `-debug-report` | Writes `tmp/notecode-debug-state.json` in the app container each time layout settles |
| `-debug-first-launch` | A fresh install: an empty in-memory store and the first-launch flags cleared, so the title screen and the Welcome note appear |
| `-debug-home` | Home over a few weeks of sample notes and three folders, in memory, with the title screen already seen and a note to continue at page 3 |

The report lists mode, orientation, page count, scroll offset, scale, zoom, the
top line (character, page, whether it starts the page, its text) and
`visibleLinesAcrossBreaks`. It is built from where TextKit actually has the
lines, not from page geometry, and the last two fields are the ones that would
have shown the 13 September view-switch bug. Bad or misspelt arguments land in
its `problems` rather than being ignored.

The arguments are deliberately not the settings keys: `-pageViewMode print`
would work with no code, but a launch argument outranks saved settings, and the
view menu would then seem broken for the whole session.

    scripts/debug-launch.sh --device "iPad Air 13-inch (M4)" -- \
      -debug-note pages -debug-orientation landscape -debug-mode print \
      -debug-page 4 -debug-then-mode seamless -debug-report

The script relaunches the installed Debug build with those arguments, waits
(`--wait`, default 4s) and prints the report. For manual runs from Xcode, put
the same arguments in the scheme's Run → Arguments.

## Implementation requirements

- TextKit 2 fence-to-code-region conversion — changes here need manual testing
  against fast typing, pasting, and mid-fence edits.
- Overlay touch handoff between the PaperKit canvas and the text view — exactly one
  layer accepts touches at any moment.
- Reading `.layoutManager` anywhere on the text view silently downgrades it to
  TextKit 1 and leaves `textLayoutManager` nil, with no error to say why.
- A button inside a `UITextView` is not simply a button. When one of the text
  view's own recognisers claims the touch, UIKit cancels the one the button was
  tracking and it never fires, so `DocumentUITextView` refuses to let those
  recognisers begin on an action bar. Changes near this need a real tap test —
  `sendActions` in a unit test cannot see the conflict. Bars are inserted
  beneath the ink canvas (`CodeBlockOverlay.ceiling`), so in draw mode the
  canvas takes every touch over them, and they're placed from TextKit's
  viewport layout as well as the text view's, since typing a block causes
  no layout pass of the text view.
- Ink is saved by `DrawingSaveScheduler` from `PageView.onInkChanged`, which
  fires only for changes the reader made. Anything that shows or moves ink
  for the app's own reasons must not call it: a save bumps `modifiedAt`, and
  opening a note would reorder the list. See step 4 of
  docs/phase-drawing-layer.md.
- **Strokes are taken into the stored ink off the main thread** (10 Oct,
  `InkCapture`). PaperKit's delegate says only that the markup changed, so
  what changed is found by walking all of it, and at 5,000 strokes that was
  400ms on the main thread per stroke even walked properly. Now
  `PageView.captureInk` only takes a snapshot of the canvas (free: a
  `PaperMarkup` is a value) with the layout it was drawn in, and a detached
  task works out the rest; while one runs, only the newest snapshot waits,
  so a burst of strokes is taken in as one. So `onInkChanged` arrives a
  moment after the stroke, and anything that needs every stroke now calls
  `PageView.commitInk()` first, which takes the newest snapshot in on the
  main thread: reading `PageView.ink` (the PDF), showing ink (a mode
  switch, with the layout the strokes were drawn in, not the new one),
  leaving the note and the app leaving the screen (`NoteEditor.commitInk`,
  from `PageDetailView`), and SwiftUI removing the page. A result computed
  from state replaced since is dropped (`inkGeneration`).
  **A test that waits for it must `await`**, not turn the run loop: the
  task comes back to the main actor, which a synchronous test turning the
  run loop is still holding, so nothing ever arrived
  (`PageViewTests.waitFor`).
- Parse and index `(textView.text ?? "").nativeUTF8`, never `textView.text`
  itself. That String is backed by the text storage's NSString, and reading
  it a character at a time is a message send per character: the parser took
  3ms a keystroke on a 23KB note, in Release too.
- Never read `Page.drawingData` from a page whose deletion has been saved.
  SwiftData traps ("backing data was detached … without resolving attribute
  faults"), since external storage leaves the attribute unloaded, and
  `isDeleted` reads false again by then — check `modelContext` too. (A note
  in Recently Deleted isn't deleted yet and can be read; this is about
  `Page.delete`, which purging uses.)
- Deleting a note is `Page.moveToRecentlyDeleted`; only purging and Delete
  Now use `Page.delete(_:from:)`. Both save at once. Other changes are saved
  by autosave, or when the app leaves the screen with a note open, and a
  deletion from the note list had neither: killed within a few seconds — a
  crash, or Xcode starting the next build — the note came back.
- Walk a `MarkupOrderedSet` with `for … in`, never `map`, `reduce`, an
  index or anything else that reads it by position. Reading one element by
  index costs what `count` does, and both grow with the set (16ms each at
  5,000 strokes); `map` reads every element that way. `PageView.frames(of:)`
  did, after every stroke: 808ms per stroke at 500 strokes, 10.6s at 2,000
  (simulator, 10 Oct), and writing stuttered and caught up seconds later.
  Even done right, every operation on the set is linear: at 5,000 strokes a
  walk with `renderFrame` is 107ms, an append 20ms, `ids` 16ms.
- **Build a `MarkupOrderedSet` with one `append(contentsOf:)`** of a Swift
  array, never an `append`, `insert`, `updateOrAppend` or `set[id] =` per
  element: each costs what `count` does, so building a set grows with the
  square of its size. Opening a note did, in `PageView.convert`: 1.5s at
  2,000 strokes and 7s at 5,000, now 141ms and 384ms; switching to print
  layout 1.7s at 2,000, now 323ms; and the PDF 7.2s at 2,000, now 1.8s,
  most of it PaperKit drawing (simulator, 10 Oct; `PageViewTests.openingCost`
  and `NotePDFTests.printingCost` keep them). Setting by id was worst:
  68s for 5,000. Removing is the exception: use `removeElement(for:)` per
  element, which is few. A markup keeps what `removeAll(where:)` takes
  out, as it does an element left out of an assigned set.
- The action bars are positioned from TextKit 2's *viewport*, never from the
  whole document. Asking for a fragment further down forces layout all the way
  to it, which is the lazy layout the editor is built on.

## Open questions

Things that are decided in someone's head but not in the code. Move them up
into a section above once they are settled.

- Where text-anchored ink lands in the schedule. Wanted for its own sake, but
  it is a phase, not a step, and November is committed.
- What goes in before November. The candidate list in docs/ROADMAP.md is
  planned properly once the drawing layer is done, alongside a UI design.
- Side-by-side pages (a scrolling-direction setting): the text view scrolls
  itself and only vertically, so pages flowing sideways means something other
  than the text view owns scrolling — the same question "Who owns scrolling"
  settled the other way for zoom.
- An infinite canvas against Letter pages: ink is stored in page coordinates,
  so an unbounded canvas is probably a second kind of note rather than a mode.
- Group notes and comments need a server. Nothing else in the app does, and
  Sign in with Apple was chosen partly because it doesn't.
