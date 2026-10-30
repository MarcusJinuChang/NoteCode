# T. Text size and the text hotbar

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## T1. Text size: instant, no alert

**Do.**
- Delete the three confirmation alerts (`PageDetailView.swift` 266–295) and
  `sizeAwaitingConfirmation`, `spacingAwaitingConfirmation`,
  `selectionSizeAwaitingConfirmation`, `inkQuestionAnswered` in `NoteEditor`.
  Keep the Custom… field. Make a note's size change and a line-spacing change
  undoable (register on the text view's undo manager; one step each).
- **Measure** a size change on a 250-line note with code and headings: time
  from the tap to the settled layout, with a `sample` of it. Find what
  dominates: restyling the whole attributed string, laying out the whole
  document (anything that asks TextKit for a fragment past the viewport;
  AGENTS.md › action bars), the per-size block-size cache in `NoteEditor`
  (line ~1033), code block re-highlighting, or the canvas.
- **Fix to the numbers.** The aim is that only the viewport lays out before
  the first frame; the rest is TextKit's lazy layout. Restyle in one
  `beginEditing`/`endEditing` that changes fonts by the size ratio rather than
  re-parsing; keep the top line still (the top character stays at the top).
  Shorten `settleDelay` to what the stepper needs (≈120ms) once the change is fast.
- **Headings as size presets** (decision 1): headings are derived from the
  body size in the same pass, so changing size never needs a second pass for
  them. If they already are, say so and change nothing.

**Done when.** No alert in any path (a test that setting a size on a note with
ink commits it); undo restores size and layout; the measured time is in the
PR before and after, with a target under 100ms to first frame on the
simulator for 250 lines; the top line stays (check with `-debug-report`'s
`topLine` before and after a change). Run `NoteEditorTests`,
`MarkdownLayoutTests`, `CodeBlockRoomTests`.
**Read:** `design/coloured-and-sized-text.md`, `design/typing-style.md` (size parts).

## T2. The text hotbar, rearranged

**Do.** The secondary row (`TextOptionsRow`) leads with what's used most:
**Bold, Italic, Underline, Strikethrough**, then the **text colours** as
swatches in a row (all of `TextColour`, plus highlight), then size. Move what
those displace (quote, link, lists, indent, heading) to the primary hotbar or
behind one "More" control, without dropping any. Remove the glass from
`TextOptionsRow` (its one `glassEffect`): a plain opaque background with a
hairline, matching W4. The row must still fit an 11-inch portrait iPad;
scroll horizontally only if it can't.

**Done when.** Every action that was reachable still is (list them in the
PR); `HotbarUITests` updated if it names buttons by position; screenshot of
the row in light and dark on the 13-inch and 11-inch portrait.
**Read:** `design/navigation-and-the-text-options-row.md`, `design/colour.md`.
