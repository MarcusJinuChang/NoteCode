# Phase 8: note list and first run

Branch `claude/ui-phase-8-list-first-run`, off `origin/main` (phase 7 isn't merged, so
the icon work isn't in this branch). Not pushed.

## What changed

- **+ is a menu with a tap.** Tap makes a note in Settings › Notes › New Notes'
  orientation (portrait until chosen). Hold shows Portrait Pages, Landscape Pages, New Folder.
- **"Inside the open folder" means the open note's folder.** The list can have several folders
  expanded, so I picked the one the reader is working in; with no note open, or an unfiled one,
  the note goes at the top. Tell me if you meant something else.
- **The note menu is the title menu.** Same view (`NoteTitleMenu`), so same rows and order.
  The list has no title to edit in place, so Rename asks in the name alert.
- **Selected row**: accent at 18% (light) / 22% (dark) behind label-coloured text.
- **Empty states**: no notes → New Note, Open Welcome Note; empty folder → a "No Notes" row;
  search already had `ContentUnavailableView.search`.
- **Welcome note**: once on a first launch, then Settings › Help and About › Welcome Note makes
  another. Plain text, no seeded ink.
- **Launch screen**: it was already the system background (empty generated `UILaunchScreen`);
  a test now pins it.

## Decisions to check

- The Welcome note is made only when the store has **no notes and no folders**. The brief said
  "first launch"; a build installed over existing notes isn't one. The flag is set either way.
- "Open Welcome Note" in the empty list makes a *new* copy (the first launch's is gone if the
  list is empty), same as Settings.

## The mechanics (for learning)

- `Menu { … } label: { … } primaryAction: { … }` gives a button whose tap runs the primary
  action and whose long press shows the menu.
- `listRowBackground` replaces the row's background *including* the system's selection
  highlight, which is why the tint works; the text colour stays `.primary` because nothing
  turns it white any more.
- `NoteTitleMenu` takes an optional `onRename`: nil means "use the system's `RenameButton`",
  which only works under a `navigationTitle` binding.
- The flag lives in `UserDefaults` rather than the store because nothing in the model needs to
  change (the store stays at version 6).

## Tests

`NoteListFirstRunTests` (new, 12 tests): the New Notes default and key, the + tap's orientation
and folder, the Welcome note's text, once-only (and failing if the flag is never set, checked by
mutation), existing notes/folders, other notes' dates untouched, title rename, tint values.
`AppStoreReadinessTests.launchScreenIsPlain`. All 700 unit tests pass; iPad and Mac build.

## Checked / not checked

Checked in a fresh simulator: first launch makes the note and it renders; the selected row's
tint; a + tap makes a portrait note and opens it. **Not checked:** the hold menu, Rename from the
list, empty list and empty folder, dark mode, Landscape via Settings, the Mac, and whether a
new note's title starts renaming (unchanged from phase 3, which flagged it unchecked).

## Your checklist

1. Fresh install: the list shows "Welcome to NoteCode"; delete it, relaunch: it doesn't return.
2. Settings › Notes › New Notes › Landscape; tap +: a landscape note. Hold +: both orientations and New Folder.
3. Open a note in a folder, open the list, tap +: the new note lands in that folder.
4. Long-press a note: Rename, Pin, Move to Folder, (Remove from Folder), Lock Text, Get Info, Delete, same as the title menu. Rename works.
5. Delete everything: New Note and Open Welcome Note both work. Make an empty folder: it says "No Notes" and the row can't be selected.
6. Selected row: tinted orange, text stays dark in light and white in dark. A bug would be solid orange or white text on a pale tint.
7. Settings › Help and About › Welcome Note makes a new note and opens it; other notes' dates don't change.
