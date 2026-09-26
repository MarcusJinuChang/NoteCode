# Phase: the drawing layer

Source of truth. Published rendering:
<https://claude.ai/code/artifact/975bdf66-66ac-4b5b-8590-b27faa2e3993>

6 Sep – 10 Oct 2026. Hard stop, because submission prep cannot slip.

## The architecture decision

**The canvas goes inside the text view, not beside it.** A `UITextView` is
already a `UIScrollView`, so a subview sits in content coordinates and scrolls
with the text automatically. That deletes the whole class of bugs the
sibling-scroll-view approach creates (one frame of lag, duelling rubber-band
curves) and makes "toggle without losing scroll position" true by construction.

A SwiftUI `ZStack` overlay lands in the same trap as sibling scroll views: it
does not move with the text view's content.

Catches:

- The canvas is PaperKit's `PaperMarkupViewController` (see the PaperKit
  amendment), and its view holds a scroll view of its own.
  `scrollConfiguration.isScrollEnabled = false` (iPadOS 27) demotes it to a
  plain drawing surface so its pan stops competing.
- It paints an opaque background over every word underneath unless its
  `contentView` is a clear view. On the simulator, a newly assigned markup
  went opaque again unless its `backgroundColor` was clear too.
- It's a view controller, so it wants a parent. `DocumentTextView` is a
  `UIViewRepresentable` and has none to offer.

### Amendment: zoom moves the scroll view — measured, and reversed (12 Sep)

This amendment put a non-scrolling text view inside an outer zoom scroll view.
Measured before building it, that doesn't survive TextKit 2: a text view that
doesn't scroll has the whole document as its viewport, however little of it is
on screen.

| 500-line note | Scrolling text view | Non-scrolling, in a container |
|---|---|---|
| Open | 137ms | 883ms |
| Keystroke | 11ms | 477ms |
| Memory | +8MB | +72MB |

At 2000 lines the container took 11.6s to open and 5.5s per keystroke.

What replaced it keeps the original decision above, literally: the text view
scrolls, the canvas is a subview of its content, and the display scale is a
**transform** on the text view. A transform leaves the viewport alone — the
same note measured 99ms to open and 9ms a keystroke. `PageView`, around it,
scrolls only sideways, for a page wider than its area.

A 700 × 30,000pt `PKCanvasView` holding 100 strokes cost 3MB. Revised 18 Sep:
that figure leaves out PencilKit's tiles. Each 512pt tile with ink keeps a 4MB
surface whether it's on screen or not. Measured on the simulator, one stroke
every 1000pt came to 144MB, and the simulator's memory footprint doesn't count
those surfaces. PaperKit draws strokes with the same tiled view, so this
carries over, and its canvas measured about 3MB more than PencilKit's at that
size. Whether the iPad counts the surfaces is a step 5 check. If it does, the
canvas has to become one per page rather than one per note.

**Amended 23 Sep: the canvas covers the screen, not the note.** PencilKit
draws a stroke into a buffer its canvas's size, and Metal refuses one past
16,384 pixels. The first stroke on a nine-page note, a canvas 9,237 points
tall at 2x, crashed the app on the simulator; on the iPad the Pencil would
have done the same, from a little under eight pages. `DrawingCanvas.cover`
now sizes the view to what's on screen, moves it with the scroll on every
text view layout pass, and tells PaperKit which part of the note is under it
through `contentVisibleFrame`. The markup still spans the note. PaperKit
centres that frame in its viewport as it stands, so after a resize the canvas
lays itself out before setting it, or the ink sits half the size change off.

Pinch zoom, built the same evening, is a user factor on that transform, with
`PageView`'s sideways scroll taking the overflow past the page area — no new
scroll view. The cost is diagonal panning: zoomed in, a pan goes one way or the
other, because `UITextView` forces its content width back to its own width and
so can't scroll sideways itself.

## Who owns the touch

One layer owns *editing*; neither owns scrolling.

