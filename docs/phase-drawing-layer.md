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

Pinch zoom isn't built. In this shape it is a user factor on the same
transform, with `PageView`'s sideways scroll taking the overflow past the page
area — no new scroll view.

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

## Build order

### 1. Spike (Sep 6–7)
Throwaway view on a scratch branch: canvas, tool picker, save button. Draw,
kill the app, reopen, see the strokes. Nothing touches the real editor.

What you're learning: `PKDrawing.dataRepresentation()` / `PKDrawing(data:)` are
the whole persistence story, and the tool picker will not appear until the
canvas is `becomeFirstResponder()`.

**Gate:** strokes survive a force-quit.

### 2. Geometry (Sep 8–14)
One layout width, `CanvasGeometry.pageWidth` = 700pt, pinned on the text
container rather than inferred from the view. The display scale is the page
area's width over 700, held between 0.75 and 1.25: past the ceiling the margins
grow instead of the text, and below the floor the page scrolls sideways. The
hotbar reserves both sides always, so the scale depends on the window alone.
Then the canvas, as a subview of the text view's content.

Ink drawn *below* the last line has nothing to scroll to, because content
height comes from the text. Lever: `textContainerInset.bottom`, grown until
content covers `drawing.bounds.maxY`. Compute it as a pure function of (text
height, ink bounds, column width, scale) so it is idempotent — deriving it from
current content height sets up a layout feedback loop.

Built 12 Sep. Found on the way: a text view first sized while scaled below 1x
takes its line width from the shrunken frame, so its container width is pinned
rather than tracked. Left for later steps: pinch zoom, and checking PencilKit
renders sharply under the transform, which needs ink on screen.

**Files:** `CanvasGeometry.swift`, `PageView.swift`, `DocumentTextView.swift`
**Tests:** `CanvasGeometryTests` (scale, reserve, frame, bottom inset) and
`PageViewTests` — canvas covers the text; ink at y = 3000 is reachable; deleting
text never clips ink; portrait and landscape scales give identical line breaks;
laying out again changes nothing. The last three were each shown to fail with
their fix reverted.
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
4. Draw below the last line, scroll to it — bottom inset grew.
5. Rotate, then Split View — scale changes; ink stays beside the same words.
6. Pinch zoom in and out — text re-renders crisp, ink tracks it.
7. Type a paragraph at the top of an annotated page — confirms known drift.
8. Type for thirty seconds on a heavily inked page — no dropped keystrokes.

## Cut list, in order

1. **Drop the bottom-growth inset.** Ink confined to the text's own height.
2. **Drop the Pencil/finger split.** `.anyInput` with an explicit scroll-lock
   button. Cruder, but removes any dependence on gesture resolution.

Dropping `PKToolPicker` used to be first on this list. The hotbar adopted it
as the plan — see the amendment under "Who owns the touch".

Not cut under any circumstance: persistence. A drawing layer that loses ink is
worse than no drawing layer.
