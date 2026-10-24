# The object system

Design note for phase 6 of `docs/feedback-plan.md` (stream O), 21 Oct. Design
and two spikes only; nothing here is built. Written from the code on `main` at
`6fabdfd`, PaperKit's iOS 27.1 and macOS 27.0 interfaces, and
`scripts/spikes/`. It follows "Isolate risk": each spike answers one assumption
the build would otherwise rest on.

## What Marcus asked for (the problem)

- Rectangular selection, of ink and of text, and recolouring selected text.
- The lasso lets go when the tool changes; no PaperKit tap-to-highlight of a
  cluster of strokes; the hotbar stays put after a lasso move.
- "Return to the previous tool after a selection" as a setting.
- Decided: our own object system now, schema version 1 edited in place, no
  version 2.

## Findings: what PaperKit lets us do today

Read from the interfaces and the code, not from the iPad. **Device-only items
are marked and are not verified.**

- **Selection is the controller's, and has a public handle.** In iOS 27
  `PaperMarkupViewController.selection` (`Set<ElementID>`) and `selectedMarkup`
  are settable, and the delegate has `…DidChangeSelection`. So the app *can*
  clear PaperKit's selection, and can set it. What there isn't: a switch for
  tap-to-select, or a hook that vetoes a selection before it shows. The other
  knobs are `isEditable`, `directTouchMode` (`.drawing` or `.selection`, which
  `DrawingCanvas` already sets to `.drawing`) and `MarkupInteractions` per element
  (`.select`, `.move`, `.resize`, …).
- **`allowedInteractions` can't make a stroke unselectable.** Measured: on a
  `PKStroke` the setter accepts `[]` and the value reads back as `.all`
  (63) before and after a save. So "mark every stroke non-selectable" is not a
  way to stop the tap-to-highlight cluster. It may work for shapes and images
  (not tried: they have their own stored setting in the interface).
- **What `DrawingCanvas` does with the lasso.** Nothing of its own. The hotbar's
  lasso is `PKLassoTool()` handed to the controller (`InkTool.swift:547`), and
  everything after that, the selection, handles, edit menu, drag, is PaperKit's.
  What the app adds is plumbing for its side effects: a two-finger pan that
  PaperKit turns back on after a selection is dragged
  (`releaseTwoFingerDrags`), `EditorMode.scrolling` so the text view's pan
  doesn't race the drag, and `InkInserter`/`NoteEditor.insertIntoInk`, which
  switch to the lasso after an insert because PaperKit selects what it inserts.