**Amended 19 Sep: in ink mode a finger draws.** The plan was that a finger
scrolls and only the Pencil draws, so that reading a lecture's notes never
meant toggling modes. The toggle itself is what changed that: ink mode is
already a deliberate switch, so a finger there means to draw, and asking for
the Pencil before anything can be marked is a worse trade than scrolling by
leaving ink mode. The hotbar carries a Pencil-only lock for when the Pencil is
in hand and a palm is on the page; locked, a finger scrolls and selects again.

| Knob | Text mode | Ink mode | Why it's in the enum |
|---|---|---|---|
| `canvas.view.isUserInteractionEnabled` | `false` | `true` | The hit-testing switch. Not `isHidden` — both layers stay visible. |
| `canvas.allowsFingerDrawing` | — | the lock's state | Not a mode setting: `DrawingCanvas` holds it, and the hotbar's lock moves it. It sets PencilKit's own `drawingPolicy` to `.anyInput` or `.pencilOnly` on the canvas inside PaperKit — `directTouchMode` alone never reached it (23 Sep) — and `directTouchAutomaticallyDraws` off either way. Left automatic, a finger draws only while a tool picker is up and the system's "Draw with Finger" setting allows — the hotbar replaced the picker, so a finger would never draw. |
| `textView.isEditable` | `true` | `false` | Stops a stray tap re-summoning the keyboard mid-stroke. |
| `textView.isSelectable` | `true` | `false` | A resting finger or a long press would otherwise start a text selection under the pen. |
| first responder | textView, if it was | nobody | Resigning puts the keyboard away. With no tool picker, the canvas has no reason to claim it. |
| saved keyboard state | restored | captured | The keyboard comes back only if it was up. Reading isn't typing. |

Five settings that move together, in one `EditorMode` enum with one `apply` —
the same argument `TextRewritingPolicy` makes for its five keyboard traits. The
canvas brought one knob rather than the two expected: who may draw turned out
to belong to the canvas, not the mode. Test: a round trip through `.ink` and back
leaves all of them as they started.

A saved `selectedRange` used to be in this table, on the expectation that the
caret would snap to offset 0 on every return from drawing. Measured on 12 Sep
with the text view in a window and mid-edit, it doesn't: UIKit keeps the
selection through everything above. Nothing saves it, and
`EditorModeTests.roundTrip` holds UIKit to that. If the canvas changes it, that
test fails and the restore goes back in.

### Amendment: one hotbar instead of the tool picker (12 Sep)

The note-page mockup puts every tool in one bar that docks to the page's left,
bottom or right edge. Undo, redo and the text/draw toggle sit in a section that
never moves. After it come heading, bold, italic, strikethrough, inline code,
bullets and code block in text mode, or pen, highlighter, eraser, lasso and five
colours in ink mode.

That is the old cut-list item 1, adopted as the plan. With no `PKToolPicker`,
the canvas never has to become first responder, so the keyboard and the picker
have nothing to argue about. Two things follow:

- Tools reach the canvas as `InkToolState.pencilKitTool`, set directly on
  PaperKit's `drawingTool` rather than through the picker's observer.
  `drawingTool` takes PencilKit tools, so `InkTool.swift` carries over. Whether
  the eraser and lasso work through it is unverified.
- Undo is routed by `NoteEditor`, not found by the responder chain, so "one
  stack or two" becomes a choice to make rather than something UIKit decides.

The bar reserves room on both sides of the page, whichever edge it is docked
to, so moving it never changes the page's scale or position. The bottom is
reserved only while the bar is there, since height doesn't affect the scale.

### Amendment: pages (12 Sep, evening)

Notes became Letter-sized pages, Notability-style: portrait or landscape per
note, and a view menu in the header for seamless (default), compressed — a
dashed line at each break — and print layout, a sheet of paper per page. Printing
itself is for later, but print layout is laid out to be the printed page.

