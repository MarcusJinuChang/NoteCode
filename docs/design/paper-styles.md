# Paper styles

**Removed on 31 Oct 2026, for the full release (Marcus: "Remove paper styles
(dots, grid, etc.) for the full release; there should be a text alignment
system but it can be implemented later").** Every note shows plain paper. The
choice came out of ••• › Paper, Settings › Notes, templates and the
Welcome note; `Paper.swift`, `PaperMenu.swift`, the shape layers in
`PageDecorationView`, the PDF and thumbnail drawing, `-debug-paper` and their
tests are deleted (the history has them). `Page.paperStyle` stays in the
model, unused, so version 1's hashes hold (`ModelFreezeTests`); drop it with
the next schema change. `NoteThumbnail.version` went to 9. Text alignment is
on docs/ROADMAP.md › After 1.0. What follows is the design as it was, kept for
whoever builds it back; the sections below describe code that is no longer there.
Roadmap item "Paper styles" (24 Oct, branch `claude/clever-mccarthy-56daf5`).
Dots, grid and lined paper behind a note's text and ink, per note, with a
default for new notes. Everything decided here was decided without Marcus
(he asked sessions to proceed): the choices are listed under **Provisional**.

## Why the first attempt was postponed

Built 13 Oct (`9f668ec`, `Paper.swift`), postponed 14 Oct, removed with the old
notes on 15 Oct. It drew a small tile image as a **pattern colour** on one
`UIView` per page body, inside `PageDecorationView`. It came out "slightly
offset or broken in compressed and print layout", and the note recorded three
facts (`insert-and-templates.md`): paper must lay nothing out; a pattern
`backgroundColor` on a bare `CALayer` draws upside down where a `UIView`'s
draws upright; and print layout's covers hide anything in a band, so a pixel
test can't see paper leaking there, only geometry can.

The cause of "slightly offset" was never found. The likely one, from the
design (not proven, there is no old build to run): a tile is a bitmap
`spacing × contentScaleFactor` pixels square, and the page raises its views'
density to the *drawn* scale (`PageView.matchRenderingScale`: 0.65x to 4x of
the display scale, capped at 3x). Wherever that product isn't a whole number
the tile is rounded to whole pixels and the error accumulates over the 34
columns and 40 rows of a page, so the pattern drifts against the words and ink
it was meant to sit under, differently per zoom and mode. A pattern colour
also has no notion of the page it belongs to.

**So this version has no bitmap.** Paper is vector: one `CAShapeLayer` per page
body, stroked by Core Animation at whatever scale the page is drawn, so there
is nothing to round. Line positions are exact multiples of the spacing from
the body's top left, computed in page points by a pure type, and the PDF draws
the same positions.

## What it is

- **Styles** (`PaperStyle`): Blank (the default, nothing stored), Dots, Grid,
  Lined (horizontal rules only).
- **Spacing** (`PaperSpacing`): Fine 16, Standard 24 (a quarter inch), Wide 32
  page points. 24 and 16 divide the page body (960 tall) exactly; 32 does too.
- **Strength** (`PaperStrength`): Light, Standard, Strong; the pattern's opacity.
- A note's **setup** is the three together (`PaperSetup`), stored as one
  string.
- **Never aligned with text.** Paper takes no part in layout, so a line of text
  does not sit on a rule. It is a ground for ink and diagrams, as in
  Notability; aligning text would mean moving lines, which moves ink.

## Where it is drawn

- In `PageDecorationView`, which is already a subview of the text view *below*
  the text and the canvas, so it is behind both and scrolls and scales with
  them by being in the same coordinates. No new view in the page's hierarchy
  order, no change to who owns touches.
- **One shape layer per page body** (`PaperLayers`), full page width, at
  `PageLayout.paperRegions`: the body, x 0 to the page width, y `bodyTop` for
  `bodyHeight`. Side margins are ruled, top and bottom margins are not. The
  regions are inside every page's `inkRegion`, so none of the bands the covers
  hide (print layout's margins and gaps, compressed's strip) ever holds paper,
  in any mode, and the covers need not know about it. In seamless there is a
  36pt plain strip at the top of the note and 72pt at the bottom; in print
  layout the 72pt margins are plain, as paper's would be.
- **The origin of the pattern is the body's top left**, the same on every page
  and in every mode, so a mode switch moves a page's paper with its words and
  ink (all three use `bodyTop`). Lines at the body's edges are left out (a
  line on the edge would hang half outside the layer), so the first line is one
  spacing in.
- All pages share one `CGPath`; the layers differ only in frame. Core Animation
  culls layers off screen.
- **Dots** are the dash trick: a horizontal line per row stroked with a round
  cap and the dash pattern `[0, spacing]`, so each zero-length dash is a dot.
  No point list, no backing store.
- **Above the sheets** in print layout: the paper host layer is moved to the top
  of the decoration view's sublayers on every update, because a mode switch adds
  sheet views after it exists.

## Colour

A tone is a colour with an alpha over whatever the page is, so it matches the
page in both appearances and whatever the surround does. Light: slate
`#64748B` at 0.12 / 0.18 / 0.28 (grid, lined) and 0.30 / 0.42 / 0.60 (dots,
which are 2pt wide and look fainter for it). Dark: white at 0.08 / 0.12 / 0.20
and 0.22 / 0.32 / 0.48. Colours are resolved per appearance on trait changes,
as the sheets' borders are. Test: the label colour keeps 4.5:1 on the page with
the strongest paper laid over it.

## The PDF and thumbnails

