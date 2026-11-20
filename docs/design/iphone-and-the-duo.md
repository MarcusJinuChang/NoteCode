# iPhone and the Duo
Roadmap step 11, first part (17 Oct, branch `claude/iphone-layout`), from the
`iPhone` board of the v3 canvas. **Everything turns on the horizontal size
class**, not the device: an iPhone, a folded Duo and a narrow iPad Split View
are compact, and get this; an unfolded Duo is regular and gets the iPad's.

- **A stack, not a split view** (`ContentView.compactStack`): Home at the
  root, the list pushed on it (Show All, a folder tile, Search), a note pushed
  on either. `compactPath` is kept in step with `selection`
  (`CompactScreen.path(_:noteOpen:)`, pure): opening a note pushes it, Home
  and Delete pop it, and the back button closing it clears the selection.
  Folding or unfolding hands what was showing across
  (`CompactScreen.path(listShowing:noteOpen:)` and `listShowing(in:)`), so a
  note stays open; the page is a new view, and opens at its remembered page.
  The note's header has no house in the stack: the back button goes home.
  The stack's types are in CompactNavigation.swift.
- **A list row opens its note by a tap in the stack**
  (`opensOnTapInCompactWidth`). The rows open by selection, which the iPad's
  sidebar makes of a tap; in a stack on an iPhone a tap selects nothing
  outside edit mode, and the binding was never set (logged in the
  simulator, 17 Oct). Nothing changes in a regular width.
- **The page is fitted by its text column** (`CanvasGeometry.fitScale`'s
  `columnWidth`, which `PageView` offers only in a compact width). Where a
  whole page would be drawn below full size, the column and the panels'
  14pt reach (700pt for portrait pages) fill the width and the margins run
  off the sides, centred (`centredOffset`, set when the fit changes at zoom
  1, never under a reader who has panned or zoomed). An iPhone 17 shows the
  column at 0.57x, the board's "about 0.58x"; on its side the page fits at
  1.07x, as on a small iPad. **An iPad in full screen is never compact, so
  nothing changes there**; a first version that switched on a scale
  threshold (0.6x) instead moved a landscape note on an iPad mini by a few
  points, and was dropped. A narrow Split View on an iPad gets the column
  too. Only the drawn size changes, never where lines wrap.
- **The hotbar stays at the bottom, with no grip** (`Hotbar.isMovable`,
  `PageDetailView.dock`): a side would take a third of a phone's width. The
  stored edge is left alone and comes back with a regular width.
- **The text options row waits for Format** (31 Oct, `Hotbar.showsTextRow`,
  `NoteEditor.wantsTextRow`). With the keyboard up on an iPhone 17 the bar
  and the row together took about 40% of what was left above it, and the
  note showed through between them. On a phone the row is out only after
  the B I U button beside the type/draw toggle asks for it (greyed in ink
  mode, so the bar's length doesn't change); the keyboard clearance asks the
  same function. An iPad is unchanged.
- **A track's cut-off end fades** (`EdgeFade`, `HiddenEdges`): a bar or row
  that scrolls fades 24pt at an end with controls past it, and not at an end
  it rests against. Before, a phone's bar stopped mid-button ("f(x").
- **Run is a ▷ button in the top bar** in a compact width, or a window under
  Home's 700pt, not the Notes | Run switch, which has no room beside the
  title and doesn't show in the overflow menu (the-note-page.md). An
  upright unfolded Duo (669pt) cut the title to "Week 6 · Has…" with it.
- **Home** has two-column grids, 16pt margins, no date, a Continue card with
  a small thumbnail and no Open pill, and its buttons stacked. Home is the one
  place width counts too: a regular Home under 700pt gets this layout
  (`HomeLayout`), since beside the list on a portrait 11-inch (about 500pt)
  the iPad's broke the card's title mid-word, dropped folder names and
  wrapped the buttons (30 Oct).
