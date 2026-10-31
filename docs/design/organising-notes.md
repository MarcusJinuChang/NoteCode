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
- **One list: a folder is a row among the notes** (24 Oct, feedback #13).
  `NoteListSections.items` is the top level and a section's `items` is what a
  folder holds, folders and notes sorted *together* by the reader's `NoteSort`
  (`NoteListRow.rows(for: items…)` flattens them). The Folders and Notes
  headers are gone.
  - **Provisional (Marcus to review):** nothing puts folders first. A folder is
    dated by its newest note anywhere under it (its own creation date when
    empty) for Date Modified, by its own creation for Date Created, by its name
    for Title; editing a note moves its folder up. Pinned stays a section on
    top, one mixed list of pinned folders and notes (a pinned note isn't listed
    again in its folder). Folders and notes aren't aligned in a column: a
    folder's chevron sits where a note's thumbnail does.
  - **Provisional:** one "Library" header sits above the main list when there
    are folders or a Pinned section, and is the top-level drop target (a note
    dropped on it leaves its folder, a folder goes to the top: the old
    `.topFolders` rule, which handles both). With no folders and nothing
    pinned there is no header.
  - **Provisional, a loss to know about:** hand-arranged folder order
    (`Folder.sortIndex`, dropping a folder on another's top or bottom edge) no
    longer shows, since the sort orders folders. The drop rules, `Folder.move`
    and the tests are untouched and still renumber the level;
    `NoteListSections.folders`, `pinnedFolders` and `children` keep that order.
    A "Manual" sort key would bring it back.
  - Drop reception is unchanged (`ListRowDrop`, `ListDrop.resolve`); only what
    the rows are changed. Still unverified on a real iPad.
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
  - **Elsewhere.** Home shows top-level folders, counting what
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
  - **How a drop reaches the list** (24 Oct, read on Marcus's iPad Pro 11-inch
    on iOS 27.0.1, by a real press and drag from `ListDragUITests` and the
    `-debug-probe` log, `DebugProbe.swift`). The first build put an
    `.onDrop(of:delegate:)` on every row, and **nothing on a row was ever
    called**: the drag lifted and the drop did nothing. The same row-level
    delegate on a row of a `LazyVStack` was called (validate, entered,
    perform), and `.dropDestination` on a stack's view too. Inside a `List`
    none of these was: `.onDrop` on a row or on the list, `.dropDestination`
    on a row, `ForEach.dropDestination`, `onInsert`, with plain text, a
    custom type or `public.data`. A `List` is a `UICollectionView` whose drag
    and drop delegate is SwiftUI's own (`CollectionViewListDragAndDropController`),
    which lifts a row for `.onDrag` and is deaf to those modifiers. The
    collection view's `dropDelegate` is public API, though: a replacement
    that logged was called with `canHandle`, `dropSessionDidUpdate` and
    `performDropWith`.
  - **So the list takes the drop as a whole** (`ListDropBridge`, behind the
    `List` in `NoteList`): it wraps the collection view's drop delegate, answers
    a drag of ours (`ListDrop.type`) from where the rows are, and forwards any
    other to SwiftUI's. Rows only record their frame in the window and draw the
    indicator (`ListRowDrop`); `ListDropHit` (pure, tested) finds the row and
    the zone from the finger's height. What is being dragged is read where
    the drag begins (`ListDragSource`, which wraps the collection view's drag
    delegate the same way): SwiftUI asks for a row's provider when it likes,
    and on the iPad asked for a *folder's* after a note's drag had begun, so
    a drag started by `onDrag`'s closure was sometimes a folder's.
  - **On macOS there is no drop** (the bridge is UIKit): its list drag is
    unchecked and the menus do the same moves.
  - **Checked on the iPad**: a note dropped on a folder files it, and on the
    Library header takes it out of its folder (`ListDragUITests`, which skip
    on the simulator, where no drop is delivered: a drag lifts and follows
    the touch and nothing is entered). **Not checked**: the hover outline and
    edge lines drawn while dragging, folder arranging by the top and bottom
    edge, and dragging near the list's edge to scroll.
  - **Onto Recently Deleted** (26 Oct, release S1): the row at the list's foot
    is a drop target (`ListDropTarget.recentlyDeleted`). A note goes through
    `Page.moveToRecentlyDeleted`, a folder through `Folder.delete(.withNotes)`,
    the same calls as the menus, with their Undo toast; something already
    deleted is refused. A drop can't ask "keep its notes?", so a folder always
    goes with them, which Recently Deleted can undo.
  - **The lift is held 0.25s**, down from the system's 0.5s: `ListDropBridge`
    finds the collection view's drag long press by class name and sets
    `minimumPressDuration`. Unverified on the iPad (the recogniser may time its
    own lift); `-debug-probe` logs what it found.
  - **A press on a row** shows its context menu; a drag lifts it after about
    a quarter of a second if the finger moves at once. A hold that stays still gets the
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
  in every section and, since 24 Oct, folders among them (see "One list"). Rows show the date the list
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
