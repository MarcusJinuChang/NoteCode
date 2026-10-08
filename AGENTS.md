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
  sideways, so its hit test hands those touches to the text view; between
  sheets, `DrawingCanvas.takesTouch` turns them away. How many fingers a
  scroll needs is set as each first finger lands (`PageView.touchWillLand`),
  so `NoteEditor` hands the mode's rule to the page, not to the pans.

## Pages

Notes are Letter-sized pages, Notability-style. The geometry is all in
`PageLayout`, as pure functions.

- **Paper.** US Letter at 96 units to the inch: 816 by 1056 portrait, 1056 by
  816 landscape, with 0.75in margins. At that size 17pt body text prints at
  12.75pt. Orientation belongs to the note (`Page.pageOrientation`), set once
  when it's made; the view mode is a per-device preference (`@AppStorage`),
  chosen from the header's view menu.
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
- **Print layout** fits its sheets inside a 24pt border of the surround
  (`CanvasGeometry.printGutter`), so they read as paper rather than one slab
  with grey bars across it. Text is a little smaller there than in the
  continuous modes, which fit edge to edge.
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
  already has from an assigned set — so building one means
  `updateOrAppend` an element at a time, as `PageView.captureInk` does.

## The note page

Laid out from the 12 September mockup.

- **Header.** ☰ opens the note list, which slides over the page
  (`.prominentDetail`) instead of narrowing it, so opening the list never
  re-wraps the note. The title sits below; the run destination, share,
  note info and account icons sit on the right. Account is a placeholder until Sign
  in with Apple.
- **Hotbar.** One bar, dragged by its grip to the left, bottom or right edge,
  snapping to whichever is nearest (`HotbarDock.nearest`). Undo, redo and the
  text/draw toggle never move; after the divider come the current mode's tools.
  Only the tools scroll when the bar is too short for them; the arrows and the
  toggle sit outside the scroll view.
  The page keeps both side edges clear, whichever one the bar is on, so moving
  it never resizes or shifts the page.
  It replaces `PKToolPicker` — see docs/phase-drawing-layer.md.
- **Ink tools** (`InkToolbar.swift`), shared by the hotbar and the palette
  the Pencil's squeeze brings up, so the two can't disagree. After the tools
  come the current tool's options: colours for the pen and highlighter, or
  the eraser's mode (pixel or whole stroke) and size (three, or custom from a
  slider). The palette (`InkPalette`) and the eraser (`EraserSettings`) are
  stored per device, like the dock. "+" opens Apple's
  `UIColorPickerViewController` from UIKit (`InkColorPicker`), not from a
  SwiftUI popover, where it's a child controller and its eyedropper and
  close button expect to be the presented one. Hold a colour to remove it;
  hold and drag to move it. A colour picked on a dark page is stored as the
  light ink that shows as it (`InkColor(chosen:on:)`).
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
- **Text lock** (4 Oct). The lock beside note info in the header, or Lock
  Text in the list's note menu, sets `Page.isTextLocked`: the text and title
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
  `Folder.delete` saves at once, like `Page.delete`.
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
  the header's magnifying glass, which switches to text mode first, since
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
- **Still missing:** the app icon (the icon set has no images, which also
  fails an upload) and the paid Developer Program.

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
- Parse and index `(textView.text ?? "").nativeUTF8`, never `textView.text`
  itself. That String is backed by the text storage's NSString, and reading
  it a character at a time is a message send per character: the parser took
  3ms a keystroke on a 23KB note, in Release too.
- Never read `Page.drawingData` from a page whose deletion has been saved.
  SwiftData traps ("backing data was detached … without resolving attribute
  faults"), since external storage leaves the attribute unloaded, and
  `isDeleted` reads false again by then — check `modelContext` too.
- Delete notes with `Page.delete(_:from:)`, which saves at once. Other
  changes are saved by autosave, or when the app leaves the screen with a
  note open, and a deletion from the note list had neither: killed within
  a few seconds — a crash, or Xcode starting the next build — the note came
  back.
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
