# Coloured and sized text
Roadmap step 10, second and third parts: colour (17 Oct, branch
`claude/text-colour`, on `claude/code-block-room`) and size (17 Oct, branch
`claude/text-size`, on `claude/text-colour`). The format is step 3's
recommendation (docs/research-notability-obsidian.md). `SpanStyle` holds the
tag, `TextColour` the palette, `SpanSize` the sizes. Any size since 18 Oct
(text overhaul, phase 1; docs/archive/text-system-overhaul.md).

- **Written as Obsidian writes it:** an HTML span with an inline style, on
  one line, colour first when it has both, so the two never nest:
  `<span style="color:#E5484D">`, `<span style="font-size:1.25em">`,
  `<span style="color:#E5484D;font-size:1.25em">`. The one convention
  Obsidian draws with no plugin that GitHub reads as plain text. Exactly
  these shapes (hex and keywords in either case); any other `<span …>`
  (another property, another order, `px`), an unclosed one or an empty one
  is visible text, so pasted HTML is never half hidden.
- **Parsed on the emphasis stack, first** (since 18 Oct; see "Inline
  nesting"): each tag is a marker node (`InlineNode.Kind.opening(.styled(_))`,
  `.closing`), a `</span>` takes the nearest opening tag, and the emphasis
  between them is settled on its own, so a span can't cross a run's edge.
  `**<span …>x</span>**` and `<span …>**x**</span>` both read, and runs
  nest. The menus always write `<span …>**x**</span>`, one run deep.
- **Because the tags are markers, everything marker-based follows for
  free:** `MarkdownLayout` collapses them to word joiners (no room), the
  caret stops at their left edges, Show Markdown never draws them, and the
  outline's titles leave them out.
- **Colour is drawn made legible:** the stored hex taken toward black on
  a light page and white on a dark one just far enough for 4.5:1
  (`AccentPalette.textHex`, as links are), so a colour from elsewhere reads
  as well as the palette's. Colour goes on before the spans inside it, so a
  link keeps the link colour.
  - **One `UIColor` per hex** (`DocumentStyler.textColour`, cached): two
    dynamic colours from the same hex aren't equal, and the styler writes
    whatever differs, so a fresh one each restyle rewrote every run and laid
    out the note below it on every keystroke.
    `TextColourLayoutTests.restyleIsNotAnEdit` fails without the cache.
  - The palette: Red `#E5484D`, Orange `#E5750A`, Yellow `#B88700`, Green
    `#2F9E44`, Blue `#3B82F6`, Purple `#9061F9`, each at least 4.5:1 once
    adjusted, in both appearances (tested).
