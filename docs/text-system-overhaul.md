# Text system overhaul

Plan, 18 Oct 2026. The goal (Marcus, 18 Oct): text in a note behaves as it
does in Obsidian and most other editors, with free resizing of any text at
the very least.

**Status:** decisions 1 to 4 below taken as recommended (Marcus, 18 Oct).
Phase 1 is built on branch `claude/free-text-size`. Phases 5 and 6 are
still to be decided.

Each phase below is one branch and one PR off `main`. A session starting a
phase reads this file, AGENTS.md and the files the phase names.

## Where it stands

From the code, not assumed. Every row is something Pages, Word, Notability
or Obsidian does differently.

| Today | Where | Elsewhere |
|---|---|---|
| A run of text has one of three sizes against the text around it: Small 0.85em, Large 1.25em, Larger 1.5em. A size read from a note snaps to the nearest, and one nearer 1em is dropped. | `SpanSize`, `SpanSize.nearest` | Any size: presets, ±1pt, or a typed number |
| Two size controls. The row's `+ 17 −` is the note's body size (seven steps); Size ▾ beside Colour ▾ is the run's step. | `TextOptionsRow` | One control, showing the size of the text at the caret |
| Italic on a bold word makes it italic, not bold italic: the markers are swapped, "since `InlineParser` doesn't nest spans". | `MarkdownFormatting.toggle` | Styles combine |
| `***x***`, `**a *b* c**` and `**<span…>x</span>**` aren't read, and show their markers. Span tags are the parser's one wrapper level. | `InlineParser.parse` | Read |
| A size or colour on half a bold word takes the whole word: "a run never cuts a span in two". | `MarkdownFormatting.styleLine` | Exactly the selected letters |
| Bold with nothing selected types `****` and puts the caret between, and it shows, since an empty pair isn't a span. | `toggle` | The next typed text is bold; nothing shows |
| A size or colour with a caret only changes the word at the caret. Nothing sets the size of text not typed yet ("Not built" in AGENTS.md). | `style` | In a word: the word (Word). Between words: the next typed text |
| Paste: no handling of its own, so presumably plain text. Not checked. | `DocumentUITextView` | Bold, italic, size and colour survive |
| No blockquote, horizontal rule, highlight or underline; Style ▾ offers H1 to H3. | `DocumentParser`, `TextOptionsRow` | Obsidian has all of them |

**What stays, because ink depends on it:**

- **Markers never appear under the caret.** Obsidian's Live Preview shows
  them while you edit a span, but layout can't depend on the caret, or the
  text moves under the ink every time the caret does. Heading hashes stay
  drawn in the margin.
- **The note stays Markdown with Obsidian's span tag.** No rich-text storage
  (option F in docs/research-notability-obsidian.md §2.5): the styler,
  formatting, lists, hidden markers, search and export are all built on the
  Markdown.
- **Room is line height, never paragraph spacing**, so every mode paginates
  alike.
- **A size change re-wraps**, so a note with ink asks once each time it is
  opened, until text-anchored ink (roadmap step 17).

## Design decisions

### 1. Any size, stored as em, shown in points (decided 18 Oct)

The tag stays `<span style="font-size:1.412em">`, now with any value, written
with at most three decimals. The control works in points: a size P chosen in
a block whose font is B is written as P/B, and shown as B × em, rounded
(the styler already sizes to the half point, so 24pt in a 17pt body writes
1.412em and comes back as 24.0).

- **For em:** a note resized with the note's size keeps its proportions, a
  run in a heading is a larger heading, and Obsidian draws it the same way.
  Notes written since step 10 read without change.
- **Against:** the number moves when the note's size changes or the text
  becomes a heading: 24 in a 17pt note shows 27 once the note is 19. Word
  and Pages keep absolute points.
- **Rejected:** `px` or `pt` written absolutely. They suit the control
  better but fight the note's size, and Obsidian's 16px body makes `24px`
  look different there. Other units stay visible text, as now.
- **Range:** 8 to 72pt from the control, with presets like Word's (8, 9, 10, 11,
  12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72). Read: any em from 0.25 to
  8, clamped. Exactly 1em is no size.

### 2. One size control (decided 18 Oct)

The row's `+ 17 −` becomes the size of the text at the caret or the
selection, as in Pages: it reads 17 in body text, 34 in a heading, 24 in a
sized run, and a dash for a mixed selection. `+` and `−` step 1pt; the
number opens the presets, Custom… and Default. Size ▾ goes. The note's own
size moves to ••• › Text Size (the same seven steps).

This reverses part of the v3 text-row decision: the stepper was asked for as
the note's size. The alternative is to keep both controls, which leaves two
`+`/`−` pairs a few points apart. In a code block the control shows the code
size, disabled.

### 3. Formatting is per character

