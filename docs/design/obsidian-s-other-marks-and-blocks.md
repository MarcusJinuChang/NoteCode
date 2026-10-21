# Obsidian's other marks and blocks
Text overhaul, phase 6 (19 Oct, branch `claude/obsidian-blocks`, off `main` with
phases 1 to 4 merged; docs/archive/text-system-overhaul.md). Underline, highlight,
quotes, rules, and H4 to H6 in Style ▾. The formats are Obsidian's, so the
note reads there as it does here.

- **Underline is `<u>text</u>`** (`InlineMarkup.underline`), read in either
  case. GitHub drops the tag and keeps the text. Drawn with `.underlineStyle`,
  on the text only (a link already has it).
- **Highlight is `==🟡text==`** (`InlineMarkup.highlight(HighlightColour)`),
  Obsidian 1.14's own, the emoji required: 🔴 🟠 🟡 🟢 🔵 🟣. A plain `==x==` is
  left alone on purpose, since a note about code is full of `a==b`, and with
  markers hidden a false highlight would make the `==` vanish; the emoji can't
  be typed by accident. GitHub shows `==🟡` as text (research §2.3).
  - **The emoji is part of the opening marker**, hidden with the `==`
    (`MarkdownLayout` swaps every UTF-16 unit, a surrogate pair's two).
  - **Both are tags**, so they pair on the stack a run's `<span>` does
    (`InlineMarkup.isTag`, `tagFamily`): a `</u>` takes the nearest open `<u>`,
    a `==` the nearest open highlight, and the emphasis between is settled on
    its own. Tags of another family opened between are dropped with it, so
    tags that cross are text, as emphasis that crosses is. `isSpanTag` is now
    every tag, which is what Backspace, search and Get Info already used it for.
  - **`=` runs.** With a highlight open, the first two `=` of a run close it;
    what is left is read next, so `==🟡a====🔴b==` is two highlights side by
    side (the writer needs that for two colours touching) and `===` is a
    closing `==` and an `=`. With none open, a run of exactly two followed by
    an emoji opens one; any other run is text (`a == b`, `====`, `===🟡`).
  - **A highlight holds no other**: the next `==` ends it, and `==🔴…` after
    that is text. A highlight's text ending in `=` can't be written
    (`==🟡x===` reads as `x` and `=`), so that edit is refused and the line is
    left whole, as any line that can't be read back is.
  - **A bare address inside a highlight stops before the closing `==`**, only
    inside one: outside, an address ending `==` (a padded base64 query) keeps it.
  - **The block signature's attribute bits were moved** to make room
    (`InlineAttributes.signature`: flags 0 to 5, the highlight 6 to 8, the
    colour 9 to 33, the size from 34); `signatures` checks no two differ.
- **Colour of a highlight** (`HighlightColour.hex`, `alpha`): a bright system
  hue laid over the page at 38% in light and 40% in dark, a dynamic colour per
  colour, made once (`DocumentStyler.highlightColour`; two made alike aren't
  equal and the styler writes whatever differs, as for `textColour`). The label
  colour reads on every one, 4.5:1 or better in both (`HighlightColourTests`
  blends and computes). A coloured run's text is made legible against the
  page, not against a highlight under it: red text on a blue highlight, as on
  screen, is less than that. Drawn with `.backgroundColor`, after code's own,
  so a highlighted code span shows the highlight.
- **Underline and highlight are written by Phase 3's writer** (`Layer.underline`,
  `.highlight`; `InlineStyle.underline`, `StyleChange.highlight`), so they combine
  with everything and come off alone, and by Phase 4's typing style
  (`TypingStyle.underline`, `.highlight`; ⌘U, the bar lit, one undo step).
  - **Twelve nestings are tried, not six**: each of Phase 3's with the two tags
    outermost and with them just outside the code. A sentence highlighted with
    one word bold is `==🟡a **b** c==` with them outside, and a highlight round
    every piece inside (`oneHighlight`).
  - **Spaces.** A tag keeps the spaces it is given, so Underline over
    `« word »` underlines them (`a<u> word </u>b`), where bold sheds them.
    Highlight is a style like Colour and Size, which leave a selection's end
    spaces out (`a ==🟡word== b`).
  - The random round trip (`StyledLineTests.roundTrip`, 3,000 stylings) has
    both in it, with colours side by side; `InlineMarkWritingTests.lookalikes`
    is 3,000 more over text full of `=`, `<`, `u` and `🟡`: refused or read
    back exactly, never half written.
