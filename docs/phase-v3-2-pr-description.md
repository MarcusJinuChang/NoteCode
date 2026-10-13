# v3 phase 2: title screen, Home, thumbnails, reopening at the last page

Branch `claude/v3-phase-2-home`, off `claude/v3-phase-1-recently-deleted`
(phase 1 isn't merged yet, so this stacks on it).

## What changed, and how it works

**Title screen** (`WelcomeScreen`). It's an *overlay* on `ContentView`, not a
`fullScreenCover`. A cover's own slide can't be told to fade, and Reduce Motion
has to; an overlay lets us choose the transition (`.move(edge: .bottom)` or
`.opacity`). The first launch is decided by the flag `welcomeScreenShown`,
which is set the moment the screen's turn is *claimed*, shown or not (the same
idea as `WelcomeNote.madeKey`). Settings › Help and About › Welcome Screen
shows it again. It isn't tied to an empty store, so a build that updates over
real notes shows it once.

**Home** (`HomeView`, `HomeSections`). `ContentView`'s detail is now Home
whenever no note is selected, and the app starts with the list hidden (`.detailOnly`);
☰ brings the list over it, as it does over a note. `HomeSections` is pure, like
`NoteListSections`: Continue (the note opened last), Recent (the next 8 by date
modified), Folders (tiles with live counts). Deleted notes appear nowhere; a
test fails without the `.live` filter. When there are no live notes, Home shows
its empty state. New in the list: a Home row at the top, and ⇧⌘H.
A folder tile opens the list with that folder open and scrolled into view
(a new `ListRequest.showFolder`).

**NoteMemory** (per device, `UserDefaults`, keyed by persistent ID). It keeps the
note opened last and each note's place as `[page, of]`. "Page 3 of 5" is *stored*
because only a laid-out note knows its page count, and laying out a closed note
costs as much as opening it. Two traps I hit, both now tests:

- `JSONEncoder` doesn't write keys in a fixed order, so one ID gave different
  keys on different calls. Places were never found, and thumbnails stayed blank.
  The fix is `.sortedKeys`.
- A `PersistentIdentifier` decoded from JSON compares `==` to the original but
  wasn't found in a `Set`. So everything is matched by *key*, never by decoding.

**Reopening.** `PageDetailView` reads the place as the note opens;
`PageView.restore(toPage:)` waits for the first layout (as `reveal` does), lays out
only down to that page, and scrolls to `scrollTop(forPage:)`. The page reports
its own place as the reader scrolls (only when the page or page count changes),
held back until the restore has run so opening at page 4 never writes page 1.

**Thumbnails** (`NoteThumbnail`, `ThumbnailStore`, `NoteThumbnailView`). They're drawn the
way the PDF draws a sheet, in light appearance, from a *prefix* of the note (80
paragraphs or 8,000 characters), never the whole note: a 2,000-line note takes 9ms
with the prefix and 333ms without. They are cached in Caches under
`<hash of ID>-<modifiedAt in ms>.png`, so a new date is a new name and no file
timestamp API is needed (no privacy-manifest change). They're made one at a time,
yielding between each, and a card that scrolls away cancels its request.
`NotePDF.drawInk` gained a resolution parameter: a sheet's ink at print
resolution is 31MB, too big for a 30pt thumbnail.

**Debug launch.** `-debug-first-launch` and `-debug-home` (in the table in AGENTS.md).

## Tests

New: `NoteMemoryTests`, `HomeSectionsTests` (Home sections, dates, excerpt, the title
screen's flag), `NoteThumbnailTests` (prefix, cache names, pixels, ink on page 1 and
not page 3, cost, the store's cache, deletion, queueing, cancelling), `ReopenTests`
(the line at the top against a note laid out from scratch, in every mode and
orientation; the first report; scrolling reports), and additions to
`DebugLaunchTests` and `NoteShortcutTests`.

Mutation checks (revert the fix, watch the test fail), done 12 Oct: the `.live`
filter in `HomeSections`; `.sortedKeys`; the thumbnail prefix; the guard that holds
back reports until the restore has run.

## Checked on screen, and not

Looked at in the iPad Pro 13-inch simulator: Home in light and dark with sample
notes (thumbnails drawn, "Page 3 of 5"), the title screen in light, and tapping
Continue's Open reopening the note at the first line of page 3.

**Not checked:** the Pencil; Reduce Motion's fade; the title screen in dark; Get
Started, the Home row, a folder tile, Show All and the toolbar by a tap (my taps on the
title screen weren't landing because the tool's coordinates are portrait-space while
the app was landscape; I stopped there rather than overrun the time-box); ⇧⌘H (the
simulator can't send chords: nothing in `NoteShortcut` uses it, and I know of no
system use of ⇧⌘H on iPad or Mac); portrait and 11-inch layouts; a thumbnail updating
after an edit while visible; a thumbnail of a note with ink on the iPad.

## Marcus's checklist (iPad)

1. **Fresh install.** Delete the app, install, launch. *Expect* the title screen, then Get Started shows Home with the Welcome note under Continue. *Bug if* the title screen appears again on relaunch.
2. **Home, light and dark.** *Expect* cards with page thumbnails (text, code panels, colour), folder tiles with their colours, and New Folder's dashed tile. *Bug if* a thumbnail stays a blank white box after a few seconds, or text looks shaded or glowing.
3. **Continue.** Open a long note, scroll to page 3, go Home (list row or ⇧⌘H). *Expect* "Page 3 of N". Tap it. *Expect* it opens at page 3's first line. Scroll to page 5, kill the app, relaunch, open it: page 5.
4. **Thumbnails.** Write in a note, open the ☰ list over it. *Expect* its row's picture to update a moment after you stop typing. Draw in a note's first page: its picture shows the ink; ink on page 3 doesn't.
5. **Folder tile.** Tap a tile. *Expect* the list slides over Home with that folder open.
6. **Home row.** In a note, ☰, then Home. *Expect* Home, with the list away, and the row tinted while Home shows.
7. **Settings › Help and About › Welcome Screen** shows the title screen; Reduce Motion on, it fades.
8. **No notes.** Delete everything. *Expect* "Start your first note". Notes in Recently Deleted don't count.
9. **⇧⌘H** with a keyboard: Home. If the system takes it instead, tell me and I'll rebind it.
10. A note with a lot of ink: Home shouldn't stutter while its thumbnail is made.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