The core of the overhaul. A line is read as visible characters, each with
attributes (bold, italic, strike, code, link, colour, size); a button sets
or clears one attribute over a range of those characters; the touched part
of the line is written back as Markdown. Every format action goes through
this, so they combine and never take in more than was selected.

- **Writing is canonical.** The tag outermost (colour and size in one tag,
  as now), then a link, `**`, `*`, `~~`, and code innermost. Equal
  neighbours merge. Spaces at a run's ends move outside `*`, `**` and `~~`,
  which can't open after or close before one; a tag keeps them. Always `*`,
  never `_`. So `**bold**` with Italic on "ld" becomes `**bo*ld***`.
- **Minimal rewrite.** Only the stretch between the nearest points where
  nothing is open is rewritten, so the rest of the line keeps what the
  reader typed, `__bold__` included.
- **Code and links are atoms.** A change that cuts one takes it whole, as
  now: half a link would be two links.
- **The selection maps by visible offset**, which a rewrite can't move.

### 4. A nesting inline parser, written in-house

Decision 3 needs a parser that reads everything the writer writes.
`InlineParser` keeps its contract (a flat, contiguous list per line) but text
nodes carry their attributes and markers are nodes of their own. Emphasis
uses CommonMark's delimiter stack ("process emphasis", spec §6.2) for `*`,
`**`, `_`, `__` and `~~`; code spans and links are found first; span tags
pair on the same stack. Pairs nest; pairs that would cross are text.

- **Not swift-markdown (cmark-gfm).** It parses a whole document into a tree
  and hands back inline HTML as loose tags, so the span pairing, the hidden
  markers' ranges and the UTF-16 offsets would all be rebuilt on top of it,
  for a subset this small.
- **Not special cases** (`***` alone, or a span inside bold alone). Each adds
  a rule to the ten files that read inline nodes; attributes replace those
  rules with one.

### 5. A typing style

