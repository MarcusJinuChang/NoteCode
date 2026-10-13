# v3 phase 3: writing, with Markdown markers hidden

Branch `claude/v3-phase-3-writing`, off `claude/v3-phase-2-home` (phase 2 isn't
merged yet, so this stacks on it).

## What changed, and how it works

**Markers take no room.** In a note whose `markdownLayout` is `rendered` (every
new note, and old notes with no ink), `#`, `**`, `*`, `~~`, backticks and a
link's `[` and `](url)` are laid out at zero width. TextKit 2 asks the content
storage's delegate for each paragraph as it lays it out, and `BlankLineLayout`
(which already swapped a blank line for a zero-width space) now also swaps each
marker for U+2060 WORD JOINER: zero width, no line break, and *the same length*,
so every offset in the paragraph still means the same character. The note's text
isn't touched, so search, copy and export see the Markdown. The ranges come from
`DocumentStyler.layouts`, the ones that dim markers in an old note, so styling
and layout can't disagree.

The point of "layout, not caret": whether a marker takes space is a function of
the text only. A marker that appeared when the caret arrived would push the
words after it and re-wrap lines, and ink stays where it was drawn.

**What the caret changes is only drawing.** A heading's `#`/`##`/`###` is drawn
in the left margin by `HeadingLayoutFragment` (right-aligned 8pt left of the
text) while the caret is on the heading, or always with Show Markdown › Always;
never in ink mode, never printed. It works like the code fences: asked at draw
time, and `setNeedsDisplay` on the fragment views that changed, so a caret move
lays out nothing and edits no text (tested). Inline formatting shows in the
hotbar instead: Bold, Italic and Code light up, and Style ▾ and List ▾ show
checkmarks.

**Editing what you can't see** (`MarkdownFormatting+Markers.swift`, all pure, on
the one line the caret is on):

- *Caret stops.* Every offset inside `**` is the same place on the page, so a
  hidden stretch is one stop: its left edge for inline markers (the end of a bold
  word is inside it, the start isn't), after it for a heading's `# `. Applied to
  taps (`closestPosition`) and on selection changes. An arrow key steps over a
  marker in one press. **Never after typing**: typing the closing `**` leaves the
  caret after it, and moving it back inside would put the next letter in the bold.
- *Backspace.* At the start of a heading's (or list item's) text it removes the
  marker; into a closing marker it deletes the last visible letter of the span,
  and an emptied span takes its markers with it. Through `replace(_:withText:)`,
  so it undoes and restyles like typing.
- *Return at the end of bold* puts the newline after the hidden `**`: the caret
  stands in front of it, and a plain newline split `**` from its word.

**Lists.** Return continues a bullet, a number (keeping `.` or `)`) or an empty
checkbox, moves the text after the caret to the new item, and on an empty item
ends the list; one undo step. Tab nests two spaces, ⇧Tab takes them back (a
`UIKeyCommand`, since a bare Tab in the menu bar would take it from every field),
only on list items. List ▾ now has Bulleted, Numbered and Checklist.

**Checklists.** `- [ ]` / `- [x]` is `ListMarker.checkbox`. `ChecklistLayoutFragment`
draws the box (outline, or accent fill with a tick) in the em space the `[ ]` was
swapped for, or over the `[ ]` glyphs in an old note. Ticked items are struck
through and quieter. The PDF draws boxes too.

**Taps on boxes and links.** A touch on an editable text view belongs to the text
view's own recognisers, which place the caret and raise the keyboard. Their
recogniser is on a view *inside* the text view, so refusing it in
`gestureRecognizerShouldBegin` doesn't work; instead `DocumentUITextView.hitTest`
answers with itself for a touch on a box or a link, so the inner view never sees
it, and a tap/hold recogniser on the text view takes it (`MarkerTaps.swift`). The
recognisers have their own delegate object: a scroll view is the delegate of its
own pan, and answering for that would answer for scrolling. Links are
`[text](url)` and bare `http(s)://` addresses (shown as typed), in the accent
colour, underlined. A tap opens Safari; a hold shows the address with Open Link
and Copy Link. Only http, https and mailto open.

