# Settings
A form sheet with a `NavigationStack`: a list of sections, each a page
(10 Oct, phase 6 of `docs/archive/ui-design-v2-implementation.md`). `SettingsView.swift`
holds the list and every page but Drawing, which is iPad-only
(`DrawingSettings.swift`); the pure parts (appearance, the snap haptic's key,
the version string, the licence text, the palette reset) are `AppSettings.swift`.

- **A row exists only if it works.** Left out on purpose, and where each
  comes back (App Icon came with phase 7, see "Shipping"): New Notes and
  Welcome Note (both came with phase 8; New Notes is the "+" button's tap, so
  a row before then would have changed nothing), Send Feedback and Privacy
  Policy (each appeared when `AppInfo.feedbackAddress` or `.privacyPolicy`
  got its value; both have one now). Ad Privacy Options (Help and About) appears only where Google's
  UMP says the reader must be able to change their consent answer
  (`AdConsent.privacyOptionsRequired`). Not built, per the brief: Account, iCloud, Templates, Recently
  Deleted, Storage, Rate, What's New, code keys, indent, line numbers.
  (Export All Notes… came with v3 phase 7; see "Notes in and out".)
- **Every row binds the key its owner already uses**, through the owner's
  constant (`HotbarDock.defaultsKey`, `NoteSort.defaultsKey`,
  `NoteEditor.fingerDrawsKey`, …),
  never a second spelling. `SettingsTests.keysAreStable` pins the stored
  names, since renaming one orphans what a device saved. Finger Draws needed
  no new key: `fingerDraws` was already per device (10 Oct, before this phase),
  so the row and the hotbar's hand button are one setting.
- **Opening it.** The gear was an inset bar at the foot of the list until
  16 Oct (a `.bottomBar` toolbar item had put it at the centre of the screen
  with the list hidden, and it wasn't there in portrait). Now Settings is in
  the list's ••• menu, after Import and Export, and a gear on Home's toolbar.
  See "The page fills the window" for why those two. ⌘, is a `CommandGroup(replacing:
  .appSettings)` in the app's menu (`SettingsCommands`), which can't see a
  window's state, so the window in front hands it its sheet's binding through
  `focusedSceneValue`. The sheet is owned by `ContentView`, above the list,
  so ⌘, works with the list slid away over a note.
  Since 21 Oct the note's ••• menu has Settings too, after a divider at its
  foot (`PageDetailView.onShowSettings`, which `ContentView` points at the same
  `showsSettings`; `HotbarUITests.testSettingsFromTheNoteMenu` taps it and
  looks for the sheet). Not checked by hand on an iPhone.
- **Open Note After Creating** (21 Oct, Settings › Notes beside New Notes; key
  `openNoteAfterCreating`, `NewNotes.opensAfterCreatingKey`, off by default).
  Off, the list's "+" tap, its hold menu (Portrait/Landscape Pages and From
  Template), a folder's New Note menu and the empty list's New Note button
  make the note, file it in the open note's folder as always, leave the open
  note (or Home) where it is, and show a toast "Note added to CS133" (or "Note
  added") with an Open button. On, they open it with its title ready to rename,
  as before. Every one goes through `NoteList.finishAdding`, and what is
  selected afterwards is `NewNotes.selection(afterCreating:current:opens:)`,
  pure and tested. **Not covered:** ⌘N, Home's New Note and From Template, and
  Import: those are explicit "make me a note and show it" commands made from a
  place where nothing visible would otherwise happen, so they still open.
- **Autocorrect** (21 Oct, Settings › Writing; key `autocorrectInProse`,
  `TextRewritingPolicy.proseDefaultsKey`, on by default). Off turns every
  rewriting trait off in prose too (autocorrect, capitals, smart quotes and
  dashes, smart insert/delete, inline predictions), as code always has them.
  It is a third `TextRewritingPolicy` case, `.proseWithoutRewriting`, so the
  type keeps its one `apply(to:)`: `at(_:in:blocks:rewritesProse:)` returns it
  for prose when the setting is off, and code is still `.code` either way. It
  is not code, so the code-keys row stays away from it. The coordinator
  (`setRewritesProse`) re-applies the policy at once, in a keyboard already up.
  The text view is handed the value by `PageDetailView`, which reads the
  `@AppStorage`; `TextRewritingPolicyTests` and `SettingsTests.keysAreStable`
  cover it, and `HotbarUITests.testAutocorrectOffKeepsThreeHyphens` types on
  the soft keyboard with it off.
  - **Three hyphens by hand, probed 21 Oct** (iPad Pro 13-inch simulator,
    soft keyboard taps): with Autocorrect on, `---` types as "—-" (U+2014,
    then a hyphen). The delegate sees the first two hyphens as ordinary
    inserts (`range=1,0 text=-`); the second becomes an em dash *after* it is
    in, with no `shouldChangeTextIn` for the replacement, so refusing it in
    the delegate is impossible (a first attempt did, and did nothing). A fix
    would have to undo the dash from `textViewDidChange`, fighting the
    keyboard; not done. **So a rule can't be typed with smart dashes on**: use
    Style ▾ › Horizontal Rule, paste, or turn Autocorrect off, where `---`
    types as three hyphens (checked by the same test).
- **Appearance is applied at the root of the scene** (`AppearanceModifier`,
  `preferredColorScheme`, on both the note view and the storage-unavailable
  view), so every window, the sheet and UIKit controllers presented from it
  follow it live. `AppearanceSettingTests` hosts a view in a window and
  changes the stored value light → dark → light → system, and fails without
  the modifier. The PDF stays light by its own means (`NotePDF`).
  - **A window's override on UIKit, not `preferredColorScheme`** (13 Oct).
    With the device in dark, picking Light and then System left the open
    Settings sheet light under a dark page: SwiftUI puts an override on each
    sheet it presents, and `preferredColorScheme(nil)` doesn't take it off.
    `AppearanceModifier` now sets the window's `overrideUserInterfaceStyle`
    (`.unspecified` for System) from a background anchor view, and
    presented controllers take their traits from the window. The Mac still
    uses `preferredColorScheme`. `sheetFollowsSystemAfterAnOverride` presents
    a **SwiftUI** `.sheet`, since a controller presented from UIKit never
    showed the bug (the first version of the test passed on the old code);
    it fails on the old modifier. Checked in the simulator, dark device.
- **Settings changes reach an open note.** The sheet sits over the page, whose
  editor was set from the device's values as it appeared, so
  `InkToolPersistence` also follows the stored eraser and Finger Draws
  (guarded by equality, so the editor's own writes aren't echoed back). Without
  it the next hand-button tap would have written the stale value over the
  Settings one. The palettes need nothing: every swatch row reads the same key.
- **Haptic on Snap** is `.sensoryFeedback(.alignment)` on the hotbar, triggered
  by a counter `drop` bumps, with the setting as its condition. It fires on
  every drop, including one that lands back on the same edge, and not on
  Toolbar Position or the "Dock …" accessibility actions, which aren't snaps.
- **Palettes** are edited in a `List` (swipe to remove, Edit to reorder, Add
  Colour from Apple's picker through `InkColorPicker`, as the hotbar does).
  Reset Colours asks first, and only rewrites the two palettes
  (`InkPalette.resetStoredPalettes`): the colour each tool is drawing in is
  left, and falls back to the palette's first on its own if the reset took it.
- **Acknowledgements** is `Acknowledgements.txt`, bundled: HighlightSwift's
  MIT licence, and highlight.js's BSD-3, which HighlightSwift carries and the
  app ships. It's copied from the package checkout, so a package update that
  changes either licence means copying again; a test checks both are present.
- **The mark** in About's header is `NoteCodeMark`, drawn in SwiftUI on the
  logo's 120-unit grid (the brief's geometry), in the colours of whichever
  `AppIconChoice` it is given: About shows the Default, and General › App Icon
  draws all three as previews. `scripts/make-icons.swift` draws the same
  shapes into the real icon; this view isn't the icon.
- **Not checked on screen:** most pages (only the section list was seen, in
  dark, in the simulator), the Mac's sheet and ⌘, (the Mac builds; it was not
  run), the haptic, Add Colour from a sheet, Reset Colours, and Appearance
  with a note open.

