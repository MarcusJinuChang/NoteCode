# Typing cost in long paged notes

Debt item D9 (docs/refactor/debt.md). A design note: what a keystroke costs in
a long paged note now, where the time goes, and which design to build next.
Nothing here has shipped. The background is
[pages.md](pages.md) › "Page breaks are pushed paragraphs" and › "Cost", and
decisions.md, 7 Nov.

## Where it stands

D9 was written down when a keystroke near the top of a 40-page note cost
about 97ms, because every page break was an exclusion path. F5 (PR 226)
changed that for nearly every note: breaks are now paragraphs pushed whole to
the next page, and the container has no paths. What is left has three parts:

1. **A paragraph taller than a page's body still uses exclusion paths**, for
   the breaks it crosses (`PagePaginator.applyBands`). A note with one such
   paragraph, anywhere, pays the whole old cost on every keystroke, wherever
   the caret is. This is the part of D9 that is still the 97ms.
2. **The paginator's walk is linear in the note.** After an edit it walks
   every paragraph from the edit to the end of the note (pages.md says why it
   must reach the end). That is about 0.12ms a page: 1.2ms at 10 pages, 24ms
   at 198.
3. **The edit itself is linear in the note, pages or not.**
   `UITextView.replace` on the configured view costs about 3µs a line before
   any layout. That is not pagination. It is a finding for another item
   (below).

## What was measured

All numbers are on the iPad Pro 13-inch (M5) simulator, Debug build, on 11
Nov, with other build lanes running on the machine. Each is the median of
nine one-character edits near the top of the note, the way
`PageViewTests.Cost` measures. The text is `StylingPerformanceTests.document`.
On the same day the existing cost tests read
`typingCostLongNote` 6.5ms (baseline 5.1), `exclusionPathsAreTheCost.with`
104.8ms (100.7), `.without` 2.0ms (0.8) and `.paged` 6.1ms (5.0). So expect
these numbers to run 10–30% high in absolute terms. The ratios are what
matter. The probe was a throwaway test file. It was not committed.

### How the cost grows with pages (no tall paragraph)

The probe splits each keystroke into three timings: the edit
(`UITextView.replace`), an explicit `PageView.paginate()`, and the
`layoutIfNeeded` that follows. "Plain" is the same text in a configured text
view with no pages.

| Lines | Pages | Paged total | edit | paginate | layout | Plain total |
|---|---|---|---|---|---|---|
| 375 | 10 | 3.1 | 1.2 | 1.2 | 0.7 | 1.8 |
| 1,500 | 40 | 11.5 | 4.4 | 5.6 | 1.5 | 4.7 |
| 3,750 | 99 | 25.1 | 11.9 | 11.2 | 2.0 | 11.4 |
| 7,500 | 198 | 52.2 | 24.9 | 23.9 | 3.4 | 25.1 |

In ms. The probe calls `paginate()` itself so it can time it, which runs the
walk a pass earlier than a layout pass would. Its totals therefore sit above
the PERF line for the same note (6.5ms at 40 pages). The paginate column grows
at 0.12ms a page. The edit column grows at the same rate with pages and
without them.

### Exclusion paths: is it how many, or where?

The test used a configured text view holding 1,500 lines, with no pagination
running, and set the paths by hand.

| Paths | ms a keystroke |
|---|---|
| none | 8.9 |
| one, at y 900 (near the edit) | 86.2 |
| one, at y 60,000 (deep in the note) | 84.5 |
| one, far past the end of the text | 92.3 |
| two, near the top | 84.4 |
| 45 (one after every page) | 100.8 |

**One path costs nearly what 45 do, and its place doesn't matter**, even when
it lies below all the text. With any path in the container, TextKit 2 lays
out everything below an edit again. The number and position of the paths
barely change that.

The same happens with none of our code involved. A bare
`UITextView(usingTextLayoutManager: true)` holding the same text costs 4.9ms
a keystroke with no path and 77.9ms with one path past the end of the text.
An edit made on the text storage directly, which leaves out UIKit's edit
path and our delegate, shows where the time lands. On the configured view it
is 0.2ms for the edit and 0.5ms for the layout with no path, and 6.2ms and
81.6ms with one path. So the time is TextKit laying out again, not
anything of ours. Through `UITextView.replace`, most of it (55–70ms) falls
inside `replace`, because UIKit lays out at once to place the caret.

### A tall paragraph in a 40-page note

The note was 1,500 lines plus one prose paragraph of about 10,000 characters
(120 lines, about two and a half pages). It gets three paths.

| Tall paragraph at | Edit at the top | Edit inside it | Edit below it |
|---|---|---|---|
| line 60 | 82.6 | 81.7 | 79.4 |
| line 1,450 | 89.7 | 55.2 | 81.3 |

