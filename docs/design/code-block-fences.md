# Code-block fences
A code block shows its backticks only while it is being edited (10 Oct,
phase 5 of `docs/archive/ui-design-v2-implementation.md`). Pure rules are in
`FenceVisibility`; drawing is `CodeBlockLayoutFragment`; wiring is
`CodeFenceDisplay.swift`.

- **Editing** is the caret or a selection in the block, from the opening
  fence's line to the end of the closing fence's line (before its newline: the
  line after is prose). An unclosed block holds the caret to the end of the
  note. A selection counts if it overlaps the block by a character. In ink
  mode nothing is being edited. Settings › Writing › Show Markdown is
  `ShowMarkdown` (`showMarkdown`, While Editing or Always); Always draws every
  fence. Its row is in Settings › Writing
  (see "Settings"); `PageDetailView` reads the key. Always keeps fences
  in ink mode too, which the brief didn't say either way.
- **Hide glyphs, never lines.** An away block's fence lines keep their
  height and place and the fragment skips drawing their text, so nothing
  below moves and ink stays on its words. No text-storage edit is made to
  show or hide them. The fragment asks the coordinator at *draw* time
  (`fenceDisplay`), finding its block from its own offset, as
  `selectedRanges` does; a state change marks the on-screen fragment views
  of the blocks that changed for display (`setNeedsDisplay`, no layout), the
  way the selection highlight does.
- **Not a rendering attribute** (the brief's first choice). Measured:
  `setRenderingAttributes([.foregroundColor: .clear])` hides the glyphs and
  lays nothing out (same fragments, no viewport layout), and follows an edit
  above its range. It does not follow one inside it: the language menu
  replacing a tag, or typing at the range's end, drew the new text again, so
  it would be set again after every edit. `CodeFenceDisplayTests.renderingAttribute`
  records this. A first spike concluded it drew nothing different; its
  measuring rect began outside the panel's rounded corner, so its first
  pixel was the page's and every panel pixel counted as ink. **Measure
  pixels inside the panel** (`Harness.interior`).
- **Cost, measured** on the simulator, 500-line note, seamless layout: a
  caret move into or out of a block 1.5ms; a keystroke at the same place
  35ms. Over the moves, zero fragments made (counted at the layout
  delegate) and zero text-storage edits. TextKit's viewport-layout callback
  still fires about once per in-and-out; nothing is laid out.
- **The opening fence, away** has the language's name (`CodeBlockLanguageButton`,
  C++, Java, Python, or the tag as typed, Code for a bare fence, renamed from Plain Text on 21 Oct) where
  the glyphs were, and a menu that retags through `replace(_:withText:)`
  (`FenceTag.retag`, pure): undoable, Run follows. It is an action-bar
  control: the overlay keeps it beneath the canvas, in `containsInteractiveElement`,
  and a locked note shows it dimmed with nothing behind it. Editing shows
  the fence in the marker colour instead, and no button. There was an accent
  ring round the block being edited until 13 Oct; Marcus found it ugly and it
  went (`CodeFenceDisplayTests.noRing` pixel-checks the edge). The PDF never
  prints fence glyphs (`NotePDF` skips `isFence`); since step 10 it prints
  the language's name in the header instead.
- **Undo and redo pass the keyboard-rewrite guard.** Undoing a retag puts text
  back by replacing it inside a code line, which is what a keyboard
  correction looks like, so `shouldChangeTextIn` turned it away and spent
  the undo step. Found by the retag's undo test.
- The panel reaches 14pt past the text column into each margin, and the
  code starts on the column (see "Code blocks: room around and inside").
- **Not checked:** a real tap on the name, the menu on the iPad, fast typing
  into a new block, a paste, a block scrolled out of view while its state
  changes (it draws its state when it returns, since it asks at draw time),
  find highlights on a hidden fence, or the Pencil.
