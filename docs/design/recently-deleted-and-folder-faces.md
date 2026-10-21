# Recently Deleted and folder faces
v3 phase 1 (12 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **Deleting moves a note to Recently Deleted** (`Page.deletedAt`), from the
  list's swipe and menu, the title menu, and a folder deleted with its notes.
  Nothing asks first; a toast offers Undo for four seconds. `modifiedAt` is left
  alone, so deleting and restoring don't reorder anything, and a note deleted
  twice keeps its first date, so its 30 days don't restart.
- **One rule decides what the reader sees: `Page.isLive`**, or `.live` on a
  collection. The list's sections (`NoteListSections`), search
  (`NoteSearch.results`), `Folder.livePages`, `NewNotes.folder(whileViewing:)`
  and the list's empty state use it; Home and Export All will. The pure types
  filter themselves, so the list can be handed every note and
  `RecentlyDeletedTests` has a test per view that fails when its `.live` is
  removed (each was removed in turn, 12 Oct, and the matching test failed).
  `NoteList` keeps its one unfiltered `@Query`; `RecentlyDeletedView` runs its
  own with `Page.deletedPredicate`, so a note it deletes for good leaves its
  rows in the same update.
- **A folder goes to Recently Deleted when its notes do** (15 Oct, roadmap
  step 7). `Folder.delete(_:_:from:)` with `.withNotes` sets `Folder.deletedAt`
  and gives every *visible* note the same date, so `Folder.restore` knows
  which notes went with it (`Folder.notesDeletedWithIt`: the ones stamped with
  its date; a note deleted on its own earlier keeps its own, older date and
  stays deleted). The folder isn't removed, so the nullify rule doesn't fire
  and the notes keep `folder`. With `.keepingNotes` the folder is deleted for
  good as before: it holds nothing worth bringing back, and the notes move to
  the top of the list.
  - **`Folder.isLive`/`.live` is the rule for folders**, as `Page.isLive` is
    for notes, applied inside the pure types (`NoteListSections`,
    `HomeSections`, `NoteExportJob.layout`) so Move to Folder, Home's tiles and
    Export All can't show one. The list's empty-state check and Export's
    disabled check use `.live` at the call site.
  - **Restoring one note of a deleted folder** puts it at the top level
    (`Page.restore` clears a folder that isn't live): it must not sit in a
    folder nobody can see.
  - **The sheet shows the folder as one row** (badge, name, "3 notes · Deleted
    today · 30 days left"); the notes that went with it
    (`Page.isDeletedWithFolder`) have no rows of their own. Delete Now on it
    removes the folder and those notes (`Folder.deleteForGood`); Delete All
    takes folders first so no note is deleted twice. Purging does the same.
  - The toast's Undo on a folder restores it with its notes.
- **Restoring** a note clears `deletedAt`: back to its folder if the folder is
  live, else the top level.
- **Purging** is `Page.purgeExpired`, once per launch from `ContentView.task`,
  *after* the Welcome note's check. A store holding only deleted notes has been
  used, so that check counts them too. It goes through `Page.delete`, which
  reads nothing from a note. Notes older than 30 days (`Page.retention`) go.
  The row's "days left" is `elapsed / 86,400` floored, so 30 on the day.
- **The view** is a sheet from a row at the list's foot, shown only when it has
  notes (`RecentlyDeletedView`): Restore and Delete Now by hold or swipe, and
  Delete All… asking first. Delete Now doesn't ask, as on the `Library` board.
- **The toast** (`ToastCenter`, `ToastView`, `ToastOverlay`): one at a time, a
  new one replaces the last and restarts the clock. The list draws it at its
  foot when the list is showing, and the open note's page draws it above the
  hotbar when the list is away (`pageToastInset`; the hotbar's thickness plus
  12pt around it when docked at the bottom). Phase 8 reuses it for Copied,
  Exported and Imported. VoiceOver is told when it appears. The Undo pill looks
  28pt and is 40pt tall to a finger.
  - Undo from the title menu's Delete reopens the note, but only if no other
    note has been opened since.
- **Folder identity.** `Folder.colorName` and `symbolName` are names, not
  colours, so one folder reads right in both appearances. `FolderColor` holds the
  eight colours' tint and symbol per appearance (the brief's table);
  `FolderAppearanceTests` computes the contrast of all 16 pairs, needs 3:1, and
  checks the calculation can fail. An unknown stored name falls back to orange
  and `folder` instead of failing.
  - **The editor** (`FolderEditor`) replaces the name alert for New Folder, a
    folder's Rename and the title menu's Move to Folder › New Folder…: preview,
    name, eight colours, sixteen symbols. Its rules are a pure `FolderDraft`
    (`apply(to:moving:in:)`). Renaming a note from the list is still an alert.
  - `FolderBadge` is the symbol on its tint, 26pt in the list's rows.
- **Duplicate** (`Page.duplicated(in:)`) copies text, ink, orientation, paper,
  Markdown layout, text size, folder and run destination, and leaves the pin and
  lock behind. A copy of a note with the old layout keeps it, since its ink
  depends on the layout it was drawn on.
