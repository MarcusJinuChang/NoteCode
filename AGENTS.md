# AGENTS.md

## Project overview

An iPad note-taking app for computer science coursework. A single continuous,
scrollable document (Obsidian-style) where:

- Regular text is typed and formatted like a normal markdown note.
- Triple-backtick fences (` ``` `) anywhere in the flow become syntax-highlighted
  code blocks — not separate files, just inline sections of the same page. Each
  block carries a run and a copy button in its top-right corner, and run hands
  the block to a free online compiler rather than executing anything locally.
- A drawing layer (Notability-style) sits over the same page and can be toggled on
  to draw handwritten notes/diagrams with Apple Pencil, then toggled back to
  text/code editing without losing scroll position or leaving the page.

Primary use case: CS133 (C++) and general algorithm practice (Java/Python), so
code blocks need to support at least C++, Java, and Python.

Running code in-app is deliberately out of scope. Every option needed either a
paid API, a self-hosted sandbox on a VPS, or a multi-megabyte WebAssembly
runtime with a four-second cold start — all for a feature whose value is lowest
exactly when the app is being used, since nobody runs code during a lecture.

The run button is a redirect, not an execution: `CodeDestination` opens a free
online compiler, and nothing in the app ever runs a program. Two ways the code
gets there, and the difference decides how the button behaves:

- **In the link.** Compiler Explorer encodes a whole session in the URL path, so
  the student lands on a finished run. Verified against the live site; the
  compiler ids are pinned and are a maintenance item, since the site has no
  "latest" alias and 1,197 compilers.
- **On the pasteboard.** Programiz and OnlineGDB keep the editor's contents in
  the browser, with no way to be handed a program, so the code is copied and the
  student pastes on arrival. This is the fallback for every other site, which is
  what makes an arbitrary custom URL a usable destination.

Compiler Explorer does not get Java: its executor compiles into a fixed
filename, so `public class Main` fails there with an error about the file name.
It does not get JavaScript either, whose only compilers there are V8 builds that
cannot execute (see "Code: languages, the keys row…").
A destination that can't take a language hands the block to one that can rather
than failing, which is why `RunRequest` reports where it actually went.

The destination resolves through levels, most specific first — page, then
its folder, then app-wide (`Page.runDestinationLevels`). The folder is one
more element of the array `resolve` walks, not another branch.

## Tech stack

- **Swift + SwiftUI** — app shell, navigation, state management.
- **TextKit 2** (`NSTextLayoutManager`) — custom text editor that detects code
  fences as you type and renders that span as a distinct, non-plain-text region.
- **PaperKit** (`PaperMarkupViewController`, `PaperMarkup`) — transparent
  overlay canvas for ink, sharing scroll position with the text layer. It is
  PencilKit's canvas plus shapes, images and text boxes; PencilKit's tools still
  drive it. Only one of (text layer, drawing layer) should own touch input at a
  time, controlled by the toggle. Chosen over a bare `PKCanvasView` on 19 Sep;
  see docs/archive/phase-drawing-layer.md.
- **SwiftData** — persistence for documents (text content + serialized
  `PaperMarkup` data per page). iCloud sync is a later-stage concern, not MVP.
- **Platforms** — iOS and macOS, each at the latest release (27.0). iPhone Duo
  runs the same iOS; see docs/ROADMAP.md.

## Conventions

- Prefer SwiftUI-native state (`@State`, `@Observable`) over introducing
  Combine unless a specific async stream genuinely needs it.
- Keep the text/code parsing logic (fence detection, language tagging)
  separate from rendering — parsing should be pure and testable without
  SwiftUI in the loop.
- Drawing data (`PaperMarkup`) is serialized independently per page and should
  never be re-encoded on every keystroke of the text layer — only on drawing
  layer changes.
- When several settings have to move together, they live in one type with one
  `apply(to:)` rather than being set individually at the call site, so they
  cannot drift apart. `TextRewritingPolicy` is the reference example.

## Architecture notes

- A "page" is the persistence unit: text content + an array of drawing
  strokes anchored to scroll position, not a list of discrete blocks.
- The toggle switches *input ownership*, not *view visibility* — both layers
  are always rendered/visible; only one accepts touches at a time.
- Code fence detection should be resilient to incomplete fences while typing
  (i.e. don't require the closing ``` to exist before showing highlighting).

