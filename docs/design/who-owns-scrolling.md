# Who owns scrolling
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
  a shorter area and cut its border off at the keyboard, and shrank the note
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

## W1 spike: the page as an object on a background (26 Oct)

Question: can the note window scroll like Notability's (drag anywhere, no
give at the top, indicator at the window edge, diagonal pan when zoomed)
without the outer vertical scroll view rejected above? The spike is on
branch `spike/w1-scroll-owner` (not merged; ~55 lines in `PageView` plus one
scratch test, `PageViewTests.w1Spike`).

**Candidate (a), as built.**
- `textView.panGestureRecognizer` is removed from the text view and added to
  `PageView` (`addGestureRecognizer`). The text view still scrolls itself, so
  the viewport, the transform and the canvas geometry are untouched.
- `PageView`'s own pan is disabled; a target on the moved pan applies the
  horizontal part of its translation to `PageView.contentOffset.x`, so one
  drag moves both axes. `isDirectionalLockEnabled` is off.
- Top clamp: a KVO observer on `textView.contentOffset` sets y back to 0 when
  it goes negative. (The brief's `scrollViewDidScroll` clamp does not exist:
  `PageView` has no delegate.)
- Indicator: a 3pt capsule on `PageView`, placed from the text view's
  `contentOffset.y`/`contentSize.height` and the display scale, pinned to the
  view's right edge (`contentOffset.x + bounds.width`).

**Measured** (iPad Pro 13-inch M5 simulator, PageView harness, median of 15
keystrokes at offset 120, `replace` + `layoutIfNeeded`):

| Note | Keystroke |
|---|---|
| 250 lines | 13.5 ms |
| 500 lines | 27.1 ms |

Within `typingCost`'s 100ms budget. The text view is unchanged and still the
scroller, so this is the existing cost by construction, not a new one; the
outer-scroll-view figure was 477ms at 500 lines. Scroll smoothness was not
measured: simulator scrolling is not representative and the brief rules out
UI automation, so it is on Marcus's iPad list.

**Per criterion.**

| # | Criterion | Result |
|---|---|---|
| 1 | Hairline under the top bar | Not part of the spike (SwiftUI chrome, W2) |
| 2 | No give at the top | Met in the harness: setting offset -80 reads back 0. A live drag past the top is not tried |
| 3 | Drag on the background scrolls | Wiring met: the pan is on `PageView`, which covers the background. `hitTest` already handed those touches to the text view, so this was mostly true before; the move makes it true for any touch `hitTest` doesn't claim. The test window was page-wide, so a beside-the-page touch was not exercised |
| 4 | Indicator at the window edge | Met: frame x = 875 in an 880 area |
| 5 | Page reads as a sheet | Not part of the spike (W2: surround colour exists, page edge/shadow is new) |
| 6 | Free diagonal pan | Plumbed (one pan drives both offsets). Not verified by touch |

**Not verified, needs a finger/Pencil:** diagonal feel; that the sideways drag
has no momentum (the target moves `contentOffset.x` directly, so W2 needs
`UIScrollView`-style deceleration or a `UIDynamicAnimator`/display-link fling
for x); that the ink-mode rules (`EditorMode.scrolling`, `touchWillLand`)
still hold with the pan on another view, including PaperKit's two-finger pan
and the lasso; that the pinch's simultaneous-recognition rule still reads
the moved pan correctly (`gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
compares by identity, so it should).

**Recommendation.** Build (a) in W2; do not try (b). Nothing measured
contradicts it, and it avoids rewriting the pinned container width and canvas
geometry. W2 should: replace the KVO clamp with a delegate or a
`DocumentUITextView` override of `contentOffset` so a fling cannot show space
at the top; give the sideways axis momentum; make the indicator a real
view that fades like the system one and ignores the keyboard inset; and
start its tests with the top clamp and a pan beginning outside the page.
Candidate (b) was not tried: no criterion failed that it would fix.

## W2: the note window, built (28 Oct)

W1's candidate (a), as recommended, with its follow-ups:

- **One pan.** `textView.panGestureRecognizer` lives on `PageView`
  (`adoptTextViewPan`); `PageView`'s own pan is off for good, so
  `PageView.pans` is just the moved one and `setPanning` toggles only it.
  A drag anywhere, beside the page included, scrolls the note, and the same
  pan moves the sideways offset: zoomed in, one drag pans diagonally
  (`isDirectionalLockEnabled` off).
- **Sideways momentum** is `SidewaysFling`: a display link decaying the
  pan's x velocity at `UIScrollView.DecelerationRate.normal`, ending at an
  edge or under 20pt/s. The vertical axis still decelerates in the text view.
- **No give at the top**: `DocumentUITextView.contentOffset` clamps y to
  `-contentInset.top` in its setter, so a drag, a fling or `setContentOffset`
  cannot show space above the page (replaces the spike's KVO). The bottom
  still bounces. Top-of-note Pencil/selection scrolling is unaffected.
- **Indicator**: a 3pt capsule on `PageView` at its right edge
  (`PageView.indicatorFrame`, pure), full window height, ignoring the
  keyboard inset; it fades 0.8s after the offset last moved.
- **Sheet**: `PageEdgeView` (page colour, a hairline in `separator` and a
  soft shadow) sits behind the text view in seamless and compressed, hidden
  in print layout, whose sheets already carry the same border and shadow
  (`PageDecorationView.makeSheet`). The surround is the existing
  `PageView.surroundColor` (`secondarySystemBackground`), not a new token.
- **Hairline** under the top bar: `PageDetailView` overlays a `separator`
  line at the top of the page area.

**Checked**: `PageViewTests` (top clamp, pan on the page, a touch beside
the page, indicator geometry, fling decay, edge follows the text view).
**Not checked** (needs the iPad): diagonal feel and fling; ink mode's
two-finger rule and PaperKit's lasso with the pan on `PageView`; the pinch
beside the moved pan; indicator fade; how the edge looks in both
appearances; scroll smoothness.
