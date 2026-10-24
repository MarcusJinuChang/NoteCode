# Home, the title screen, thumbnails, reopening
v3 phase 2 (12 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **The title screen is an overlay on `ContentView`**, not a `fullScreenCover`
  (`WelcomeScreen`, the `Main` board): a cover's slide can't be told to fade,
  and Reduce Motion has to. Normal motion slides it up; Reduce Motion fades.
  Flag `welcomeScreenShown`, set when `claimFirstLaunch` is asked, shown or
  not. Not tied to an empty store, as the Welcome note is: a build that updates
  over notes shows it once, as the new home's introduction. Skipped, without
  spending the turn, when storage is in memory or a debug launch opened a note.
  Settings › Help and About › Welcome Screen shows it again, dismissing
  Settings first.
- **The app opens on Home** (`HomeView`) **with the list beside it** (24 Oct,
  feedback #3; `SidebarPlan`): in a regular width `ContentView`'s detail is Home
  whenever `selection` is nil, and the split view is `.balanced` there, so the
  list is a column, not a slide-over. Opening a note switches the style to
  `.prominentDetail` and the list goes away (`.detailOnly`); ☰ brings it over
  the page as before, so opening it never rescales a note. The house button
  beside ☰ in a note's header, ⇧⌘H (`goHome`), Delete and closing a note all
  bring Home back with the list showing. The compact stack (iPhone, a folded
  Duo) is unchanged: Home at its root. Folding a Duo from Home gives Home, and
  unfolding onto Home gives the list beside it (`SidebarPlan.showsList`,
  `.stackShowsList`).
  - **The list comes in 400ms after launch** (`SidebarPlan.launchDelay`). A
    split view that *started* with its sidebar visible pinned the main thread
    at 100% CPU, with a blank screen, in the iPad Pro 11-inch simulator (iOS
    27.0 debug build; sampled: AttributeGraph walking a type's layout
    descriptor, and `NoteList.body` re-run from toolbar updates). The unmodified
    build was fine, and so was the list brought in after launch, or over Home
    by ☰. With the list shown after the first layout, `-debug-home` and
    `-debug-first-launch` load at 0% CPU. **The cause isn't understood**; the
    delay is a workaround, and slow hardware may need longer. Storage failed
    takes the same route.
  - **Provisional (Marcus to review):** the sidebar is *shown* on Home, not
    locked: the system's sidebar button (or ⌃⌘S) can still hide it, and it comes
    back on the next Home. In portrait it takes about 320pt of 834 and Home's
    Continue card gets cramped; narrowing the sidebar is the lever. Switching
    style when a note opens rebuilds the split view, so the list's open and
    closed folders reset then (they are `NoteList` state). Checked in the
    simulator, portrait and landscape: Home with the list, a note opened from
    the list, the house button. Not checked: a Duo folding, Stage Manager or a
    narrow Split View, Reduce Motion. No hosted test: a split view in a test
    window showed one navigation bar either way, so the wiring is checked on
    screen and `SidebarOnHomeTests` holds the rules.
  - **Sections are `HomeSections`**, pure, handed every note. Continue is the
    note opened last; with none recorded, or it gone (deleted), the note edited
    last, so Home always has a way back in. Recent is the next 8 by
    `modifiedAt`. Folders are tiles in name order with live counts. `hasNoNotes`
    shows the empty state: no *live* notes, so a store of folders alone, or of
    deleted notes, is empty. The test that a deleted note is in none of it
    fails with `.live` removed (checked 12 Oct).
  - **"Page 3 of 5" is remembered, not computed.** Only a laid-out note knows
    its page count, and laying out a closed note costs what opening it does
    (see Note info). So `NoteMemory.Place` keeps `[page, of]` as of the last
    time the note was read.
  - **The Ink chip is on Continue only.** `Page.drawingData` is external
    storage; reading `isEmpty` loads the file, and Recent has up to 8 cards.
  - **Colours are the grouped pair** (`HomePalette`): light grey with white
    cards, black with dark grey ones, so cards stand out in both. Not the
    page's surround, which is darker than its page in dark.
  - **A card's shadow goes on its shape, in `.background { … .shadow }`.**
    On the stack it shaded the text too (seen in the simulator, light).
  - A tap on a folder tile is `ListRequest.showFolder`: the list opens over
    Home with that folder open and scrolled to.
  - From Template (phase 5) and Import (phase 7) sit beside New Note, in
    both its states.
  - **⇧⌘H is bound but not tried with a real keyboard**: the simulator tools
    can't send chords. Nothing else in `NoteShortcut` uses it, and neither the
    iPad's global shortcuts (⌘H is the Home Screen, ⌘Space, ⌘Tab, ⇧⌘3/4/5) nor
    the Mac menu bar's (⌘H Hide, ⌥⌘H Hide Others) include it. If a device
    shows the system taking it, change `NoteShortcut.home`.
- **`NoteMemory` is per device and keyed by persistent ID**, in `UserDefaults`:
  the note opened last (`lastOpenedNote`) and every note's place
  (`notePlaces`, one dictionary). Not in the model: where someone was reading
  is not an edit, and must not move `modifiedAt`.
  - **Keys must be made with `.sortedKeys`.** `JSONEncoder` writes an object's
    keys in no fixed order, so the same `PersistentIdentifier` gave different
    strings on different calls: places were never found again, and a
    thumbnail's cache name changed between asking and storing, so every
    thumbnail came back blank. Found by `NoteMemoryTests`, after the simulator
    showed it.
  - **Find a note by its key, never by decoding a key into an ID.** A decoded
    ID passed `==` but a `Set` of IDs didn't find it, so pruning forgot every
    place at each launch. `HomeSections` compares `key(for:)`; `prune` builds a
    set of keys.
  - **A new note's ID is temporary until the context saves it**, and a key
    made from one never matches again. `Page.settledID` saves first, then
    answers; `key(for:)` refuses a temporary ID.
  - Pruned once a launch, with every note's ID (deleted ones too).
- **Reopening at the last page.** `PageDetailView` reads the note's place once
  as it opens and hands `DocumentTextView.resumingAtPage`; `PageView.restore`
  waits for the first layout, as `reveal` does (a search's match wins), lays
  out down to that page as scrolling there would (`DebugLaunch.scroll`'s
  technique, not the whole note) and scrolls to `scrollTop(forPage:)`.
  - **The page reports its own place** through `onReadingPlaceChanged`,
    whenever the page at the top or the page count changes, held back until
    the restore has run: otherwise opening at page 4 first wrote page 1 over
    it. The place is the page at the top edge plus 1pt, since exactly on a
    page's scroll-top the edge is mid-band and rounding could name the page
    before. Written as the reader scrolls, not on closing, so an app killed
    mid-read keeps where it was.
  - A place past a shortened note's end opens at the end, scrolled as far as it
    goes: the last page's top can lie beyond the furthest the view scrolls.
  - Tests check the line at the top against a note laid out from scratch, in
    every mode and orientation, and that the first report is the restored
    page. Layout in those tests is forced a few passes at a time: a window made
    outside the test host's scene has no display link, and the report hooks
    run from layout passes.
- **Thumbnails** (`NoteThumbnail`, `ThumbnailStore`, `NoteThumbnailView`): the
  first page, drawn as the PDF draws a sheet (`PrintedNote`, `NotePDF.drawInk`),
  light, at 0.55 pixels to the page point (449 by 581 for Letter).
  - **Never the whole note.** The printed text view is fed `prefix(of:)`: 80
    paragraphs or 8,000 characters, whichever comes first, clear of what one
    page holds. Measured on the simulator, a 2,000-line note: 9ms with the
    prefix, 333ms without; 40 lines is 4ms. The cost test fails without it.
  - **Ink is drawn at the thumbnail's resolution**, not the PDF's:
    `NotePDF.drawInk` takes `pixelsPerPagePoint`. A sheet's crop at 288 dots
    per inch is 31MB. Only elements touching page 1 are drawn.
  - **Cached in Caches** as `NoteThumbnails-v1/<hash of the ID>-<modifiedAt in
    ms>.png`. A new date is a new name, so no timestamp is read (the privacy
    manifest needs a reason for file timestamps), and the note's older files are
    removed as a new one is written. Bump `NoteThumbnail.version` when a note
    starts looking different for another reason: phase 3's hidden markers
    did (2), step 10's code blocks did (3), code in the light theme on a
    dark device (4, 16 Oct), spans that nest (5, 18 Oct), and underline,
    highlight, quotes and rules (6, 19 Oct).
  - **One per turn of the main actor** (`ThumbnailStore.Gate`, a class: a
    struct held across the gate's suspension was an exclusive-access trap),
    each yielding before it starts; a request cancelled while it waits draws
    nothing. A row that is being edited shows its last picture and waits 600ms
    of quiet before asking for the next.
  - A note whose deletion has been saved is never read (AGENTS.md, drawing
    data): the store checks `modelContext` and `isDeleted` before touching it.
  - macOS draws a placeholder; `PrintedNote` is UIKit.
- **Debug launch:** `-debug-first-launch` and `-debug-home` (see the table).
- **Not checked:** the Pencil; Reduce Motion's fade; the title screen in dark;
  the Home row, a folder tile, Show All and the toolbar's search and + by a
  tap; ⇧⌘H; Home on an 11-inch iPad or in portrait; a thumbnail updating after
  an edit on screen; thumbnails of a note with ink on the iPad; the macOS
  Home (it builds).