**Old notes.** A note with ink keeps its visible markers until the title menu's
**Hide Markdown Markers…** (with the board's wording). PDF and thumbnails take
the same layout (`PrintedNote(rendersMarkdown:)`), or paper would break lines
where the screen doesn't. A thumbnail's cache name now says whether the note is
rendered, since hiding markers isn't an edit.

**One parser change you didn't ask for.** `2 * 3 * 4`, `int *p and *q` and
`snake_case_name` parsed as emphasis. That was a dimmed asterisk before; with
markers hidden it would make characters vanish from notes about code. Emphasis
now can't start with a space or end after one, and `_` can't open or close inside
a word (`InlineMarkupLookalikeTests`). `__init__` is still bold, as in CommonMark.

## Decisions to look at

- **No `primaryActionForTextItem` spike.** The box needs the tap path anyway and
  it serves links too. Easy to revisit if you'd rather use the system's.
- **Numbers aren't renumbered** after an inserted item (`1. 2. 2. 3.`), as the
  brief says "next number".
- **Return/Backspace/Tab rules apply in legacy notes where they make sense**
  (Return, Tab, list Backspace not: Backspace's rule is about *hidden* markers).
- **Exit from bold at a line's end** is an invisible caret stop (arrow right
  moves from inside the bold to just past the markers); the hotbar's Bold shows
  which side you're on. Mid-line the arrow moves one visible place.

## Tests

`MarkdownLayoutTests` (the probe: every line equals the same note with markers
deleted, in seamless, print and landscape; carets; edits that change the parse,
including a fence opened above; paper; typing cost), `HeadingMarkerTests`,
`MarkerEditingTests` (caret stops, Backspace, Return, Tab, boxes, links, state as
tables), `InlineParserTests`. 895 unit tests pass on the iPad Pro 13-inch (M5);
the macOS build succeeds. Three `HotbarUITests` reach tests fail looking for a
"Red" swatch, **identically on the phase 2 branch** (checked on a clean
worktree), as in phase 1.

Mutation checks: swapping markers off fails the line-equality test in all three
layouts; the caret-stop and Backspace rules disabled fail their tables and the
text-view tests; shrinking the heading's drawing area fails
`surfaceReachesTheHashes`. A keystroke in a 500-line rendered note costs 37.2ms,
legacy 37.0ms.

## What I did and didn't check on screen

Looked at in the iPad Pro 13-inch simulator (dark): markers hidden in a note with
headings, bold, code, strike, links, bullets, numbers and checkboxes; a real tap
on the heading puts `#` in the margin with the text not moving; a real tap ticked
a box without a keyboard shifting the page; Return at the end of a checklist item
made a new open box that typed into.

**Not checked:** the Pencil; a hardware keyboard (⇧Tab, Tab, arrows past markers,
⌘B on a double-tapped word); a tap on a link and the hold menu; light mode of the
margin hash by eye (the pixel test covers it); fast typing and pasting into a
rendered note; Hide Markdown Markers… on a note with ink; the macOS app running.

## Marcus's checklist (iPad)

1. New note. Type `# Hash tables`, Return, then `A **bold** word and `code``.
   Expect: the `#` and `**` vanish as you finish each; the words don't jump
   afterwards. Tap the heading: `#` appears in the margin and the text doesn't move.
2. Hold Return/Backspace at the start of the heading: Backspace removes the
   heading (one press).
3. Put the caret at the end of "bold" with the arrow keys. Bold lights up in the
   hotbar; typing stays bold. Press → : you're past the closing markers, typing
   is plain. At the end of a line, Return keeps the bold whole.
4. List ▾ › Checklist; type items with Return between. Tap a box: it ticks, the
   keyboard doesn't move, the caret stays. Return on an empty item ends the list.
5. Tab and ⇧Tab (hardware keyboard) nest and un-nest.
6. Type `[notes](https://example.com)`: tap "notes" opens Safari; hold shows the
   address with Open Link / Copy Link. A bare `https://…` link too.
7. A note with ink from before: markers still show. Title menu › Hide Markdown
   Markers…, confirm, and look at where the ink sits.

**Counts as a bug:** text moving when the caret enters a heading or a bold word;
a caret that stalls for several presses at a marker; a letter typed after a
closing `**` landing inside the bold; a box tap that raises the keyboard, moves
the caret or scrolls; Return splitting `**` from its word.