**One pagination.** The modes differ only in how tall the band between two
pages' bodies is; each page's body is the same height in all three. Text flows
around the bands as exclusion paths, so a line lands on the same page, at the
same place on it, in every mode — `PageViewTests.paginationIdenticalAcrossModes`
holds that, and fails with the bands removed. Seamless keeps a 1pt band, which
is what pushes a straddling line; it shows as up to a line's extra space.

**Ink in print coordinates.** Stored where it prints, shown converted to the
current mode, and never converted back from the screen. Converting into print
layout is exact; converting out isn't, since a margin stroke reaches onto the
next page where breaks are narrower. Strokes drawn on the canvas, once the
toggle makes that possible, need converting into print coordinates as they're
added, one at a time.

Revised 18 Sep: so do strokes the eraser splits and the lasso moves. That
means matching each stroke on screen to the stored stroke it came from.
PaperKit gives every element an ID on iPadOS 27, so that's a lookup. The same
goes for shapes and images once they exist.

**Measured before building:**

| Keystroke near a note's top | No bands | Bands |
|---|---|---|
| 100 lines | 2.8ms | 13.7ms |
| 250 lines | 5.5ms | 33.8ms |
| 500 lines | 9.7ms | 66ms |

The count of bands barely matters (5 and 60 cost the same); their existence
does, because TextKit 2 then lays out everything below an edit. Worth checking
on the iPad in step 5. If long notes lag there, the alternative is pushing whole
paragraphs with paragraph spacing, computed lazily.

Found on the simulator: after a mode switch, TextKit set the text's height
after the layout pass that sized the note from it — a five-page note sat 500pt
short, and a reader at its end was pushed down. Asking for extra layout passes
didn't fix it. Rounding to whole pages inside the text view's `contentSize`
setter does, since that's where TextKit's height arrives; `PageSettlingTests`
fails on the observer-based version. Scrolling a 500-line note
end to end in print layout, by contrast, never changed its page count: the
bands keep the estimate honest once layout has run.

Two more from the simulator, each with a test that fails without its fix:

- A code line pushed onto a new page keeps a fragment frame that begins above
  the break. The code panel, drawn over that frame, filled the gap between two
  sheets. Panels and their buttons now take their position from the lines
  (`CodeBlockPageBreakTests`).
- Switching from print layout, scrolled to a sheet's top, opened the note three
  lines into the page. The page count was worked out from the old mode's text
  height, so it swung 11 → 9 → 10 → 9 as the text reflowed; each change
  reassigned the bands, relaying out the note, and TextKit shifted the scroll
  offset to compensate. The old text bottom is now converted into the new mode
  before the count is taken, so the bands are set once. An orientation change,
  where nothing converts, keeps the line at the top instead. Two other suspects
  were measured and ruled out: layout done while scrolling and a full layout
  paginate identically (366 of 366 lines), and laying out the whole note on
  every switch would cost 500ms at 2,000 lines.

**Fixed (13 Sep): the page-count fix corrected the scroll offset, not what the
reader saw.** Deep in a note the offset landed on the right page edge while
TextKit showed the previous page's lines there — ten lines off at sheet 4 of a
landscape note on the simulator. `ccaf69c` had reported it fixed on a test that
compared the offset to page geometry.

Cause: TextKit 2 keeps its viewport anchor when the bands change under it. A
probe comparing every visible line to a note laid out from scratch found all 40
exactly 167pt low — print layout's 168pt break less seamless's 1pt, one stale
break's worth. The page breaks on the text container were correct throughout;
`invalidateLayout(for: documentRange)`, a full `ensureLayout` (68ms on that
note) and relaying out the viewport changed nothing. Scrolling to the top and
back put every line right.

Fix: `PageView` scrolls to the note's top after applying the bands, then
restores the reader's place, all before the next frame. Verified in the app
with logging: after the same sheet-4 switch, "Line 64" — page 4's first line —
is at the top and stays there. `PageSettlingTests.roundTripDeepShowsPagesFirstLine`
failed before the fix and passes after; the full suite passes (349 tests).