## Design notes (read on demand)
Per-feature design notes, decisions and what was measured live in `docs/design/`.
Comments and docs that say "AGENTS.md › Section" mean the file below with that title.
Read the one that matches the area you are changing; do not read them all.

| Section | File |
|---|---|
| Colour | [docs/design/colour.md](docs/design/colour.md) |
| Page geometry, orientation, and zoom | [docs/design/page-geometry-orientation-and-zoom.md](docs/design/page-geometry-orientation-and-zoom.md) |
| Who owns scrolling | [docs/design/who-owns-scrolling.md](docs/design/who-owns-scrolling.md) |
| iPhone and the Duo | [docs/design/iphone-and-the-duo.md](docs/design/iphone-and-the-duo.md) |
| The page fills the window | [docs/design/the-page-fills-the-window.md](docs/design/the-page-fills-the-window.md) |
| Pages | [docs/design/pages.md](docs/design/pages.md) |
| The note page | [docs/design/the-note-page.md](docs/design/the-note-page.md) |
| Keyboard, edit menu, pointer, Dynamic Type | [docs/design/keyboard-edit-menu-pointer-dynamic-type.md](docs/design/keyboard-edit-menu-pointer-dynamic-type.md) |
| Recently Deleted and folder faces | [docs/design/recently-deleted-and-folder-faces.md](docs/design/recently-deleted-and-folder-faces.md) |
| Home, the title screen, thumbnails, reopening | [docs/design/home-the-title-screen-thumbnails-reopening.md](docs/design/home-the-title-screen-thumbnails-reopening.md) |
| Writing: hidden Markdown markers, lists, checklists, links | [docs/design/writing-hidden-markdown-markers-lists-checklists.md](docs/design/writing-hidden-markdown-markers-lists-checklists.md) |
| Code: languages, the keys row, indentation, line numbers, output | [docs/design/code-languages-and-keys.md](docs/design/code-languages-the-keys-row-indentation-line-num.md) |
| Insert and templates | [docs/design/insert-and-templates.md](docs/design/insert-and-templates.md) |
| Navigation and the text options row | [docs/design/navigation-and-the-text-options-row.md](docs/design/navigation-and-the-text-options-row.md) |
| Notes in and out, and one editor per note | [docs/design/notes-in-and-out-and-one-editor-per-note.md](docs/design/notes-in-and-out-and-one-editor-per-note.md) |
| Settings, toasts, polish (v3 phase 8) | [docs/design/settings-toasts-polish-v3-phase-8.md](docs/design/settings-toasts-polish-v3-phase-8.md) |
| Settings | [docs/design/settings.md](docs/design/settings.md) |
| The list's foot and the tip jar | [docs/design/the-list-s-foot-and-the-tip-jar.md](docs/design/the-list-s-foot-and-the-tip-jar.md) |
| Code-block fences | [docs/design/code-block-fences.md](docs/design/code-block-fences.md) |
| Code blocks: room around and inside | [docs/design/code-blocks-room-around-and-inside.md](docs/design/code-blocks-room-around-and-inside.md) |
| Coloured and sized text | [docs/design/coloured-and-sized-text.md](docs/design/coloured-and-sized-text.md) |
| Inline nesting | [docs/design/inline-nesting.md](docs/design/inline-nesting.md) |
| Formatting per character | [docs/design/formatting-per-character.md](docs/design/formatting-per-character.md) |
| Typing style | [docs/design/typing-style.md](docs/design/typing-style.md) |
| Obsidian's other marks and blocks | [docs/design/obsidian-s-other-marks-and-blocks.md](docs/design/obsidian-s-other-marks-and-blocks.md) |
| Paste and copy with formatting | [docs/design/paste-and-copy-with-formatting.md](docs/design/paste-and-copy-with-formatting.md) |
| Organising notes | [docs/design/organising-notes.md](docs/design/organising-notes.md) |

