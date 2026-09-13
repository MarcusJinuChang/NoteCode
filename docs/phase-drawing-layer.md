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

- `PKCanvasView` is *also* a `UIScrollView`. `isScrollEnabled = false` demotes
  it to a plain drawing surface so its pan gesture stops competing.
- `canvas.backgroundColor = .clear` and `canvas.isOpaque = false`, or the
  canvas paints opaque white over every word underneath.

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

A 700 × 30,000pt `PKCanvasView` holding 100 strokes cost 3MB, so a canvas as
tall as the note is not a concern.

Pinch zoom, built the same evening, is a user factor on that transform, with
`PageView`'s sideways scroll taking the overflow past the page area — no new
scroll view. The cost is diagonal panning: zoomed in, a pan goes one way or the
other, because `UITextView` forces its content width back to its own width and
so can't scroll sideways itself.

## Who owns the touch

One layer owns *editing*; neither owns scrolling. In ink mode a finger must
still scroll, or you toggle modes every few lines during a lecture.

| Knob | Text mode | Ink mode | Why it's in the enum |
|---|---|---|---|
| `canvas.isUserInteractionEnabled` | `false` | `true` | The hit-testing switch. Not `isHidden` — both layers stay visible. |
| `canvas.drawingPolicy` | — | `.pencilOnly` | `.default` changes behaviour depending on whether a Pencil ever paired. |
| `textView.isEditable` | `true` | `false` | Stops a stray tap re-summoning the keyboard mid-stroke. |
| `textView.isSelectable` | `true` | `false` | A resting finger or a long press would otherwise start a text selection under the pen. |
| first responder | textView, if it was | nobody | Resigning puts the keyboard away. With no tool picker, the canvas has no reason to claim it. |
| saved keyboard state | restored | captured | The keyboard comes back only if it was up. Reading isn't typing. |

Six settings that must move together, in one `EditorMode` enum with one
`apply` — the same argument `TextRewritingPolicy` makes for its five keyboard
traits. The four text-side ones are built (`EditorMode.apply(to:saved:)`); the
two canvas ones join with the canvas. Test: a round trip through `.ink` and back
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

- Tools reach the canvas as `InkToolState.pencilKitTool`, set directly, rather
  than through the picker's observer.
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

Changing a note's orientation re-wraps it, so its ink keeps its printed
position but not its words. Harmless today, with no saved ink; the persistence
step should ask before re-wrapping a note that has some.

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
tracked. Left for later: checking PencilKit renders sharply under the transform,
which needs ink on screen.

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
knobs are what's left.

Two surprises to expect:

- **Undo may be shared.** `UIResponder.undoManager` walks the responder chain,
  and the canvas's chain runs through the text view, which vends its own. Ink
  may register in the text editor's undo stack. Verify on device; don't assume.
- **Scroll position is safe, content insets are not.** Dismissing the keyboard
  changes `adjustedContentInset`, which can shift visible content anyway.

**Files:** `EditorMode.swift`, `NoteEditor.swift`, `Hotbar.swift`, `+DrawingCanvas.swift`, `DocumentTextView.swift`, `PageDetailView.swift`
**Gate:** toggle mid-document — scroll offset unchanged, caret where you left it.

### 4. Persistence (Sep 22–28)
`Page.drawingData` already exists, so no schema change. Encode on
`canvasViewDidEndUsingTool`, **not** `canvasViewDrawingDidChange` — the first
fires when the user lifts the tool, the second fires continuously mid-stroke.

Drawing changes must bump `page.modifiedAt`, or a page you only drew on sinks
to the bottom of the list.

Decode failure must not overwrite. Follow `Storage.swift`'s posture: corrupt
bytes give an empty canvas and a visible warning, and the stored data is left
alone. Silently replacing unreadable ink turns a transient bug into a destroyed
semester of notes.

**Files:** `+DrawingCodec.swift`, `+DrawingSaveScheduler.swift`, `Page.swift`
**Gate:** draw, background, force-quit, reopen — ink intact on the right page.

### 5. Device pass (Sep 29 – Oct 10)
Ink latency, palm rejection, and Pencil-versus-finger routing are all
unrepresentative in the simulator. Real iPad time plus the fixes it turns up,
plus buffer.

Measure `dataRepresentation()` on a page with a few hundred strokes before
choosing the save debounce — the highlighter's 20ms came from measuring, not
guessing.

## Known limitation: drift

Ink is anchored to the page, not the paragraph. Insert a paragraph above an
annotation and the text moves while the stroke does not. A fixed column width
protects against rotation and Split View; nothing protects against insertion
above, or a Dynamic Type change.

See `GeometrySpike` on branch `spike/page-geometry` for a live demonstration.

**The fix, wanted for its own sake:** anchor each stroke to an `NSTextLocation`
plus an offset from that paragraph's fragment origin; on relayout, ask the
layout manager where each anchor is now and translate its stroke group.
`PKDrawing.strokes` is mutable and `PKStroke` has a `transform`. Needs a
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

## Cut list, in order

1. **Drop pages added for ink.** Ink confined to the pages the text makes.
2. **Drop the Pencil/finger split.** `.anyInput` with an explicit scroll-lock
   button. Cruder, but removes any dependence on gesture resolution.

Dropping `PKToolPicker` used to be first on this list. The hotbar adopted it
as the plan — see the amendment under "Who owns the touch".

Not cut under any circumstance: persistence. A drawing layer that loses ink is
worse than no drawing layer.