Changing a note's orientation re-wraps it, so its ink keeps its printed
position but not its words. Harmless today, with no saved ink; the persistence
step should ask before re-wrapping a note that has some.

### Amendment: PaperKit instead of PencilKit (19 Sep)

The canvas is PaperKit's `PaperMarkupViewController` rather than a
`PKCanvasView`, and ink is stored as a `PaperMarkup`. PaperKit is PencilKit's
canvas with an element layer on top: shapes, lines with arrowheads, images and
text boxes, each selectable, movable and resizable. Lists, trees and graphs are
what a CS student draws. Building that layer on PencilKit would mean writing our
own hit-testing, handles, save format and undo.

It became possible when the target moved to iPadOS 27 on 19 Sep. Below 27 a
`PaperMarkup` is opaque: it can move everything at once, but not one stroke,
and ink in print coordinates moves each stroke by its own page's offset. 27
adds `subelements`, with an ID and `applyTransform` for every element.

Measured on the iOS 27 simulator, 1,000 strokes:

| | PencilKit | PaperKit |
|---|---|---|
| Mode switch: move every stroke to its page | 1.6ms | 56ms |
| Assign the result to the canvas | 0.8ms | 24ms |
| After a stroke: find the new one, move it | ~1.5ms | ~10ms |
| Save | 1.4ms, 738KB | 73ms async, 1.1MB |

PaperKit is about 30 times slower, which is still fine. The big numbers come
once per mode switch or save, and `PaperMarkup` is `Sendable`, so both can run
off the main actor. At 3,000 strokes the mode switch took 145ms. Build the
moved set in one pass and assign it once. Calling `updateOrAppend` element by
element is quadratic: 3.3s at 1,000.

Found on the way:

- Building a `PKDrawing` from strokes read out of a `PaperMarkup` crashed
  PencilKit, with an exception inside `PKDrawing(strokes:)`. Treat the move as
  one-way.
- There's no end-of-stroke callback. Saving hangs off
  `paperMarkupViewControllerDidChangeMarkup`.
- The controller is `public`, not `open`, so it can't be subclassed. Anything
  that needs overriding, like undo, goes on a view around it.
- Resizing its view shifted the content until the markup was assigned again
  (simulator). `PageView` resizes the canvas whenever the page count changes.
- A finger drag over it scrolled the text view in every configuration tried,
  including `directTouchMode = .drawing`. The missing piece was thought to be
  `directTouchAutomaticallyDraws`: left on, PaperKit decides for itself and a
  finger never draws without a tool picker. **Corrected 23 Sep:** off, with
  `.drawing`, a finger still didn't draw in the app. PencilKit's canvas inside
  PaperKit kept its drawing policy at `.default`, its drawing recognisers took
  only the Pencil, and a finger hit the selection view above them, however and
  whenever `directTouchMode` was set. Setting that canvas's own
  `drawingPolicy` (found by class name, setter checked first) is what makes a
  finger draw. It isn't public API, so it can break with an OS update; if it
  does, the Pencil still draws.

**Scope for 10 Oct:** the canvas with today's hotbar tools. Inserting shapes,
images and text comes after, as its own piece of work.

## Build order

### 1. Spike (Sep 6–7)
Throwaway view on a scratch branch: canvas, tool picker, save button. Draw,
kill the app, reopen, see the strokes. Nothing touches the real editor.

What you're learning: `PKDrawing.dataRepresentation()` / `PKDrawing(data:)` are
the whole persistence story, and the tool picker will not appear until the
canvas is `becomeFirstResponder()`.

**Gate:** strokes survive a force-quit.