Planning docs: `docs/ROADMAP.md` (status and what is left); finished plans are in `docs/archive/`.

## The model

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
- **Gone with the old notes**: `Page.paperStyle` (paper is postponed),
  `Page.markdownLayout` and the legacy layout it chose, and the title menu's
  Hide Markdown Markers….
- **Don't run an older branch on a device** whose store this build has opened:
  an older build may fail to open it.

## Shipping

What an upload checks before a person sees the app (4 Oct).
`AppStoreReadinessTests` checks each of these in the built app.

- **The privacy manifest** (`PrivacyInfo.xcprivacy`) has to list a reason
  for every required-reason API the app calls, or the upload is rejected.
  Today that's only UserDefaults, through `@AppStorage`, for the app's own
  settings (`CA92.1`). Calling one from another category — file
  timestamps, system boot time, disk space, active keyboards — means adding
  its reason. `CACurrentMediaTime` isn't on Apple's list. Notes never leave
  the device, so nothing is collected or tracked; a server would change
  that.
- **Exempt encryption.** `ITSAppUsesNonExemptEncryption` is `NO` in
  Info.plist: the only network traffic is the system opening a compiler's
  page over HTTPS. Encryption of the app's own would change the answer.
- **No background modes or entitlements it doesn't use.** Xcode's template
  declared push as a background mode and had an unused entitlements file
  for iCloud and push; both went on 4 Oct, since a mode the app never uses
  is a question in review. iCloud sync brings them back, through Signing &
  Capabilities.
- **Signing is the paid team** (9 Oct). Automatic signing, team
  `N454V8HV9J`. That ID was the free Personal Team, whose device profiles
  last seven days, and it can't sign push or CloudKit; Marcus re-obtained
  the paid Developer Program membership, and the same ID is now a paid
  Individual team, so the project's team setting didn't need to change.
  Read from Xcode's team list (`defaults read com.apple.dt.Xcode
  IDEProvisioningTeamByIdentifier`: `isFreeProvisioningTeam = 0`, team name
  "Marcus Chang" with no "(Personal Team)"), a new "Apple Development:
  Marcus Chang" certificate issued 8 Oct to 8 Oct 2027, and the app's
  team provisioning profile, made 8 Oct and valid a year. When an on-device
  build misbehaves, check which team signed it before reading any Swift.
  - **Marcus's working tree carries an uncommitted `project.pbxproj` edit**,
    and has since 8 Oct: Xcode set `CODE_SIGN_IDENTITY = "Apple Development"`
    for every SDK, in place of ad-hoc `-` for macOS (`"CODE_SIGN_IDENTITY
    [sdk=macosx*]" = "-"`), and added an empty `PROVISIONING_PROFILE_SPECIFIER`,
    when the paid account came back. It is his local state: **leave it
    unstaged, never commit or revert it, and don't mention it in summaries or
    PRs** (he knows). Stage files by name, never `git add -A` or `-a`. If a
    change needs `project.pbxproj` itself, stop and ask first.
- **iPad only, build 2** (14 Oct, v3 phase 8). The NoteCode target (both
  configurations) has `TARGETED_DEVICE_FAMILY = 2` and
  `CURRENT_PROJECT_VERSION = 2`; the test targets are untouched. The iPhone
  layout is designed, not built, so TestFlight 1 is iPad only; macOS is a
  separate platform in `SUPPORTED_PLATFORMS` and still builds. Bump the build
  number for every upload. The edit sits in Marcus's working tree beside his
  signing change and is not committed (see above).
