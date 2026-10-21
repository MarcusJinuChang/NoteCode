# Writing: hidden Markdown markers, lists, checklists, links
v3 phase 3 (12 Oct, `docs/archive/ui-design-v3-implementation.md`).

- **Markers take no room** (`MarkdownLayout`; every note is laid out this way
  since 15 Oct, when `Page.markdownLayout` and its legacy case went). `BlankLineLayout`'s content-storage delegate swaps each
  marker for U+2060 WORD JOINER in the paragraph TextKit lays out: same
  length, so offsets map straight through, and the text storage still holds
  the Markdown. The ranges are `DocumentStyler.layouts`' own (`blockMarkers`,
  each inline's `markers`), so styling and layout can't disagree. Collapsed:
  a heading's `# `, the markers of complete inline spans (inline code only its
  backticks), a link's `[` and `](url)`, and a checkbox item's `- `. A bullet
  `-`/`*`/`+` lays out as `•`; `[ ]` or `[x]` as an em space plus two joiners,
  and the box is drawn in the em space. Nothing in a code block. The coordinator's
  `rendersMarkdown` is still a flag, off by default, and the app turns it on for
  every note: the test harnesses (`CodeFenceDisplayTests.Harness` and its
  neighbours) are written against the flag being off, and flipping the default
  means rewriting their expectations, so that is left for its own change.
  - **State-independent**: the swap is a function of the text alone. The caret,
    the mode and Show Markdown never change it.
  - **Probe, as tests** (`MarkdownLayoutTests`). Every line frame (fragments
    and lines) of a note with bold, code, strike, a link, a heading, bullets
    and boxes equals that of the same styled text with the markers physically
    deleted, in seamless, print and landscape. A control test and a mutation
    (swap off) both fail it. Carets beside a run are full height. A closing
    marker typed, a span broken, and a fence opened or closed above all lay
    out the same as a fresh note, *in the edit that makes them*: the styler's
    attribute edit regenerates the paragraphs whose parse changed, so nothing
    stale survives. A keystroke in a 500-line rendered note: 37.2ms against
    37.0ms legacy (`MarkdownLayoutCostTests`); the runs are computed once per
    edit (`layoutMarkerRuns`), not per paragraph, and a layout parses nothing.
  - **Measured, so it isn't tried again**: a joiner is zero width in the body
    font, next to an em space too (CoreText); `closestPosition` over a bold
    word returned offsets on both sides of each marker and never inside one;
    a test's ground truth has to keep the em space and `•` the swap puts in,
    or the checkbox and bullet lines look 10pt off.
  - **Markers at a line's end** (15 Oct). TextKit puts a caret in front of a
    zero-width character at the line's *start* when nothing drawn follows it
    on the line: a plain `UITextView` with no app code does it, for U+2060,
    U+200B and U+FEFF alike. So in `[Apple](apple.com)` alone on its line,
    the offset after "Apple" sat at x = 0: the link measured no width
    (`enumerateTextSegments`) and couldn't be tapped, and a caret after a
    bold word that ends its line was drawn at the line's start. A link with
    words after it was fine, which is why every link checked on 13 Oct
    worked. `MarkdownLayout.laidOut` now lays out the last joiner of a run
    that ends its paragraph as a no-break space kerned back by its own
    advance (`anchorTrailingJoiners`): a glyph to measure against, still no
    width and no break. `MarkdownLayoutTests.caretsInMarkersEndingALine`
    checks every caret in such runs, and the lines' frames, against the
    markers-deleted note, and fails without it.
  - **`PrintedNote` takes `rendersMarkdown`** (PDF and thumbnails), or the
    paper breaks lines where the screen doesn't. `NoteEditor.rendersMarkdown`
    carries it from the coordinator. A thumbnail's cache name has `-r` for a
    rendered note, since hiding markers isn't an edit and leaves `modifiedAt`
    alone, and `NoteThumbnail.version` was 2 (3 since step 10's code blocks,
    4 since code is coloured light on a dark device).
  - **The parser got stricter on the way** (`InlineParser`): an emphasis span
    can't start with a space or end after one, and `_` can't open or close
    inside a word. `2 * 3 * 4`, `int *p and *q` and `snake_case_name` were
    spans, which was a dimmed-asterisk quirk before and a vanished character
    once markers are hidden.
