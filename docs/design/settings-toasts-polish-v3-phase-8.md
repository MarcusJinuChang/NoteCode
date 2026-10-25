# Settings, toasts, polish (v3 phase 8)
v3 phase 8 (14 Oct, `docs/archive/ui-design-v3-implementation.md`). Most of the phase's
list had arrived with the phase that needed it; this one filled what was left.

- **Settings** gained Notes › Recently Deleted (a pushed `RecentlyDeletedPage`;
  the list's sheet is the same page in its own stack with a Done button) and a
  new Show Markdown footer, which now says what the setting covers: hashes and
  backticks on the heading or block being edited, Always for everywhere, and
  that bold, italic, code and link marks stay hidden either way. No new keys, so
  `SettingsTests.keysAreStable` is unchanged. **No Paper row**: paper is
  postponed (see "Insert and templates"), and a row exists only if it works.
  Send Feedback and Privacy Policy still wait for `AppInfo.feedbackAddress`
  and `.privacyPolicy`.
- **Toasts:** the only one missing was Copy Block's "Copied". The coordinator's
  one `copy` path (button, edit menu, ⇧⌘C) now calls `NoteEditor.onBlockCopied`,
  which `PageDetailView` points at the toast centre. `copyToasts` fails with the
  call removed (checked). Moved to Recently Deleted · Undo, Exported N and
  Imported N were already in.
- **Empty states use the mark** (`EmptyStateMark`, the default icon at 64pt, in
  the Label's icon slot): the list with no notes, Recently Deleted when empty,
  and Open in Another Window. Home's empty state already drew it. The outline's
  "No Headings" popover and the storage-failure view keep their symbols: one is
  a small popover, the other should not look friendly.
- **Reduce Motion:** the dock snap and the palette reorder now skip their
  `.snappy` animation. The options rows, the toast, the title screen and the
  page badge already crossfaded or only changed opacity. Not changed: list
  insert/remove animations, which the system tones down itself.
- **VoiceOver:** Share's spinner has a label. The text row, outline, badge and
  Copy/Share menus already had them.
- **Measured, not caused by this phase:** the `Code keys and indentation in
  the editor` suite (11 issues in 8 tests) fails on unmodified `origin/main`
  source in this Mac's simulator, run alone, with the row never appearing. That
  suite reads the real `GCKeyboard.coalesced`, so a hardware keyboard attached
  to the Mac, which the simulator inherits, would take the row away. Not proven
  to be that. The other 1,124 tests pass.
  - **Fixed 23 Oct:** it was that. With `HardwareKeyboard.isConnected` forced to
    "attached", the suite fails the same way (8 tests); the suite now pins it to
    "not attached" in its `init()`, so it passes with or without a keyboard on
    the Mac. The one test that attaches one puts the closure back as it found it.
- **Not checked on screen:** any of the above. The macOS build compiles.
