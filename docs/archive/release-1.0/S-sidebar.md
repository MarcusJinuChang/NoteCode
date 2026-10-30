# S. Sidebar

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## S1. Drag to Recently Deleted; quicker, smoother drag

**Do.**
- Recently Deleted's row in the sidebar takes a dropped note or folder:
  `Page.moveToRecentlyDeleted` for a note, and for a folder the same as its
  menu's Delete does today (find it; don't invent a second path). It goes
  through `ListDropBridge` (`NoteListDrop.swift`), since a `List` delivers no
  drop to SwiftUI modifiers (see `design/organising-notes.md`).
- Shorter hold before a drag lifts: the list's drag begins from the
  collection view's long press; lower its `minimumPressDuration` to about
  0.25s if the bridge can reach it, and say what it was.
- Smoother: one probe run with `-debug-probe` (what the drop delivers and
  when) to find any frame-long stall; fix only what it shows.

**Done when.** A test in the drop suite moves a note and a folder to Recently
Deleted through the bridge's entry point; the note is in Recently Deleted and
saved (re-fetch). iPad checklist: drag a note and a folder onto Recently
Deleted; hold time feels short; nothing jumps while dragging.
**Read:** `design/organising-notes.md`, `design/recently-deleted-and-folder-faces.md`.

## S2. A shorter long-press menu

**Do.** List every item in the note and folder context menus in the PR, then
remove what's duplicated elsewhere (drag now moves and deletes, so "Move to…"
can go to a submenu or stay only as an accessibility path; Share and Export
can merge; Rename stays). Target: at most six top-level items each, grouped
with dividers. Put the before/after list in the PR for Marcus to veto.
Accessibility: anything removed from the menu must still be reachable
(VoiceOver drag is not reliable), keep it in an `accessibilityActions` or a
submenu.

**Done when.** The before/after list is in the PR; UI test not required.
