# Formatting per character
Text overhaul, phase 3 (18 Oct, branch `claude/per-character-formatting`;
docs/archive/text-system-overhaul.md, decision 3). Bold, Italic, Code, Strike,
colour, size and + and − act on exactly the characters asked for, and
combine: Italic on a bold word is bold italic, a size on "ld" of a bold word
sizes "ld". The pure part is `StyledLine`; `MarkdownFormatting.toggle` and
`.style` sit on it through `lineParts` and `restyle`.

- **A line is read as glyphs** (`StyledLine.glyphs`): each composed
  character the page shows, with what it is drawn with (`Style`: bold,
  italic, strike, code, a link, colour, size). A change sets or clears one
  attribute on a range of glyphs, and the line is written back.
- **Only the stretch that has to change is rewritten**: out from the
  changed glyphs to the nearest places where nothing is open *and* the node
  just outside isn't a marker (`mayStart`, `mayEnd`). Without the second
  half, bolding `b` in `**a**b` wrote `**a****b**`, which reads as one bold
  holding four stars; with it the stretch takes in `**a**` and comes out
  `**ab**`. The rest of the line keeps its bytes, `__bold__` included, and
  the edit is cut to what changed (`minimalEdit`, never between the halves
  of a surrogate pair).
- **Written the shortest way that reads back.** Six nestings are tried
  (`Layer.orders`): the run's tag outside the emphasis or inside it, bold
  outside italic or inside, emphasis outside a link or, for a link with part
  of its own text bold or coloured, inside it; code always innermost. Each
  is written, parsed again and compared glyph for glyph with what was asked
  (`draws`); the shortest that matches wins, the first of equals. So a size
  on "ld" of a bold word is `**bo<span …>ld</span>**`, not
  `**bo**<span …>**ld**</span>`, and a bold sentence holding a link is
  `**see [it](u) now**`, not split round the link. Equal neighbours share
  markers. The plan's one fixed order (tag, link, then emphasis) split
  every bold sentence round its links, which is why there are several.
- **Stars, then underscores.** Italic that starts where bold ends puts `*`
  beside `**`, and the three make one run that pairs another way
  (CommonMark's rule of three): in random tests 47 of 3,000 stylings had no
  nesting that read back with stars alone. `**`/`_` and `__`/`*` are tried
  after `**`/`*` (`Delimiters.choices`), only if no star version works.
- **Spaces at the ends of bold, italic and strike go outside them**, which
  can't open before a space or close after one, and so lose them
  (`normalised`, judged by the style asked for: a space just made code is
  code). A tag and code keep theirs.
- **What can't be written is not written.** The parser has no escapes, so a
  `*` typed as text can pair with new markers: `restyled` returns `nil` when
  no nesting reads back, and the button does nothing rather than leave a
  line showing its markers. `x*` made bold is `__x*__`; `*x_` made bold
  can't be written, nor `` `**x**` `` taken out of code.
- **Code spans and links are atoms** (`wholeAtoms`): a change that touches
  part of one takes all of it. Half a link would be two links, and code
  can't hold a marker.
- **Toggle with a selection** sets the style on every glyph of each line's
  part, or clears it if every glyph but spaces already has it (spaces
  can't carry it at a stretch's end, so "word " selected in a bold word
  unbolds it). Lines of code are left alone; before, a selection into a code
  block wrapped its lines in `**`.
- **Toggle with a caret** acts on the word the caret is strictly inside
  (`StyledLine.wordGlyphs`), as a selection of it would, out to the whole
  link or code span if the word is in one; a caret anywhere else is the typing
  style's (phase 4, "Typing style"), and `toggle` returns no edit. The whole
  span a caret is in no longer loses or gains the style: at the end of a
  bold word that took the word just typed with it. The empty pair `****` is
  gone. A caret in code does nothing.
- **The selection keeps its characters**: from just after the markers in
  front of its first glyph to just before those behind its last. A caret
  stands in front of its glyph, before any markers there, which is the
  caret stop anyway. So two lines made bold read `**«one**\n**two»**`.
- **The bar lights Bold for a selection when every glyph but spaces is
  bold**, over every line (`formatting(at:)`), which is when Bold takes it
  off. It lit only for a selection inside one bold span before, so
  `**a** **b**` selected showed Bold off and Bold removed it.
- **+ and −** step each glyph from its own size: see "Coloured and sized
  text".
- **Read the same by GitHub** (its Markdown API, 18 Oct) for nine written
  lines of ten: `***word***`, `**bo*ld***`, a run inside bold, bold inside a
  run, a link inside bold, `**)_`:`_**_`a`_`, `__x*__`, `*a****b***`, bold
  inside a link. The tenth, `**_c~~( b~~_**`, GitHub reads without the
  strike: GFM won't open `~~` after a letter and before punctuation, and
  the parser has no flanking rule for tildes (phase 2 kept today's). Not
  looked at in Obsidian.
- **Tests** (`StyledLineTests`): 3,000 random stylings of marker-free text
  (bold, italic, strike, code, colour, size, links, overlapping), every one
  written and read back as asked, spaces aside; 4,000 random lines full of
  markers and lookalikes with a random selection toggled, each either no
  edit or every glyph the same with only the style set or cleared; and the
  cases above. `StyledLineEditorTests` sizes two letters of a bold word in
  the editor and undoes it in one step.
- **Mutation-checked** (18 Oct, each fails the tests named): the read-back
  skipped (`roundTrip`, `neverCorrupts`, `refusesWhatWouldShowMarkers`; the
  test host crashes); a stretch let start beside a marker (`joinsNeighbours`);
  stars only (`roundTrip`, `refusesWhatWouldShowMarkers`); no atoms
  (`atoms`); the bar's old rule for a selection
  (`ListEditingTests.selectionState`). A space judged by its old style, not
  the one asked for, was found by `roundTrip` while writing it.
- **Cost:** a button rewrites one line in about 0.04ms (Mac, through the
  same files compiled alone); reading 500 lines as glyphs takes about 6ms,
  which is what the bar's check on a select-all would cost, so it stops at
  the first line that settles every style. The keystroke path is untouched.
- **Not checked on screen:** any of it. The iPad, the Pencil, a hardware
  keyboard (⌘B, ⌘I on a selection), the edit menu, the bar's lit state on a
  selection, and Obsidian.