### 2. Geometry (Sep 8–14)
Built 12 Sep at one 700pt width, then made page-based the same evening (see
the pages amendment). Lines wrap at the note's pages' text width, pinned on the
text container rather than inferred from the view. The display scale fits the
page's width to the area, up to 1.25x, times the reader's zoom. The hotbar
reserves both sides always, so the scale depends on the window alone. The
canvas is a subview of the text view's content.

Ink drawn *below* the last line has nothing to scroll to, because content
height comes from the text. The note now ends on a whole page, and ink below
the text adds pages: `textContainerInset.bottom` pads to the last page's end.
It's computed from the text's height excluding that inset, so it's idempotent —
deriving it from current content height sets up a layout feedback loop.

Found on the way: a text view first sized while scaled below 1x takes its line
width from the shrunken frame, so its container width is pinned rather than
tracked.

Checked 18 Sep on the simulator: PencilKit does not render sharply under the
transform. At 1.25x the canvas's tiles stay at 2x and the ink is visibly soft.
Giving the canvas a matching `zoomScale` or counter-scaling it didn't fix it.

**Fixed 25 Sep, on PaperKit,** after the iPad showed ink softer than Notes'.
Zooming PaperKit to the page's scale *and* shrinking the canvas by the same
factor (`DrawingCanvas.renderScale`) has it draw its tiles at the density
they're shown at: 2.48 where they were 2.0, and one partly covered pixel row
at a stroke's edge where there were two. It needed a third change, which a
test caught: PaperKit sizes its content as the markup's bounds divided by the
zoom, so the canvas's copy of the markup has the note's size times the zoom,
or every element lands 81.6 points right of its words at 1.25x.

**Files:** `PageLayout.swift`, `CanvasGeometry.swift`, `PageView.swift`, `PageViewMenu.swift`, `DocumentTextView.swift`
**Tests:** `PageLayoutTests`, `CanvasGeometryTests` (fit, zoom, focus, reserve)
and `PageViewTests` — lines never sit in a break; pagination identical in every
mode; ink shown on its page in every mode, and margin ink surviving a trip
through seamless; zoom keeps the pinch point still; reading place kept across a
mode switch; ink adds pages; deleting text never clips ink; portrait and
landscape iPads give identical line breaks; laying out again changes nothing.
**Gate:** reach a stroke at y = 3000; rotate and confirm identical line breaks.

### 3. The toggle (Sep 15–21) — flagged risk
`EditorMode`, the hotbar's text/draw toggle, and the first-responder handoff.
The keyboard-versus-picker argument left with the picker; what remains is the
keyboard leaving and coming back cleanly.

Built early, on 12 Sep, because it doesn't depend on geometry: the text side
of `EditorMode`, `NoteEditor`, the hotbar, and the page header. The canvas
followed on 19 Sep: `DrawingCanvas`, the mode's input knob, tools and the
Pencil-only lock from the hotbar, ink undo of its own, and strokes captured
into `ink` as they're drawn.

What it turned out to involve:

- **Undo is shared, and had to be unshared.** The canvas's `undoManager` is
  the text view's, whether or not the text view is first responder, so ink
  landed on the text stack. PaperKit's controller is `public`, not `open`, so
  `DrawingCanvas` is the view between it and the text view, and vends its own.
  `NoteEditor` picks the stack the mode is using. `showInk()` re-places the
  markup on every mode switch, which left that stack pointing at strokes in
  the old mode's positions, so it clears the stack there (20 Sep).
- **Scroll position is safe, content insets are not.** Dismissing the keyboard
  changes `adjustedContentInset`, which can shift visible content anyway.
- **A finger reaches the canvas, and now draws there.** Locked to the Pencil,
  a finger drag scrolls the text view instead, and the canvas's tap and
  long-press recognizers can select an element. The text view still sees
  finger taps through the canvas either way. With a finger drawing, two
  fingers scroll — see step 5.
