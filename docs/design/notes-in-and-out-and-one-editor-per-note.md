# Notes in and out, and one editor per note
v3 phase 7 (14 Oct, `docs/archive/ui-design-v3-implementation.md`). The pure parts are
`NoteInterchange.swift`; the model-touching parts are `ExportAll.swift` and
`ImportFiles.swift`.

- **Share ▾** (`NoteShareButton`) is a `Menu` with a primary action, as the
  list's + is: a tap shares the PDF as before, holding shows PDF, Markdown, Copy
  as Markdown and Print… (the same `printNote` as ⌘P). The `.md` is
  `NoteMarkdown.data(for:)`, the note's text byte for byte ("Markdown export
  equals `content`"): no title heading is added and line endings aren't
  touched. The text comes from the text view, as the PDF's does, so the last
  keystrokes are in it (`NoteEditor.currentText`); hiding markers is layout
  only, so the storage holds the Markdown as typed. Copy shows the Copied toast.
- **File names** are `NoteFileName.stem(for:)`, which `NotePDF.fileName` now
  uses too: `/ \ :` become `-`, a leading `.` goes (or the file would be
  hidden), control characters go, 80 characters at most, never blank.
- **Export All Notes…** is in the list's ••• and Settings › Notes (a pushed
  page there, a sheet from the list: `ExportAllView` is both). `NoteExport.plan`
  decides the layout before anything is written: a subfolder per folder
  (empty ones too), an `.md` per note, names made unique within a directory
  ignoring case (`Name`, `name 2`, `Name 3`), oldest note first so a re-export
  names the same notes the same. The top folder is `NoteCode 2026-10-14`.
  Notes in Recently Deleted are left out because the view hands the job
  `pages.live` (`deletedLeftOut` passes the live ones; it can't see a missing
  `.live` in the view, which is a one-word change to check by eye).
  - **A PDF is added only for a note that has ink.** The brief says "optional
    PDFs with ink"; the canvas's tree shows a PDF beside one note of three. A
    text-only note's PDF would repeat its `.md`. The toggle is on by default,
    as on the canvas, and not stored (a new key would be one more for phase 8
    to pin). The PDF is made from the *stored* ink (`DrawingCodec.decode` of
    `drawingData`) and the note's own layout, so it breaks lines where the
    screen does. Ink the open note drew in the last moments may still be on
    its way into the store (`DrawingSaveScheduler`'s pause), so a PDF of the
    note being drawn on can miss its latest stroke; not handled.
  - **Written to a temporary folder, then handed over.** `NoteExportJob` writes
    one note per turn of the main actor (so the progress bar moves and Cancel
    can be tapped), then `fileExporter` takes a directory `FileWrapper` made
    from that folder with `FileWrapper(url:)`, which reads the files as they
    are copied rather than holding them. Cancelling, leaving the page, a
    failure and finishing all remove the folder. Progress reads "Exporting n of
    N". `generation` keeps a cancelled run that is still unwinding from
    clearing a newer run's folder; **no test fails without it** (tried: the
    guard removed, `restartAfterCancel` still passed), so it is reasoning, not
    proof.
  - **`FileDocument` is deprecated in iOS 27** (the SDK says to conform to
    `WritableDocument` or `Transferable`). `ExportFolderDocument` is a
    `FileDocument` anyway: a directory wrapper is the long-standing way to
    export a folder. The plural-`contentTypes` overload is the one with an
    `onCancellation` callback (the singular one has none). Whether the
    iPadOS Files picker writes the whole folder is not checked (below).
  - Toast "Exported N notes" after the reader has chosen where; Settings
    dismisses itself first (`onExportFinished`) so the toast isn't under it.
- **Import…** is on Home (beside From Template, in both states) and in the
  list's •••, through `.fileImporter` on `ContentView`. `NoteImport.note` turns
  a file into `(title, content)`: `.md`, `.markdown` and `.txt` as written (line
  endings made `\n`, a BOM dropped); a source file as **one fenced block
  tagged from its extension** (`cpp cc h hpp` → C++, `c`, `java`, `py` →
  Python, `js`, `rs`, `go`, `sql`). `.h` is C++, not C, since the course is C++.
  The fence is one backtick wider than any run starting a line in the code,
  because the parser closes a block on a bare fence at least as wide as the
  opening one (`fenceInsideCode`); the content ends after the closing fence
  with a newline so there's a line below the block. Title is the file name
  without its extension.
  - `Page.importFiles` goes through `Page.create` (so a new note's orientation
    from Settings › New Notes and the rendered layout), in
    `NewNotes.folder(whileViewing:)`, with security-scoped access opened and
    closed around each read. A file that isn't a supported kind, can't be read,
    is over 2MB (`NoteImport.maxBytes`: a log would lay out for minutes) or
    isn't text (a NUL byte, or bytes that aren't UTF-8 or UTF-16 with a mark) is
    skipped with its reason and the rest come in; the reasons show in an alert.
  - One file imported is opened; several stay in the list. The toast reads
    "Imported 3 notes into CS133", or "Imported 3 notes" at the top level.
    Existing notes' dates and text are untouched (`otherNotesKeepTheirDates`).
- **One editor per note** (`OpenNoteRegistry`, `WindowToken`).
  `UIApplicationSupportsMultipleScenes` is already `YES` in the built plist,
  so a second window is possible and nothing stopped it selecting a note the
  first had open; both would write it and the later save would win. Now each
  window's `ContentView` holds a `WindowToken` and **claims** the note it
  selects; a window that selects a note another holds shows "Open in Another
  Window" (`OpenElsewhereView`, with Go Home) in place of `PageDetailView`.
  - **Keys, not notes**: a claim is a `NoteMemory.key(for:)` string, which two
    contexts' copies of one note share (`keysAreSharedAcrossContexts`) where
    the objects don't compare. A new note's temporary ID has no key, so it's
    saved first (`settledID`), as `NoteMemory` does.
  - **A claim names its window weakly.** A discarded scene never says so, so a
    claim whose token has gone doesn't count (`windowGone`), and the token's
    `deinit` asks the registry to sweep so a window waiting on the note sees
    it free. A window that sees the other let go claims the note itself
    (`onChange(of: isOpenElsewhere)`).
  - Not the fallback (multiple windows off): the guard is built, so the plist
    is untouched.
- **Tests** (`NoteInterchangeTests`, 44): the Markdown file equals the text; the
  plan's folders, collisions, empty folders and tree; every extension's tag and
  that the result parses as one block in that language; titles; the files
  written by a real job, read back through its wrapper, with and without PDFs;
  the registry. Mutation-checked on 14 Oct (each fails with the rule removed):
  unique names, the wider fence, the registry's first-claim rule. Not
  mutation-proven: `generation` (above).
- **Not checked, at all, on screen:** the Share menu's hold, its items and the
  share sheet for `.md`; Copy as Markdown's toast; Home's Import button and the
  list's two new menu items; the Files picker for Import, a real file coming
  in, and the alert for a skipped one; Export All's sheet, its progress and
  Cancel; **`fileExporter` writing the folder** on the iPad (and what the Files
  app shows: a folder of the right shape, PDFs readable); Settings › Notes ›
  Export All Notes… and the toast after it; a second window showing "Open in
  Another Window", and it letting go when the first closes (the simulator
  tools can't open a second window; Stage Manager or Split View on the iPad
  can). The simulator's screenshots stopped updating partway through a first
  look (14 Oct), so none of this was seen.
