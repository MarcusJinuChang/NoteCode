# Typing style
Text overhaul, phase 4 (18 Oct, branch `claude/typing-style`;
docs/archive/text-system-overhaul.md, decision 5). A button with a collapsed caret
either acts on a word or sets what the next text typed will look like, and
that text is written in the style when it is typed. The pure parts are
`TypingStyle`, `MarkdownFormatting.caretTarget` and `.typed`
(MarkdownFormatting+Typing.swift) and `StyledLine.edited`; the state and the
keyboard's side are in `NoteEditor` (`typingStyle`, `typingTextDidChange`).

- **Where a press goes** (`MarkdownFormatting.caretTarget`): a caret
  **strictly inside a word**, a word character on each side
  (`StyledLine.wordGlyphs`; letters, digits and `_`, read off the glyphs, so
  hidden markers don't count), acts on the word, as a selection of it would
  (`toggle`, `colour`, `size`, with a link or code span taken whole). Anywhere
  else in prose is the **typing style's**: a word's start or end, between words,
  a line's end, a blank line, an empty list item. Nothing at all in a code
  block, in a heading's or list item's marker, or at the edge of a link or inline
  code (typed text there would join it). This is Word's rule, and **the one place
  it can be tuned**: if the owner finds a tap that lands at a word's end should
  act on the word, `caretTarget` is the function. It changes Phase 3 in three
  ways: the *run* or *span* a caret is in is no longer its target (the end of a
  bold word used to unbold the whole word just typed), a size or colour with the
  caret touching a word no longer takes the word, and the size control is on
  everywhere in prose, a blank line included.
- **A blank line is a line of no glyphs** (`StyledLine("")`, `LineRuns("")`).
  The parser makes no block for an empty line, so both returned `nil`, and Bold
  pressed on a blank line did nothing in the simulator: the first version of
  this phase, found in its first run on a keyboard.
- **The state is `TypingStyle`**: Bold, Italic, Strikethrough and Code each on,
  off or as the text has it, a colour and a size in points each set or taken
  off (`Setting`). Off is a setting: at the end of a bold word the next text is
  bold, and Bold pressed there turns that off for it. A size is points, written
  against the line's own text when the text is typed, as the size control
  writes one. `NoteEditor.formattingShown` is the text's own formatting with it on
  top, which the hotbar's Bold, Italic, Code and Strikethrough, the colour menu's
  face and the size control read; `typingStyle` is observed, so they redraw.
  The size control's `+`, `−`, picks and Custom… set the typing size at once,
  with no pause and no ink question, since nothing is laid out again.
- **No empty pair, ever.** `toggle` with a caret that isn't in a word has no
  edit; `isEmptyPair` and its tests are gone.
- **Written after the fact, from `textViewDidChange`, never from
  `shouldChangeTextIn`** (probed first, on 18 Oct, iPad Pro 11-inch simulator,
  iOS 27; the write-up is in the session notes folder, `phase-4-typing-probe.md`):
  - A unit test's `insertText`, `replace` and `setMarkedText` never call the
    delegate's `shouldChangeTextIn`, only a keyboard's input does; the
    existing tests call it by hand for that reason.
  - Through a real keyboard it gets one call per letter (`range=n,0`,
    `marked=nil`), an autocorrect as a replacement of a range that is **not** the
    selection (`range=0,7 text="the"`, then a separate call for the space), and
    **the Korean keyboard's first jamo with `marked=nil`, then each next jamo as
    `range=5,0 text="ㅏ"` with the caret at 5 while the text view really
    replaces the character before it** (ㅎ became 하, 하 became 한, with no
    marked text at all). So what it is told isn't what is done, and "replace the
    inserted text in `shouldChangeTextIn`" would write a jamo that was never
    there and wreck the composition; and "never inside marked text" isn't enough
    of a guard for Korean.
  - So `textViewDidChange` is where the typed text is found, from the note's
    own text, by a **place that doesn't depend on what the keyboard says**:
    `TypingAnchor` holds where the typed text starts (`from`), the note's
    length less the caret's place (`suffix`) and where the caret was left
    (`caret`). While text is typed or replaced at the caret `suffix` doesn't
    change, so `length − suffix` is where the typed text ends whatever the
    keyboard did to get there. The run `[from, length − suffix)` is written
    with the style (`MarkdownFormatting.typed`), the caret is put just after it,
    inside whatever closes behind it, and the anchor moves there. An edit that
    leaves the caret anywhere else, or starts in front of `from`, only moves the
    anchor (an autocorrect of the word behind the caret, which would otherwise
    have its new last letters taken for typing).
  - **The caret just after the written text is what makes a keyboard's next move
    work**: the Korean keyboard's next jamo replaces the character before the
    caret, which after the rewrite is the same character inside the markers
    (`**ㅎ|**` → `**하|**`). Seen working on the simulator's Korean keyboard
    (한 글, a space between), and with an English autocorrect inside the span
    (`range=6,3 "the"`: the keyboard's word range is the visible word, markers
    outside it).
  - **A composition (`markedTextRange`) is the keyboard's until it commits**: the
    anchor's caret follows it and nothing is written, and the style goes on at
    the commit (`unmarkText`, where `textViewDidChange` comes with no marked
    text). Probed with `setMarkedText` for kana (ひ, ひら, 平); **not seen with a
    Japanese keyboard**, which the simulator doesn't have installed. The caret's
    selection callback at the commit arrives with no edit, and had cleared the
    style as a caret move until the anchor's caret followed the composition.
  - **Same undo step.** The rewrite is a `replace(_:withText:)` made inside the
    callback, so it is in the same turn of the run loop as the typing; one undo
    takes the letter and its markers (`oneUndoStep`; fails when the rewrite is
    given a group of its own).
  - The app's own edits (a heading, a list's Return, an undo) aren't typing
    (`isTyping` false: `isFormatting`, `isApplyingMarkerEdit`, retagging,
    undo and redo): they only move the anchor. A newline in the run (Return, a
    pasted break) ends the style, as a caret move does; a run over 2,000
    characters is left as it is.
