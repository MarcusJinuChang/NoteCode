# Organising notes
A flat, date-sorted list of pages does not survive a semester of coursework,
so notes file into folders by class — CS133, algorithm practice (built 3 Oct).

- **One folder per note, or none** (decided 3 Oct). `Folder.pages` is
  to-many with a nullable inverse, `Page.folder`, so a note can sit at the top
  of the list. Several folders per note would make "move" and deleting a
  folder with its notes ambiguous, and grouping by class doesn't need it.
  Folders nest since 16 Oct (below).
- **Folders open and close in place** in the list (`NoteList`), rather than
  leading to a column of their own: the list slides over the page, and a
  second column would cover more of it. Open state is per launch.
- **Folders nest, are arranged by hand and can be dragged** (16 Oct, roadmap
  step 8, decided by Marcus: a folder can go inside another, a note dropped on
  a folder is filed in it, and folders can be rearranged). This reverses
  "folders don't nest".
  - **Model.** `Folder.parent` and `.subfolders` (a self-relationship, both
    optional for CloudKit) and `Folder.sortIndex`, the reader's order among
    the folders of one parent. `Int.max` is "never arranged": it sorts after
    every arranged folder, by name, so a new folder lands last and an
    untouched level stays in name order. `Folder.move(_:into:at:among:)`
    places a folder and renumbers the level it joined (and the one it left, if
    that one was arranged). `canMove(into:)` keeps a folder out of its own
    subtree and is checked by every route in.
  - **Depth is unlimited**; the list indents up to six levels. A pinned
    folder is listed in Pinned and not again in its parent. Notes keep the
    reader's sort; only folders are arranged.
  - **Deleting.** With its notes, a folder, every live folder below it and
    every live note in any of them go to Recently Deleted under one date
    (`Folder.deletedTogether`); only the top one has a row there
    (`isDeletedWithParent`), and its count and Restore cover the group.
    Restoring a folder alone whose parent is deleted puts it at the top level.
    Keeping its notes, what was in the folder (notes *and* folders) moves up
    one level, to the folder's own parent. Delete Now takes the group once,
    however many of its members are handed in.
  - **Elsewhere.** Run destinations are inherited down the folders
    (`Page.runDestinationLevels`); Home shows top-level folders, counting what
    is inside; Export All writes `CS133/Labs` as nested directories
    (`NoteExport.plan(folderNames:parents:items:)`); Move to Folder lists every
    folder by its path ("CS133 › Labs"); a folder's menu has New Folder
    Inside and Move To, which reach everything dragging does.
  - **The list** (`NoteListRow`, `folderTree`) draws folders and what is open
    in them as one flat run of rows, so each can be lifted and dropped on. The
    arrow is on the left, its own 44pt target; a tap on the row does what the
    arrow does. Open state is per launch.
  - **Dropping** is `ListDrop.resolve`, pure and tested: a note on a folder, or
    beside another note, is filed in that folder; on the Notes header, taken
    out of its folder. A folder on the middle of a folder goes inside it; on the
    top or bottom 28% of the row it is arranged before or after it, among that
    folder's siblings; on the Folders header it goes to the top level. Nothing
    into its own subtree, a pinned folder only takes things into it. A moved
    note keeps its date. The drag carries only a marker
    (`ListDrop.payload`, own-process, the type declared in Info.plist); which
    row was lifted is `ListDragState.item`, so a drop from elsewhere is refused.
  - **NOT TRIED: the drops themselves.** In the simulator a drag lifts and its
    preview follows the touch, but neither `.onDrop(of:delegate:)` (on rows and
    on the whole list) nor `.dropDestination` was ever called, for a custom type,
    `.item` or plain text (synthesised touches: the drag started at the lift,
    which logged twice, and never reached a target). So whether a drop lands,
    and the line or outline `ListRowDrop` draws for where, is unverified on
    screen and on the iPad. The rules behind it are tested, and the menus
    do the same moves. If the drops don't work on the iPad, the first thing to
    try is `dropDestination(for:)` with a `Transferable` token, which reports
    only the whole row (no before or after) and would want separate edge views.
  - **A press on a row** shows its context menu; a drag lifts it after about
    half a second if the finger moves at once. A hold that stays still gets the
    menu.
- **Deleting a folder asks** whether its notes go too, or move to the top.
  `Folder.delete` saves at once, like `Page.delete`. "Go too" means Recently
  Deleted now, not gone for good (see "Recently Deleted").
- **Moving a note isn't an edit.** It keeps its date modified, or filing a
  week of notes would make them all look written today.
- The list's grouping and order are pure (`NoteListSections`): folders sort
  in the reader's order (name, numbers compared as numbers, until arranged by
  hand) and notes by the reader's sort.

- **Pinned goes to the top** (3 Oct). Pinned folders and pinned notes, from
  any folder, sit in a Pinned section above the folders. A pinned note is
  listed there and not again in its folder, so no note has two rows (a
  selectable list would highlight both), and a folder's count is the notes
  under its own row; a pinned note's row names its folder instead. Pinning,
  like moving, isn't an edit and keeps the date.
