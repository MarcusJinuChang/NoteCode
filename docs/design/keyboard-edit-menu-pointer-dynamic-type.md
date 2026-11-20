# Keyboard, edit menu, pointer, Dynamic Type
Phase 9 of `docs/archive/ui-design-v2-implementation.md` (12 Oct).

- **One table of shortcuts** (`NoteShortcut`): title, key and modifiers for
  every shortcut in the brief, read by the menu bar and by the two places
  that already owned one (⌘F in the header's ••• menu, ⌘, in
  `SettingsCommands`). `NoteShortcutTests.noTwoShareKeys` is where a collision
  is ruled out, and `matchesTheBrief` compares each against the brief's table
  written out by hand.
- **They are menu-bar buttons** (`NoteCommands`), not `UIKeyCommand`s, so the
  ⌘ overlay and the menu bar both list them, titled. The window in front
  hands the menu its state through scene values, since a command can't see a
  window's: `WindowActions` from `ContentView` (new note, new folder, search,
  the note list) and `OpenNote` from `PageDetailView` (the editor, the view
  mode, print). ⌘N replaces New Window (`.newItem`), ⌃⌘S replaces the system's
  sidebar toggle (`.sidebar`: the list slides over the page and only
  `ContentView` knows its state), ⌘P replaces Print, and Format's group
  replaces the system's, whose Bold and Italic act on rich text this view
  doesn't allow.
- **Bare keys (P, H, E, L, [ and ]) are typing whenever a field has the
  keyboard.** The menu turns them off unless the note is in ink mode, no field
  is being edited and no sheet is over the window. "No field is being edited" is
  `TextInputActivity`, which watches the begin and end notifications every
  `UITextField` and `UITextView` posts, by identity (a tap from one field to
  another begins the second before the first ends). It covers the list's
  search field, a title being renamed, alerts and Settings without any of
  them knowing. Nothing on the page is first responder in ink mode, so
  nothing else competes for the keys.
- **⌘Z and ⇧⌘Z are replaced** (`.undoRedo`). The system's Undo reaches only a
  first responder that has an undo manager, and in ink mode there is none, so
  it would have been dead exactly when ink has the page. They go to
  `NoteEditor.undoFromKeyboard`: the note's own stack for the mode, unless some
  other text input has the keyboard, in which case that field's undo manager
  (`UIResponder.currentFirstResponder`, found by sending an action to no one).
- **Run Block (⌘R) and Copy Block (⇧⌘C)** act on the block the caret is in, in
  text mode (`CodeBlockAction.target(atCaret:)`); the coordinator registers
  them on the editor in `connect`. Run, Copy and the edit menu share the
  coordinator's `run` and `copy`, so there is one path for each.
- **Code Block, last language (⇧⌘K)**: `LastCodeLanguage`, per device
  (`lastCodeLanguage`), written by every code-block insert including the
  hotbar's menu, C++ until one is made, Code (no language) remembered as `plain`.
- **[ and ]** step the selected tool's width (`InkToolState.stepWidth`): the
  pen's and the highlighter's three, the eraser's three sizes (from a custom
  size, the nearest preset that way), nothing for the lasso.
- **The edit menu** (`textView(_:editMenuForTextInRanges:)`): the system's Cut,
  Copy and Paste lead (`EditMenuOrder`, 31 Oct; the app's rows used to come
  first, five of them filled the iPad menu's first page and Paste was on the
  second), then, on prose, Bold,
  Italic, Code, then Format › (Strikethrough, Heading 1–3, Body); none when
  the note is locked or in ink mode. In a code block, Run Block (not for a
  block with no language the app knows), Copy Block, then Share Block, which
  was there before and wasn't asked to go.
- **Copy Block taps** (`Haptics.copyBlock`, a light impact), from the button,
  the edit menu and ⇧⌘C; a seam so a test can see it. The dock's snap tap
  was already there and is behind its setting; this one isn't.
- **Pointer:** `.hoverEffect(.highlight)` on the options-row controls and the
  bar's menus, and `isPointerInteractionEnabled` on the run, copy and language
  buttons. **Not on `HotbarButton`** (12 Oct): with it, a touch in the 8pt gap
  between the options row and the bar ran the Text button, 18pt away, and the
  three `HotbarUITests` reach tests failed from Phase 9 on (bisected: they pass
  at the Phase 8 merge, and with only that effect removed). Moving the effect
  onto the icon, or pinning it with `contentShape(.hoverEffect, .rect)`, didn't
  help. The bar's undo, redo, mode and tool buttons therefore have no pointer
  highlight; an `onHover` highlight would be the way to give them one. Seen
  with the simulator's synthesized taps, not a finger or the Pencil.
- **Print (⌘P)** opens the system's print dialog on the note's PDF
  (`NoteEditor.printNote`), the same PDF the share button makes.
- **The note body no longer follows Dynamic Type.** It did: the text view's
  font was `preferredFont(.body)` with `adjustsFontForContentSizeCategory`
  on, so a reader who raised the system's text size re-wrapped every note and
  moved every line from under its ink, which "Page geometry" says must not
  happen. Now fonts come from `preferredFont(forTextStyle:compatibleWith:)`
  at the default (`.large`) category, so they are the same 17pt body and
  34/28/22/20/17/15 headings, and the text view's adjusting is off. The list,
  Settings and menus use semantic fonts and scale (checked at the largest
  accessibility size: the list wraps and stays usable).
  - **Don't use `UIFont.systemFont(ofSize:)` for these.** First version did,
    and every line came out 1.7pt shorter: the system's body font has
    *leading* (1.71pt) that a plain system font of the same size doesn't,
    though `lineHeight` is identical (20.29 either way). Existing notes would
    have re-paginated away from their ink. `PageViewTests.orientationKeepsTopText`
    failed on it; that is the only thing that noticed. Headings kept their
    old weights too (title3 and below are semibold + bold trait, not bold).
  - `KeyboardAndMenuTests.bodyIgnoresTextSize` puts an accessibility size on
    the text view and window and checks the font, the styled text and the
    content height didn't move; it fails with the old two lines back.
  - **Decided 12 Oct (Marcus), built in v3 phase 6:** text size is a property
    of each note (`Page.textSize`), set from ••• › Text Size (the text
    options row until 18 Oct). It is
    still never an app-wide setting and never follows Dynamic Type, which is
    what the two bullets above are about. See "Navigation and the text
    options row".
- **Not checked:** any shortcut with a real keyboard (the simulator tools
  can't send modifier chords: the ⌘ overlay, the menu bar, the bare keys
  being off in a field, ⌘Z in ink mode), ⌘P's dialog on the iPad, the list
  taking ⇧⌘N and ⇧⌘F after it slides in (it waits 350ms for the slide), the
  pointer effects, the haptic, the edit menu on the iPad.
