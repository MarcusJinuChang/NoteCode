# Insert and templates
v3 phase 5 (13 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **Insert is PaperKit's own popover** (`InkInserter`, `InkInsert.swift`): a
  button after the ink tools, not a tool (`InkToolKind` stays the four
  PencilKit tools, so no `switch` over it grew a case). It presents
  `MarkupEditViewController(supportedFeatureSet: .latest, additionalActions:
  [Photo…])` from UIKit, like `InkColorPicker`, and is the controller's
  delegate. Not in the Pencil's squeeze palette, where it would be a popover
  from a popover.
  - **Probed, so it isn't probed again** (`InkInsertTests`). The canvas's own
    controller, called through that delegate, tells the canvas's delegate once,
    registers one ink undo, selects what it inserted, and puts it at the middle
    of `contentVisibleFrame`, ignoring a frame it is handed (the size is kept).
    That middle can be a margin or a break, so `DrawingCanvas.inserting(around:_:)`
    sets the visible frame to one centred where the page wants it, runs the
    insert, and puts it back. `InkInsertion.centre` picks the point: the middle
    of the screen, moved into a page's `inkRegion` and, where the element fits,
    kept wholly on one page. Without it, print layout put 16% of inserts in a
    margin the covers hide.
  - **The lasso is selected after an insert** (`NoteEditor.insertIntoInk`),
    so the new element can be moved at once. Not seen on a device: whether
    PaperKit's selection takes a drag while the pen is the tool is open.
  - **Photo…** is `PHPickerViewController` (out of process, no permission or
    Info.plist string), not SwiftUI's `PhotosPicker`, which would need state in
    `PageDetailView` to present from a hotbar button. The file is decoded in the
    picker's callback with ImageIO's thumbnail (`InkInsertion.downscaled`: at
    most 2 pixels to a point of page width, turned upright, never enlarged),
    since the file is gone when the callback returns. Shown at most 60% of the
    page's width, and inserted through the controller's `insertNewContents`.
  - **`InkCapture` told changes by frame alone**, so a shape recoloured or a
    text box retyped where it stood was never stored. A text box is a
    `ShapeMarkup` with `attributedText`. `InkContent.fingerprint` hashes what a
    shape or image looks like apart from where it is, kept in
    `InkCapture.State.contents` beside `shown`. An element with no record is
    taken as unchanged, so nothing but a real change re-stores (and
    re-converts) an element. Fails without it: `editInPlaceIsCaptured`.
  - Elements that aren't strokes are never cut (`InkPages`); they move whole by
    their middle's page, as before. Saving, a mode switch, undo and the PDF are
    tested with a shape, an ellipse, a text box and a photo
    (`survivesSavingAndPrinting`, `shapeFollowsTheModes`, `insertIsUndoable`).
- **Paper was postponed until after v3** (14 Oct, decided by Marcus) and is
  built now, differently: see `paper-styles.md` (vector layers, not tiles). Dots and
  grid (a per-note `Page.paperStyle`, drawn behind text and ink in each page's
  body) were built and came out slightly offset or broken in compressed and
  print layout, so the whole system waits and none of it is in the app.
  `Page.paperStyle` left the model on 15 Oct; add it back with the feature. What the first
  attempt found, for whoever picks it up: paper must lay nothing out; a
  pattern `backgroundColor` on a bare `CALayer` draws its tile upside down
  while a `UIView`'s draws upright; and print layout's covers hide anything in
  a band, so a pixel test can't see paper leaking there, only geometry can.
- **Templates** (`NoteTemplates.swift`: `NoteTemplate` lecture, problem, lab;
  `Page.create(from:)`). Text only, like the Welcome note, the contents of the
  `InAndOut` board. Bracketed words are placeholders and not links (a link needs
  its parenthesis, and no template has one: Problem's was `[link](https://)`,
  which opened Safari's start page, and is now `Link: [URL]`). A placeholder
  is not selected on opening: the new note opens with its title being renamed,
  and selecting text in the editor on open would take the caret from that. The
  note's title is the template's name and it opens ready to rename. The code
  block is tagged with the language most of the **open note's folder's live**
  notes' blocks are in (ties to the earlier language in the menus; Recently
  Deleted notes don't vote: `deletedNotesDontCount`), else C++. Offered from
  + › From Template › (in the open note's folder, in Settings › New Notes'
  orientation) and on Home, in both its states.
- **The Insert button's highlight follows the popover itself**, not the
  delegates' callbacks (14 Oct): a tap outside while one of PaperKit's nested
  pickers was up left the button lit and the popover unopenable until the note
  was left. `InkInserter` watches its controller's `presentingViewController`
  and checks it again on every tap (`popoverStateFollowsTheController`).
- **Not checked on a device or at all:** dragging an inserted element with the
  Pencil or a finger; From Template on Home and in the + menu on screen; the UI
  tests (`HotbarUITests`) were not run for the extra button.
