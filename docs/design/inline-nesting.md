# Inline nesting
Text overhaul, phase 2 (18 Oct, branch `claude/priceless-ardinghelli-fb07ea`,
on `claude/free-text-size`; docs/archive/text-system-overhaul.md, decision 4). The
parser phase 3's per-character formatting needs: `***x***`, `**a *b* c**`,
`**<span …>x</span>**` and `<span …>**x**</span>` now read, markers hidden.

- **Nodes, not spans.** `InlineParser.parse` still returns a flat,
  contiguous list per line, but a marker is a node of its own
  (`InlineNode.Kind.opening(InlineMarkup)`, `.closing`) and text carries
  what it is drawn with (`InlineAttributes`: bold, italic, strike, code,
  link, colour, size), every pair around it folded in. A marker's
  attributes are its pair's surroundings, which is the font a hidden marker
  keeps, so a line is as tall as before. `InlineSpan.spans(in:)` reads the
  pairs back out, outer first, bare addresses included, for the rules that
  act on a whole span (Backspace, the caret's formatting, links, colour and
  size, toggle).
- **How a line is read.** Code spans and links as they come, left to right,
  as before: nothing in code is read, and a link's text is read on its own,
  so nothing in it pairs with anything outside. Then CommonMark's process
  emphasis (spec §6.2) over `*`, `**`, `_`, `__` and `~~`, rule of three
  included: each closer takes the nearest opener of its character, two
  characters from each where both have two, and what lay between can't pair
  past them. Which runs can open and close is still today's rule (no opening
  before a space nor closing after one, no `_` in a word, none for `~~`),
  not CommonMark's punctuation rules.
- **Runs pair first**, on the same stack, as a link's brackets do in
  CommonMark: a `</span>` takes the nearest open tag and the emphasis
  between them is processed on its own, so emphasis that would cross a run's
  edge is text and shows its `**`. Letting the first closer win instead
  would have put a whole `<span style="color:#E5484D">` on the page for a
  bold that crossed a run (`TextColourTests.spansDontCross` asserts the
  former). A run with nothing in it, or nothing to close it, is text.
- **Runs nest**, though the menus never write one: the inner colour, and
  sizes multiplied, as em does in Obsidian's HTML.
- **The styler is one pass over nodes** (`DocumentStyler.apply`): the
  block's font, sized, then bold and italic traits (both for `***x***`), or
  monospaced for code, bold code where it is inside bold. Links keep the link
  colour inside a coloured run. The block signature's inline hash carries
  each node's attributes (`InlineAttributes.signature`): `hxtp://a.io` made
  `http://a.io` is one text node of the same length either way
  (`NestingStylingTests.signatureCarriesAttributes`).
- **Toggle** is per character since phase 3 (see "Formatting per
  character"). A run's tags are never a toggle's span.
- **What changed besides nesting**, found while moving the consumers:
  - A bare address ends at `<`, and before `*`, `_` or `~` at its end that it
    holds none of elsewhere, as GitHub's autolinks do: `**https://…**` is a
    bold address, and `</span>` after an address in a run is the run's. An
    address that holds the character keeps it: `https://x.com/*b*`.
  - Code wins over a run's tags: `` `<span …>x</span>` `` is code. The tags
    were found first before, backticks and all.
  - Bold with the caret just in front of a run's `</span>` replaced the tag
    with `****` (`<span …>word****`): the tag was a span to `toggle`. It no
    longer is.
  - Backspace on the last letter of bold inside a run, from in front of the
    bold's `**`, takes the run's tags too, rather than leaving
    `<span …></span>` on the page.
  - Search masks the tags the parser reads, so a tag in a code block is
    found.
  - Inline code inside bold is code to the keyboard (`TextRewritingPolicy`;
    it was prose), and an unclosed backtick inside bold counts as code
    being typed.
  - The three above were run against the code before, to be sure they were
    what it did.
  - Lines whose stars CommonMark pairs differently from the old left-to-right
    scan: `*foo**bar**baz*` was three emphases and is now emphasis round
    strong.
- **Tests.** `NestingInlineTests`: 108 of the spec's 132 emphasis examples
  (0.31.2), the ones where today's flanking and CommonMark's agree, on one
  line, with no escapes, HTML or entities, generated from the spec's
  `spec.json`; crossing, runs, links, addresses; 4,000 seeded random lines
  checked for contiguous nodes, pairs that nest and text attributes that
  match the pairs around them; and every editing rule on nested lines.
  `MarkdownLayoutTests.nestedLinesEqualMarkerlessLines` is the
  frames-equal-markers-deleted check on nested lines in three layouts.
  Tests written against the old node shape read through `TopLevelSpan`
  (test target), which folds nodes back into that shape, so their
  assertions are unchanged. No existing test asserted the old non-nesting:
  the whole suite passed once those helpers were moved.
- **Mutation-checked** (18 Oct, each fails the tests named when broken):
  the rule of three (spec examples); what lay between a pair left on the
  stack (`crossing`, `randomLines`); a run's emphasis not processed on its
  own (`TextColourTests.spansDontCross`, `crossingARun`, `randomLines`);
  `_` opening inside a word (spec examples 359, 360, 376 and more: the
  lookalike tests alone don't see it, since the closing half of the rule
  already keeps `snake_case_name` text); attributes left out of the
  signature (`signatureCarriesAttributes`); a link's text not read
  (`linkText`); an address running past `<`, or keeping the closing `**`
  round it (`addressEnds`); Backspace taking the innermost emptied span
  (`backspace`, `TextColourTests`); italic dropped under bold (`drawn`);
  markers inside a pair not collapsed (`nestedLinesEqualMarkerlessLines`);
  the caret's formatting reading one span (`caretFormatting`).
- **Cost, measured** (iPad Pro 11-inch simulator, three runs each against
  Phase 1's branch): a keystroke in a 500-line rendered note 37.7–38.9ms
  against 38.1–38.2 (legacy moved the same), `PageViewTests.typingCost`'s
  keystroke 12.7–13.3ms against 13.0, parsing a 500-line note 2.3ms against
  2.7, a full styling pass 5.4ms either way.
- **Not checked:** anything on screen. Nested lines were looked at only
  through the layout tests and the styled storage; the iPad, the Pencil,
  typing a nested span by hand, and the PDF of one were not.
