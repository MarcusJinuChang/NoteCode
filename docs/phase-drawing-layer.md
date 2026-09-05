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

### Amendment: zoom moves the scroll view

The principle survives — one scroll view, both layers inside, no sync. What
changes is *which* view that is. A `UIScrollView` zooms a subview it owns, and
a `UITextView` will not zoom its own text. So pinch zoom means an **outer**
scroll view owning scroll and zoom, with a non-scrolling text view and the
canvas in one container that scales as a unit. Scaling both layers together is
exactly what keeps ink aligned at any zoom.

Costs: TextKit 2's viewport-based lazy layout (a non-scrolling text view lays
out the whole document to report its height — measure against
`StylingPerformanceTests`), plus keyboard avoidance and scroll-to-caret.

**Decided:** build it now, in step 2. ~3 days out of step 5's buffer.

## Who owns the touch

One layer owns *editing*; neither owns scrolling. In ink mode a finger must
still scroll, or you toggle modes every few lines during a lecture.

| Knob | Text mode | Ink mode | Why it's in the enum |
|---|---|---|---|
| `canvas.isUserInteractionEnabled` | `false` | `true` | The hit-testing switch. Not `isHidden` — both layers stay visible. |
| `canvas.drawingPolicy` | — | `.pencilOnly` | `.default` changes behaviour depending on whether a Pencil ever paired. |
| `textView.isEditable` | `true` | `false` | Stops a stray tap re-summoning the keyboard mid-stroke. |
| first responder | textView | canvas | The tool picker only appears for a first responder; claiming it dismisses the keyboard. |
| `toolPicker.setVisible` | `false` | `true` | Paired with the responder change so they cannot disagree. |
| saved `selectedRange` | restored | captured | Without it the caret snaps to offset 0 on every return from drawing. |

Six settings that must move together, in one `EditorMode` enum with one
`apply(to:canvas:toolPicker:)` — the same argument `TextRewritingPolicy` makes
for its five keyboard traits. Test: a round trip through `.ink` and back leaves
all six as they started.

## Build order

### 1. Spike (Sep 6–7)
Throwaway view on a scratch branch: canvas, tool picker, save button. Draw,
kill the app, reopen, see the strokes. Nothing touches the real editor.

What you're learning: `PKDrawing.dataRepresentation()` / `PKDrawing(data:)` are
the whole persistence story, and the tool picker will not appear until the
canvas is `becomeFirstResponder()`.

**Gate:** strokes survive a force-quit.

### 2. Geometry (Sep 8–14)
One canonical layout width (~700pt), centred by adjusting
`textContainerInset.left/right` on bounds change, plus a base display scale per
orientation. Then the outer zoom container. Then the canvas.

Ink drawn *below* the last line has nothing to scroll to, because content
height comes from the text. Lever: `textContainerInset.bottom`, grown until
content covers `drawing.bounds.maxY`. Compute it as a pure function of (text
height, ink bounds, column width, scale) so it is idempotent — deriving it from
current content height sets up a layout feedback loop.

**Files:** `+CanvasGeometry.swift`, `+PageContainerView.swift`, `DocumentTextView.swift`
**Tests:** `CanvasGeometryTests` — canvas covers the text; ink below the last
line extends the bottom inset; deleting text never clips ink; same scale in
both orientations yields identical line breaks; applying twice changes nothing.
**Gate:** reach a stroke at y = 3000; rotate and confirm identical line breaks.

### 3. The toggle (Sep 15–21) — flagged risk
`EditorMode`, a toolbar button in `PageDetailView`, and the first-responder
handoff. This is where the keyboard and the tool picker argue.

Two surprises to expect:

- **Undo may be shared.** `UIResponder.undoManager` walks the responder chain,
  and the canvas's chain runs through the text view, which vends its own. Ink
  may register in the text editor's undo stack. Verify on device; don't assume.
- **Scroll position is safe, content insets are not.** Dismissing the keyboard
  changes `adjustedContentInset`, which can shift visible content anyway.

**Files:** `+EditorMode.swift`, `+DrawingCanvas.swift`, `DocumentTextView.swift`, `PageDetailView.swift`
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

1. **Drop `PKToolPicker`** for a fixed pen/eraser/colour/undo toolbar. Removes
   the keyboard-versus-picker fight entirely; keeps the whole feature.
2. **Drop the bottom-growth inset.** Ink confined to the text's own height.
3. **Drop the Pencil/finger split.** `.anyInput` with an explicit scroll-lock
   button. Cruder, but removes any dependence on gesture resolution.

Not cut under any circumstance: persistence. A drawing layer that loses ink is
worse than no drawing layer.
