# W. The note window

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## W1. Spike: the page as an object on a background

What Marcus wants, as acceptance criteria (Notability's note window):

1. A hairline separates the top bar from the note area.
2. No give at the top: scrolling up stops at the page's top edge, with no
   rubber band showing space above it. (The bottom may bounce.)
3. Dragging on the grey background beside the page scrolls the note, in text
   and ink mode alike (finger only in ink mode, by the existing rule).
4. The scroll indicator runs at the window's right edge, not the page's.
5. The page reads as a sheet lying on the background (edge or shadow), not as
   a view filling its own frame.
6. **Zoomed in, the page moves freely**: one drag pans diagonally, as
   Notability's page does. Today a pan picks vertical (the text view) or
   sideways (`PageView`), ROADMAP › Deferred work. Candidate (a) makes this
   possible, since one pan on `PageView` can drive both offsets. Not a
   blocker for W2 if it fails, but it is what keeps the narrower note area
   beside R's panel from feeling cramped.

Today the page-width `UITextView` scrolls itself, with its indicator off, and
`PageView` around it scrolls only sideways (`design/who-owns-scrolling.md`;
an outer vertical scroll view was rejected for a 40× keystroke cost, so it
stays rejected).

**Spike, in a scratch branch, not merged**, two candidates, each measured:
- **(a) Move the text view's pan to `PageView`**
  (`pageView.addGestureRecognizer(textView.panGestureRecognizer)`, the
  documented UIScrollView technique), so a drag anywhere scrolls the text
  view; draw our own indicator at the window edge from the text view's
  `contentOffset` and `contentSize`; clamp the top bounce in the existing
  `scrollViewDidScroll` clamp (PageView.swift:998). Drive `PageView`'s
  sideways offset from the same pan (criterion 6). Check the ink-mode
  two-finger rule still holds.
- **(b) A window-wide text view** with the page centred by insets. Likely
  breaks the pinned container width, the scale transform and the canvas
  geometry; try only if (a) fails a criterion.

**Output:** a short note appended to `design/who-owns-scrolling.md` (what was
tried, numbers: keystroke cost at 500 lines, scroll smoothness, which criteria
each meets) and a recommendation. No PR of app code.

## W2. The note window, built

Build W1's choice. Plus the hairline (criterion 1) and the page's sheet look
(criterion 5): background `Color(.systemGroupedBackground)`-like token from
`design/colour.md`, page edge or a soft shadow, the same in all three view
modes. Tests: `PageViewTests` for the top clamp (offset never below the top
inset after a fling) and for a pan started outside the page moving the text
view; the paginate-alike sweep stays green.
**Read:** `design/the-page-fills-the-window.md`, `design/who-owns-scrolling.md`.

## W3. Home and sidebar as one control, and the way home

- One joined control at the top left (decision 2): sidebar and home, new
  icons drawn in SwiftUI `Path`s on the 24pt grid, in `NoteIconGeometry`'s
  style; a `HotbarIconTests`-style render test that each icon draws
  non-empty in light and dark (the invisible-icon bug of `colour.md`).
- **Animation home**: the note shrinks into its card on Home
  (`.matchedTransitionSource` on the card and `.navigationTransition(.zoom)`,
  or a matched geometry if Home isn't a navigation destination; find which in
  `ContentView`). Reduce Motion: a cross-fade. Commit ink first, as leaving
  the note already does (`NoteEditor.commitInk`).

**Done when.** Screenshot of the control in both appearances; the transition
seen once in the simulator (a screen recording is enough); iPad checklist line.

## W4. No Liquid Glass

Remove every glass surface: the `glassEffect`s in `Hotbar`, `CodeKeysRow`
(TextOptionsRow's is T2's), any `.buttonStyle(.glass…)`, and the system's glass
on the note's top bar (an opaque toolbar background, or our own bar if the
system one keeps glass on iOS 27). `grep -rn "glass" NoteCode` is empty at the
end except comments. One opaque material token for all bars from `colour.md`.

**Done when.** The grep is clean; screenshots of the note window, Home and the
hotbars in light and dark; `HotbarUITests` build.