- **Privacy and support pages** are drafted in `docs/site/privacy.md` and
  `support.md` for Marcus to host: nothing collected, notes stay on the device,
  Run sends a block's code to the compiler site the reader picked. They carry
  `DATE` and `EMAIL ADDRESS` placeholders. When they're hosted, set
  `AppInfo.privacyPolicy` and `.feedbackAddress` and the two About rows appear.
- **The app icon** (10 Oct, phase 7 of `docs/archive/ui-design-v2-implementation.md`):
  the set had no images, which fails an upload; it has them now. They are
  **drawn by `scripts/make-icons.swift`** (Core Graphics, the Logo board's
  120-unit geometry), which rewrites the three icon sets and their
  `Contents.json` outright: `swift scripts/make-icons.swift` from the
  repository root. Edit the script, never the PNGs.
  - **`AppIcon`**: Default (opaque), Dark (brackets and pencil on a
    transparent ground: the system supplies the background) and Tinted
    (greyscale, with the pencil at the orange's luma so it stays darker than
    the brackets once tinted), plus the ten macOS slots. Each macOS size is
    drawn at its own pixel size, not scaled from the 1024.
  - **Opaque except Dark.** The App Store rejects a marketing icon with an
    alpha channel, so the Default, both alternates and the Tinted image are
    written with none (`sips -g hasAlpha`); `AppIconTests.alpha` checks it.
  - **Alternates** `AppIcon-Paper` and `AppIcon-Orange`, named in
    `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, **scoped to the iPhone
    and iPad SDKs** (`[sdk=iphone*]`): they have no macOS art, so unscoped
    the Mac build warned "No applicable app icon found" for both. macOS has
    no `setAlternateIconName` either. One image each, with no Dark or Tinted
    variant, so they look the same in every Home Screen style.
  - **Full-bleed squares**, as the design says. The macOS slots are the same
    art, unmasked: not seen on a Mac, so check the Dock before shipping there.
  - **The colours live twice**, in the script and in `AppIconChoice`
    (AppSettings.swift), which Settings draws its previews from, since an
    icon set can't be loaded as an image by name. `AppIconTests` samples the
    background, a bracket and the pencil in each PNG against the model, so a
    change to one side fails until the other follows.
  - **Settings › General › App Icon** (iOS only) reads
    `UIApplication.alternateIconName` as it appears and after each change,
    and stores nothing: iOS keeps the choice, so a copy in `UserDefaults`
    could only disagree with the Home Screen. iOS puts up its own "You have
    changed the icon" alert on a change; it can't be turned off without
    private API. The Mac has no row.
  - **Not done:** Icon Composer's glass look (out of scope; Marcus can rebuild
    from the script's geometry), and the icon on a real Home Screen with
    Increase Contrast or a tint colour (the system composes both).

## Build/test

Scheme `NoteCode`; targets `NoteCode`, `NoteCodeTests`, `NoteCodeUITests`.
One SwiftPM dependency: HighlightSwift 1.1.0.

    xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

Tests use Swift Testing (`@Suite` / `@Test`), not XCTest. Suites that touch
UIKit are wrapped in `#if canImport(UIKit)` and marked `@MainActor`.

Since 13 September, runs fail to launch on Xcode's cloned simulators ("Busy
… failed preflight checks"). Add `-parallel-testing-enabled NO`.

Run on a physical iPad with Apple Pencil for anything involving ink — latency
and palm rejection in the simulator are not representative.

## Debug launch options

Debug builds only (`DebugLaunch.swift`, all behind `#if DEBUG`). They put the
app in a known state in one command and report what's on screen, so a check
doesn't take twenty gestures, a pasteboard that syncs with the Mac, or a
rebuilt copy of the app with logging.