So a note with one such paragraph costs a keystroke what every 40-page note
did before F5, wherever the reader types.

### A gap inside a paragraph, without a path

This probe used a bare TextKit 2 view and the same tall paragraph. It set
`.baselineOffset` on the characters of one of the paragraph's lines (line 10
of 120):

- **−60** made that line exactly 60pt taller (20.3 → 80.3), with its glyphs at
  the bottom and the space above them. **+60** made it 55.9pt taller, with the
  space below the glyphs. A negative offset is the exact one.
- **The wrap did not change.** It was still 120 lines with the same character
  ranges, since a baseline offset changes no glyph's width. Lines above stayed
  where they were. Every line below, and the next paragraph, moved down by
  exactly the growth.
- **A keystroke at the top cost 4.6ms**, against 4.9ms with nothing and 77.9ms
  with one path. Nothing below the edit was laid out again.
- **Hit-testing** a point on the moved glyphs lands in that line.
- **UIKit's caret and selection rectangle cover the whole grown line**, 82pt
  against 22pt for a normal line. In our view `DocumentUITextView.caretRect`
  already corrects this for code fences, but reads the text storage's
  attributes and not the layout copy's (risks, below).

## Candidate designs

### A. Fewer exclusion paths (one per visible region, or only near the caret)

**Rejected by measurement.** One path anywhere costs 85–92ms, about what 45
cost, and a single path below all the text costs the same. Any design that
keeps even one path while the reader types keeps the cost.

### B. A text container per page

TextKit 2 has one container per `NSTextLayoutManager`, and a `UITextView`
has one layout manager. Pages as containers would mean a layout manager and a
view per page over one content storage, and our own editing across them:
caret and selection across a page boundary, the edit menu, the keyboard,
marked text, and which layer owns touches. It would also undo "Who owns
scrolling" (the text view scrolls itself). **Rejected**: this is a new editor,
not a fix, and every trap in AGENTS.md around the text view would have to be
learned again.

### C. Page breaks inside a tall paragraph as a per-line gap in the layout copy

This handles a tall paragraph the way F5 handles every other paragraph.
Paths go away entirely, and the break becomes space in the copy of the
paragraph that TextKit lays out. `BlankLineLayout` (the content storage's
delegate) already adds the push to that copy as paragraph spacing. For a
tall paragraph it would also give the characters of the **first line after
each break** a negative `.baselineOffset` of the break's height. That height
is the distance `PageBreakRule.linePlacement` already works out today. The
note's text and styles are untouched, as with pushes.

- **Cost**: the probe's 4.6ms. A keystroke in a note with a tall paragraph
  costs what one without does.
- **Where the lines fall**: it reproduces the line tops the paths give now,
  so the tall paragraph does not move on the page. That is unlike F5, which
  moved split paragraphs and accepted ink drift (decisions.md, 7 Nov). **There
  is no new drift.** Ink is anchored to the page, and the lines it sits beside
  stay put. This is an acceptance criterion, not an assumption.
- **Risks, against the traps**:
  - *The caret and the selection.* UIKit draws both the height of the grown
    line, which is a caret that runs through the page gap, and in print
    layout across two sheets' margins. `caretRect(for:)` reads the storage's
    `.baselineOffset`, which the copy-only gap is not in. It would need the
    gap from `PagePushTable`, and `selectionRects(for:)` would need the same
    clamp, which the view does not override today. Both need a real look on
    the iPad.
  - *Attributes already there.* The styler sets `.baselineOffset` on some
    paragraphs (DocumentStyler.swift:402), and `MarkdownLayout` lifts single
    characters. The gap has to be added to the value already there, never
    replace it, or those glyphs drop.
  - *The wrap must not move.* The probe shows a baseline offset changes no
    line's characters, so placing the gap needs no second pass. If a later
    TextKit changed that, the paginator's repeat-until-still loop
    (`passLimit`) would bound it, and the guard test below would catch it.
  - *Position things from lines* (pages.md). A line's typographic bounds
    would include the gap above its glyphs. Anything drawn at a line's top
    on a gap line would land in the gap. A gap line is never a paragraph's
    first line, so list markers and checkboxes are safe, but blockquote and
    callout bars, highlights and the hidden-marker runs need checking.
  - *Code panels* read the container's paths
    (CodeBlockLayoutFragment.swift:493). Code lines are paragraphs of their
    own and are never tall, so nothing changes for them. The read becomes
    dead code once nothing sets paths. Remove it in a separate step.
  - *The PDF* draws text from the same layout, so the glyphs follow. But
    `NotePDF.drawFormulas` (NotePDF.swift:463) reads `.baselineOffset` from
    the line fragment's `attributedString`, which is the layout copy, and
    subtracts it from the glyph origin to place a formula. With the gap in
    that attribute, a formula on the first line after a break would be drawn
    about the gap's height away from its glyphs. Stage 1 has to settle this.
    TextKit only moves glyphs by `.baselineOffset`, so the gap has to be in
    it, but the copy can also carry the gap under a key of its own on the
    same characters, and readers like this one subtract that. The other way
    is for each reader to subtract the gap from `PagePushTable`. Grep for
    every reader of the copy's `.baselineOffset` when building it.
    `NotePDFTests`, with a formula on a gap line, and a look at a printed
    tall paragraph confirm it.
  - *Fence detection, `.layoutManager`, `nativeUTF8`*: not touched. The gap is
    an attribute in a paragraph copy, applied where pushes already are.