With a collapsed caret, Bold, Italic, Strike, Code, a size or a colour acts
on the word when the caret is inside one (Word's rule, and today's for size
and colour). Between words or at a line's end it becomes the typing style:
lit in the bar, nothing written. The next text typed there is written with
it, in the same undo step. A caret move, a mode switch or the keyboard going
away clears it. Typing at the end of a styled run already continues it (the
caret stop's rule).

### 6. Fonts at free sizes

`DocumentStyler.font(_:sizedTo:)` sizes the block's font with `withSize`.
Phase 9 found a plain `systemFont(ofSize:)` lacks the system's leading and
made every line 1.7pt shorter. **Measured 18 Oct: `withSize` keeps it,
scaled** (1.713pt at 17, 2.418 at 24), and a run at its text's own size lays
out exactly as plain text (22.0pt lines both). So `withSize` stays.

## Phases

| | Phase | Size | Needs |
|---|---|---|---|
| 1 | Free sizes, one control | S | decisions 1 and 2 |
| 2 | Nesting parser | L | — |
| 3 | Formatting per character | L | 2 |
| 4 | Typing style | M | 3, a device |
| 5 | Paste and copy with formatting (optional) | M | 3 |
| 6 | Obsidian's other blocks (optional) | S each | 2 |

**Before the November submission:** Phase 1, since it changes what is
written (an older build reads `1.412em` as its nearest step, Larger). Phases
2 to 6 change what is read and how edits are written. No stored note needs
converting, so they can land before or after the release.

### Phase 1: free sizes and one control

Built 18 Oct, branch `claude/free-text-size`; AGENTS.md › Coloured and
sized text has what was found on the way.

- `SpanSize` becomes a value holding `em`, clamped, written with at most
  three decimals and no trailing zeros. `nearest(toEm:)` and the three
  cases go. `CaretFormatting.size` reports the size in points.
- **Measure first** (half an hour). A run whose em rounds back to the
  block's own size must lay out exactly the lines plain text does. A 24pt
  run's line height should match what the system's 24pt text gets. If
  `withSize` loses the leading, make sized fonts from the block font's
  descriptor with its text style kept.
- The control from decision 2, with the stepper's 300ms settle, so five
  quick taps re-wrap once and ask the ink question once. The question is
  shared with the note's size, as now.
- A mixed selection: `+` and `−` set it all to the size at its start ±1pt.
  Phase 3 steps each run separately.
- Still true after this phase: a size on half a bold word takes the word.
- **Tests:** points to em and back at every body size and H1 to H6;
  0.85, 1.25 and 1.5em from step 10's notes read unchanged; clamping;
  1em is no size; the pagination sweep (`CodeBlockRoomTests.paginatesAlike`)
  with random sizes; ⌘+ and ⌘− (Marcus's decision 3, below).
- **AGENTS.md:** "Coloured and sized text" ("a size read from elsewhere
  snaps to the nearest step") is reversed.

### Phase 2: the nesting parser

- `InlineParser` as decision 4. Moved to attributes: `DocumentStyler.apply`
  (one pass: the block's font, its size, then traits), `MarkdownLayout`
  (hide marker nodes), `caretStop` and `backspace` (marker stretches),
  `formatting(at:)`, `NoteOutline`, `NoteInfo`, `NoteSearch` via
  `SpanStyle.maskingTags`, `links(onLineAt:)` and `TextRewritingPolicy`'s
  inline code. The signature's inline hash includes the attributes.
- **No behaviour change but nesting.** `***x***`, `**a *b* c**`,
  `**<span…>x</span>**` and `<span…>**x**</span>` now read; every other
  test passes unchanged. Bump `NoteThumbnail.version`.
- **Tests:** the CommonMark spec's emphasis examples that fall inside the
  subset; `MarkdownLayoutTests`' frames-equal-markers-deleted check over
  nested lines; `MarkdownLayoutCostTests` and `PageViewTests.typingCost` no
  worse.

### Phase 3: formatting per character

- A pure type (`StyledLine`, say) for decision 3, beside
  `MarkdownFormatting`. It replaces `toggle` for Bold, Italic, Code and
  Strike, and `style` for colour and size.
- Italic on bold is bold italic, and Bold again leaves italic. A size on
  "ld" of a bold word sizes "ld". `+` and `−` on mixed sizes step each run.
- **Tests:** a property test, thousands of random styled lines (fixed
  seed): written, then read, gives back the same characters and
  attributes. Untouched stretches stay byte for byte. One undo step per
  change. A few written lines checked against GitHub's renderer and in
  Obsidian, once, by hand.

### Phase 4: the typing style

- Decision 5. Bold's empty `****` goes.
- **Probe first**, one question: does replacing typed text in
  `shouldChangeTextIn` survive autocorrect, predictive text, dictation and
  an input method (Japanese kana, Korean)? Fallback: write the style after
  the fact from `textViewDidChange`, never inside marked text.
- XCUITest's `typeText` skips autocorrect, so a check taps the keyboard's
  keys or uses the iPad.

### Phase 5: paste and copy with formatting (optional)

- Check first what a paste of styled text does today.
- Paste: bold and italic traits, the point size against the block's font
  and the colour are read off the pasted text and written by Phase 3's
  writer. Pasting into code stays plain.
- Copy: the Markdown as the plain string, as now, and an RTF copy beside it,
  so Pages and Mail keep the formatting.

### Phase 6: Obsidian's other blocks (optional, any order)

Blockquote `> ` (a bar drawn in the margin by its fragment), horizontal rule
`---` (a fixed-height line), highlight `==🟡text==` (research §2.6),
underline `<u>text</u>`, and H4 to H6 in Style ▾. Tables aren't in this
plan.

## Risks

- **The parser feeds about ten files** (DocumentStyler 18 references,
  MarkdownFormatting+Markers 13, DocumentNode 13, then seven more). Phase 2
  changes nothing but nesting, and the whole suite is green before Phase 3
  starts.
- **The writer could write what the parser reads differently.** The
  round-trip property test is the definition of done for Phase 3.
- **The typing style against the keyboard** is the riskiest piece of UI:
  autocorrect, the suggestion bar and input methods all edit around the
  caret. Phase 4 probes before building.
- **Mixed sizes on a line:** line height, the caret (`caretRect` reads the
  font before the caret, so it should follow) and selection highlights,
  which stay the line's height. Notability shipped a fix for mixed sizes on
  one line (research §2.2).
- **Ink moves more often** once any text can be resized. The ask-once rule
  stays; text-anchored ink is the fix.
- **Cost per keystroke.** Nested parsing stays linear in a line's length;
  the cost tests bound it.

## Done means, on screen

On the iPad, not through a value the code computes:

1. "ld" selected in a bold word and set to 24: those two letters are 24pt
   bold, the rest unchanged, the control reads 24, and one undo puts it
   back.
2. Bold, then Italic, on a word: bold italic. Italic again: bold.
3. A caret after a space, 30 chosen, "hi" typed: "hi" is 30pt, and no
   marker showed at any point.
4. `+` tapped five times fast on a note with ink: one question, one
   re-wrap.
5. The exported `.md` opens in Obsidian with the same sizes, styles and
   colours, and reads as clean text on GitHub.
6. A note with mixed sizes paginates the same in seamless, compressed and
   print layout (test), and its PDF matches the screen.

## Decisions for Marcus

1. Sizes as em, shown in points. **Decided 18 Oct, as recommended.**
2. The row's `+ 17 −` becomes the selection's size and the note's size moves
   to ••• › Text Size. **Decided 18 Oct.**
3. ⌘+ and ⌘− follow the row's control, as in Pages. **Decided 18 Oct.**
4. 8 to 72pt, with presets like Word's. **Decided 18 Oct.**
5. Phases 5 and 6 in or out? Open.
