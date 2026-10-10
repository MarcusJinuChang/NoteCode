# Phase 5: code-block fences, away and editing

Branch `claude/ui-phase-5-fences`, off `origin/main` at `d6d0020` (phase 4 is
merged). Not pushed.

## What changed

A code block shows its backticks only while the caret or a selection is in it
(opening fence to closing fence).

| | Opening fence line | Closing fence line | Panel |
|---|---|---|---|
| **Away** | the language's name on the left (C++, Java, Python, the tag as typed, Plain Text for a bare fence); Copy and Run on the right | nothing drawn | as before |
| **Editing** | "```cpp" in the marker colour; Copy and Run | "```" in the marker colour | plus a 1.5pt accent ring |

- The **language name is a button**. Tap it for C++, Java, Python, Plain Text
  (the block's is ticked). Choosing rewrites the fence's tag through
  `replace(_:withText:)`, so it can be undone, and Run follows the new language.
  A locked note shows the name dimmed and the menu does nothing.
- **Ink mode:** every block is away. **The PDF:** fence lines and the ring are
  never printed.
- **Setting:** `ShowMarkdown` (While Editing, the default, or Always), stored at
  `showMarkdown`. `PageDetailView` reads it already; its row in Settings is
  phase 6.
- An **unclosed block** counts as being edited while the caret is anywhere from
  its fence to the end of the note, as it is highlighted today.

## Which approach, and a mistake I made on the way

The brief said to try a clear `.foregroundColor` rendering attribute first.

1. **My first spike said it didn't draw.** That was wrong. I measured it by
   counting pixels in the fence line's rect that differed from the rect's first
   pixel. The rect began outside the panel's rounded corner, so the first pixel
   was the page's, and every panel pixel counted as "ink". Hiding the glyphs
   changed nothing in that count. I built the whole feature on that wrong
   conclusion before a corrected measurement (inside the panel) contradicted it.
2. **Measured properly, the attribute works:** 896 pixels → 0, the same
   fragment objects, no viewport layout.
3. **But it fails the edit that matters.** It follows an edit *around* its
   range and not one *inside* it. Replacing the tag (which the new language
   menu does) drew the new text again (0 → 1296 pixels), and so did typing at
   the range's end (1515). So it would have to be set again after every edit to
   an away fence.
4. **So the fragment draws its own fences** (the brief's (b)): it asks the
   coordinator at draw time whether its block is shown, and skips drawing the
   fence line's text if not. There is no state to go stale. This is a choice I
   made on measured grounds that the brief's order didn't anticipate, so say if
   you'd rather have (a) with re-application on each edit.

`CodeFenceDisplayTests.renderingAttribute` records the measurement.

## The mechanics (for learning)

1. **Hiding is drawing.** A TextKit 2 paragraph is drawn by a layout fragment,
   and ours is `CodeBlockLayoutFragment`. Its `draw(at:in:)` paints the panel,
   the selection, then calls `super.draw` for the text. For a fence line of an
   away block it simply doesn't call `super.draw`. The line is still laid out,
   so it is exactly as tall as before and nothing below it moves. That is the
   rule "hide glyphs, never lines".
2. **Why a closure and not a stored flag.** The answer ("is my block
   shown?") changes with the caret while the fragment isn't laid out again. So
   the fragment holds a closure, like `selectedRanges` does, and asks each time
   it draws. It finds its block from its own place in the note
   (`FenceVisibility.blockIndex`, a binary search), because an edit above can
   move a block without touching the fragment.
3. **A fragment view caches what it drew.** On a state change the coordinator
   marks the on-screen fragment views of the blocks that changed with
   `setNeedsDisplay`, using the helper the selection highlight uses. That redraws
   without a layout pass. It only looks at fragments TextKit has already laid
   out in the viewport, so a caret move can't force layout of a far-away block.
4. **The rules are pure** (`FenceVisibility.at`, no UIKit): selection, the
   block ranges, the setting and ink mode in, the set of blocks being edited
   out. The caret rule needed one new fact per block, the end of the closing
   fence's line before its newline (`CodeRange.lastCaret`), because a caret at
   the very end of that line is still on the fence and one a character later is
   prose.
5. **The ring is an open path per fragment.** Each paragraph of a block is its
   own fragment, so each draws only its part: sides always, top and corners on
   the first, bottom and corners on the last. Where fragments meet, the sides
   overlap by the panel's existing overhang; an opaque stroke over itself shows
   no seam. It is inset by half its width so the rendering surface doesn't clip it.
6. **The name is a view** (`CodeBlockLanguageButton`), not drawn text, because a
   fragment can't take a tap. It follows the action-bar rules in AGENTS.md: it
   sits beneath the ink canvas, and its frame counts in
   `containsInteractiveElement` so the text view's own gestures stay off it.
7. **A bug the test found, outside this feature.** Undoing a language pick put
   text back by replacing it inside a code line. That looks exactly like the
   keyboard correcting code, which `shouldChangeTextIn` turns away, and it
   spent the undo step without changing anything. Undo and redo now pass that
   guard. The retag's undo test failed before the fix and passes after.
8. **Another small one:** after a menu pick `replace(_:withText:)` leaves the
   caret inside the fence, which would put the block straight back into
   "editing" and show the fence the pick was made from. `setLanguage` puts the
   caret back where it was, shifted by the edit.

## Cost (the brief asks for it)

Simulator, iPad Pro 13-inch, 500-line note, seamless layout (page breaks are
exclusion paths, so a layout below an edit is what it costs), median of 9, the
method of `PageViewTests.typingCost`:

| | |
|---|---|
| Caret moves into a block | 1.5ms |
| Caret moves out of a block | 1.5ms |
| A keystroke at the same place | 35ms |
| Fragments made during caret moves (counted at TextKit's layout delegate) | 0 |
| Text-storage edits during caret moves | 0 |

TextKit's viewport-layout callback still fires about once per in-and-out cycle;
the fragments are the same objects and nothing is laid out. That is why the
test asserts on fragments made rather than on that callback.

## Tests

- `FenceVisibilityTests`: which blocks are being edited (a caret on each line of
  a block, either side of it, closed at the end of the note, the empty last
  line, CRLF, unclosed, selections, two blocks), ink mode, Always, block lookup;
  `FenceTagTests`: every retag shape.
- `CodeFenceDisplayTests`, on the real text view in a window, light and dark:
  every line frame is identical editing, away and in ink mode, in seamless and
  print layout; the closing fence draws 0 pixels away and its backticks editing;
  the code is drawn the same; the ring is orange along the whole left edge,
  top to bottom, and absent away; the name's position and tap handling; the menu
  and its ticks; choosing, undo, Plain Text; locked; ink mode; typing a block
  out, pasting one, a block added above.
- `CodeFenceCostTests`: the table above; a block split by a page break keeps
  every line where it was.
- `CodeFencePDFTests`: the PDF's text has the code and no "```" and no tag.

**Mutation checks** (patched in, confirmed failing, reverted): collapsing the
fence lines through a text-storage attribute fails the line-frame, no-layout
and cost tests; drawing fences always fails the closing-fence and ink-mode
tests; printing fences fails the PDF test; leaving the undo guard as it was
fails the retag undo test. A sensitivity test also shows the line-frame
comparison does change when fence lines are really removed.

661 tests pass. The macOS target builds.

## What I did and didn't check on screen

Rendered the text view in the simulator test host, light and dark, away,
editing and ink, and looked at the images: the name where the backticks were,
the ring round the block, and the ring splitting at a page break with nothing
between the sheets. **Not** tapped through, not run on the iPad, not tried with
the Pencil, no real typing.

One thing visible in those images that was already true: code text starts at
the panel's left edge, so with the ring on, the first letter of each code line
touches it. I didn't change the panel's padding; say if you want some.

## Marcus's checklist (iPad)

1. **Away and editing.** Open a note with a C++ block. Tap in prose: the block
   shows "C++" on the left, Copy and Run on the right, no backticks. Tap in the
   code: "```cpp" and "```" appear, the name goes, an orange ring wraps the block.
   *Bug if:* any line below jumps when you tap in or out.
2. **Language menu.** Away, tap the name: C++, Java, Python, Plain Text, the
   current one ticked. Pick Python. *Should:* the name changes, Run opens the
   Python site, one undo puts "cpp" back. *Bug if:* the fence appears under the
   menu, the caret jumps into the block, or undo does nothing.
3. **Fast typing into a new block.** Type a fence, a language, some code and a
   closing fence quickly, then a newline and a word. *Should:* fences stay
   while you type; the moment the caret is on the line after, they go and the
   name appears. *Bug if:* the name appears early or the fence flickers.
4. **Pasting a block.** Paste a whole block from elsewhere with the caret after
   it. *Should:* away at once.
5. **Undo across a fence.** Type into a block, tap out, undo. *Should:* the text
   comes back and the block is editing again.
6. **A block split by a page break** (print layout and seamless). Tap in and out.
   *Bug if:* any line moves, the ring looks wrong at the break, or ink drawn
   over the block ends up on different words.
7. **Dark mode:** repeat 1. The ring and name should read in both.
8. **Ink mode:** switch to Draw. *Should:* every block away, names showing,
   nothing moving. Back to Text: the block you were in shows its fences again.
9. **Locked text:** names show, tapping them does nothing.
10. **Share as PDF:** no backticks anywhere, the code panels as before.
11. **A long note:** scroll away from a block you were editing, tap elsewhere,
    scroll back. *Should:* it's away.
12. **Find in Note** for "cpp": the match on an away block's hidden fence has
    nothing to show. I didn't check what that looks like.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