- **Reveal is drawing only.** `HeadingLayoutFragment` widens
  `renderingSurfaceBounds` into the left margin and draws the hashes in
  `secondaryLabel`, right-aligned 8pt left of the text on the first line's
  baseline: while the caret or a selection is on that heading (Show Markdown ›
  While Editing) or always (Always); never in ink mode, never printed (the
  PDF draws lines, not fragments). Redrawn the way fences are
  (`HeadingMarkerDisplay.swift`, state in `HeadingMarkerVisibility`, asked at
  draw time, `setNeedsDisplay` on the changed fragment views): a caret move
  makes no fragment and edits no storage (tested, as `CodeFenceCostTests`
  does). **A unit test can't see the crop**: `layer.render` doesn't apply the
  fragment view's bounds, so the pixel test passed with the reach removed. The
  contract is tested instead (the area reaches past the hashes at every level;
  fails without the union), and the real crop was looked at in the simulator.
  A fragment's default area reaches only 11pt left of its text.
- **Inline formatting shows in the hotbar** (`NoteEditor.caretFormatting`,
  `MarkdownFormatting.formatting`): Bold, Italic and Code light up, Style ▾
  and List ▾ show checkmarks. A caret is in a span from just after its first
  marker character to the end of its text, which is what typing there makes.
