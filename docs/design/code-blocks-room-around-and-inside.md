# Code blocks: room around and inside
Roadmap step 10, first part (16 Oct, branch `claude/code-block-room`): the
run and copy buttons had no room and the block looked cramped. The numbers
are `CodeBlockRoom`'s.

- **Code blocks stay paragraphs of the one text.** An embedded view per
  block would free its chrome, but a block would be one line that can't
  split, so a block longer than a page couldn't cross a page break, and
  selection, Find, undo, the PDF and the hidden markers all assume one text.
- **The panel reaches 14pt into each margin** (`outset`); the code keeps the
  prose column, so it wraps where it would with no panel and nothing moves
  sideways. The fragment's rendering surface reaches as far, the overlay's
  `panelRight` matches, and line numbers sit 16pt left of the panel's edge.
- **Room above and below is line height, never paragraph spacing.**
  Measured 16 Oct, sweeping a block a line at a time across the first page
  break (25 placements): 18pt of `paragraphSpacingBefore` on an opening fence
  put the block 13.3pt down its page in seamless and at the top of it in
  compressed and print, and every line after it moved with it. TextKit keeps
  paragraph spacing outside the line, so seamless's 1pt band and print's
  168pt one disagree about whether the line fits; a line is pushed across a
  break whole. `CodeBlockRoomTests.paginatesAlike` is that sweep with the
  real styler, and taller fence lines passed it in the probe where spacing
  failed.
  - The opening fence's line is the 12pt gap above the panel and a 40pt
    header; the closing fence's is a footer (0.8 of the code size, 12pt at
    the default) and the 12pt gap below. Both are fixed heights (minimum =
    maximum), set by `DocumentStyler.applyFenceRoom` on the fences as
    paragraphs.
  - **Their glyphs are lifted with `baselineOffset`**, since a taller line
    puts its extra height above the glyphs. TextKit's rule, measured: a
    fixed-height line whose baseline is raised past the font's descent loses
    that descent and ends at the baseline, the glyphs drawn `baselineOffset`
    above it. So each style asks for its height plus the descent, and
    `CodeBlockRoomTests.lineHeights` checks the laid-out heights. The opening
    fence's glyphs are centred (by cap height) in the header, where the
    language button stands; the closing fence's backticks, which sit high,
    are centred in the footer.
- **Code is 15pt beside a 17pt body** (`NoteTypography.code`: 15/17 of the
  body at every size, to the half point) on the prose's 22pt line
  (`codeLineHeight`): about 73 columns before a wrap instead of 65, and air
  between lines. Inline code keeps the size of the text around it. The code
  line's paragraph style is in `codeAttributes`, so a line made by Return is
  the right height before the restyle reaches it.
- **The header** holds the language's name and Run and Copy, centred
  (`CodeBlockRoom.header`); the buttons are 32pt, 8pt from the panel's edge,
  and no longer overhang the lines around them. Corners are 10pt.
- **The PDF prints the language's name in the header**
  (`CodeBlockLayoutFragment.drawHeaderLabel`, `FenceTag.label(ofFenceLine:)`),
  so a block on paper doesn't open with an empty row.
- **A wrapped line of code continues past its own indentation, with a mark**
  (suggested by the step 3 research, 16 Oct). Before, a continuation started
  at column 0 and read as a statement of its own: `{ System.out.println…`
  under `public static void main(…)`.
  - **The indent** is a paragraph style per line
    (`DocumentStyler.applyCodeLineIndents`): `headIndent` is the line's
    leading spaces and tabs (tabs to TextKit's 28pt stops,
    `CodeBlockRoom.leadingWidth`) plus 2 columns, never past 32. A
    constant, not Settings › Code › Indent Width, which is per device and
    would wrap one note differently on two iPads. Whole paragraphs, newline
    included, or the storage's own fixing would differ from the styler's
    copy and every restyle would write.
  - **It restyles on any edit to the block**, since a code block's signature
    carries a hash of its code. `indentFollowsEdits` edits the indentation
    mid-line on purpose: at a line's start, the typed characters' typing
    attributes carry an unindented line's style and become the paragraph's,
    which passed the test with the hash taken out (mutation, 16 Oct).
  - **The mark** is ↳ drawn in those 2 columns, just before each
    continuation (`drawWrapMark`), in `tertiaryLabel` (the output panel's
    label colour on a console), by the fragment on screen and line by line
    in the PDF. Paint only. **A stroked path, not an SF Symbol:** a tinted
    symbol image drew a grey box round itself in the PDF.
- **The caret is the font's height, not the line's** (17 Oct, reported on
  the iPad). UIKit draws a caret the height of its line, a point above and
  half a point below, which for prose is the font's own height. Every line
  this section makes taller than its font got a tall caret: 23.5pt beside
  15pt code, 53.5pt on an opening fence, and on a line holding larger sized
  text, the large height beside the small letters too. `DocumentUITextView`
  overrides `caretRect(for:)`: the font of the character before the caret
  (or after it at a line's start), on the laid-out line's baseline less
  the fence's lift, from a point above the ascender to half a point below
  the leading (`CaretHeight`). Prose and headings come out exactly as UIKit
  draws them. A fence's caret is kept on the panel
  (`CodeBlockRoom.caretRoom`): the header has room for it, the 12pt footer
  doesn't, so there it is the footer's height. The view's own tap handling
  (blank lines, line ends, selection handles over links) measures lines,
  so it uses UIKit's rect (`lineCaretRect`). `CaretHeightTests` fails
  without the override. Seen in the simulator on a code line and both
  fences; selection highlights are still the line's height.
- Every line below a code block moved, which is fine while no old notes are
  kept (see "The model"). `NoteThumbnail.version` went to 3 here (4 since
  code is coloured light on a dark device).
- **Checked in the simulator:** the 13-inch in light, seamless (margins,
  header, gaps, a block being edited with its fences showing); the 11-inch at
  0.96x in dark, print layout; a block split by compressed's page break and
  an output block, dark; and a PDF of that note, both pages, the header's
  name printed. **Mutation-checked** (16 Oct, each fails with its rule
  broken): the gap as paragraph spacing (`paginatesAlike`, 5 of 55
  placements), the lost descent left out (`lineHeights`), no outset
  (`reachesIntoMargins`), glyphs not lifted (`fenceGlyphsInPlace`). **Not
  checked:** the iPad, the Pencil, taps on Run, Copy and the language name,
  typing a fence open and closed, a caret on a fence line, light print
  layout, landscape, other text sizes on screen.
