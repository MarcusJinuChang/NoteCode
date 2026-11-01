# Code: languages, the keys row, indentation, line numbers, output
v3 phase 4 (13 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **Eight languages** (`CodeLanguage`): C++, Java, Python, then C, JavaScript,
  Rust, Go and SQL, in that order in every menu (`CodeBlockKind.menu`: the
  languages, a divider, Output, Code; "Code" was "Plain Text" until 21 Oct, the stored key stays `plain`). Each has its tags (`js`, `golang`,
  `rs`, `postgres`, …), `displayName`, `canonicalName` (Compiler Explorer's own
  language id), `highlightName` (what highlight.js is asked for, so `golang` and
  `js` colour without depending on its aliases) and `canRun`. The raw value is
  what `insertCodeBlock` writes after the fence, and reads back as itself.
  - **SQL is Copy only** (`canRun` false): the sites that take it run it against
    a database of their own, so a Run would only open a page. No destination
    lists it; the menu says "Copy only" under it.
  - **Run mapping, checked on the live sites on 13 Oct.** Compiler Explorer
    ids are pinned: C `cg162` (`-O2 -std=c17`), Rust `r1990` (`-O`), Go `gl1260`,
    beside `g162` and `python314` (re-checked 23 Oct: nothing was retired, but
    gcc 16.2 and Python 3.14 were out, so those three moved up from `cg152`,
    `g142` and `python313`, each compiled and run through the API). Each was compiled and run through
    `/api/compiler/<id>/compile` with `execute` on, and a `clientstate` link
    for each of C, Rust and Go was opened in a browser and landed on "Program
    returned: 0" with the program's output (Go's first compile took 17s cold).
    **The brief and canvas say JavaScript runs on Compiler Explorer. It can't:**
    its only JavaScript compilers are two V8 builds with `supportsExecute` false,
    so JavaScript is Programiz by paste, like Java. (OnlineGDB, a choice
    until 30 Oct, had no JavaScript or SQL page either.)
    The ids are a maintenance item: retired ones still show the code, with the
    compiler pane complaining.
  - Tags other than these are unknown, so a block tagged `ruby` still has no
    Run and keeps its tag as the language button's label.
- **Output blocks** (```` ```output ````, `CodeBlockKind.output`,
  `CodeBlock.isOutput`): a console on the code panel's own colours
  (31 Oct; it was a near-black panel in both appearances, which sat as a black
  hole on a white page). `CodeOutputPanel`: `#F2F2F7`/`#111113`/`#6C6C70`
  light, `#1C1C1E`/`#F5F5F7`/`#98989D` dark (fill/text/label; the code panel's
  `secondarySystemBackground`, `label` and `secondaryLabel` resolved, with the
  text a hair off `.label` so the styler can tell it). The label "Output", Copy and no Run, no highlighting, no
  auto-indent, no line numbers. Contrast, computed from the tokens:
  text 16:1 light, 15:1 dark; label about 4.8:1 light and 6:1 dark. (Before
  the change the dark label was 4.3:1 and tested at 4:1.)
  - **Three things the retag between a language and Output taught**, so they
    aren't found again. (1) Python and output are both six letters, so the
    styler's block signature didn't change and the text kept its old colour;
    `styleDetail` now includes `isOutput`. (2) A highlighting pass handed an
    output block resets its text to `.label` (`applyColors(clearing:)`), so
    output is left out of the jobs, and `codeColors` doesn't carry the
    console's text colour into a block just turned into code. (3) **A retag
    between languages never re-coloured anything**, which predates v3:
    `highlightedBlocks` was keyed by `CodeBlockID`, which is the block's
    ordinal and code and not its tag, so python → sql left python's colours on
    the text. It is keyed by the id and the tag now (`HighlightKey`).
    `OutputBlockTests.retagRecolours` fails with the tag taken out of the key.
    **That test restyles once before its first check**: the harness's window
    applies its appearance after the first restyle, a change of appearance
    forgets everything highlighted, and until then the mutation looked
    harmless.
  - The fragment's `isOutput` is set when it is made. A retag restyles the whole
    block, which lays every paragraph of it out again, so none keeps the old
    answer (`retagTurnsEveryLine`).
- **Return in code** (`CodeIndent.returnEdit`, pure, applied from
  `shouldChangeTextIn` through `Coordinator.apply`, so one undo step): keeps the
  line's indent as far as the caret is in it; one level deeper after `{`, `(` or
  `[` and, in Python only, a colon (not in a `#` comment; `case 1:` in C++ is a
  plain newline); between a bracket and its own closer the closer goes to its
  own line and the caret lands between; a line the caret leaves blank has its
  indent moved down, not copied, so a blank line stays blank. Not on a fence
  line, not in output, not for a selection that leaves the block. One level is
  Settings › Code › Indent Width (2 or 4, default 4), or a tab if the line is
  indented with one.
- **Backspace in an indent takes back a level** (`CodeIndent.backspaceEdit`,
  13 Oct): with a collapsed caret in a code line's leading spaces, one press
  deletes back to the previous multiple of the indent width, so four spaces
  typed by ⇥ go in one press and six go to four. One space over a level, a
  tab indent (already one level a character), a caret after text and a
  caret outside a block's own lines are the ordinary delete. Applied from
  `shouldChangeTextIn` like Return, so one undo step.
- **A block with no language is plain** (13 Oct). The styler carries syntax
  colours across a restyle, since highlighting is async; it carried them
  for a block whose tag had just been deleted too, and no highlight pass
  comes for a bare fence, so the old language's colours stayed on the text
  (`DocumentStyler.codeColors` now skips blocks with no tag,
  `CodeBlock.hasLanguageTag`). A tag the app doesn't know (`ruby`) still keeps
  what highlight.js makes of it.
- **⇥ and ⇧⇥** (`CodeIndent.indentEdit`; the hardware Tab arrives as a `"\t"`
  in `shouldChangeTextIn`, ⇧Tab is the existing `UIKeyCommand`, which now
  answers for code too): one level in or out on **every line the selection
  touches, which with a caret is its line, wherever the caret is in it**, not
  an insert at the caret. That is the brief's wording ("indent or outdent the
  selected lines"), chosen over VS Code's tab-at-the-caret since on a tablet a
  line is what is wanted. Blank lines in a multi-line selection are left alone;
  a single blank line takes the indent, or ⇥ there would do nothing. ⇧⇥ with
  nothing to take off hands the key back. Code lines only: a selection running
  into a fence or prose isn't Tab's. Lists keep their own Tab.
- **The code-keys row** (`CodeKeysRow`, `CodeKeys`): ⇥ ⇤ `{ } ( ) [ ] < > ; = " '
  : / \ | & * #` ← →, on a bar-material capsule, 40pt keys in a 52pt row, an
  `inputAccessoryView` set while `TextRewritingPolicy` says the caret is in
  code, and swapped **before the one `reloadInputViews()`** that crossing
  already does (`applyRewritingPolicy`), so the traits and the row change in a
  single redraw. The first tap into a note that opens on code crosses nothing,
  so the unchanged-policy path refreshes it too
  (`refreshedWithoutCrossing` fails without that). The symbols scroll in a narrow Split
  View; the indent and arrow keys stay at the ends. Each key goes through the
  same paths as typing (`replace(_:withText:)`, `apply`), so it undoes like
  typing; ← and → collapse a selection to its edge.
  - **Not with a hardware keyboard** (`HardwareKeyboard`): `GCKeyboard.coalesced`
    non-nil, with a refresh on `GCKeyboardDidConnect`/`DidDisconnect`. Not the
    on-screen keyboard's visibility, which says nothing about whether a
    hardware one is attached. Asked last (an autoclosure), since the row is
    decided on every caret move. **Not checked with a real keyboard**, or in the
    simulator with "Connect Hardware Keyboard" on.
  - **`CanvasGeometry.keyboardInset` needed no change, measured.** UIKit's
    `keyboardFrameEnd` includes the accessory: on the iPad Pro 13-inch
    simulator in landscape it was `(0, 534, 1376, 498)` in prose and
    `(0, 482, 1376, 550)` in code, 52pt taller and higher, and the move from one
    to the other posts a new frame, so the text view re-insets as the caret
    crosses. The hotbar, docked at the bottom, rides above the row.
    `KeyboardInsetTests.codeKeysRow` and `PageViewTests` pin the arithmetic
    with those numbers.
- **Line numbers** (Settings › Code, off by default): `CodeBlockLayoutFragment`
  draws each code line's number, right-aligned 16pt left of the panel, in the
  page's margin, on the paragraph's first line's baseline (a wrapped line has
  one), `secondaryLabel`, monospaced digits at 85% of the code's size. **Never a
  gutter inside the panel**, which would shift the code, re-wrap it and move
  ink. It's the way a heading's hash is drawn: the fragment's rendering surface
  always reaches `PageLayout.margin + 5` to the left (on or off, so the setting
  is a redraw and no layout), the number is asked for at draw time
  (`lineNumber`), and the coordinator `setNeedsDisplay`s the on-screen fragment
  views of every block when the setting changes. The number is the count of
  newlines from the block's start, so an edit above renumbers nothing. Not on
  fence lines or output. Printed when on (`NoteEditor.showsLineNumbers` →
  `NotePDF.Note.lineNumbers`, once, on the page a split paragraph's first line
  is on); thumbnails never show them. Measured: a keystroke in a 500-line note
  30.9ms off, 30.7ms on; a rendered-note keystroke 34.4ms against legacy 35.3ms,
  and the fence cost test 36ms — no worse than before. **A pixel test does see a
  crop here**: with the surface's margin union removed, the digits vanished
  from the render (`rightAligned`, `surfaceReach`), unlike the heading hash's.
- **Settings › Code** has Code Keys, Indent Width and Line Numbers beside Run
  Code In. `CodeEditorSettings` carries the three to the editor with one
  `apply(to:in:)` (the repo's one-type rule), from `PageDetailView`'s
  `@AppStorage`. Keys: `codeKeys`, `indentWidth`, `lineNumbers`, pinned in
  `SettingsTests.keysAreStable`. A width the picker can't have made reads as 4.
- **Not checked:** the Pencil; a real hardware keyboard (⇥, ⇧⇥, the row
  disappearing); a floating keyboard; the row in a narrow Split View; VoiceOver
  on the keys; Return in the Korean layout the simulator started with was the
  only keyboard used; the Output panel's selection highlight (orange at 30%, chosen
  for the old near-black panel; now on a light one, not looked at) beyond looking at it; line numbers at 4+ digits on
  screen (the area is tested for five); the macOS app running (it builds).

## The Run panel (R3, 28 Oct)

- **A pane, not a frame.** `PageDetailView.runLayout` puts `RunDock` beside the
  note's content in an `HStack`. The page is handed a narrower area and nothing
  else; its zoom and top line are its own (`PageView` already handles an area
  that changes width). Width is `RunDockWidth`: 360pt to start, 280pt to half
  the window, `@AppStorage` app-wide. In a compact width `RunPanelHost` shows
  the same `RunPanel` as a bottom sheet, medium and large, with background
  interaction on at medium so the page stays usable.
- **State is `RunSession`** (one per `NoteEditor`, fed from the coordinator's
  parse like the action bars). Results and input are kept by block *ordinal*
  and moved by `RunSession.remap` after each parse: an unchanged block is
  followed to its new ordinal, an edited one stays where it is, and its result
  is then stale (`ranHash != contentHash`, dimmed with "Code changed since this
  run"). Output blocks and SQL are not in the strip.
- **The runner is injected.** `RunServiceFactory.make()` returns the debug stub
  under `-debug-run-stub ok|compile-error|runtime-error|time-limit|capped`,
  which also opens the panel and runs the first block after a second; with no
  runner the Notes | Run control isn't shown. R4 supplies the real client.
- **Free readers**: the Run segment carries a PRO mark and, until P2's
  paywall exists on main, opens an alert saying Run is Pro's.
- Not in R3: Keep in Note, compile-error links, the ▷/⌘R wiring, the
  offline fallback button (all R4).