- **Code-block bars straddled the canvas — fixed 25 Sep.** Bars for blocks
  that existed when a note opened were added before `PageView` added the
  canvas, so they sat under it; bars for blocks added later sat above it and
  caught the Pencil. Bars are now inserted beneath the canvas
  (`CodeBlockOverlay.ceiling`): in draw mode a stroke that starts on a run
  button draws, and in text mode the buttons work. Checked with real taps on
  the simulator. The same check found a block typed into a note got its bar
  only once something else laid the text view out; bars are now placed from
  TextKit's viewport layout too.
- **The wiring moves.** `EditorMode.apply(to:saved:)` takes only the text view,
  and `editor.attach` runs before `PageView` creates the canvas
  (`DocumentTextView.swift:44-45`). The canvas also needs a parent view
  controller. Either `DocumentTextView` becomes a
  `UIViewControllerRepresentable`, or the controller's view is hosted without
  one. The simulator spike ran both ways.
- **`PageView`'s ink changed type.** `ink`, `setInk`, `showInk()` and
  `convert` moved from `PKDrawing` to `PaperMarkup`, and so did the
  `PageViewTests` that build strokes.
- **A markup is a document that merges, not a value that replaces**, and three
  measurements on 19 Sep shaped how ink is captured:
  - Assigning `markup` calls the delegate **twice, synchronously**. Showing
    stored ink looked exactly like someone drawing it, and the page converted
    what it had just shown straight back into storage. `DrawingCanvas` marks
    its own assignments and ignores those calls.
  - Leaving an element out of an assigned set **keeps** it. Erasing calls
    `removeElement(for:)`.
  - A merge only takes if it comes from the canvas's **own** document. A copy
    made from `ink` branched before the canvas's edits, so assigning it changed
    nothing and ink stayed where it was drawn through every mode. `showInk()`
    moves the canvas's own elements by the distance the stored copy says.
  - Elements assigned as a set from an unrelated markup are dropped, though
    `updateOrAppend` takes them one by one.

**Files:** `EditorMode.swift`, `NoteEditor.swift`, `Hotbar.swift`, `+DrawingCanvas.swift`, `PageView.swift`, `DocumentTextView.swift`, `PageDetailView.swift`
**Gate:** toggle mid-document — scroll offset unchanged, caret where you left it.
**Status (25 Sep):** built; the code-block bars are fixed on branch
`rendering-sharpness`. Its checks on the iPad are step 5's.

### 4. Persistence (Sep 22–28)
`Page.drawingData` holds `PaperMarkup.dataRepresentation()` bytes of
`PageView.ink`, in print coordinates, and is empty for a note never drawn on.
It has `@Attribute(.externalStorage)`, so a note's ink isn't loaded with its
title every time the list is fetched.

Save from `paperMarkupViewControllerDidChangeMarkup`, since PaperKit has no
end-of-stroke callback. It also fires — twice, synchronously — when the app
assigns the markup itself, so `DrawingCanvas` marks those and the page ignores
them. Encoding is async, 73ms for 1,000 strokes on the simulator, so it runs
off the main actor. A save started as the app leaves the screen needs a
background task to finish in.

Drawing changes must bump `page.modifiedAt`, or a page you only drew on sinks
to the bottom of the list.

Decode failure must not overwrite. Follow `Storage.swift`'s posture: corrupt
bytes give an empty canvas and a visible warning, and the stored data is left
alone. Silently replacing unreadable ink turns a transient bug into a destroyed
semester of notes.

- **Empty data.** `PaperMarkup(dataRepresentation:)` throws on empty data too,
  with the same error as corrupt bytes, so empty `drawingData` means "no ink"
  and is checked before decoding.
- **Any error counts.** Failures arrive as `CRCodingError` from PaperKit's
  storage layer, not the `MarkupError` its API declares, so the codec catches
  every error.
- **Too new is a warning too.** A markup saved by a newer PaperKit, with
  `incompatibleFormatTooNew`, gets the warning like corrupt bytes, never an
  overwrite.

**Built 23 Sep.** `DrawingCodec` reads and writes the bytes;
`DrawingSaveScheduler`, one per open note, decides when.