- **The Duo, measured in the 27.1 simulator** (`-debug-report` writes
  `sizeClass`, `windowSize`, `horizontalOffset` and `folds`). Folded it is
  compact, 466 by 678pt, with no fold regions, and the system runs the
  status bar and the navigation bar's buttons down the right side; the page
  sits at 0.55x, centred 31.7pt in. Unfolded and held sideways it is
  regular, 951 by 669pt, and gets the iPad's layout, the page at 1.06x;
  upright, 669 by 951pt, the page at 0.82x, with the navigation bar across
  the top. Its fold is one division region (`UIView.reservedRegions(kind:
  .division)`, iOS 27.1), a 40pt band through the middle with the margins
  for controls included (down the screen sideways, across it upright),
  **inactive while the Duo is flat open and active while it is partly
  folded**. `simctl` can't fold or unfold it; Xcode 27.1's DeviceHub
  app (where Simulator.app was) can, and can half-fold it.
- **The hotbar keeps off an active fold** (`FoldAvoidance`, pure;
  `FoldReader` reports the active regions on layout and on the hinge moving,
  through `UIHingeInteraction`). A fold down the screen crossing the bottom
  band sends a bottom bar to the left, away from the system's buttons on the
  right; a fold across the screen crossing a side band sends a side bar to
  the bottom. Flat open, the fold is inactive and the bar stays where it
  is: the API says content may cross it then. The stored edge is never
  changed, so the bar comes back when the fold goes. Seen in the simulator:
  half-folded, the bar went to the left and the page re-fit to 0.92x; opened
  flat, back to the bottom at 1.06x.
- **Options rows scroll when longer than the space beside the bar**
  (`Hotbar.maxRowLength`, the page area less the bar's margins, offered by
  `BesideBarLayout`; `OptionsRowTrack` reuses `HotbarTrack`, inside the
  row's glass so the capsule's ends stay put). The pen's row is about
  391pt: whole on an iPhone 17's 402, scrolling on an iPhone 17e's 390
  (seen, swiped). An iPad's rows fit and are laid out as before
  (`HotbarLayoutTests`). `NarrowOptionsRowTests` fails with the limit
  ignored (checked).
- **Settings › General leaves out Toolbar Position and Haptic on Snap in a
  compact width**, where the bar can't move. A sheet's own size class isn't
  the window's, so the window hands it `hotbarCanMove` through the
  environment (`settingsSheet`). Seen on an iPhone 17 (left out) and an iPad
  (shown).
- **Sheets on an iPhone 17, looked at:** Settings and General, Note Info,
  the folder editor (the eight colours fit across), Export All and Recently
  Deleted. All are standard sheets and fit; only the two Settings rows
  needed a change.
- **Decided 17 Oct (Marcus): a phone fits the text column**, the board's
  open question, as built. A note opens at that fit; pinch zoom makes it
  larger.
- **Checked in the simulator:** iPhone 17 (Home, a note opened from
  Continue, the list pushed from Show All, a note opened from the list and
  back, the hotbar and both options rows at the bottom, ink mode, the
  sheets above), iPhone 17e (the rows), and the Duo folded, unfolded flat
  and half-folded, and unfolded upright. **Not checked:** an iPhone in
  landscape on screen, the list's search, a folder tile, Delete's Undo in
  the stack, a search result row's tap, the Duo upright and half-folded, a
  physical Duo (none to hand: the simulator is all there is before it
  ships), the Pencil, `HotbarUITests` (XCUITest, not run).
- **Turned on for 1.0.1** (31 Oct, Marcus). Strings that name the device
  read `AppInfo.deviceName`, set at launch from the idiom, so a phone's
  paywall, assistant, Settings and title screen say "this iPhone" (a Duo
  is one); they said "this iPad" everywhere. Seen on an iPhone 18 Pro Max
  (iOS 27.0) while making the store's 6.9-inch screenshots: a note, the
  Run sheet, Home, dark, the paywall.
