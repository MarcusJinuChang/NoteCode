# O. Objects

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## O1. The object popup appears when an object is inserted

**Bug.** Insert (shape, photo) doesn't show the selection's options row,
though `InkInsert` says it "selects what it inserted" (InkInsert.swift:123).
Find why with one probe run, not reading: log, at insert, whether
`InkSelection` has the new object, whether the Select tool is current, and
whether the overlay is active (the `-debug-probe` log, `DebugProbe`). Likely
causes, in order: the selection is set before the canvas has the element
(`InkCapture` is asynchronous; see AGENTS.md › strokes taken in off the main
thread), so the hit test finds nothing; or the tool isn't switched to Select
so the overlay never shows.

**Done when.** A test in `InkSelectionTests` inserts a shape and finds the
selection non-empty and the options row's model visible, `await`ing as
`PageViewTests.waitFor` does; it fails before the fix. iPad checklist line:
insert a rectangle and a photo, the row appears each time.
**Read:** `design/object-system.md` › Build state (24 Oct) and decision 5.

## O2. Resizing an object is smooth

**Measure first.** `InkSelectionOverlay` previews a scale by assigning the
whole markup (`controller.markup =`), throttled to 30 per second. Time one
preview at 100, 1,000 and 5,000 strokes on the simulator (Release), and put
the numbers in the PR.

**Then fix, cheapest first:** during the drag, scale a snapshot (a layer
transform of a rendered image of the selection, with the originals hidden),
and write the markup once on release. That makes the drag cost independent
of the note. Keep the one rebuild on release (`append(contentsOf:)`, AGENTS.md
› MarkupOrderedSet rules).

**Done when.** The per-frame cost during a drag is under 4ms at 5,000 strokes
(measured), the end result is identical to today's (a test compares the
markup after a scale with the old path's), undo is one step.