- **Sorting is per device** (`NoteSort`, `@AppStorage`, 3 Oct): date
  modified, date created or title, either way round, and picking a key picks
  the way round that reads naturally — newest first, A to Z. It orders notes
  in every section; folders stay in the reader's order. Rows show the date the list
  is sorted by. Ties fall back to title, then creation, so the order never
  shuffles between launches.
- **The list's toolbar holds two items**, ••• and +. Edit and Sort By share
  the ••• menu on iPad, and Done takes its place while editing: with Edit,
  Sort and New side by side, the sidebar had no room left for its title.
- **The + is a `Menu` with a primary action** (12 Oct, phase 8 of
  `docs/archive/ui-design-v2-implementation.md`). A tap makes a note in Settings ›
  Notes › New Notes' orientation (`NewNotes`, key `newNoteOrientation`,
  portrait until chosen); holding it shows Portrait Pages, Landscape Pages and
  New Folder. A note made from either goes in **the open note's folder**
  (`NewNotes.folder(whileViewing:)`), or the top of the list with no note open:
  the list has several folders open at once, so "the open folder" had to mean
  something, and this is where a student working through a class's notes is.
  All creation goes through `Page.create`, so the tap, the menu and the folder
  menu can't disagree about what a new note is.
- **The note menu is the title menu**: `NoteTitleMenu` is used by both, and the
  list passes `onRename` where the title uses the system's `RenameButton`, so
  rows and order can't drift. The list's Rename asks in the name alert
  (`FolderNaming.renamePage`) and moves the date, as renaming from the title
  does. Delete still doesn't ask in the list, as before.
- **The selected row is the accent tint** (`RowSelectionTint`, 18% light, 22%
  dark) set with `listRowBackground`, label-coloured text. Seen in the
  simulator: it replaces the system's solid highlight rather than sitting
  under it. Light only; dark not looked at.
- **Empty states.** No notes and no folders: `ContentUnavailableView` with New
  Note and Open Welcome Note. A folder with nothing in it shows a "No Notes"
  row that can't be selected. No search results was already
  `ContentUnavailableView.search`.
- **The Welcome note** (`WelcomeNote`) is plain text, no seeded ink. It is made
  on first launch (`ContentView.task`, flag `welcomeNoteMade`), **only when the
  store has no notes and no folders**: the brief said "first launch", and a
  build that updates over a semester of notes isn't one. The flag is set
  either way and never cleared, so deleting the note doesn't bring it back. Not
  made when storage is in-memory (the flag would claim a first launch happened)
  or under a debug launch's note. Settings › Help and About › Welcome Note, and
  the empty list's Open Welcome Note, make a **new** note each time and open
  it. Making one writes nothing to any other note
  (`NoteListFirstRunTests.otherNotesKeepTheirDates`).
- **The launch screen is the system background and nothing else**:
  `INFOPLIST_KEY_UILaunchScreen_Generation` writes an empty `UILaunchScreen`,
  already the case; `AppStoreReadinessTests.launchScreenIsPlain` pins it.
- **Note info is derived, never stored** (3 Oct). `NoteInfo` works out
  words and code blocks by language from the text, through
  `DocumentParser`, each time the sheet opens: nothing to keep in step
  with typing, and no model change. Code isn't words, and markdown markers
  around prose aren't either. Get Info in the list's note menu leaves out
  the page count, since only a laid-out note knows it (`PageView.pageCount`)
  and laying out a closed note costs what opening it does; the info button
  in an open note's header adds it. The sheet is a standard form sheet with
  two closely spaced sections, which holds every row for code in up to
  three languages. Page size left most of the sheet empty, and
  `.presentationSizing(.form.fitted(...))` collapsed it to its title bar,
  since a Form reports no height of its own (measured 3 Oct).

- **Search is every word, anywhere** (4 Oct, `NoteSearch`): each word
  typed has to be in the title or the text, in any order, ignoring case and
  accents and word boundaries. Results replace the sections while the field
  holds words, as one flat list: title matches first, then the reader's
  sort, since a search is for one note and sections of one row each read
  slower. Each row shows the line of its first match. Ink isn't searched.
- **A note opened from a result shows where it matched.** `ContentView`
  takes the search as the selection changes, not live, so typing in the
  field doesn't redraw the note under the list; `PageView.reveal` waits for
  the first layout, lays out down to the first match (as scrolling there
  would), scrolls it a quarter of the way down, and highlights every match
  through the text view's own find decorations (`decorate(foundTextRange:)`),
  which sit on the text at any zoom. The highlights go at the first edit.
- **Find within a note is UIKit's** (`isFindInteractionEnabled`): ⌘F, or
  Find in Note in the header's ••• menu, which switches to text mode first, since
  the text takes no selection while ink has the page.

Pinning, sorting, note info and search needed no model change: the pins
(`Page.isPinned`, `Folder.isPinned`) came in with folders.
