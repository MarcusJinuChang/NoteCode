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
