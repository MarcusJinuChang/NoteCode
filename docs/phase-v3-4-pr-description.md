# v3 phase 4: code

Branch `claude/v3-phase-4-code`, off `claude/v3-phase-3-writing`.

**Heads up on the stack:** PRs #48 and #49 (phases 2 and 3) were merged into their
*stacked* branches (`claude/v3-phase-1-recently-deleted` and
`claude/v3-phase-2-home`), not into `main`, so `main` still has only phase 1. This
branch's base is phase 3's tip, which holds all of it. Merging this into `main`
directly would bring phases 2 and 3 in with it.

## What changed, and how it works

**Five more languages** (`CodeLanguage`): C, JavaScript, Rust, Go, SQL. Each has
its tags (`js`, `golang`, `rs`, `postgres`, …), a display name, a Compiler Explorer
language id, a highlight.js name and `canRun`. Highlighting now asks highlight.js
for the language by its own name, so `golang` and `js` colour without leaning on its
aliases. Code Block ▾ and the language button list all eight, then a divider, Output
and Plain Text, from one list (`CodeBlockKind.menu`) so they can't disagree. SQL is
**Copy only**: the free sites that take it run it against a database of their own, so
a Run would only open a page.

**Running them, checked on the live sites** (13 Oct). Compiler Explorer takes C
(`cg152`), Rust (`r1990`) and Go (`gl1260`) in the link. Each id was compiled and run
through its API, and a link built the way the app builds it was opened in a browser
for each language: "Program returned: 0" and the program's output. **JavaScript is not
one of them, against the brief:** the only JavaScript compilers on Compiler Explorer
are two V8 builds that cannot execute. So JavaScript goes to Programiz by paste, like
Java does. OnlineGDB has no JavaScript or SQL page (404), so it hands JavaScript to
Programiz too. The ids are pinned and are a maintenance item.