- **Only a change the reader made is saved.** `PageView.captureInk` hands the
  ink over once it has found one. Showing ink — on opening, or moved for a
  mode switch — hands nothing over, so looking at a note never moves it up the
  list.
- **Half a second after drawing pauses**, one save at a time, each taking the
  newest ink. Run side by side, a slow encode finished after a newer, faster
  one and wrote older ink over it (`newestInkWins`, with saves concurrent).
- **Off the main actor, on purpose.** With approachable concurrency on, a plain
  `nonisolated async` function runs on its caller's actor, so
  `DrawingCodec.encode` is `@concurrent`.
- **At once when the note closes, and when the scene stops being active** —
  not only on reaching the background, because swiping the app away in the
  switcher never gets there. That save runs under a background task and then
  saves the model context, since autosave may not come round again before the
  app is suspended or killed.
- **Reading is on the main actor**, as the page is made: 1,000 ten-point
  strokes come to 665KB and read back in 29ms (simulator).
- **Unreadable ink** shows a warning under the header, and saving stays off
  for that note.
- **A note deleted while its ink encodes** isn't written to.
- **Erasing everything** stores no bytes, so the note reads as never drawn on.

**Files:** `DrawingCodec.swift`, `DrawingSaveScheduler.swift`, `Page.swift`,
`PageView.swift`, `DocumentTextView.swift`, `PageDetailView.swift`
**Tests:** `DrawingCodecTests`, `DrawingSaveSchedulerTests`, and in
`PageViewTests` — drawing hands ink over in print coordinates; showing it
hands nothing over; saved ink reopens on the same words in both orientations
and all three modes.
**Gate:** draw, background, force-quit, reopen — ink intact on the right page.
**Gate passed 23 Sep, on the simulator.** On a store written by the previous
build — which also showed `.externalStorage` migrates without a mapping — a
stroke was drawn, the app sent home with the Home button, terminated,
relaunched and the note reopened. The stroke came back on the same pixels (none
differed across the page), and `modifiedAt` kept the drawing's time, not the
reopening's. Not checked yet: the app killed inside the half-second pause
without leaving the screen first, which is what a crash does; and the flush as
a note closes, which only the unit tests reach. Step 5 repeats the gate on the
iPad.

### 5. Device pass (Sep 29 – Oct 10)
Ink latency, palm rejection, and Pencil-versus-finger routing are all
unrepresentative in the simulator. Real iPad time plus the fixes it turns up,
plus buffer.

Measured 19 Sep on the iOS 27 simulator: 1,000 strokes encode in 73ms, off the
main actor. The debounce is there to coalesce saves, not to hide their cost.
Confirm on the iPad. Also on the iPad:

- tile memory on a long inked note (see the geometry amendment);
- ink sharpness under the page scale — fixed on the simulator 25 Sep, see
  the geometry step; confirm against Notes on the iPad;
- typing on a long note — a keystroke near the top of an eight-page note
  still cost 16ms (Release) to 20ms (Debug) on a busy Mac's simulator after
  25 Sep's fixes, against a 120Hz frame of 8.3ms; about half is the one
  layout below the caret that exclusion paths cost. Judge it on the iPad in
  a Release build — Xcode's Run button installs Debug;
- that the eraser and lasso work through `drawingTool`.

**Started 25 Sep, on the simulator,** with the checks it can answer: its
touches are a finger's, and a finger draws. Found and fixed (branch
`device-pass`):

- **A lasso selection couldn't be dragged.** The text view's pan took one
  finger or the Pencil in ink mode and won the drag from PaperKit, so the
  page tried to scroll instead. In ink mode the Pencil no longer scrolls,
  and while a finger draws, scrolling takes two fingers
  (`EditorMode.scrolling(fingerDraws:)`).