### D. Split a tall paragraph into several elements for layout

A custom `NSTextContentManager` (or an `NSTextContentStorage` override) would
hand TextKit a tall paragraph as one element per page, each with an ordinary
push. **Rejected for now**: the delegate we use maps one paragraph range to
one element, and replacing the content manager reaches into location mapping,
selection and every `textElement`-based reader (`appliedPush`,
`laidOutPanelRuns`, the caret). It is far more surface than C for the same
result.

### E. Drop the paths while the reader types, restore them on a pause

**Rejected.** While the paths are gone, the tall paragraph's lines past each
break slide up into the gap and then jump back. Ink beside them is wrong in
between, and a mode switch or a PDF taken mid-burst would have to restore
first. It trades a cost for a visible fault.

### F. Stop the walk early (for part 2, not the tall case)

After a keystroke that changes no paragraph's height, every paragraph below
is where the last full walk found it. So the walk could stop at the first
paragraph past the edit whose top and push match that walk's. Comparing with
TextKit's current frame is not enough. TextKit has already moved the
paragraphs below by the edit's change in height, so a frame can agree with
the running position while a paragraph further down now crosses a break. The
table would have to keep each paragraph's checked top and shift those tops
with edits, as it shifts pushes. That is not a tiny change. It saves at most
the paginate column (5.6ms at 40 pages, 24ms at 198). **Worth doing after C**,
with `ReopenTests` and `PageSettlingTests` as the guard for the page count.

## Recommendation: C, then F

C removes the only remaining 97ms case, keeps every line where it is now
(so no ink moves), and reuses the mechanism F5 built (a layout-only attribute
in `BlankLineLayout`, kept in `PagePushTable`, applied with
`edited(.editedAttributes…)` over one paragraph). F is an independent
follow-up for very long notes.

### Staged plan

0. **Probe in the real view (test only).** In a `PageHarness` note with one
   tall paragraph, apply the gap through `BlankLineLayout` for its breaks
   with the paths cleared. Check three things: the paragraph's line tops
   equal those of today's path layout within 0.5pt, in all three modes; the
   wrap is the same; and a keystroke at the top falls to the no-tall cost.
   If the line tops can't be matched, stop. C would then move ink, which
   needs a decision like F5's.

   **Done 11 Nov: it passes** (`PagedGapProbeTests`, iPad Pro 13-inch (M5)
   simulator, Debug). The gap is laid in by a test-only content storage
   delegate that wraps the view's `BlankLineLayout` and adds a negative
   `.baselineOffset` to the copy of the first line after each break, of the
   height `linePlacement`'s rule gives; no app code changed. The push table
   is frozen while it runs (`isApplying`), so the walk neither runs nor puts
   the paths back, since teaching the walk the gaps is stage 1.

   | Mode | Breaks | Gap | Line feet moved | Glyphs drawn moved | Wrap |
   |---|---|---|---|---|---|
   | seamless | 6 | 11pt | 0.000pt | 0.00pt | same (298 lines) |
   | compressed | 6 | 34pt | 0.000pt | 0.00pt | same |
   | print | 6 | 178pt | 0.000pt | 0.00pt | same |

   The note is a 228-line paragraph between prose. The gap is the break's
   band (1, 24 and 168pt) plus the 10pt foot of the page the line would have
   straddled, so both branches of the rule are used: a line starting in the
   band and a line crossing into it. "Glyphs drawn" is the
   first inked row of each of its lines, with the paragraph's layout fragment
   drawn at 2 pixels a point, with paths and with gaps. Every line of the note
   below the paragraph also stays put. A gap line's typographic bounds grow
   by the gap, upwards, as the bare-view probe found. One reader to watch:
   `NSTextLineFragment.glyphOrigin` leaves `.baselineOffset` out, so on a gap
   line it reads exactly the gap high while the glyphs are drawn where the
   paths drew them. Anything placed from it needs the gap taken off, as
   risk *The PDF* says for `.baselineOffset`.

   The cost, a keystroke at the top of the 40-page note with a
   10,000-character paragraph at line 60. Each number is the best of three
   batches, each batch the median of nine keystrokes on a monotonic clock.
   The gaps are timed on a harness of their own. Two runs, in ms:

   | | Run 1 | Run 2 |
   |---|---|---|
   | No tall paragraph | 5.5 | 5.2 |
   | No tall paragraph, table frozen | 5.1 | 5.2 |
   | Tall, exclusion paths | 76.4 | 76.8 |
   | Tall, exclusion paths, table frozen | 76.3 | 77.2 |
   | Tall, gaps, table frozen | 5.0 | 5.0 |

   So with gaps a keystroke costs what one in a note without a tall
   paragraph does, and freezing the table is not what saves the time. The
   walk (about 0.12ms a page) comes back on top in stage 1, as for any note.
   Earlier runs, with a single batch timed on `Date()`, gave gaps 5.2-5.6ms
   against 5.1-6.3ms without a tall paragraph and 78-91ms with paths.

   *Frozen* means more than "no walk". The table ignores the edits, so it
   neither lowers `through` nor shifts its pushes, and after a frozen run its
   keys past the edit are out by the characters typed. The comparison is
   still fair. The edits are at offset 120, in a paragraph with no push, and
   TextKit asks the content storage's delegate again only for the paragraph
   edited, so no stale key is read while the run is timed. Every frozen run
   is frozen the same way, and none is laid out again afterwards.

   The test's bounds are loose: gaps under a third of paths, and under twice
   the frozen note without a tall paragraph plus 2ms.
