# LaTeX

Design note for ROADMAP "After the submission" item 3 (stream L), 23–24 Oct.
Design and a spike only; nothing is built. What is measured is marked; the rest
is reasoning. **Every decision below is Provisional (Marcus to review)**: the
tag is on each section heading, and a decision that overrides one it gives is
said so. The spike is `scripts/spikes/latex-swiftmath/`
(a scratch SwiftPM package, SwiftMath 1.7.3, run on the iPad Pro 11-inch
simulator with `xcodebuild test -scheme LaTeXSpike-Package`; `SPIKE|` lines).

## Syntax (Obsidian's) — Provisional (Marcus to review)

- **Inline `$…$`.** The opening `$` is followed by a non-space, the closing one
  is preceded by a non-space and not followed by a digit (Pandoc's rule, which
  Obsidian's follows). So `costs $5 and $10` and `$5–$10` stay text; no
  formula can contain a newline.
- **`\$` is a literal dollar**, in and out of math (it doesn't close one). The
  parser has no escapes today; this is the only one, and the `\` is a hidden
  marker like the others.
- **Display `$$…$$` is a block when the line starts with `$$`**: one line
  (`$$ x $$`) or `$$` … `$$` over lines (the closing line ends with `$$`).
  `$$x$$` in mid-line is inline math in display style. **An unclosed `$$` is
  text**, never a block running to the end of the note (a fence does that; a
  hidden unclosed math block would make the rest of the note vanish while
  typing). Closing within 50 lines or it is text.
- **Code wins, left to right**: code spans and fences are found first, so
  `` `$x$` `` is code. A math span is an atom: nothing in it is emphasis
  (`$a*b*c$`, `$x_1+y_2$`). Math in a link's text is text.
- Markdown export is unchanged (the note's bytes); Obsidian reads it.

## Parsing — Provisional (Marcus to review)

- Pure and SwiftMath-free: `InlineMarkup.math(MathStyle)` as an opening/closing
  pair around one text node, with `InlineAttributes.math`, found in the same
  first pass as code spans and links; `BlockNode.Kind.math(MathBlock)` for
  `$$` blocks, line-aligned like `.code` (there is already a
  `// .math arrives with a later step` in `DocumentNode.swift`).
- **Built in step 1** (as the parser now does it): `\$` is `InlineNode.Kind.escape`
  (a marker with no partner, so `closing` still always closes the innermost
  open pair); `MathBlock` carries the `$$` ranges, the TeX range and an FNV
  hash for `styleDetail`; "within 50 lines" is 50 lines in all, both `$$`
  lines included (`DocumentParser.maxMathLines`); a fence line ends the
  search for a close; a mid-line `$$ x $$` may have spaces, `$ x$` may not;
  a closing-`$` search skips code spans and `\$`; the leftmost opener wins, so
  `$5 for $x$` reads `5 for $x` as a formula (Pandoc does too; `\$5` is the
  way out). Blank-only TeX is text. Styler and layout treat a math block as
  prose until step 3/4.

- **Whether the TeX is valid is a separate question**, asked of
  `MTMathListBuilder.build(fromString:error:)` (Foundation only, no UIKit),
  through one cached `FormulaValidity` that both the styler and
  `MarkdownLayout.runs` ask, so styling and layout can't disagree. An invalid
  formula is not swapped and the styler paints its source `secondaryLabel`
  (the error case: "shows its source dimmed"). An empty formula is invalid.
  Measured: unbalanced braces, unknown commands and unknown environments fail
  at parse with a message; typesetting never failed after a parse.

## Drawing (decision) — Provisional (Marcus to review)

- **An `NSTextAttachment` swapped in by the layout delegate**, exactly as
  markers are: `MarkdownLayout.Run.Kind.formula` covers the whole `$…$` and its
  replacement is U+FFFC then word joiners, the same UTF-16 length, so every
  offset still maps. Measured on a real TextKit 2 `UITextView`: the swap is
  honoured (line `attributedString.length` equals the source's), a line grows
  to the formula only when it is taller than the text (a fraction over a sum:
  27.0pt against 20.29pt; a small `$x$` leaves the line at 20.29pt), and
  **room is line height, never paragraph spacing**, as the rules say.
- **A custom layout fragment can't reserve width in a line**, so it only suits
  display; an image run is the same thing as an attachment. Rejected.
- **Image attachment (bitmap) over a view provider (MTMathUILabel as the
  view)**: the image variant laid out, aligned, took the colour and drew in
  the probe; the view variant laid out but drew nothing (or nothing the
  right colour) in an off-screen `layer.render`, which says nothing about
  a real screen, so **unverified**; it would give vector sharpness and a tap
  target for free, and is the thing to try if the bitmap's sharpness at zoom
  disappoints. The bitmap is rendered at the page's draw scale (as
  `DrawingCanvas.renderScale` does) and cached by latex, size, mode and scale.
  **Sharpness at zoom is not established**: the probe's measure (share of soft
  pixels) read 1.000 at 1x and 0.989 at 4x for the bitmap, which is too blunt
  to say anything.
- **Baseline (measured, image variant, "H" beside text at 17pt, 4x):** the
  attachment's bounds are `y = -descent`, so ink sits on the text's baseline
  to within 0.5pt; a descender hangs below it by the metric's descent to 0.2pt
  at 14–36pt.
- **Colour comes from the run.** SwiftMath's own drawing takes a concrete
  `UIColor` (measured: black, white and red all draw exactly), so a dynamic
  colour must be resolved per appearance. **Better, measured: a template
  image (`.alwaysTemplate`) drawn by the text view takes the run's foreground
  colour**: red text gave ink at (232, 92, 97), white text on black gave
  (226, 226, 226). So one bitmap per latex, size, mode and scale serves both
  appearances and every `<span color>`, and the colour is not in the cache key.
  The PDF resolves its own colour (light, black).
- **Upside down:** SwiftMath's label layer is geometry-flipped, so rendering it
  into a UIKit context needs one more flip. The first contact sheet came out
  inverted; the baseline test now uses a descender.
- **Display blocks**: the first line carries the attachment (centred by the
  paragraph style), the source lines and the closing line are word joiners
  with `minimumLineHeight = maximumLineHeight = 1`. **Measured: TextKit keeps a
  1pt line (heights 20.29, 20.29, 1.00, 1.00, 20.29), so the source lines can
  be made to take no room.** **Not working, measured:** `attachmentBounds` was
  called once for the opening line with `(0, −26.5, 34, 60)` (a 17pt `\sum`
  plus an 8pt gap each side) yet the line stayed 20.29pt and wasn't centred
  (`typographicBounds` x = 0, width 34), where an inline fraction grew its line
  to 27.0pt. Both an inline bounds with `y ≈ −descent` and a taller display
  one went through the same swap, so the cause is something this probe changes
  (the 8pt gap's negative `y`, `.center`, or the tiny paragraphs after it);
  not isolated. **Step 4's first task** is to vary those three one at a time.
  The fallback that needs no TextKit surprise is what the code fences'
  header does: a fixed height on the opening line (min = max, formula height
  plus gap) with the attachment lifted by `baselineOffset`.
- **A formula wider than the column** scales down to fit (the text container's
  width is pinned per note, so this depends on the note alone); no floor.
- **Editing: tap opens an editor popover** (a sheet in a compact width) with the
  source in monospace and a live preview; Done writes back through
  `replace(_:withText:)` (one undo step). Why this isn't caret-dependent: what
  takes room is a function of the text alone, the same with the caret
  anywhere; the editor is a separate surface, so no line ever re-wraps because
  of the caret (revealing the source on entry, as Obsidian does, would, and
  ink would drift). Caret stops treat a formula as one place; Backspace after
  it deletes the whole span; a selection edge inside it snaps outwards. A
  locked note opens the editor read-only. New formulas: Style ▾ gets Inline
  Formula and Display Formula, inserted on Done.
- **Size**: the formula's font size is the point size of the text at the
  span (the styler already sizes runs and headings), times a scale. Measured
  at 17pt: Latin Modern's x-height is 7.51pt against SF's 8.95 (84%) and its
  cap height 11.5 against 11.98 (96%), so formulas look small at the same
  size: **scale 1.1** (provisional), re-judged on screen.
- Bold and italic mean nothing to a formula; colour and size apply to it.

## PDF, thumbnails, search, copy, the Mac — Provisional (Marcus to review)

- **`NSTextLineFragment.draw` can't be trusted for formulas** (measured: the
  view variant drew 0 pixels, the image variant 15 dark pixels of a fraction), so
  `NotePDF.draw` draws each formula itself after its line, **as vectors**:
  `MTMathUILabel.displayList.draw(_:)` into the PDF context works (public;
  88KB for one formula with its embedded font subset, so the PDF stays text
  plus paths), light, concrete black. Thumbnails take the PDF's path.
  `NoteThumbnail.version` goes to 7.
- **Search** reads the source (people search "log n"); no change. **Outline**
  titles drop the `$`. **Get Info** skips words inside math.
- **Copy**: plain text is the Markdown byte for byte (unchanged); the RTF
  carries the source in Menlo, `$…$` included. **Paste** of rich text escapes
  a `$` as `\$` only when the line would otherwise parse a math span the
  source didn't have.
- **The Mac editor is a plain `TextEditor`**: it shows the source. The pure
  parser compiles there; SwiftMath links into both platforms and is unused on
  the Mac.
- **Ink**: typing a formula changes the line height, so the lines below move,
  as any edit that re-wraps does.

- **Built in step 2**: `FormulaValidity.check(_:)` (cached, bounded at 2,000
  answers) returns `.valid(tex:)` with the alias-resolved TeX to typeset, or
  `.invalid(message:)`; `TeXAliases.resolve` is a command-by-command scan, so
  `\\dfrac` (a line break, then text) and `\dfracs` are left alone, and
  `\operatorname*` stays unsupported (its limits can't be drawn). `\pmod{n}`
  becomes `\ \left(\mathrm{mod}\ n\right)` and `\bmod` `\mathrm{\ mod\ }`.
  Nothing calls them yet: the styler and layout do in step 3.

## What SwiftMath can't draw (measured, 56 probes at 17pt)

- **Fail at parse**: `\operatorname`, `\underbrace`, `\overbrace`,
  `\xrightarrow`, `\cancel`, `\boxed`, `\dfrac`, `\bmod`, `\pmod`, `\substack`,
  `\overset`, `\tag`, `\newcommand`, `\implies`, `\varnothing`, `\not`,
  `\sideset`, `\href`, `\hline`, `array`, `align*`.
- **Draw**: `\frac`, `\sqrt`, `\sum`/`\prod`/`\int` with limits, matrices
  (`pmatrix`, `bmatrix`), `cases`, `aligned`, `\binom`, `{n \choose k}`,
  `\mathbb`, `\mathcal`, `\mathbf`, `\mathrm`, `\text`, `\left…\right`,
  `\lceil`, `\lfloor`, `\overline`, `\hat`, `\vec`, `\tilde`, `\arg\min`,
  `\max\limits`, `\displaystyle`, `\ldots`, `\cdots`, `\vdots`, `\color`.
- **A small alias table in our own pure layer** covers the common failures
  (`\dfrac`/`\tfrac` → `\frac`, `\implies` → `\Rightarrow`, `\varnothing` →
  `\emptyset`, `\operatorname{x}` → `\mathrm{x}`, `align`/`align*` → `aligned`,
  `\bmod`/`\pmod` → `\mathrm{mod}` forms); the rest show their source dimmed.
- **App size**: the package copies a 7.1MB `mathFonts.bundle` (twelve fonts)
  into the app; only Latin Modern is used. Pruning means a fork. Measured size
  of the built bundle: not taken.

## Measurements (simulator on this Mac, so Mac CPU; the iPad is slower)

- Typeset: 0.2–2.3ms warm; the first call 33–44ms (font load), with outliers
  of ~20ms. Bitmap at 2x: 0.1–1.3ms. Bitmap sizes at 2x: 10KB (`⌈log₂ n⌉` at
  14pt) to 420KB (the quadratic at 36pt); 40KB for a typical 17pt line.
  200 typesets of `\sum \frac{i}{i+1}`: 0.48ms each; 200 images: 0.27ms (2x),
  0.22ms (3x). A note of 200 formulas typesets in about 100ms cold, so
  prewarm off the main actor is not needed, but the cache is.
- `MTMathUILabel` typesets twice per formula (once for `intrinsicContentSize`,
  once in layout); the public API leaves no way round it.
- SwiftMath's typesetter is internal; everything goes through
  `MTMathUILabel.displayList` (public `ascent`, `descent`, `width`, `draw`).

## Adding the package (Marcus, by hand; `project.pbxproj` is not touched here)

In Xcode: File › Add Package Dependencies…,
`https://github.com/mgriebling/SwiftMath.git`, Exact Version 1.7.3, add the
`SwiftMath` product to the NoteCode target. That makes four edits in
`project.pbxproj`, mirroring HighlightSwift's (ids illustrative):

1. A `PBXBuildFile`: `AA000000000000000000AA11 /* SwiftMath in Frameworks */ =
   {isa = PBXBuildFile; productRef = AA000000000000000000AA12 /* SwiftMath */; };`
   and its line in the target's Frameworks phase `files`.
2. A `packageProductDependencies` entry on the NoteCode target and an
   `XCSwiftPackageProductDependency` (`productName = SwiftMath`).
3. An `XCRemoteSwiftPackageReference` (`repositoryURL`
   `https://github.com/mgriebling/SwiftMath.git`, `kind = exactVersion;
   version = 1.7.3;`) listed in the project's `packageReferences`.
4. `Package.resolved` (`xcshareddata/swiftpm`) gains the `swiftmath` pin.

Also: add MIT (SwiftMath) and the Latin Modern font licence (GUST) to
`Acknowledgements.txt` (a test checks it); check the privacy manifest (the
spike found no required-reason API in SwiftMath's sources).

## Build steps (one PR each) — Provisional (Marcus to review)

0. **Marcus: the package** (above). Steps 2 onwards need it.
1. **Parser**: `InlineMarkup.math`, `BlockNode.Kind.math`, `\$`; files
   `InlineParser.swift`, `DocumentNode.swift`, `DocumentParser.swift`; tests in a
   new `MathParserTests` (currency, `\$`, code interplay, unclosed `$$`, the
   50-line cap, a random-lines property test as `NestingInlineTests` has).
2. **Validity + aliases**: `FormulaValidity`, `TeXAliases` (pure); tests over
   the probe's lists above. Needs the package (step 0, Marcus).
3. **Layout**: `MarkdownLayout.Run.Kind.formula`, `FormulaAttachment` and its
   cache, inline only; the styler's dimming; `MarkdownLayoutTests` extended:
   frames equal the same note with the source replaced by a box of the
   formula's size, in seamless, print and landscape; pagination alike in the
   three modes (`CodeBlockRoomTests.paginatesAlike`'s sweep).
4. **Display blocks**: resolve the opening-line height first (see above);
   `MarkdownLayout.swift`, the styler's paragraph styles for the block's
   lines; tests: the lines' heights, and the three modes paginate a block
   across a page break alike (the `paginatesAlike` sweep with a block in it).
5. **Editing**: `MarkerTaps.swift` (a third gesture), a new
   `FormulaEditor.swift` (popover or sheet, live preview), caret stops in
   `MarkdownFormatting+Markers.swift` (a formula is one stretch), Backspace
   there, selection snapping in `DocumentUITextView`, Style ▾ items in
   `MarkdownFormatting` and `NoteShortcut`; **undo**: the editor and Backspace
   both go through `replace(_:withText:)`, so one undo step each, tested as
   `TextRowEditorTests` tests undo (separate turns of the run loop). Tests:
   tap lands on a formula (finds the point in the note with the source
   replaced, as `LinkTapTests` does), Backspace, snapping, undo.
6. **PDF and thumbnails**: vector draw in `NotePDF.draw` after each line,
   `NoteThumbnail.version` 7; tests: `NotePDFTests` with a formula (ink in
   the sheet where the line is; the source text isn't printed), light on a
   dark device.
7. **Info, outline, copy, paste**: `NoteInfo.swift` (skip math), 
   `NoteOutline.swift` (titles without `$`), `RichCopy.swift` (source in
   Menlo), `RichPaste.swift` (escape an accidental `$`), `SpanStyle.swift`'s
   search masking left alone; tests per rule.

## Built in step 3 (inline layout)

- `MarkdownLayout.Run.Kind.formula(tex:display:opening:)` covers the whole
  `$…$`, dollars included; its replacement is U+FFFC then word joiners (same
  UTF-16 length). `laidOut` gives the first unit a `FormulaAttachment` and the
  attributes of the **TeX text** (the dollars carry the marker colour, which
  would otherwise tint the template image).
- `FormulaAttachment` (UIKit, app target): `MTMathUILabel` to a template
  image at 3x, attachment `bounds.y = -descent`, size scale 1.1, cached by
  tex, point size and mode (colour and scale are not in the key). Caches up to
  500 and starts over.
- An undrawable formula (`FormulaValidity`) gets no run: its dollars show, and
  `DocumentStyler.dimUndrawableFormulas` paints the whole span `secondaryLabel`.
  Layout and styler both ask `FormulaValidity.check`, so they agree.
- Bitmap scale is fixed at 3, not the page's zoom: sharpness at zoom is still
  unverified.

## Built in step 4 (display blocks)

- `MarkdownLayout.Run.Kind.displayFormula(tex:)` is a `$$` block's first line
  (all of it, `$$ x $$` included); every other non-empty line of the block is
  `.joiners`. An undrawable or blank block gets no runs and the styler dims it
  (`DocumentStyler.styleDisplayFormula`).
- **The opening-line height, resolved** (probes, 29 Oct, simulator, 17pt): the
  `NSTextAttachment` line did grow-and-not-clamp because the attachment *hung
  below the baseline* (`bounds.y = -descent`): a fixed line holding one came
  out taller than asked by about its descent less the font's (a sum over a
  fraction asked 50 gave 66.3), whatever the baseline offset. With the
  attachment sitting on the baseline (`make(fitting:)`: `bounds.y = 0`, its
  descent part of its height) the line is exactly the height asked plus a
  constant 1.71pt TextKit adds to every fixed line, which `DisplayFormula.slack`
  takes off. The formula is raised by `gap - font descent - slack` so its bottom
  is 8pt above the line's end; the ink then has equal white above and below
  (`DisplayFormulaTests.inkInLine`, three formulas).
- Source lines are `min = max = 1` and measure 2.71pt (the same constant).
- Centring is the paragraph style's `.center`; a formula wider than the column
  is scaled down by `FittingAttachment.attachmentBounds` (no floor).
- Not tested against a ground truth of "the block replaced by its attachment":
  the swapped text has no trailing anchor, so it differs by that 1.71pt.

## Built in step 5 (editing)

- `FormulaEditing` (pure) finds the drawable formulas from the parse
  (`FormulaValidity`, the same answer the layout swaps by) and holds the rules:
  inside an inline formula (between its two edges) the caret has no place and
  goes to the edge it came from, or the nearer one for a tap; both edges are
  real places. A block's inside, and its closing line, go to its start or to
  the start of the line below it (the closing line is 1pt high). Backspace from
  after a formula, or inside one, deletes the whole span; from the start of the
  line below a block it deletes the block and the break after it. A selection
  edge inside a formula is moved outwards (`snapped`). All of it is one
  `replace(_:withText:)`, so one undo step.
- A formula's dollars are no longer hidden markers in `hiddenStretches`: a
  drawable one is handled above, and an undrawable one shows them, so the caret
  must be able to stand beside them.
- `MarkerTapTarget.formula` (a third gesture target): an inline formula's
  attachment (padded 4pt), or any point on a block's first line. Found in a
  locked note too, whose editor is read-only. A hold on one does nothing.
- `FormulaEditor` is a SwiftUI popover (a page sheet where narrow) hosted from
  the coordinator: source in a monospaced `TextEditor`, the formula drawn live
  from `FormulaAttachment` above it, SwiftMath's message beneath when the TeX
  can't be drawn. Done is off while the source is empty; Remove deletes.
  What is written is `FormulaEditing.cleaned`: an inline formula is one line
  with no space against its dollars, a `$` is escaped to `\$` (or the formula
  would end there), a block drops its blank lines. A formula edited to
  something undrawable stays in the note, dimmed, to be fixed in place.
- Style ▾ › Inline Formula / Display Formula (hotbar menu, the edit menu's
  Format submenu, ⇧⌘M and ⌥⌘M) open the same popover empty, or seeded with the
  selection; Done inserts. A display formula takes lines of its own. Not in a
  code block.

## Built in step 6 (PDF and thumbnails)

- `MarkdownLayout.laidOut` puts a `FormulaAttachment.Source` (tex, text point
  size, display) under `FormulaAttachment.sourceKey` on each formula's U+FFFC.
  `PrintedNote.draw` reads it after each line: it blanks the attachment's
  bitmap first (so the line's own draw can't add a second, heavier copy) and
  calls `FormulaAttachment.drawVector`, which typesets the formula again and
  draws the display list into the context (y flipped, baseline `descent` below
  the label's origin). Concrete black; a coloured span prints black, as paper is
  light. A display block scales to the column as on screen and is lifted by its
  `baselineOffset`.
- The x is `locationForCharacter`; the baseline is the line's `glyphOrigin.y`
  less the lift. Thumbnails share `PrintedNote.draw`, so they get formulas for
  free. `NoteThumbnail.version` is 8 (7 was taken by the paper styles).
- Tests (`NotePDFTests`): an inline and a display formula leave ink on the
  sheet (the display one centred), the source is not in the PDF's text, a
  formula note stays small, the thumbnail version.
- Not looked at by eye: the page in a PDF viewer.

## Built in step 7 (info, outline, copy, paste)

- **Get Info**: `NoteInfo` skips a `$$` block whole and any word inside an
  inline formula (dollar to dollar, found from the parse's math markers, as
  colour tags already are). An escaped `\$5` is prose and counts.
- **Outline**: needed no change. A title is the unmarked inline text, so a
  formula's dollars were already dropped; tests keep it so, and keep a `#` line
  inside a `$$` block out of the outline.
- **Copy** (`RichCopy`): a line in a `$$` block (found by parsing the note, and
  only when it holds `$$`) is copied whole in Menlo; in a prose line each
  inline formula is copied from its opening dollar to its closing one in Menlo,
  since the glyphs hold only the TeX. The plain text and the app's own Markdown
  type are untouched.
- **Paste** (`RichPaste.escapingAccidentalMath`): on the written Markdown, the
  dollars the parser reads as math markers are escaped to `\$`, back to front.
  Escaped dollars and dollars in code are not markers, so they stay. It runs on
  the whole paste, so the lines of a pasted `$$` block are escaped together. The
  note around the paste isn't consulted (a pasted lone `$` beside a `$` already
  on the line can still pair); the rule applies only to rich pastes, as plain
  ones go to the text view. A line whose pasted dollars would pair is also a
  line that doesn't read back through `StyledLine`, so it is written plain and
  loses its bold and links; the dollars are escaped all the same.
- Not looked at on an iPad: RTF opened in Pages or Mail.

## Unverified

On an iPad; the view-provider variant; display-block look on a real page (heights, centring and the ink's position are tested in the simulator); sharpness at zoom; the 1.1 scale by eye;
`NSTextLineFragment.draw` with a formula in the PDF (the vector draw into a PDF
context ran and wrote 88KB, but the page wasn't looked at); a real tap and the popover's arrow, size and keyboard;
VoiceOver (label the attachment with its source); the built app's size with
the font bundle.
