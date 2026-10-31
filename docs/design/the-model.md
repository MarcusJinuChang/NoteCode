# The model

Moved out of AGENTS.md on 26 Oct; AGENTS.md › The model keeps the rules.

`Page` and `Folder` are typealiases for `NoteSchemaV1.Page` and `.Folder`,
whose classes are in Page.swift and Folder.swift. `NoteSchema.current` is
version 1's schema, and `Storage` opens every store with `NoteMigrationPlan`,
which holds version 1 and no stages (17 Oct, step 13 of docs/ROADMAP.md).

- **Edited in place until the release** (decided 15 Oct, step 4). Nothing
  important was stored in the app, so the frozen versions 1 to 7, the
  version-7 stage and `SchemaMigrationTests` went, and are in the history of
  NoteSchema.swift. Their numbers are reused: today's version 1 is the shape
  that ships, not the old one.
- **Version 1 is frozen by its hashes** (`ModelFreezeTests`). SwiftData
  matches a store to a version by Core Data's entity version hashes, so the
  test pins them (`NSManagedObjectModel.makeManagedObjectModel(for:)`,
  `entityVersionHashesByName`). Adding an attribute fails it, and so does
  opening stores without the plan (both mutation-checked, 17 Oct).
  - **Before the App Store release** a model change may still edit version
    1 in place and update the pinned hashes; TestFlight testers then
    reinstall.
  - **After it, a changed hash means a new version.** Copy the classes as
    they were into `NoteSchemaV1` (frozen: same names, types, defaults,
    external storage and relationships), move the live ones to
    `extension NoteSchemaV2`, point the typealiases at it, add a stage, and
    write a test that saves a store with the frozen copy and opens it through
    `Storage`, never a container built some other way. Pin version 2's
    hashes beside version 1's.
- **A store from before versions opens as version 1**, since its shape is
  the same: the TestFlight builds from 17 Oct opened a plain
  `Schema([Page.self, Folder.self])`, and
  `ModelFreezeTests.storeFromBeforeVersionsOpens` writes one that way, with
  ink, nested folders and a deleted note, and opens it through `Storage`.
- **A store that can't be opened looks like lost notes.** `Storage` falls back
  to an in-memory store with a warning; the file is untouched, but the app
  can't see it.
- **Shaped for CloudKit**, so iCloud sync later needs no migration of its own:
  every relationship optional, every attribute optional or with a default,
  nothing `.unique`.
- **Unused, kept**: `Page.paperStyle` (paper styles were removed on 31 Oct)
  and `Page.runDestination`, so version 1's hashes hold.
- **Gone with the old notes**:
  `Page.markdownLayout` and the legacy layout it chose, and the title menu's
  Hide Markdown Markers….
- **Don't run an older branch on a device** whose store this build has opened:
  an older build may fail to open it.