1. **Build C.** `PagePaginator`'s `.tall` case records gaps per line start in
   `PagePushTable`, shifted with edits like pushes. `BlankLineLayout` adds
   them to the copy's `.baselineOffset`. `applyBands` and the paths go.
   `caretRect(for:)` and a new `selectionRects(for:)` take the gap from the
   table and keep the caret and highlight to the glyphs. Readers of the
   copy's `.baselineOffset` that place things by it (`NotePDF.drawFormulas`)
   must not count the gap: record it under its own key in the copy and
   subtract it there (risk *The PDF*, above). `PageBreakRule.linePlacement`
   should return each line's gap, so the paginator and its tests use one
   rule (the stage 0 probe has a copy of it). Add a perf test,
   `PageViewTests.Cost.typingCostTallParagraph`, with a PERF line in
   baseline.md, that types above the tall paragraph and inside it (D9's
   symptom is a slow keystroke anywhere in the note; stage 0 timed only
   above it), and a test that the line tops match a stored path layout.
2. **Tidy (refactor step).** Remove the exclusion-path readers that nothing
   feeds any more: `CodeBlockLayoutFragment`'s `breaks` from the container,
   and `PageBands`' clearing. Then update `exclusionPathsAreTheCost` so it
   still shows the old cost on a plain view of its own, as it does now.
3. **F**, as above, if a long note still feels slow on the iPad.

### Acceptance numbers

Measured as `PageViewTests.Cost` measures, in the same run:

- **A 40-page note with one tall paragraph**: a keystroke at the top, inside
  the tall paragraph and below it each cost at most 1.5× `typingCostLongNote`.
  Today they cost 55–90ms against about 6ms.
- **`typingCostLongNote` and `exclusionPathsAreTheCost.paged`** are no more
  than 10% worse than their PERF lines.
- **Line tops**: every line of a tall paragraph within 0.5pt of the path
  layout, in seamless, compressed and print, and on the page it was on.
- **Caret**: on a gap line it is the height of a caret on an ordinary line of
  that font, and its top is not above the glyphs' line.
- `PageSettlingTests`, `ReopenTests`, `NotePDFTests` and the code-panel tests
  pass as they are.
- **PDF formulas**: a new `NotePDFTests` case puts an inline formula on the
  first line after a break in a tall paragraph and checks it is drawn on its
  glyphs' baseline, within 0.5pt, not a gap's height away.
- After F (if built): the paginate share at 198 pages under 2ms, from 24ms.

## Finding outside D9

`UITextView.replace` on the configured view costs 4.0ms at 1,500 lines and
24ms at 7,500, with or without pages. The same edit made on the text storage
directly costs 0.2ms. The evidence points at UIKit's own edit and caret
path rather than at our code: a bare `UITextView(usingTextLayoutManager:
true)` with none of our delegate, styler or parser costs 4.9ms a keystroke
at 1,500 lines, the configured view with no pages 4.7ms, and its `replace`
alone 4.4ms. UIKit also lays out at once inside `replace` to place the caret
(above). So most of it is probably UIKit laying out to the caret, and it
grows with the note. How much of it, if any, is ours was not measured: the
probe did not time the delegate, the styler and the parser on their own.
F5's measurements did not separate it out either. It is worth a debt row of
its own, starting with that split, since at 198 pages it is half of the
keystroke.