**Output blocks** (```` ```output ````). A dark console panel in both appearances
(`CodeOutputPanel`, the design's tokens), the label "Output", Copy and no Run, no
highlighting, no auto-indent, no line numbers. Pick it from Code Block ▾ to start one,
or from a block's language button to turn one into it.

**Return in code** (`CodeIndent.returnEdit`, pure, so the rules are tables in a test).
It keeps the line's indent; goes one level deeper after `{`, `(` or `[` and, only in
Python, a colon; and between a bracket and its own closer it puts the closer on its
own line and the caret between. A line the caret leaves blank keeps no whitespace. It
runs from `shouldChangeTextIn` and applies through `replace(_:withText:)`, the path
typing takes, so it is one undo step.

**⇥ and ⇧⇥** indent or outdent every line the selection touches (a caret's line,
wherever in it the caret is). That is the brief's wording; the alternative is "insert
a tab at the caret", which on a tablet is rarely what you want. Say if you'd rather
have that. Hardware Tab arrives as a `"\t"` in `shouldChangeTextIn`; ⇧Tab is the
`UIKeyCommand` phase 3 added, which now answers for code too.

**The code-keys row** (`CodeKeysRow`). ⇥ ⇤ `{ } ( ) [ ] < > ; = " ' : / \ | & * #` ← →
on a glass capsule, as an `inputAccessoryView`. `TextRewritingPolicy` already decides
"is the caret in code" to switch autocorrect, so the row follows the same answer, and
it is swapped before the one `reloadInputViews()` that crossing already does: traits
and row change in a single redraw. It is not shown with a hardware keyboard
(`GCKeyboard.coalesced`, refreshed on connect and disconnect). Its keys go through the
same paths as typing, so they undo like typing.

**`keyboardInset` needed no change.** The brief says it must include the row. UIKit's
keyboard frame already does: measured in the simulator it was 498pt tall in prose and
550pt in code (52 more, with its top 52 higher), and the move between the two posts a
new frame, so the text view re-insets as the caret crosses. The tests pin the
arithmetic with those numbers.

**Line numbers** (Settings › Code, off by default). Drawn by the code block's fragment
in the page's left margin, right-aligned against the panel, on each paragraph's first
line. **Not a gutter inside the panel**: that would push the code right, re-wrap it and
move ink. It is drawn the way a heading's `#` is: the fragment's drawing area always
reaches into the margin (so the setting is a redraw and no layout), and the number is
asked for at draw time. A test checks every line frame is where it was with numbers on,
in all three view modes and landscape. They print when on.

**Settings › Code** gains Code Keys, Indent Width (2 or 4) and Line Numbers, carried to
the editor as one `CodeEditorSettings` value with one `apply(to:in:)`.

## A bug found on the way (older than this phase)

Changing a block's language never re-coloured its code. The editor remembers which
blocks it has highlighted by `CodeBlockID`, which is the block's position and its
*code*, not its tag, so python → sql left python's colours on the text. The memory is
keyed by id and tag now. Output made it matter (Python and `output` are both six
letters, so the styler didn't notice the change either; `styleDetail` includes it
now).

## How this was checked

- 1,000 unit tests pass on the iPad Pro 13-inch (M5) simulator;
  the macOS target builds.
- Tables for Return and ⇥/⇧⇥ in C++, Java and Python, 2 and 4 wide, with tabs, blank
  lines, braces, brackets, selections and block boundaries. The row's key set by region
  (code, fence line, inline code, an unclosed backtick or fence, prose). Each new
  language parses, highlights (the colours land on the theme's six roles, all 4.5:1 on
  the panel) and gives run URLs. A margin pixel test in both appearances; the
  right edge lines up for one and two digits; the drawing area reaches five digits.
  The PDF has the numbers when on.
- **Regression tests were proven to fail** with the fix taken out, one at a time:
  styler signature (retag), highlight skip for output, highlight key by tag, output
  colour carried into code, the unchanged-policy refresh, Python's colon, SQL's
  `canRun`, the margin reach, output kept out of numbering, and the PDF's numbers. One
  earlier version of the highlight-key test passed with the fix removed: the test
  window applies its appearance after the first restyle, and a change of appearance
  forgets everything highlighted. It restyles once first now.
- Cost, simulator, 500-line note: a keystroke 30.9ms with line numbers off, 30.7 on;
  34–37ms for the rendered/legacy and fence tests, as before (35–37 on phase 3).
- Looked at in the simulator: the row above the keyboard in code and gone in prose;
  Return after a Python colon on the real keyboard; ⇥ from the row; `{` and `>` from
  the row; the language menu with its divider and "Copy only" on SQL (light); turning
  a block into Output (dark and light); line numbers in the margin (dark and light)
  with a wrapped line numbered once.

## Not checked, and where to look

I couldn't send hardware-keyboard chords or use the Pencil. So, on the iPad:

1. **Hardware keyboard.** Attach one, tap into a code block: the row should not
   appear. Detach it: the row should appear on the next tap (or at once). Tab and
   ⇧Tab indent and outdent the line; Return in a `{ … }` splits the braces.
2. **Typing a program.** In a new C++ block type `int main() {` Return, `return 0;`
   Return, `}`. The body should be indented and the `}` should sit at the left edge
   (you type that `}` yourself; there is no auto-dedent).
3. **The row.** Every key types its character; ← → move a character; a selection
   collapses to its edge. In Split View at about 320pt wide the symbols scroll.
4. **Code Block ▾** shows eight languages, a divider, Output, Plain Text, and SQL says
   "Copy only". Choosing SQL shows Copy and no Run.
5. **Run** a C block, a Rust block and a Go block with Compiler Explorer as the
   destination: they land on a finished run. A JavaScript block opens Programiz with
   the code on the pasteboard.
6. **Line numbers** (Settings › Code): on, with a note of several pages and a long
   wrapped line; scroll past a page break. Off again. Share the note as a PDF: numbers
   present when on.
7. **Output.** Turn a block into Output and back; the colours should return.

A bug would be: numbers clipped at the page's left edge, the code moving when numbers
turn on, a stray space after Return on a blank line, the row on top of the hotbar, or a
hardware keyboard showing the row.

## Left for later

- The label colour on Output in dark is the design's own and is 4.3:1, a little under
  4.5 for 13pt text.
- No auto-dedent when you type `}`, as the brief didn't ask for it.
- `Compiler Explorer` ids will go stale; re-check them if a Run lands on an error.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