- **How a run is written** (`MarkdownFormatting.typed`): the run is taken out
  of the line, the rest read as glyphs, and the run put back as characters of
  the line *read before it was typed*. That matters: a space typed at the end
  of bold makes `**hello **`, which shows its stars until the next callback, and
  reading the line as it stands would take the stars for text.
  - The run's style is what the text around the caret has (`typedStyle(at:)`,
    the same pairs the bar's lit state follows), then the typing style's
    settings. It isn't written inside a link or inline code.
  - A space can't end bold, italic or strikethrough, so one typed at the end
    of bold goes outside it and the caret with it (`**hello** |`); the style
    stays on, so the next text is written in it again, and **spaces just
    before the run, after text drawn the same way, are drawn that way too**:
    `**hello** |` + w is `**hello w|**`, not `**hello** **w**`. A tag keeps its
    spaces.
  - `StyledLine.edited(replacing:with:styles:)` is `restyled` made general
    (`restyled` calls it): replace a range of glyphs, or insert at an empty
    range, rewriting the stretch between the nearest places where nothing is
    open, shortest nesting that reads back. An insertion's stretch starts from
    the markers between its two neighbours.
  - Text that can't be written as asked is written plain (the line whole, never
    showing stars), or not at all if even that can't be read back.
  - A rewrite equal to the line as it is (text typed inside the span that
    already has the style) is no edit: the cost while a style is on is one parse
    of the line without the run and one of the stretch.
- **What clears it:** a caret moved anywhere the typing didn't take it
  (`typingSelectionDidChange`, with no edit since the last selection change), a
  selection, a mode switch (`setMode`), a locked note, the keyboard going away
  (`textViewDidEndEditing`), a newline in the text typed or in an edit the app
  makes (a list's Return, `Coordinator.apply`), and a new text view
  (`attach`). Pressing a button with the keyboard away brings it up first, as every
  formatting button does. Ink mode and a lock both put the keyboard away, so
  `textViewDidEndEditing` clears the style for them too; `setMode` and
  `setTextLocked` clear it themselves as well, and their test takes the text
  view's delegate away so that only those can (without that, removing either
  survived).
- **Tests** (`TypingStyleTests`: 37): the rules as tables (`caretTarget`, `typed`,
  colour and size on the word and not the run), a seeded property test (5,000
  random lines, a caret at a glyph boundary, a random typing style and run: the
  edit reads back as the line before with the run inserted, the run drawn as asked
  or as the text around it, everything else as it was, spaces aside, the caret
  just after the run) and the editor with a real text view driven the way a
  keyboard drives it: `insertText`, `replace` for an autocorrect and for Korean's
  replace-the-previous-character, `setMarkedText` and `unmarkText`, and the
  coordinator's `shouldChangeTextIn` called by hand for the stale hint.
- **Cost, measured** (iPad Pro 11-inch simulator, debug build): `typed` on a
  100-character line with bold, code and a link on it is 0.13ms. That is the
  keystroke's whole cost while a style is on; with none it is nothing
  (`typingTextDidChange` returns first).
- **Mutation-checked** (18 Oct; each fails the tests named when broken): a
  word's edge counted as the word (`caretTargets` and three more); nothing
  written after typing (ten, every editor test that types); an app edit
  taken for typing (`headingIsNotTyping`); no stale hint
  (`autocorrectBehind`); no bridging over a space (`spaces`,
  `spacesAndWords`, `autocorrect`); any selection change clearing it (nine,
  `caretMoveClears` first); a mode switch, a lock or the keyboard going away
  not clearing it (`otherClears`, each of the three alone); a rewrite inside
  marked text (`markedText`); a newline not ending it (`returnClears`) and a
  list's Return not ending it (`listReturnClears`); off ignored
  (`styleOff`, `offAtTheEndOfBold`); the rewrite in an undo step of its own
  (`oneUndoStep`, `undoThenType`); a caret taking the run it is in
  (`wordNotRun`); the style around the caret ignored (`combines` and three
  more); the caret left before the run (`property`, `typedAfterASpace`
  and others); text joining a link written in (`noEdit`, `property`).
- **Checked in the simulator** (iPad Pro 11-inch, light, real keyboard by soft-key
  taps, Korean 2-set and English): Bold on a blank line then 한; a typed space
  and the next syllable 글 across it; English "teh" autocorrected to "the" inside
  the span and a space after it; Bold, then Red from the colour menu (the
  keyboard stays up and the style survives the menu), then "red bold" typed with
  hardware-style key events: drawn bold and red, no marker showing, the bar lit
  for both; a tap elsewhere on the line, after which Bold isn't lit. **Not
  checked:** a Japanese or Chinese
  keyboard, dictation, a QuickType suggestion tapped (it inserts a word and a
  space at once, which the run handles but nobody has seen), Scribble, a hardware
  keyboard's ⌘B at a caret, the colour and size controls by a tap, the ink on
  a note when the typing size changes the lines below, the PDF of a note typed this
  way, the iPhone layout, macOS.