`NotePDF` draws paper on each sheet before the text, ink last, in the light tone
(the PDF is forced light), at the same positions: the sheet's body, origin the
body's top left. Lines are filled rectangles, dots are filled circles (a PDF
viewer's reading of a zero-length round dash varies), so the file stays vector.
**Printed at 0.75 of the screen's alpha**, so a printout isn't grey. Thumbnails
take the PDF's path, so they show paper too; `NoteThumbnail.version` goes up
and the cache name needs no new part, since the version is in it and a note's
paper isn't an edit (see below): the thumbnail's key includes the stored string
(`-p<paper>`), like text size.

## Cost

Paper is **drawing only**: it adds no text-storage edit, no exclusion path and no
line to lay out, and the page height is a function of the text alone. Tests
compare every line fragment's frame, the content height and the page count of
the same note with paper on and off in all three modes and both orientations,
and the typing cost test is unchanged. Measured separately (see the table at
the end) the cost of building the layers for a long note and of rendering a page
of paper.

## The model

`Page.paperStyle: String?` in version 1, edited in place (the release is not
out, `AGENTS.md` › The model). `nil` is Blank. Optional with no default, so it is
CloudKit-shaped. `ModelFreezeTests.versionOneHashes["Page"]` is updated in the
same commit as the attribute. Format: `style`, `style/spacing` or
`style/spacing/strength`, with trailing defaults omitted (`grid`,
`grid/fine`, `lined/standard/strong`); an unknown style reads as Blank, an
unknown spacing or strength as the default, so a later build's value never
breaks this one. Blank is always `nil`, whatever spacing was chosen.

Changing a note's paper is **not an edit**: `modifiedAt` stays and the text undo
stack is untouched, as for pinning and the text size. It moves nothing, so there
is no ink question.

## Defaults and carrying

- **New notes** take the device's default (`PaperSetup.preferred`, three keys:
  `defaultPaper`, `defaultPaperSpacing`, `defaultPaperStrength`), Settings ›
  Notes › New Notes › Paper. Blank until changed. It changes new notes only.
  `Page.create` is the one path every new note goes through, so the "+" tap,
  the menu, a folder's menu, templates and Import all take it.
- **Duplicate** copies the setup. **Templates** use the default like any new note.
  **Import** is a new note. **Welcome note** too.
- **Export All** writes Markdown (and PDFs for notes with ink); a PDF carries
  the paper because it is made by `NotePDF`. Markdown has no place for it.
- **One type, one `apply(to:)`**: `PaperSetup.apply(to:)` for a page view, and
  for a note, so the picker, Create and Duplicate cannot set one part and
  forget another.

## Where the reader picks it

- ••• › **Paper** in the open note's header menu, a submenu: the four styles
  with the current ticked, then Spacing and Strength (each three, ticked).
  Off while Blank for the last two. Available in a locked note: it is not text.
- Settings › Notes › **New Notes › Paper**: the same three, for new notes.

## Provisional (Marcus to review)

- Spacings 16 / 24 / 32 and the colours above; strength Standard by default.
- Margins left plain (bodies only), not the whole sheet. The alternative, whole
  sheet in print layout, needs the covers to draw paper too.
- Paper is not drawn in the top 36pt / bottom 72pt of the seamless note.
- Printed at 0.75 alpha. No setting for "don't print the paper".
- Per-note spacing and strength, not only per-note style: spacing matters to
  ink drawn along it, so it travels with the note.
- No paper colour (white/cream/etc.), no per-folder default.

## Measured

Simulator (iPad Pro 13-inch, 24 Oct), `PaperLayerTests.cost`, a 300-page note:
setting any style up takes 0.6ms (one frame and the shared path per layer);
drawing one page's layer in full in software, an upper bound on the render
server's work for a page on screen, takes 1.2ms for lined, 2.0ms for grid and
6.9ms for dots (Fine spacing, the densest: about 2,950 dots a page; Standard has 1,287).
Layout is untouched: `laysNothingOut` compares every text fragment's frame
and the content height with and without paper (grid and dots, all modes and
both orientations) and they are equal.

**Pixel checks** read the rendered page at a rule, between rules, at a dot and
between dots, in seamless, compressed and print layout, light and dark, at
zoom 1, 1.37, 1.7 and 2.2: the rule is on its note point and the rest is the
page colour. A control with no paper is read at the same points first.
**The snapshot goes black at zoom 3 in a unit test** (`drawHierarchy` on a
page scaled that far, with or without paper), so zoom 3 and 4 are not
covered by a test; they are on the on-iPad checklist.

Mutation-checked (24 Oct): the layers moved 5pt (`layersFollowBodies`,
`rulesSitOnTheirPoints`, `dotsSitOnTheirPoints`); the host not kept above the
sheets (`aboveSheets`); the PDF's paper call removed (`printedGrid`,
`printedDotsAndLines`, the thumbnail test).

## Looked at in the simulator

Grid in seamless (light), dots at Fine and Strong in print layout (light), lined in
compressed (dark), each behind the text and the code panel, margins plain. Not
looked at: ••• › Paper and Settings › Notes › Paper (built, compiled, their
binding logic tested), landscape, the Pencil, a real iPad.

## On-iPad checklist

1. ••• › Paper: pick each style, spacing and strength; the tick follows; Blank
   hides Spacing and Strength. The note's date and the list order don't change.
2. Settings › Notes › Paper, then a new note from "+": it has that paper, an old
   note doesn't change.
3. Pinch-zoom to 4x on grid and dots; draw a line along a rule with the Pencil.
   The paper stays on the same words and ink as you zoom, and is sharp.
4. Switch seamless / compressed / print layout and rotate the iPad: the paper
   stays with its page body.
5. Scroll a 20-page note with dots at speed: no hitching.
6. Share ▸ PDF, open it in Files: paper is faint, vector (zoom in), margins plain.
7. Duplicate a ruled note; Export All with a ruled note that has ink.
