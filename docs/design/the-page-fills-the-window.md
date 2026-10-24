# The page fills the window
Roadmap step 5 (16 Oct, branch `claude/page-fills-window`, off `claude/drag-folders`).

- **The page fills its area.** `PageDetailView.pageInsets` was zero on every
  edge but the one a bar is docked to (see the buffer below). No 12pt gap above, no border, no
  rounded corners (`PageView.outline` and `outlineCornerRadius` are gone). The
  surround still shows where the page is narrower than its area (the 1.25x cap
  on a wide screen) and in print layout between sheets.
- **A buffer of `Hotbar.pageBuffer` (10pt) on every edge the bar doesn't take**
  (23 Oct, feedback item 1: the page edge touched the screen edge). Top
  included, under the nav bar; the bar's own side has its strip instead, and a
  bar at the bottom floats over the page, so the bottom has none then
  (`CanvasGeometry.areaInsets`, `PageDetailView.pageInsets`). The surround
  shows in the gap. It is area, not text: the text container stays at the
  pages' width, so nothing re-wraps and every mode paginates alike; the fit
  scale drops by the buffer's share of the width (2.4% on an 11-inch in
  portrait). 10 is a little under the bar's 12pt margin. `HotbarLayoutTests`
  hosts the real page in portrait and landscape, with the bar on each edge,
  and measures the gap to each screen edge from the nav bar and the safe areas
  (fails with the buffer removed, checked). Not looked at on screen.
- **A bar at the bottom floats over the page and moves nothing.** To let the
  note's last lines scroll clear of it, `PageView.restingClearance` insets the
  text view's bottom by `Hotbar.footprint` (the bar and the options row, in
  screen points over the display scale). It is the larger of that and the
  keyboard's inset, not the sum: `keyboardClearance` already includes the bar.
- **A bar at a side takes one strip from that side**
  (`CanvasGeometry.hotbarReserve(dock:side:)`), and the page is fitted to what
  is left and centred in it. The strip is `Hotbar.footprint`: bar, margin,
  gap and the options row's reach, reserved whether the row is out or not, so
  a change of tool or mode never moves the page (the roadmap's proposal for
  its open question). **This reverses "moving the bar never resizes the
  page"**, which was a choice; the docks now differ in width, so the scale
  can differ between edges on a narrow screen (on a wide one the 1.25x cap
  absorbs it and the page only shifts half the strip).
- **The page moves with the bar** (17 Oct, reported on the iPad). SwiftUI
  lays a UIKit view out where it ends up, at once, so while the bar slid to
  its new edge with `.snappy` the page jumped to its new size and place.
  Logged: a dock change resizes `PageView` with no animation in effect, and
  a change between left and right only moves a container above it, which
  `PageView` never hears of. So the note page hands `DocumentTextView` the
  edges it leaves (`areaInsets`) and the bar's animation (`areaAnimation`);
  `PageView.areaWillChange` is called before SwiftUI lays the new area out,
  remembers that the page should move, and lays out again; `layoutSubviews`
  then puts the text view back where it was on screen (its window
  position, scale and size from the last pass) and animates it to its new
  place with the same `.snappy`. The view stops clipping while it slides,
  so the page doesn't lose a strip at its old edge; the SwiftUI
  `.clipped()` went for the same reason (a scroll view clips itself at
  rest). **The animation is passed, not read from the transaction**: the
  dock is `@AppStorage`, and its change reached `updateUIView` with no
  animation though the drop sets it in `withAnimation` (logged). Nothing
  under Reduce Motion. `PageMotionTests` checks the page moves, ends where
  a still layout puts it, and doesn't move for an animated update that
  keeps the area; the first fails without the move. Seen in the simulator
  in a screen recording, left to bottom and bottom to left, on the 13-inch
  in portrait. Not seen: the 11-inch, landscape, zoomed in, the iPad.
- **`Hotbar` owns the numbers** (`margin`, `barFootprint`, `footprint`) that
  `PageDetailView`, `keyboardClearance` and `ContentView.pageToastInset` each
  spelled as a 12 before.
- **Home** is a house button at the top left of a note's header, beside ☰
  (`PageDetailView.onGoHome`, `homeButton`). The list's Home row is gone.
- **Settings and Recently Deleted left the list's bottom bar**, which is gone.
  Settings is in the list's ••• and on Home's toolbar; ⌘, still works anywhere.
  It is not in the note's •••, which is about the note (View, Run Code In,
  Outline, Find, Add Page). Recently Deleted is the list's last row, shown
  only when it holds something. Reaching Settings from a note: ☰ › ••• ›
  Settings, or Home › gear, or ⌘,.
- **The note's header is Home, ☰, title on the left; lock (while locked),
  Share and ••• on the right.** Outline moved into •••.
- **Not checked on screen:** any of it. The tests cover the pure geometry, the
  text view's inset and the square corners; the strip, the floating bar, the
  header and the list were not looked at, nor were Reduce Motion, the Pencil
  or an 11-inch iPad.