| Argument | Does |
|---|---|
| `-debug-note pages\|code\|empty` | Opens a built-in note, in an in-memory store — the simulator's notes are untouched |
| `-debug-note-file <path>` | Opens a note read from a file on the Mac |
| `-debug-orientation portrait\|landscape` | The seeded note's pages |
| `-debug-text-size 14\|15\|16\|17\|19\|21\|23` | The seeded note's text size |
| `-debug-mode seamless\|compressed\|print` | Sets the view mode, in the saved setting the menu uses |
| `-debug-ink-file <path>` | The seeded note's ink, read from a file on the Mac (`DrawingCodec` bytes), to look at a note with thousands of strokes |
| `-debug-page <n>` | Scrolls to page n's top edge, counted from 1 |
| `-debug-then-mode <mode>` | Switches mode once the page has settled |
| `-debug-then-delay <seconds>` | Wait before that switch; default 1 |
| `-debug-report` | Writes `tmp/notecode-debug-state.json` in the app container each time layout settles |
| `-debug-first-launch` | A fresh install: an empty in-memory store and the first-launch flags cleared, so the title screen and the Welcome note appear |
| `-debug-home` | Home over a few weeks of sample notes and three folders, in memory, with the title screen already seen and a note to continue at page 3 |
| `-debug-tip-jar` | The tip jar with three stand-in tips, each thanked after a moment, nothing charged (`DebugTipStore`) |

The report lists mode, orientation, page count, scroll offset, scale, zoom, the
top line (character, page, whether it starts the page, its text), the point
size of the text there (`topLinePoints`) and
`visibleLinesAcrossBreaks`. It is built from where TextKit actually has the
lines, not from page geometry, and the last two fields are the ones that would
have shown the 13 September view-switch bug. Bad or misspelt arguments land in
its `problems` rather than being ignored.

The arguments are deliberately not the settings keys: `-pageViewMode print`
would work with no code, but a launch argument outranks saved settings, and the
view menu would then seem broken for the whole session.

    scripts/debug-launch.sh --device "iPad Air 13-inch (M4)" -- \
      -debug-note pages -debug-orientation landscape -debug-mode print \
      -debug-page 4 -debug-then-mode seamless -debug-report

The script relaunches the installed Debug build with those arguments, waits
(`--wait`, default 4s) and prints the report. For manual runs from Xcode, put
the same arguments in the scheme's Run → Arguments.

## Implementation requirements

- TextKit 2 fence-to-code-region conversion — changes here need manual testing
  against fast typing, pasting, and mid-fence edits.
- Overlay touch handoff between the PaperKit canvas and the text view — exactly one
  layer accepts touches at any moment.
- Reading `.layoutManager` anywhere on the text view silently downgrades it to
  TextKit 1 and leaves `textLayoutManager` nil, with no error to say why.
- A button inside a `UITextView` is not simply a button. When one of the text
  view's own recognisers claims the touch, UIKit cancels the one the button was
  tracking and it never fires, so `DocumentUITextView` refuses to let those
  recognisers begin on an action bar. Changes near this need a real tap test —
  `sendActions` in a unit test cannot see the conflict. Bars are inserted
  beneath the ink canvas (`CodeBlockOverlay.ceiling`), so in draw mode the
  canvas takes every touch over them, and they're placed from TextKit's
  viewport layout as well as the text view's, since typing a block causes
  no layout pass of the text view.
- Ink is saved by `DrawingSaveScheduler` from `PageView.onInkChanged`, which
  fires only for changes the reader made. Anything that shows or moves ink
  for the app's own reasons must not call it: a save bumps `modifiedAt`, and
  opening a note would reorder the list. See step 4 of
  docs/archive/phase-drawing-layer.md.
- **Strokes are taken into the stored ink off the main thread** (10 Oct,
  `InkCapture`). PaperKit's delegate says only that the markup changed, so
  what changed is found by walking all of it, and at 5,000 strokes that was
  400ms on the main thread per stroke even walked properly. Now
  `PageView.captureInk` only takes a snapshot of the canvas (free: a
  `PaperMarkup` is a value) with the layout it was drawn in, and a detached
  task works out the rest; while one runs, only the newest snapshot waits,
  so a burst of strokes is taken in as one. So `onInkChanged` arrives a
  moment after the stroke, and anything that needs every stroke now calls
  `PageView.commitInk()` first, which takes the newest snapshot in on the
  main thread: reading `PageView.ink` (the PDF), showing ink (a mode
  switch, with the layout the strokes were drawn in, not the new one),
  leaving the note and the app leaving the screen (`NoteEditor.commitInk`,
  from `PageDetailView`), and SwiftUI removing the page. A result computed
  from state replaced since is dropped (`inkGeneration`).
  **A test that waits for it must `await`**, not turn the run loop: the
  task comes back to the main actor, which a synchronous test turning the
  run loop is still holding, so nothing ever arrived
  (`PageViewTests.waitFor`).