- **Markers: off, dim or full** (23 Oct, feedback item 9; `MarkerDimming`,
  `MarkerDimmingTests`). Settings › Writing › Markers has four rows, Heading
  Marks, List Bullets, Checkboxes and Code Fences, each Off, Dim or Full, per
  device (`markerDimming.headings`, `.bullets`, `.checkboxes`, `.fences`, pinned
  in `SettingsTests.keysAreStable`). **Dim is today's look and the default.**
  - **Dim** is the marker's grey (heading hashes in the margin
    `secondaryLabel`, the rest `tertiaryLabel`, an output block's fences its
    panel's label colour); **Full** is the text's own colour (`label`, the
    panel's text colour on an output block); **Off** hides it **without
    touching layout**, as Show Markdown's hiding does: a clear colour, or not
    drawn. A setting is paint, so no word moves from under its ink
    (`changeRestylesAndMovesNothing`).
  - **What each covers.** Heading marks: the hashes drawn in the margin
    (`HeadingLayoutFragment.markerColour`, asked at draw time) and the marker
    characters in the text, which a rendered note collapses anyway. List
    bullets: bullets and numbers (`DocumentStyler`, list markers). Checkboxes:
    an unchecked box's outline (`ChecklistLayoutFragment.outlineColour`); a
    ticked box is the item's state and always shows, and the PDF draws its own
    boxes (the paper's `drawBox` default). Code fences: the backticks and tag
    while they show (editing, or Always).
  - **One type, one `apply(to:in:)`** (the Conventions rule, as
    `CodeEditorSettings`): `PageDetailView` reads the four `@AppStorage`s into
    a `MarkerDimming`, `DocumentTextView.updateUIView` hands it to the
    coordinator once, and a change restyles the note (`invalidateStyling`, so
    every block takes it) and redraws the fragments that draw a marker
    themselves. The coordinator holds the value, so a PDF or thumbnail made
    by another coordinator uses `.standard`: paper doesn't follow the device's
    taste.
  - **Typing after a hidden fence line** doesn't pick up its clear colour
    (`inheritedCodeColor` skips it as it skips the grey), or text typed after
    the tag would be invisible (`typingDoesNotInheritAHiddenFence`).
  - **Tested:** the keys and default colours, each setting reaching only its
    own marker (table over all levels), a change restyling with no line
    moved, and pixels: hashes in the margin (none when off, darker when full)
    and a box's outline (none when off, a ticked one stays). Fails with the
    styler, the heading fragment or the box ignoring the setting (all three
    removed in turn, 23 Oct).
  - **Checked in the simulator** (launch arguments `-markerDimming.fences full
    -markerDimming.headings full -showMarkdown always`): the hash and every
    fence line in the text colour. **Not checked:** the Settings rows
    themselves, Off on screen, dark mode, a change made with a note open, the
    Pencil, the macOS build. "Off" for a checkbox leaves a ticked box visible
    on purpose; if Marcus wants it gone too, `drawBox` is the place.