- **Any size, stored as em, shown in points** (decided 18 Oct, Marcus;
  docs/archive/text-system-overhaul.md, decision 1). `SpanSize` holds thousandths of
  an em against the block's font, so a heading's run is a larger heading
  (still bold), and a note resized as a whole keeps its proportions. The
  styler sets it to the half point (`SpanSize.points(against:)`,
  `DocumentStyler.font(_:sizedTo:)`), and a size chosen in points is
  written as points over the block's size (`init(points:against:)`), to the
  thousandth: every half point from 8 to 72 comes back exactly, beside every
  block of every note size (`SpanSizeTests.pointsRoundTrip`,
  `SpanSizeLayoutTests.pointsInEveryBlock`). Step 10's 0.85, 1.25 and 1.5em
  read as before; any em reads as written, clamped to 0.1–10; exactly 1em
  is no size. Spans inside a sized run build on the sized font, so bold in
  a large run is large bold.
  - **The number moves with its block.** 24 in a 17pt paragraph is 1.412em,
    and shows 27 once the note is 19, or 48 moved into an H1. Word and Pages
    keep points; em was chosen for the note's size and for Obsidian.
  - **`withSize` keeps the leading, scaled** (measured 18 Oct: 1.713pt at
    17, 2.418 at 24, where `systemFont(ofSize:)` has none), so a run at its
    text's own size lays out exactly as plain text, and a sized line is as
    tall as its own text makes it (31.06pt at 24). The system's 23pt body
    at xxxLarge has a smaller leading than 17pt scaled to 23 (1.553 against
    2.317): sizes made by `withSize` are their own line height, not a
    Dynamic Type step's.
  - **A sized line is taller, and that is all:** a line is pushed across a
    page break whole, so every mode still paginates alike (see "Code blocks:
    room around and inside" for why room is never paragraph spacing).
  - **It re-wraps, and never asks** (T1, 26 Oct): there was an alert on a
    note with ink, since ink stays where it was drawn. A size is used too
    often for a question; it is undoable instead (the selection's size is a
    text edit, the note's size and line spacing register one undo step each,
    `NoteEditor.applyTextSize`). Measured on the simulator, a size change on
    a 376-line note with headings and code takes 55 to 100ms to its first
    frame, four fifths of it layout and 7 to 20ms the restyle
    (`TextSizeCostTests`), so the restyle was left alone. Headings come from
    the body size in the same pass (`NoteTypography.blockSizes`).
- The block signature's inline hash carries the style, since a recolour or
  resize changes no length.
- **The size control** is the row's `+ 17 −` (`SizeControl`, decision 2,
  18 Oct): the size of the text at the caret or the selection in points,
  from `CaretFormatting.sizes` (each line's heading level and run size,
  `MarkdownFormatting.sizes`), turned into points with the note's fonts
  (`NoteEditor.selectionTextSize`, `NoteTypography.blockSizes`). A dash for
  a selection in several sizes, a heading and a paragraph included. Size ▾
  went into it.
  - **+ and −** step a point (`NoteEditor.stepSelectionSize`), and wait out
    `settleDelay` as the note's size does, so five taps re-wrap once (120ms after the last tap). Since phase 3 each character steps from its own
    size (`SizeRequest.steps`, `StyleChange.steps`), so a selection of 17
    and 24 goes to 18 and 25 and the control keeps its dash. They stop at 8
    and 72; text already past them steps back towards them
    (`SpanSize.stepped`).
  - **A caret moved during the pause** puts the size on at once, and stays
    where the reader put it (`NoteEditor.offset(_:through:replacing:)`, since
    the edit rewrites whole lines); text typed during it drops the tap.
  - **The number** lists the presets, 8 to 72 as Word's are, then Default
    (the text's own size: takes the size off) and Custom…, an alert asking
    for points (`NoteEditor.points(typed:)`: "pt" or not, a comma for a
    point, clamped, to the half point).
  - **Off** in code (it shows the code's size) and on a locked note. A
    caret not inside a word sets the typing style's size instead of sizing
    text (text overhaul, phase 4; see "Typing style").
- **The colour menu** ends the text options row for a paragraph, heading or
  list item (`ColourMenu`: the six colours and Default; its face is the
  caret's colour or an empty ring), `.menuOrder(.fixed)`, so it reads top to
  bottom whichever way it opens. `MarkdownFormatting.style` makes the edit
  for colour and size (`colour`, `size`, `size(points:blockSizes:…)`, which
  writes each line against its own block, and `size(steppedBy:…)`), per
  character since phase 3 (see "Formatting per character"):
  - the selection, or the word the caret is strictly inside (the run it is
    in is no longer the caret's target, since phase 4; a caret anywhere
    else sets the typing style, see "Typing style");
  - each line's part, after a heading's or list item's marker, spaces at
    the ends left out;
  - exactly those characters: part of a red run made blue is a blue run
    beside a red one, and half a bold word can be red;
  - each keeps its other setting: a large red run made blue stays large,
    and text that loses its last setting leaves its run;
  - code spans and links are taken in whole.
- **Smart punctuation is turned away during a formatting edit.** UIKit runs
  smart quotes over a formatting edit's text as if typed, as separate
  one-character edits inside the replace, and turned a run's quotes curly,
  so it stopped being a tag and showed as text (seen 17 Oct on screen, two
  `"` → `“`/`”` edits logged while `isFormatting`). The coordinator refuses
  them (`TextRewritingPolicy.isSmartPunctuation`). A unit test can't see
  it: with no keyboard up, UIKit converts nothing. Checked in the simulator.
- **Backspace** on a run's last visible letter takes both tags with it (or
  `<span …></span>` would show as text), from in front of bold's closing
  `**` inside the run too, and from inside or after `</span>` acts as from
  in front of it, never deleting a hidden tag character.
- **Search and Get Info leave tags out.** Search reads the note with each
  tag replaced by word joiners unit for unit (`SpanStyle.maskingTags`), so
  "span" or "color" finds nothing, an excerpt shows no tag, and match
  offsets still point at the note's own characters. The tags are the
  parser's, so a tag in a code block is code, and found. Get Info skips
  words inside tags.
- **Not built:** a colour shortcut. Highlight is built (phase 6, "Obsidian's
  other marks and blocks"), as are a typing colour and size (phase 4,
  "Typing style").
- **Checked in the simulator** (11-inch, light and dark): colour runs, the
  colour menu and its face, recolouring a run beside another on one line,
  colouring a word in a list item; sized runs in a heading, a paragraph and
  a small aside, the size menu lit and resizing a run. **Not checked:** the
  iPad, the Pencil, a hardware keyboard, the PDF
  of a coloured or sized note, a selection over several lines on screen.
- **Free sizes, checked in the simulator** (18 Oct, 11-inch, light, bottom
  dock): the control dimmed with no caret on a word and live at 17 with
  one; + stepping a word from 17 to 22 and the line growing after the
  pause, the caret staying after the word; the list (72 down) and 36 picked
  from it. One of five synthesised taps in quick succession didn't count
  (21, not 22); a single tap after it did, and `stepsSettleOnce` counts five.
  **Not checked:** Custom…, Default, ••• › Text Size, ⌘+ and ⌘−, the ink
  question, a selection in several sizes (the dash), a side dock, dark
  mode, the iPad, the Pencil.