- Parse and index `(textView.text ?? "").nativeUTF8`, never `textView.text`
  itself. That String is backed by the text storage's NSString, and reading
  it a character at a time is a message send per character: the parser took
  3ms a keystroke on a 23KB note, in Release too.
- Never read `Page.drawingData` from a page whose deletion has been saved.
  SwiftData traps ("backing data was detached … without resolving attribute
  faults"), since external storage leaves the attribute unloaded, and
  `isDeleted` reads false again by then — check `modelContext` too. (A note
  in Recently Deleted isn't deleted yet and can be read; this is about
  `Page.delete`, which purging uses.)
- Deleting a note is `Page.moveToRecentlyDeleted`; only purging and Delete
  Now use `Page.delete(_:from:)`. Both save at once. Other changes are saved
  by autosave, or when the app leaves the screen with a note open, and a
  deletion from the note list had neither: killed within a few seconds — a
  crash, or Xcode starting the next build — the note came back.
- Walk a `MarkupOrderedSet` with `for … in`, never `map`, `reduce`, an
  index or anything else that reads it by position. Reading one element by
  index costs what `count` does, and both grow with the set (16ms each at
  5,000 strokes); `map` reads every element that way. `PageView.frames(of:)`
  did, after every stroke: 808ms per stroke at 500 strokes, 10.6s at 2,000
  (simulator, 10 Oct), and writing stuttered and caught up seconds later.
  Even done right, every operation on the set is linear: at 5,000 strokes a
  walk with `renderFrame` is 107ms, an append 20ms, `ids` 16ms.
- **Build a `MarkupOrderedSet` with one `append(contentsOf:)`** of a Swift
  array, never an `append`, `insert`, `updateOrAppend` or `set[id] =` per
  element: each costs what `count` does, so building a set grows with the
  square of its size. Opening a note did, in `PageView.convert`: 1.5s at
  2,000 strokes and 7s at 5,000, now 141ms and 384ms; switching to print
  layout 1.7s at 2,000, now 323ms; and the PDF 7.2s at 2,000, now 1.8s,
  most of it PaperKit drawing (simulator, 10 Oct; `PageViewTests.openingCost`
  and `NotePDFTests.printingCost` keep them). Setting by id was worst:
  68s for 5,000. Removing is the exception: use `removeElement(for:)` per
  element, which is few. A markup keeps what `removeAll(where:)` takes
  out, as it does an element left out of an assigned set.
- The action bars are positioned from TextKit 2's *viewport*, never from the
  whole document. Asking for a fragment further down forces layout all the way
  to it, which is the lazy layout the editor is built on.

## Open questions

Things that are decided in someone's head but not in the code. Move them up
into a section above once they are settled.

- Where text-anchored ink lands in the schedule. Wanted for its own sake, but
  it is a phase, not a step, and November is committed.
- What goes in before November. The candidate list in docs/ROADMAP.md is
  planned properly once the drawing layer is done, alongside a UI design.
- Side-by-side pages (a scrolling-direction setting): the text view scrolls
  itself and only vertically, so pages flowing sideways means something other
  than the text view owns scrolling — the same question "Who owns scrolling"
  settled the other way for zoom.
- An infinite canvas against Letter pages: ink is stored in page coordinates,
  so an unbounded canvas is probably a second kind of note rather than a mode.
- Group notes and comments need a server. Nothing else in the app does, and
  Sign in with Apple was chosen partly because it doesn't.