- **Caret stops** (`MarkdownFormatting.caretStop`, pure, on the one line,
  parsed with the styling's parsers). Every offset in a hidden stretch is one
  place on the page; the stop is its left edge for inline markers (the end of
  a bold word is inside it, the start isn't) and after it for a heading's
  marker or a checkbox's `- [x] `. Touching markers are one stretch.
  Applied in `closestPosition(to:)` and in `textViewDidChangeSelection`
  (`normalizeCaret`).
  - **Never after an edit.** Typing the closing `**` leaves the caret after
    it; normalising would put it back inside the bold and the next letter
    with it (`typingIsLeftAlone`). An edit is told by `editCount`.
  - **An arrow is a caret that moved one place with no finger down**
    (`wasTouchedRecently`, from `hitTest`); a tap, or any other landing, goes
    to the stop. An arrow leaves a stretch the way it came in: right from an
    inline stop goes one visible place on, except at a line's end, where it
    goes just past the markers, the only way out of bold there (invisible,
    and the hotbar's Bold shows it). Left from a heading's stop goes to the
    line above.
  - **A tap past a line's end goes after its markers** (13 Oct). A line that
    ends in a bold word or a link has two places at its end, either side of
    the hidden markers, and the stop rule put every tap on the one inside
    the span, so tapping in the empty space after such a line left the caret
    short of the end. `DocumentUITextView.isBeyondLineEnd` asks whether the
    touch is more than 8pt right of the line's last glyph; if so
    `closestPosition` and `normalizeCaret` leave the caret at the line's end
    (`CodeEditingFixesTests.tapAfterBold`, `.tapAfterLink`). A tap *on* the
    last letter still stands inside the span. Not tried with a real
    finger.
- **Backspace** (`MarkdownFormatting.backspace`, applied in `shouldChangeTextIn`
  through `Coordinator.apply`, which is `replace(_:withText:)`, so undoable and
  restyled): at the start of a heading's or list item's text it removes the
  marker (keeping indentation); in front of, inside or just past a closing
  marker it deletes the last visible character of the span by grapheme, and an
  emptied span goes with its markers. Elsewhere the ordinary Backspace.
- **Return, Tab, ⇧Tab.** Return in a list item continues it (same bullet, next
  number keeping `.` or `)`, an empty box); on an empty item it ends the list;
  text after the caret moves to the new item; one undo step. In a rendered note
  Return at the end of a line that ends in closing markers puts the newline
  *after* them (the caret stands in front, and a plain newline split `**` from
  its word). Tab nests two spaces, ⇧Tab takes them back, only on list items
  (otherwise the key is given back). Tab arrives as `shouldChangeTextIn` with
  `"\t"`; ⇧Tab is a `UIKeyCommand` on `DocumentUITextView` with priority,
  not a menu button, since a bare Tab in the menu bar would take it from every
  field. Numbers after an inserted item aren't renumbered.
- **List ▾** has Bulleted, Numbered and Checklist (`toggleList`): another kind
  converts, the same kind takes the list off, numbers count written lines.
- **Checklists**: `- [ ]` / `- [x]` (any bullet char; `[ ]` then a space or the
  line's end) is `ListMarker.checkbox`. `ChecklistLayoutFragment` draws the box
  (2pt `tertiaryLabel` outline, 6pt radius; checked: accent fill and a white
  tick) in the em space, or over the `[ ]` glyphs in a legacy note, and the PDF
  draws it with its line (accent by name: paper has no tint). A ticked item is
  struck through in `secondaryLabel`.
- **Taps on boxes and links** (`MarkerTaps.swift`). **Decided without the
  spike**: `textView(_:primaryActionFor:)` wasn't tried; the brief's fallback is
  what a box needs anyway and one path serves both. Recognisers on the text
  view take the tap and the hold. The text interaction's recognisers (the
  caret's tap, the loupe, Scribble's) sit on the text view too and see the
  same touch, so on a box or a link `DocumentUITextView` refuses all but
  scrolling and the marker gestures in `gestureRecognizerShouldBegin`. UIKit
  asks only the view a touch *lands on*, so `hitTest` answers with the text
  view itself there; without that the touch lands on a view inside it and the
  text view is never asked. **Fixed 15 Oct** (links not opening on the iPad,
  reported 13 Oct), logged on the device: until then only the `hitTest` half
  existed and kept nothing off, the caret's tap beginning alongside the link's
  on every tap, cancelled only by the handler's `resignFirstResponder`; and a
  link that ended its line measured no width (see "Markers at a line's end"),
  so a tap on it was plain text. A lifted hold isn't also a tap
  (`MarkerGestures.heldThisTouch`, a flag, since on the iPad the hold had
  ended before the tap asked). Within 22pt of a selection's ends nothing is
  refused, so a handle over a link stays draggable (not tried on screen).
  They live on a separate delegate object
  (`MarkerGestures`): a scroll view is the delegate of its own pan and pinch.
  `LinkTapTests` finds the tap point in the note with its markers deleted,
  and fails without either fix; the `hitTest` half needs a real touch, and was
  seen working only on the iPad (finger and Pencil in the log, the trackpad by
  eye). A box needs an
  editable view; a link opens in a locked note too. Link text: `[text](url)`
  and a bare `http(s)://` address shown exactly as typed, `#B85900` / `#FFAA33`
  underlined (`DocumentStyler.linkColor`); inline code isn't a link. Only
  http, https and mailto open (`LinkTarget`); no scheme means https. A hold
  shows the address with Open Link and Copy Link (`UIEditMenuInteraction`).
- **Hide Markdown Markers…** is gone (15 Oct): it converted a note from before
  v3, and no note is kept from before v3 (see "The model").
- **Not checked** (see the PR's checklist): the Pencil; a real keyboard (⇧Tab,
  Tab, arrows past markers, ⌘B on a double-tapped word); Return and
  Backspace by the hardware keyboard; the margin hash in light mode on screen
  (dark was looked at; light is covered by the pixel test); fast
  typing and pasting into a rendered note; the title menu's conversion on a
  note with ink; the macOS app running (it builds); `closestPosition` for a
  selection drag handle.