- **Why the lasso doesn't let go on a tool switch.** `NoteEditor.inkTool.didSet`
  assigns `canvas.tool` and nothing else. The selection is controller state, not
  tool state, so it survives. `controller.selection = []` there is the
  one-line candidate (**unverified on a device**; it is also a quick win that
  doesn't need the object system, see step 0).
- **The hotbar displacement is not explained.** The hotbar is a SwiftUI sibling
  of the page layer; its only inputs from the page are the keyboard (it keeps the
  keyboard's safe area and `keyboardClearance` rides it above) and the dock.
  `PageView.keyboardWillChangeFrame` also insets the text view from the same
  notification. PaperKit's controller overrides `canBecomeFirstResponder`, so a
  selection can take first responder from the text view and post keyboard-frame
  changes (the edit menu, an accessory). That is a hypothesis, nothing more. It
  needs one logging run on the iPad (step 0) before anyone claims the object
  system fixes it. If it is the first-responder theory, our own selection
  overlay, which never makes PaperKit first responder, removes it.
- **Tap-to-highlight is not located.** Which tool or mode produces the cluster
  highlight (pen with a finger? lasso tap? `directTouchMode`?) isn't in the
  code or the interface, and the simulator's synthesised touches don't
  reproduce a Pencil. It decides how much we must remove, so it is step 0's
  other question.
- **What is stored.** `Page.drawingData` is `Data`, external storage: the bytes
  of one `PaperMarkup` in **print coordinates** (`PageView.ink`).
  `DrawingCodec` is the only reader/writer (`decode` at four call sites:
  `DrawingSaveScheduler`, `ExportAll`, `NoteThumbnail`, and `PageView` through
  the page; `encode` once). Strokes are stored **cut into per-page pieces**
  (`InkPages`), a stroke's identity being its *family* (the first ten bytes of
  its `PKStroke.id`), with overflow pieces marked in the id.
- **What a PaperKit element carries.** All are `Markup`: `elementID`,
  `renderFrame`, `frame`, `rotation`, `allowedInteractions`, `applyTransform`.
  A `PKStroke` has ink, path, transform, mask, random seed and a settable `id`;
  a `ShapeMarkup` has shape, fill and stroke colour, line width, opacity, line
  markers and `attributedText` (a text box *is* a shape with text); an
  `ImageMarkup` has the image, `contentsBounds`, orientation and opacity.
  `InkContent.fingerprint` already hashes the last two so edits in place are
  seen.
- **`InkCapture` infers what the reader did by diffing the canvas** against the
  last frames (`State.shown`) and contents (`State.contents`), off the main
  thread. That is right for pen and eraser, whose changes PaperKit makes and the
  app only observes. It is the wrong tool for selection commands the app itself
  issues: it has to guess "moved" from a frame change, and its overflow rule
  (hidden pieces translated by the middle's shift) is a lossy guess for
  resize and rotate, which AGENTS.md already notes ("a lasso's resize or
  rotation isn't carried exactly").

## Decisions

### 1. What an object is

- **An ink object is a family of elements, not an element.** A stroke is its
  `InkPages.Family` (own piece plus overflow pieces, shown or hidden); a shape,
  text box or image is one element. The unit the reader selects, moves,
  recolours and deletes is the object; the pieces are storage.
  *Why:* the reader sees one stroke across a page break. Selecting pieces would
  leave half of it behind, and the current lasso already needs a special rule
  for hidden overflow.
- **A text range is a selection, not a stored object.** The note's text is the
  Markdown in `Page.content`; a range of it gets recoloured by editing the
  Markdown (`MarkdownFormatting.style`), which is how colour already works.
  Nothing new is stored for text.
  *Why:* the text system is already the source of truth for formatting, with
  undo, search, export and paste built on it. A second place that holds colour
  would drift.
- **Object identity** is the `ElementID` on the canvas and the family id in the
  store; the object table (below) keys on the stroke `id`/`MarkupID`, which
  survives save, transform and recolour (measured: the same `elementID` and
  `id` after `applyTransform`, and after a recolour that rebuilds the stroke
  with its `id` set; a plain rebuild loses it).
- **Out of scope for the first build:** the free text-box tool, more shapes,
  logic gates (plan, phase 6). Existing shapes, text boxes and images from Insert
  stay objects.

### 2. The selection model

One `Selection` value on `NoteEditor`, observed:

    enum Selection { case none; case ink(Set<ObjectID>, text: [NSRange]) }

- **One Select tool with two shapes**, replacing the lasso: **Lasso** (free
  polygon) and **Rectangle** (a drag), switched in the options row (the lasso has
  no row today, so there is room). *Why one tool:* the same selection, handles
  and commands follow; two tools would double the previous-tool rules.
- **Ink hit test:** an object is selected when any point of its visible path
  falls inside the shape (frame prefilter, then path points; measured cheap, see
  the spike). *Why touching and not "fully inside":* a handwritten diagram is
  caught by dragging roughly around it; "fully inside" needs precision a pencil
  on a tablet doesn't give. A lasso drawn right through a cluster selects the
  cluster by design; the stray multi-stroke highlight is gone because *nothing*
  selects on a tap. A tap on an object selects only that object (one family),
  with no clustering by time or proximity.
- **Text in the shape:** in the same drag the shape also collects text. For a
  Rectangle, each laid-out line it crosses contributes the characters whose
  glyph rects fall in it (a column, one range per line); for a Lasso, the same
  from the polygon. The text ranges are per line, which is what
  `MarkdownFormatting.style` already takes. Code blocks contribute nothing
  (code is never coloured). This is **Marcus's call to confirm** (question 3).
- **Commands on a selection:**
  - Ink: move (drag), delete, duplicate, recolour (strokes, shapes), uniform
    scale by a corner handle. Rotate and shape-specific edits (text-box
    editing, line ends) are **handed to PaperKit for one object** through an
    explicit "Edit" (`controller.selection = [id]`), the one case PaperKit's
    selection UI stays (see decision 5).
  - Text: recolour, size, bold, italic, highlight, i.e. anything the text row
    does, applied per range. Not move, not delete (a deletion here would be a
    surprise; Backspace on a real text selection stays the text view's).
  - **Recolour is one control for both**: choosing a colour recolours the ink
    and the text in the selection. Text takes `TextColour`'s palette (legible
    adjustment), ink takes the ink palette's shade; they are different palettes
    today (`InkShade` vs `TextColour`), so the control shows the ink palette and
    maps each to the nearest text colour. **Unverified design:** question 4.
- **Unselect:** a tap on empty space (no object, no text), a tool switch, a mode
  switch (text ↔ ink), the note closing, and after Delete. Not after a move,
  recolour or duplicate: the reader often does two in a row.
- **Previous tool.** `NoteEditor` already keeps `previousInkKind`. New setting,
  `returnToPreviousTool` (Settings › Drawing, default **off**, key stable-pinned
  in `SettingsTests.keysAreStable`): when on, the selection *ending by the
  reader's choice* (tap empty, Delete) switches back to the tool before Select. A
  tool switch ends the selection but never triggers it (the reader just chose
  a tool). Insert is the one exception: it selects the new object and switches
  to Select as now, and with the setting on it returns after the selection ends,
  so a photo is dropped, nudged and the pen is back.

### 3. Input ownership with the toggle

The toggle (`EditorMode`) stays: **exactly one of the text view and the ink
side owns touches.** Within ink mode a second rule: **exactly one of the canvas
and the selection overlay owns them.**

- A new `InkSelectionOverlay` (a `UIView`, above `DrawingCanvas` in the text
  view's content, below the code action bars' ceiling) is interactive only
  while the Select tool is current; the canvas is `isUserInteractionEnabled =
  false` then. With any other tool the overlay is non-interactive and the
  canvas owns touches as today. *Why a flag on the canvas rather than a tool
  PaperKit doesn't know:* PaperKit never sees a touch while we select, so it
  cannot highlight, and its pan/two-finger bugs can't start.
- Scrolling: unchanged (`EditorMode.scrolling`). A drag that starts on a selected
  object moves it; one that starts elsewhere draws the shape; two fingers
  scroll when a finger draws, as now. `takesInk` still decides where a touch may
  start, and the overlay uses it (print layout's margins take nothing).
- Text selection in ink mode needs no first responder: the text view stays
  non-editable and non-selectable, and the overlay draws the text highlight
  itself, from line rects. **The edit is applied with `replace(_:withText:)`
  while the text view is not editable: measured to work** (spike 2), which
  removes the biggest doubt about recolouring text from ink mode. The locked
  note check is ours to make (the API doesn't enforce it, and a locked note
  stays selectable but unchangeable).
- Hit testing on the overlay and gestures live on one delegate object
  (`SelectionGestures`), like `MarkerGestures`, since a scroll view is the
  delegate of its own pan.

### 4. PaperKit stays the renderer; what we replace

- **Stays:** drawing (`PKInkingTool`, `PKEraserTool`: latency and Pencil
  behaviour can't be rebuilt), rendering of every element, zoom through
  `renderScale`, saving (`PaperMarkup.dataRepresentation`), shape/image/text-box
  *display*, and the PDF path. *Why:* replacing the renderer is a rebuild of the
  ink layer for no feature Marcus listed, and PencilKit's own canvas can't draw
  shapes, images or text boxes.
- **Replaced:** selection, handles, drag/move, delete, recolour, duplicate and
  the edit menu, for strokes, shapes and images; the lasso tool; the
  two-finger-pan workaround; "select the inserted object".
- **Lasso tool removed from the PencilKit tool mapping.** `InkToolState
  .pencilKitTool` has no `PKLassoTool`; while Select is current the canvas holds
  the last drawing tool and is non-interactive.
- **Edits are explicit commands on the stored ink, not diffs of the canvas.**
  `InkCapture` keeps doing what it does for pen and eraser. For Select's commands
  the app computes the new stored ink itself (a command applied to every piece
  in the family, shown or hidden, so resize and rotate are exact) and reshows
  it. *Why:* it removes the lossy overflow-translation rule and makes undo a
  proper inverse command on our own undo entries rather than PaperKit's
  registration.
- **How a command is applied, measured (spike 1):**
  - `updateOrAppend` and `removeElement` per element cost 1.7s and 2.0s for 114
    of 5,000 strokes. **Never use them for a command.**
  - Rebuilding the whole set into a fresh `PaperMarkup` with **one**
    `append(contentsOf:)`, with the changed elements transformed or recoloured,
    costs 127ms (move) and 131–152ms (recolour) at 5,000 strokes and 11ms at 500.
    That is the existing rule ("build a set with one append") and it is the
    command primitive. It runs off the main thread on a snapshot (a markup is a
    value), then `show { controller.markup = … }`.
  - During a drag nothing touches PaperKit's set. A drag moves a **lifted
    preview** (the selection drawn with `PaperMarkup.draw` into a layer, or the
    canvas's own tiles masked: step 2 decides), and one rebuild runs at drop.
    **Unverified:** the cost of `controller.markup = …` for the canvas redraw at
    5,000 strokes (the app's own `convert` is 141ms for 2,000, which is the
    nearest number).
  - Frame test: walking the canvas costs 65–116ms at 5,000 strokes, so selection
    never walks it. `InkCapture.State.shown` is already a `[ElementID: CGRect]`
    of every element: scanning it is 0.1ms at 5,000. The exact test (path points)
    runs on the candidates only: 2.4ms for 56 of 500, 26ms for 114 of 5,000.
  - Recolour keeps identity: `PKStroke(ink:path:transform:mask:randomSeed:)` with
    `id` copied over: same `elementID`, same z position when replaced.

### 5. PaperKit behaviour to remove, and the one place it stays

- Remove: PaperKit's selection for strokes, always. The lasso tool, the stray
  highlight, the edit menu on a selection, `releaseTwoFingerDrags` if the probe
  shows it unneeded, and `insertIntoInk`'s switch to the lasso.
- **Where PaperKit's selection UI stays: a single shape, text box or image,
  on an explicit "Edit".** Resize with rotation and aspect, a text box's text,
  and a line's ends are PaperKit's UI and rebuilding them is not part of this
  phase (and the text-box tool isn't wanted yet). The Select tool's command bar
  has "Edit" for exactly one such object; it sets `controller.selection` and
  clears it when anything else is selected or the tool changes.
- **Defence in depth for tap-to-highlight:** the delegate's
  `DidChangeSelection` clears `controller.selection` when the change wasn't
  made by us (a flag, as `isShowingInk` does for markup). It may flash for a
  frame, so it is a net under the real fix (not being the touch owner), not the
  fix. **Unverified:** that the callback is synchronous and the flash invisible.

### 6. Storage: the format change, and why it needs no migration

Two options. **Recommended: A.**

- **A. A container inside `drawingData`; no schema change.** The bytes are
  either **legacy** (a bare `PaperMarkup` blob, exactly today's) or a container:
  `"NCOB"`, a version byte, a `UInt32` length, an **object table** (JSON), then
  the PaperKit bytes. `DrawingCodec` is the only reader and writer, so the
  container is hidden behind it: `Loaded.ink(PaperMarkup)` is unchanged and a new
  `objects` accompanies it. **The writer emits legacy bytes whenever the table
  is empty**, which is every note until something uses it: stored ink is then
  bit-for-bit what today's build writes, so existing notes, TestFlight notes and
  an older build all keep working until the first anchored object exists.
  - `ModelFreezeTests`' pinned hashes **don't change** (no attribute added, no
    relationship touched), and `storeFromBeforeVersionsOpens` is unaffected.
    This is the strongest version of "no migration": there is nothing to
    migrate because a legacy blob is a valid container-less value.
  - Measured (spike 1, Q5): legacy bytes still read as legacy and PaperKit
    accepts them; container bytes are refused by `PaperMarkup(dataRepresentation:)`,
    so an older build treats them as "unreadable" and, per `DrawingCodec`'s rule,
    leaves them untouched rather than saving over them. Don't run an older
    branch on a device whose note has used it (the AGENTS.md line for the model,
    now for ink).
  - Cost: a note with a table can't be read by a PaperKit-only tool (nothing
    does), and `Page.duplicated`, `ExportAll`, thumbnails and search read through
    `DrawingCodec` and so see through it.
- **B. A new attribute** (`Page.inkObjects: Data = Data()`, external storage),
  edited into version 1: the entity hash changes, `ModelFreezeTests.versionOneHashes`
  is updated in the same commit, and `storeFromBeforeVersionsOpens` must still
  pass (a new attribute with a default opens an old store only if a lightweight
  migration is permitted with no versions, which it is **not** with the plan's
  single version: **unverified**, and exactly the risk A avoids).
- **Table contents.** Only objects with something the PaperKit bytes don't
  say: `{id, kind, anchor?, group?}`. Empty by default. **Selection state is
  never stored.** Strokes, shapes and images stay in the PaperKit bytes, where
  they are today, in print coordinates.
- **The table is optional per entry and open to new kinds**: an unknown
  `kind` or `anchor.kind` is kept and written back as it was, so a newer build's
  data survives an older reader's save. The version byte is for a change to the
  container itself.

### 7. Anchoring, so text-anchored ink needs no second format change

The roadmap's text-anchored ink (strokes follow the paragraph they were drawn
beside) must be addable to this format. The design makes the position stored in
PaperKit's bytes always the **resolved** one and the anchor an optional **link**:

- `anchor` in the table entry is `{kind: "text", offset: <UTF-16 offset in
  content>, affinity, dx, dy}` meaning: when last saved, the object's frame equals
  the fragment origin at `offset` plus `(dx, dy)`. For page-anchored ink (every
  object today, and the default) there is no entry and the geometry in the
  PaperKit bytes is the whole story. **So page-anchored is the degenerate case
  of the same format**, not a different one.
- On a text edit above, a pure function adjusts every anchor's `offset` by the
  edit (`Anchor.adjusted(forEditAt:replacing:with:)`, the way caret offsets are
  already tracked), and after layout the resolver translates each anchored
  group by the difference between where its anchor resolves now and where it
  resolved when saved (`applyTransform`, one rebuild per layout change, off
  the main thread like `InkCapture`). Stored geometry is rewritten from the
  resolved position, so a reader that ignores the table (older build, PDF)
  still shows the ink where it was last put.
- `group` ties pieces and clusters together so an anchored drawing moves as one.
- **What isn't solved here, deliberately:** page breaks cutting an anchored group
  (stroke pieces are per page and anchors are not), anchoring across a mode
  switch (layout changes only the gaps; `PageLayout.convert` already maps y), and
  what an anchor means after the paragraph is deleted (nearest surviving offset,
  the caret rule). Each is a decision for the anchoring phase and none changes the
  format: they change what the resolver does with the table.
- **Order against `docs/ROADMAP.md`.** The roadmap lists text-anchored ink
  (item 4) *before* the object system (item 6) and says the object system's
  storage is "the one format change after release". Marcus moved the object
  system ahead of the submission (21 Oct), so the table has to carry anchors
  from its first version, which is what this section is for: with it, anchored
  ink after release changes no format, only what the resolver does. The
  roadmap line wants updating when this lands.
- This is why the table keys on stable object ids from the first build, and why
  commands are applied to families: the thing that later gets an anchor is the
  object the user already selects.

## Risks

- **Tap-to-highlight and the hotbar displacement are unlocated** (device
  only). If PaperKit selects on a pen tap even with the overlay owning Select, our
  own selection fixes only half of it. Step 0 exists to find out first.
- **PaperKit may refuse a programmatic markup assignment during an active
  pen stroke or with a selection up** (`controller.markup =` while PaperKit holds
  selection). Mitigation: clear `controller.selection` before every command and
  gate commands on "no stroke in progress" (the delegate's `DidBeginDrawing`).
- **Drag preview fidelity at zoom.** The canvas is shrunk by `renderScale` and is
  only as big as the screen (the 16,384-pixel Metal limit); a lifted preview must
  follow `cover()` and the page's transform. Likeliest place for a visible lag or
  a one-pixel jump on drop. Needs the iPad.
- **A rebuild keeps z order but loses identity unless `id` is copied**
  (spike: a plain rebuild changes `elementID`); every constructor in the command
  layer must copy `id`. A test per element kind.
- **Pieces and masks:** recolour, scale and move of a masked piece must keep the
  mask in the stroke's own space (move keeps it via `transform`; scale changes the
  stroke's frame and so its page piece). Scale across a page break is the case
  `InkPages` can't answer exactly. First cut: **scale is disabled for an object
  across a page break**; move and recolour are fine.
- **Own undo.** ink undo moves from PaperKit's registration to our inverse
  commands on `DrawingCanvas.inkUndoManager`; pen and eraser still register
  through PaperKit on the same stack. Interleaving them must undo in order: the
  stack is one `UndoManager` for both, which is how it is now.
- **Text from ink mode:** the edit works (spike 2) but no first responder means
  no typing-style, no marked text and no keyboard, which is intended; `isFormatting`
  must be set so the rewrite guard and `typingTextDidChange` leave the edit alone,
  and a locked note must refuse it.
- **Colour mapping** between the ink palette and `TextColour` is a design choice,
  not a fact (decision 2).
- **Stream conflicts.** C (colours and icons) wants the Select tool's icons;
  S owns `SettingsView` (the setting's row is one line there). P owns `PageView`
  and `PageLayout`; step 3 touches `PageView` minimally (an overlay slot and
  `captureInk` bypass), so it merges after P's PRs.

## Build steps (PR-sized, in order)

Each leaves the app working. Files are the main ones; tests follow "prove the
test fails without the fix".

0. **Probe on the iPad, and the one-line fix.** A debug-only logging build
   (`notecode_device_probe.md`'s method): log `DidChangeSelection`, the first
   responder, keyboard notifications and the hotbar's frame across a lasso move;
   find which tool/mode yields the cluster highlight. In the same PR,
   `NoteEditor.inkTool.didSet` clears `controller.selection` when the kind leaves
   `.lasso`. Files: `NoteEditor`, `DrawingCanvas`, `DebugLaunch`. Test: a unit
   test that sets a selection, changes tool, asserts it is empty (fails without
   the line); the rest by hand.
1. **Storage reader/writer.** `DrawingCodec` reads legacy and container, writes
   legacy when the table is empty; new pure `InkObjectTable` (kinds, anchor,
   unknown-entry round trip). No behaviour change. Files: `DrawingCodec`,
   new `InkObjectTable.swift`, `DrawingSaveScheduler` (carries the table).
   Tests: legacy bytes decode as before; a table round-trips; unknown kinds
   survive a save; empty table writes bytes identical to `PaperMarkup`'s; a
   container read by PaperKit alone is refused (so the leave-alone rule applies);
   `ModelFreezeTests` unchanged and green. Mutation: writer always wraps →
   byte-identity test fails.
2. **Object model, hit testing and commands (pure).** `InkObject`/family
   resolution through `InkPages`, `SelectionShape` (rectangle, lasso polygon),
   hit tests from `InkCapture.State.shown`, and the commands (move, recolour,
   delete, duplicate, scale) as whole-set rebuilds that preserve `id`s. No UI.
   Files: new `InkObjects.swift`, `InkCommands.swift`; `InkCapture` (state
   updated by explicit commands, no diff). Tests: selection by rect and polygon
   (touching; stroke across a break selects the family); identity preserved
   through each command for stroke, shape, image; hidden overflow moved and
   recoloured with the shown piece; 5,000-stroke cost bounds like
   `PageViewTests.openingCost`. Mutation: per-element `updateOrAppend` fails the
   cost bound; a recolour that drops `id` fails the identity test.
3. **Rectangular and lasso select for ink, on the overlay.** `InkSelectionOverlay`,
   `SelectionGestures`, the Select tool replacing the lasso (`InkToolKind`,
   `InkToolbar`, hotbar button, options row with Lasso/Rectangle, a command bar),
   canvas non-interactive while selecting, drag preview and commit, own undo.
   Files: new `InkSelectionOverlay.swift`; `DrawingCanvas`, `InkTool`,
   `InkToolbar`, `PageView` (overlay slot), `EditorMode`, `NoteEditor`.
   Tests: input ownership (the canvas takes no touch while Select, the overlay
   none with another tool, `HotbarLayoutTests`-style host); drag moves and commits
   once; undo/redo through pen, eraser and select in order. **Device:** drag at
   1.25x and 3x, in print layout, the Pencil. Needs `HotbarUITests` run.
4. **Text range selection and recolour.** The shape also collects text ranges
   (`CaretFormatting`-style per-line ranges from layout fragments), the overlay
   draws them, and the recolour control applies to ink and text together
   (`MarkdownFormatting.style` per range, through `replace(_:withText:)`, one undo
   step). Files: `NoteEditor`, `MarkdownFormatting+Style`, `TextOptionsRow`
   (shared colour control), `InkSelectionOverlay`. Tests: ranges from a rectangle
   on a rendered note equal the glyphs inside it (against layout, not offsets);
   code and locked notes refused; one undo step; edit works with
   `isEditable == false`.
5. **Tool-switch and previous-tool rules.** Selection clears on tool, mode and
   note change; `returnToPreviousTool` setting and its Settings › Drawing row;
   Insert's select-then-return. Files: `NoteEditor`, `DrawingSettings`,
   `AppSettings` (key pinned in `SettingsTests.keysAreStable`), `InkInsert`.
   Tests: each ending, with and without the setting; a tool switch never
   returns; the old behaviour (stays) when the setting is off.
6. **Remove PaperKit's selection.** Drop `PKLassoTool` from `pencilKitTool`,
   `insertIntoInk`'s lasso, `releaseTwoFingerDrags` if step 0 shows it
   unneeded; the delegate clears foreign selections; "Edit" bridges a single
   shape or image to PaperKit. Files: `InkTool`, `InkInsert`, `NoteEditor`,
   `DrawingCanvas`, `EditorMode`. Tests: a canvas whose selection is set by
   PaperKit is emptied; the hotbar frame is the same before and after a move
   (the displacement check from step 0, now asserted if reproducible).
   AGENTS.md and the plan are updated.

Steps 1 and 2 are file-disjoint from every other stream. Step 3 touches
`PageView`: sequence it after P's changes there.

## Step 0, as built (21 Oct)

- **Fix:** `NoteEditor.inkTool.didSet` calls `DrawingCanvas.clearPaperKitSelection()`
  when the tool *leaves* the lasso. Leaving only: `insertIntoInk` selects what it
  inserted and then switches to the lasso, which must keep the selection. Tests in
  `NoteEditorTests` (leaving clears, entering keeps, a pen colour change keeps).
  Mutation-checked: with the call removed, `leavingTheLassoClearsTheSelection`
  fails. **Not yet seen on the iPad.**
- **Probe:** `SelectionProbe` (debug builds, off unless launched with
  `-debug-selection-probe`) writes `tmp/selectionprobe.log` in the app container:
  every touch in the window (finger, Pencil or pointer, what it hit), PaperKit's
  selection and began-drawing callbacks, keyboard notifications, who is first
  responder, the text view's inset and offset, the page frame, and the hotbar's
  frame in global coordinates. Each touch's result is snapshotted 0.2s after it
  lifts.
- **Built** for `generic/platform=iOS` (Debug, signed, `BUILD SUCCEEDED`), so the
  loop below works as written; the simulator run of `NoteEditorTests` passes.
- **Run it** (the iPad must be plugged in; `devicectl list devices` shows it
  `available`):

      xcodebuild build -project NoteCode.xcodeproj -scheme NoteCode -configuration Debug \
        -destination 'generic/platform=iOS' -allowProvisioningUpdates
      xcrun devicectl device install app --device 00008142-000C28EA2109401C <path to NoteCode.app>
      xcrun devicectl device process launch --terminate-existing --device 00008142-000C28EA2109401C \
        com.marcus.NoteCode -debug-selection-probe

  Then: (1) in ink mode with the pen, tap a few strokes close together (the
  cluster highlight), then with the lasso, select and move something, then tap
  empty space; (2) switch lasso → pen with a selection up (should now let go);
  (3) watch the hotbar after the lasso move. Pull the log with
  `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer
  --domain-identifier com.marcus.NoteCode --source tmp/selectionprobe.log
  --destination <file>`.
- **Reading it:** a `selection changed` line with `pkSelection > 0` after a pen
  tap says the pen selects; the line before it has the touch and its view chain.
  The hotbar lines (`hotbar frame`) beside `keyboard…` lines and a changed
  `firstResponder` or `textView inset` say which of the hypotheses above holds.

## Provisional (Marcus to review)

Marcus asked for the work to go on without him (23 Oct), so each question below
was answered with its recommendation and built that way. Anything he changes is
a small edit to the step named.

| # | Question | Taken | Where it lands |
|---|---|---|---|
| 1 | Storage | **A**, container in `drawingData`. **No `ModelFreezeTests` hash change**, though the brief expected one: nothing in the model changes, which is the point of A | step 1 |
| 2 | PaperKit the renderer | Yes; its selection UI only for an explicit single-object "Edit" | steps 3, 6 |
| 3 | Rectangle over text | The characters inside it, one range per line | step 4 |
| 4 | Recolour | One control; ink palette mapped to the nearest text colour | step 4 |
| 5 | Previous tool | Setting off by default; returns after Delete or a tap on empty space, never after a move or a tool switch; Insert too | step 5 |
| 6 | Rectangle selects | What it touches | step 2 |
| 7 | Scale/rotate | Move, delete, duplicate, recolour and a corner-handle scale; rotation through PaperKit's "Edit" | steps 3, 6 |
| 8 | iPad probe first | Not waited for: step 0 is built and its probe is in; the hotbar cause is the one thing that needs the log, so it is the last step and the note says what to read | step 6 |

## Build state (23 Oct, usage limit reached; read this first)

Branch `claude/o-object-system-design-617825`, nothing pushed.

- **Step 0: done, tested** (90d4357). Probe not yet run on the iPad.
- **Step 1: done, tested** (50921a0). `InkContainerTests` plus the scheduler,
  codec and `ModelFreezeTests` pass (27 tests). No model change, hashes
  untouched. Mutation check (writer always wraps → `emptyTableIsLegacy` fails)
  **not run**.
- **Step 2: written, last run 6 of 11 pass.** `InkObjects.swift`,
  `InkObjectCommandTests`. The 5 failures were wrong test expectations (the
  set orders strokes before shapes, so tests now compare against the
  original order); fixed, **not re-run**. `ShapeMarkup` has no `elementID`
  member; use `ElementID(shape.id)`. The 5,000-stroke `cost` test passed
  once; mutation check (per-element `updateOrAppend`) not run.
- **Step 3: written, never compiled together with its tests.** Files:
  `InkSelection.swift`, `InkSelectionOverlay.swift`, `SelectionOptions.swift`;
  edits in `PageView` (overlay slot, `setSelecting`, `selection.clear()` after
  `forgetUndo`), `NoteEditor` (`applySelecting`, `selection`, clears on
  leaving the lasso or ink mode), `DrawingCanvas` (`replaceMarkup`,
  `showPreview`), `InkTool` (`SelectionKind`, `InkToolState.selectionKind`,
  `hasOptions` now always true), `InkToolbar` (lasso row, persistence),
  `InkCapture` (stroke `inkSignature` so a recolour is stored; hidden overflow
  recoloured with its shown piece). `InkSelectionTests` has 12 tests incl.
  recolour capture. Last build error was `RowGroupBackground` being private
  (removed). Expect small compile fixes next.
- **Next step, exactly:** run
  `scratchpad/runtests.sh s3 InkObjectCommandTests InkSelectionTests InkToolHandoverTests NoteEditorTests`
  (runner: builds on simulator `NC-object`, kills only its own child), fix
  compile or test failures, then check `HotbarLayoutTests`,
  `NarrowOptionsRowTests`, `HotbarUITests` (the lasso now has an options row,
  which they may assume absent) and the cost tests in `PageViewTests`
  (`InkContent.fingerprint` now hashes every stroke's colour on each capture).
  Then mutation-check, commit step 2 and step 3 separately.
- **Not started:** step 4 (text range selection and recolour: the probe showed
  `replace(_:withText:)` works with `isEditable == false`), step 5 (tool-switch
  rules done in part: selection clears on tool or mode change; the
  `returnToPreviousTool` setting, `InkSelection.onEnded` is the hook, is not
  built), step 6 (drop `PKLassoTool` from `pencilKitTool`, `insertIntoInk`'s
  lasso, delegate clearing of foreign selection, "Edit" bridge) and the hotbar
  displacement, which needs the step 0 log.
- **Deviation from decision 4:** the first build keeps `InkCapture`'s diff of
  the canvas as the path into storage (commands change the canvas; capture
  stores the net change) rather than commands acting on stored ink. Undo is a
  markup snapshot per command (`DrawingCanvas.replaceMarkup`). Scaling a stroke
  that crosses a break moves its hidden part by translation only.
- **Unverified on device:** everything in step 3 (touches, drag preview cost at
  zoom, the overlay above the canvas in print layout, the Pencil).

## Questions for Marcus (with a recommendation)

1. **Storage: container inside `drawingData` (A) or a new attribute (B)?**
   Recommend **A**: no schema change, hashes stay as they are, nothing to
   migrate, and old bytes are the new format until used.
2. **Does PaperKit stay the renderer?** Recommend **yes**, for drawing and
   display, with our own selection on top and PaperKit's selection kept only for
   an explicit "Edit" of one shape or image.
3. **What does a rectangle over text select?** Recommend: the characters
   inside it, one range per line crossed (a column, like an editor's
   alt-drag), so a rectangle around part of a heading and a paragraph recolours
   just those words. The alternative, whole lines it touches, is simpler and
   less precise. Which did you mean?
4. **Recolour: one control, two palettes?** Recommend the ink palette
   mapped to the nearest `TextColour` for text, with the text's own legibility
   adjustment. Or separate controls for ink and text?
5. **"Return to previous tool": when, and what default?** Recommend: off by
   default; when on, it returns after the selection ends by Delete or a tap on
   empty space, never after a move or a tool switch. After Insert, the same.
6. **Rectangle selects what it touches** (my recommendation) **or what it
   fully contains?** A later option can add the second.
7. **Scale/rotate:** first release has move, delete, duplicate, recolour and a
   corner-handle scale; rotation and shape-specific editing go through PaperKit's
   "Edit". Acceptable, or must our selection rotate too (a bigger step 3)?
8. **Step 0 on the iPad first.** Can you run a logging build once to find the
   tap-to-highlight tool and the hotbar displacement? Without it we are
   guessing which of them the object system fixes.

## What the spikes showed

`scripts/spikes/object-system-probe.swift` and
`scripts/spikes/text-edit-while-ink-probe.swift`, run on the iOS 27.0
simulator with `scripts/spikes/run-object-system-probe.sh <udid> [file]`.
(Not run on macOS: PaperKit 27's element API isn't on this Mac's macOS 26.)
Numbers are release builds on the simulator, so an iPad's will differ.

- Identity: `applyTransform` keeps `elementID` and `id`; a recolour rebuild
  keeps them **only if `id` is copied**.
- `updateOrAppend` replaces in place (same index, count unchanged).
- A stroke's `allowedInteractions` can't be lowered (reads back as `.all`).
- At 500 / 5,000 strokes: rect select by frame table 0.0 / 0.1ms, by walking
  the canvas 6 / 65–116ms, path test on candidates 2.4 / 26ms; move through
  one rebuild 11 / 127ms against 78 / 1,736ms per element; recolour 11 / 131ms;
  delete per element 81 / 1,994ms; translate whole note 6 / 49ms; save 18 / 200ms.
- A container with our header and PaperKit's bytes: legacy bytes unchanged,
  container refused by PaperKit alone.
- `replace(_:withText:)` edits a text view whose `isEditable` and
  `isSelectable` are false, so text can be recoloured from ink mode.

**Not verified:** anything on the iPad; PaperKit's selection on a pen tap and
whether `…DidChangeSelection` can clear it in time; the hotbar cause; the cost
of assigning `controller.markup` at 5,000 strokes; drag preview at zoom; a
real container saved by the app and read by an older build; undo interleaving.