- **Nothing scrolled a note while a finger drew.** Two fingers didn't reach
  the text view: PaperKit's own scroll view, scrolling off, kept a
  two-finger pan and took the drag. It was off when a note opened and came
  on for good the first time a selection was dragged, so switching it off
  didn't last; `DrawingCanvas` now allows it no touches. Found by reading
  the recognisers' state from the running app with lldb.

Answered on the simulator:

- **The eraser and lasso work through `drawingTool`**, so the cut list's
  PencilKit fallback isn't needed for them. The pixel eraser splits a
  stroke; the lasso selects, and brings up PaperKit's own menu (colour,
  duplicate, delete, more).
- Check 9: pen, highlighter, eraser and lasso each do their job. The
  highlighter takes the selected colour, and the default black hides the
  words under it; the palette has no yellow. A question for the UI design.
- Check 10: locked to the Pencil, one finger scrolls and leaves no mark.
- Check 11: with a finger drawing, two fingers scroll and draw nothing.
  Pinch zoom still works in ink mode.

Left for the iPad, since the simulator can't produce them: anything with
the Pencil — that it never scrolls, draws or drags a selection, and that a
palm resting on the page leaves no mark (checks 3 and 10); two fingers
landing a moment apart, as real fingers do, rather than together (check 11);
ink latency; and the rest of the list above.

## Known limitation: drift

Ink is anchored to the page, not the paragraph. Insert a paragraph above an
annotation and the text moves while the stroke does not. A fixed column width
protects against rotation and Split View; nothing protects against insertion
above, or a Dynamic Type change.

See `GeometrySpike` on branch `spike/page-geometry` for a live demonstration.

**The fix, wanted for its own sake:** anchor each stroke to an `NSTextLocation`
plus an offset from that paragraph's fragment origin; on relayout, ask the
layout manager where each anchor is now and translate its stroke group.
Every PaperKit element has an ID that survives saving, and an
`applyTransform`, so anchors key on element IDs. A relayout moves the anchored
groups in one batched pass. Needs a
`drawingAnchors: Data` property on `Page` — additive with a default, so cheap
to add now while the store is nearly empty.

## Verification

Unit-testable: `CanvasGeometryTests`, `DrawingCodecTests`, `EditorModeTests`,
`DrawingSaveSchedulerTests`.

Hardware only:

1. Type a page with a code block, switch to ink, annotate it, switch back —
   scroll offset unchanged, caret restored, syntax colours intact.
2. Draw, force-quit, reopen — ink there, right page.
3. Rest a palm and draw, then scroll with one finger — no stray marks.
4. Draw below the last page, scroll to it — a page was added.
4a. Annotate a page, switch through seamless, compressed and print layout — ink
    stays on its words in all three.
5. Rotate, then Split View — scale changes; ink stays beside the same words.
6. Pinch zoom in and out — text re-renders crisp, ink tracks it.
7. Type a paragraph at the top of an annotated page — confirms known drift.
8. Type for thirty seconds on a heavily inked page — no dropped keystrokes.
9. Pen, highlighter, eraser and lasso from the hotbar — each does its job on
   the canvas.
10. Draw with a finger, then lock to the Pencil — a finger scrolls again, and
    a resting palm leaves no mark.
11. With a finger drawing, scroll a long note: does a two-finger pan reach the
    text view?

## Cut list, in order

1. **Drop pages added for ink.** Ink confined to the pages the text makes.
2. **PencilKit's canvas instead of PaperKit's.** If the eraser or lasso don't
   work through `drawingTool`, or ink undo can't be separated, fall back to
   `PKCanvasView`, which `PageView` has today. Shapes and images then wait.

Dropping `PKToolPicker` used to be first on this list, and dropping the
Pencil/finger split was second. Both became the plan instead: the hotbar
replaced the picker, and a finger draws by default with a lock for the Pencil —
see the amendments under "Who owns the touch".

Not cut under any circumstance: persistence. A drawing layer that loses ink is
worse than no drawing layer.