- **Where they are in the UI.** ⌘U (`NoteShortcut.underline`, in Format) and the
  edit menu's Underline; Style ▾ has Underline above Strikethrough; the text
  row has a Highlight menu (the highlighter, the six, None) after Colour on a
  paragraph or a list item. The face is the highlighter in the caret's colour.
- **H4 to H6** are in Style ▾ and the edit menu's Format. The parser, fonts and
  outline already took six levels (H4 title3, H5 headline, H6 subheadline, bold
  all); only the menus stopped at three. `MarkdownFormatting.headingLevels` is
  the one range. The text row keeps chips for Body and H1 to H3: a row is for
  what is used most, and at H4 to H6 none is lit.
- **A quote is `> text`** (`BlockNode.Kind.blockQuote(depth:inlines:)`): up to
  three spaces, then one or more `>` each with an optional space, the depth
  the count. One block a line, as every prose line is. Its text is inline
  Markdown and nothing else: `> # h` and `> - a` show their `#` and `-`.
  - **The marker is hidden** like a heading's (`MarkdownLayout`, the caret
    stop after it, Backspace at the start of the text removes it).
  - **Indented, not in the margin**: 16pt a level (`ProseBlockMetrics.quoteIndent`)
    by the paragraph's head indents, so the bar is drawn in that room
    (`BlockquoteLayoutFragment`) and a quote never leaves the page's column.
    Wrapped lines hang under the first (`indent` checks the caret's x).
    `applyTypingAttributes` carries the indent, or a new line starts at the margin.
  - **The bar is drawn from the lines**, never the fragment's frame: one stretch
    per run of lines that touch (`ProseBlockMetrics.barRuns`), so a quote
    split by a page break has a bar on each page and none across the gap. The
    PDF and thumbnails draw a page's lines one at a time, and `NotePDF.draw`
    calls `drawBars(of:)` with the ones on the sheet.
  - **Return** carries the `>`s to the next line; on an empty quote line it
    ends the quote (as an empty list item ends a list); before the marker it is
    a plain newline. **Quote** toggles (`MarkdownFormatting.toggleQuote`): it
    replaces a heading's or a list item's marker, leaves a line that is
    already a quote, and takes off every level when all are quotes. The text row
    has a Quote chip after H3; Style ▾ has Quote, ticked inside one.
- **A rule is `---`** (`BlockNode.Kind.rule`), three hyphens or more and
  nothing else, up to three spaces in front and any after. The dashes are its
  marker, hidden; its content is the line's end alone, so a rule's inlines are
  its terminator, as a heading's are with no text.
  - **`---` only.** `***` and `___` are rules in CommonMark, but a line of just
    `***` is where `***bold italic***` begins, and with its marker hidden the
    stars would vanish as the third was typed. `- - -` isn't one either.
  - **Not a setext heading**: text above `---` isn't made a heading, as it is on
    GitHub and in Obsidian. Put a blank line above a rule to read the same
    everywhere; **Horizontal Rule** (Style ▾, `MarkdownFormatting.insertRule`)
    does: on an empty line it takes its place, on a line of text it goes below
    with a blank line between, and the caret lands on a fresh line under it.
  - **An ordinary line of text**, no fixed height: `RuleLayoutFragment` draws
    1.5pt across the column (the container's width less the padding, resolved at
    draw time as the code panel's is) through the middle of the line's x-height.
    A fixed height would have meant the baseline lift code fences need, for
    nothing a rule shows, and every line still paginates alike.
  - **The caret stops after the dashes**, wherever it lands in them, so Return
    makes the next line and Backspace there takes the dashes (the line is empty).
  - **Typing `---` by hand**: prose has smart dashes on, which may turn `--`
    into an em dash before the third hyphen arrives. **Not tried.** The menu
    item and a paste make a rule.
- **Search, Get Info, the outline** needed nothing more than `isSpanTag` and a
  prefilter: `SpanStyle.maskingTags` parses only a note that could hold a tag
  (`<span style="`, `<u>`, or `==` and an emoji: a note of code is full of `==`).
- **`NoteThumbnail.version` is 6**: a note with these drew their markers before.
- **Tests**: `InlineMarksTests` (reading, writing, drawn, colours, search,
  typing) and `ProseBlockTests` (reading, editing, on the page): each `=` run
  and lookalike above, nesting and crossing, the writer's round trip, the styler's
  attributes and that a restyle is no edit, contrast of all twelve colour
  pairs, quotes' and rules' markers laid out at no width with every line where
  it would be with the markers deleted (seamless, print, landscape), pixels: the
  bar beside a quote, a rule across the column in both appearances, and both in
  a thumbnail, which takes the PDF's path. `MarkdownFormattingTests`,
  `KeyboardAndMenuTests` and `NoteShortcutTests` changed for the new menu
  items and chord.
- **Mutation-checked** (19 Oct; each fails the tests named when broken):
  the bar not drawn (`barIsDrawn`), nor the quote's fragment made
  (`barIsDrawn`), the rule not drawn (`ruleIsDrawn`), the PDF skipping the bars
  or the rule (`printedBars`, `printedRule`: the first version of that test
  passed with the PDF's call removed, since the `>` glyphs were ink in the room
  beside the text too, so it now measures a stripe a line tall in one column,
  which a glyph isn't); the quote's and rule's markers left laid out
  (`markersCollapse`), the quote's indent left out of the styler (`indent`), the
  caret stops and Return ignoring quotes (`caretStops`, `returnContinues`); a
  closing tag pairing with a tag of another family (`crossing`), a run of four
  not ending one highlight and starting the next (`adjacent`), the writer
  without the outer nestings (`oneHighlight`), the signature without
  underline (`signatures`), highlight and underline not drawn (`highlight`,
  `underline` in `InlineMarkDrawingTests`), Get Info and search seeing the new
  tags (`words`), the search prefilter missing a note whose only mark is a
  highlight (`highlightAlone`), Underline writing strikethrough
  (`underline`), the typing style forgetting either (`written`, `inTheEditor`),
  highlights too opaque to read under (`legible`), Style ▾ stopping at H3
  (`levelsAreTheParsers`). **Not mutation-checked:** the fragments'
  `renderingSurfaceBounds` (see below), the 12-nesting inner variant alone,
  ⌘U's chord, the edit menu's Underline, and the `ProseLine` prefilters.
- **A unit test can't see a crop** (as for a heading's hash): `layer.render`
  doesn't apply the fragment view's bounds, so removing the bar's
  `renderingSurfaceBounds` union leaves the pixel test passing. The bar and
  the rule were looked at in the simulator instead.
- **Checked in the simulator** (iPad Pro 13-inch, iOS 27.0, a note with every
  mark and block): seamless in light and dark (launched with `-appearance dark`;
  `simctl ui … appearance` alone left the app light, since the app's own
  setting outranks it) and print layout. Underline; the six highlights; two
  colours touching; a coloured word inside a highlight; bold and underline
  inside one; a quote of two lines wrapping onto a third with a nested level,
  bars continuous; a rule; H4 to H6; `a == b` and an unclosed `<u>` left as text;
  the text row's Quote chip and Highlight menu. **Not checked:** the Pencil; a
  hardware keyboard (⌘U, Return and Backspace in a quote); typing the marks by
  hand; the Highlight menu and the Quote chip by a tap; Style ▾'s new items open;
  a quote across a page break on screen, and the PDF in the share sheet (the
  thumbnail takes its path); the 11-inch iPad, portrait, the iPhone layout;
  ink over a note whose lines these change.
