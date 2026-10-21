# Paste and copy with formatting
Text overhaul, phase 5 (19 Oct, branch `claude/paste-copy-formatting`;
docs/archive/text-system-overhaul.md). Styled text pasted into a note keeps its
bold, italic, strikethrough, underline, highlight, links, colour and size; a copy from a note
carries them to Pages, Mail and Notes. The pure part is `RichPaste.markdown`;
`RichCopy` builds the RTF; the text view's side is `DocumentUITextView`'s
`copy`, `cut` and `paste` overrides, and the coordinator's is
DocumentTextView+Clipboard.swift.

- **Before, measured 19 Oct** (iPad Pro 13-inch simulator, a real text view):
  RTF on the pasteboard arrived as its plain text (`allowsEditingTextAttributes`
  is off, deliberately: foreign fonts and colours would fight the styler), and a
  copy put one item on the pasteboard, `public.utf8-plain-text`, the Markdown
  with its stars, hashes and `<span>` tags. HTML-only pasteboards pasted nothing
  in the probe, which looked like the simulator's pasteboard cache failing to
  hand over the data (its log was full of "claims" errors) and was not
  followed up.
- **Paste** (`DocumentUITextView.paste` → `Coordinator.richPaste(into:)`) reads
  the pasteboard's RTF, flat RTFD or HTML, richest first
  (`RichPaste.attributedString`), turns the attributes into runs
  (`RichPaste.runs`, the only UIKit step) and the runs into Markdown
  (`RichPaste.markdown(from:atLineStart:)`, pure). It takes the paste only when
  the Markdown differs from what a plain paste would give, so unstyled text,
  and everything the text view already did well (the typing style, autocorrect
  traits), is untouched. It stands aside for:
  - **code**: a caret or selection in a code block, or reaching into one
    (`touchesCode`; an unclosed block holds the caret to the end of the note),
    is the text view's own plain paste;
  - **a copy from a note** (below), which is pasted as the Markdown it came as;
  - a locked note, a composition going, and a paste over 200,000 characters.
    RTF and RTFD over 2MB are left alone, and HTML over 400KB: its import runs
    on the main thread and a page's worth takes seconds.
- **A size is against the paste's body, not the note's font** (a change to the
  plan, which said "against the block's font"). The size most of the pasted
  characters have is the body (Pages' 12pt, Safari's 16px; monospaced text and
  white space don't vote) and every other size is its ratio to it, as `<span
  style="font-size:2em">`. Taken against the note's 17pt, every character of a
  16px page would have been 0.94em. Within 4% of the body is the body. Seen as
  a rule: the paste keeps its proportions and the note's own size decides how
  large they are.
- **Colours: only colours.** Black, white and anything within 15% of grey is the
  source's text colour and not a choice (`isDefaultColour`); links and code
  keep the app's own colours.
- **Code stays code.** A line whose words are all monospaced is pasted as
  plain text, since pasting a block from a web page in backticks line by line
  is worse than the plain paste; monospaced text among proportional text is an
  inline code span (and is never bold or coloured: a span can't hold a marker).
- **Lists.** A source that draws its list with a bullet or number and a tab
  (`\t•\tItem`, which is how RTF from Notes and Pages is assumed to carry one:
  the tests write it by hand) becomes `- Item` or `1. Item`, nested two spaces
  per tab past the first. A `-` or `*` needs a tab before it. Pasted into the
  middle of a line, a list item's marker is left out. **HTML lists carry no
  marker at all**: iOS's HTML importer keeps `<ul>` and `<ol>` out of the
  text (measured 19 Oct, a list came back as `One\nTwo`), so a list copied
  from a web page pastes as plain lines, as it did. Getting them would mean
  reading the HTML itself.
- **Written by Phase 3's writer, a line at a time.** A line is a blank
  `StyledLine` (or one holding only a list marker) with the line's characters
  inserted at its start, styles and all (`StyledLine.edited`), which reads back
  what it writes. A line that can't be written with its links is written
  without them, and one that still can't is the plain text (so a literal `*`
  in a bold line never leaves a line showing its markers). Links are kept only
  where the app would open them (`LinkTarget`: http, https, mail), their
  addresses escaped as the Link button does.
- **Normalised:** every line end is `\n`, no-break spaces are spaces and the
  object-replacement character an attachment leaves is dropped.
- **The paste is an app edit, not typing.** It goes through `Coordinator.apply`
  (`isApplyingMarkerEdit`), so it is one undo step, restyled like typed text,
  and written back to the page; it clears the typing style first, or the
  keyboard's rule for a paste would have written over it. The caret is left
  after the pasted text.
- **Copy** (`DocumentUITextView.copy` and `.cut` → `RichCopy`): the plain text is
  still the selected Markdown, byte for byte, and beside it come an RTF
  (`public.rtf`) of **what can be seen** and a type of the app's own
  (`RichPaste.ownType`) holding the Markdown.
  - The lines the selection touches are read whole (`StyledLine`), and a
    glyph is in the RTF if the selection touches it, so a selection that begins
    inside `**` still has the bold, and no marker is ever in it.
  - Fonts are the page's (`DocumentStyler.font(for:over:)`), a heading the
    heading font, a run its size against it. Colours are as a light page draws
    them (`AccentPalette.textHex`), since Pages' page is light; plain text has
    no colour, so a dark document keeps its own.
  - **The fonts are Helvetica Neue and Menlo** at the page's sizes and weights
    (`RichCopy.portable`), not the system font: its name in RTF is private and
    another app may not find it. `copiesBoth` fails on any font whose name
    isn't Helvetica Neue's.
  - Lists keep a marker when the selection reaches it (a bullet, `1.`, `☐`/`☑`),
    indented by depth. Code is monospaced text, a line each, with no fences, no
    panel and no syntax colours.
  - **Why the Markdown rides twice.** Pasting into a note reads RTF if there
    is any, and would turn a note's own copy into RTF's idea of it: the fences,
    headings and checkboxes RTF has no word for, `__bold__` rewritten as
    `**bold**`. So `ownType` says "this came from a note" and the paste is
    plain, which carries the Markdown exactly. It also crosses Universal
    Clipboard to another device running the app.
- **HTML, checked through the importer** (`RichClipboardTests.html`, Safari-like
  markup run through `NSAttributedString`'s HTML import, 19 Oct): `<b>`, `<i>`,
  `<a>`, a coloured `<span>`, `<del>`, an `<h1>` (bold at twice the body, written
  `<span style="font-size:2em">**Title**</span>`), `<code>` among words and a
  `<pre>` block all come through as the rules above say. Black text and the link
  blue are the source's and the app's, and don't appear. Not a pasteboard with
  real Safari content on it.
- **Tests** (`RichPasteTests`, `RichClipboardTests`: 40): the conversion as
  tables, a seeded property test (3,000 random pastes full of markers: the
  lines are kept, and each comes out as its own text or reads back as it), the
  adapter's reading of fonts, strikes, links and colours, and the editor with a
  real text view: a paste is one undo step, replaces the selection, keeps a
  colour, a size and a link, stands aside for code, locked notes and its own
  copies, and clears the typing style; a copy has the Markdown, an RTF without
  markers whose weights, sizes, colours and strikes read back, a selection
  starting inside a span, code without fences, list markers, a cut, and nothing
  where nothing can be seen.
- **Mutation-checked** (19 Oct; each fails the tests named when broken): twenty-one
  mutations, each one rule broken in turn and the two suites run (xcodebuild
  hangs after the tests finish, so the run killed it once "Test run with" was in
  the log); none survived. Default colours kept (`colours`); a dash or star with
  no tab before it a list marker (`dashes`); no list markers at all (five tests);
  all-code lines styled (`code`, `codeLines`); a list marker mid-line
  (`listMidLine`, `lists`); no 4% tolerance (`sizeTolerance`); the body taken as
  the largest size (four tests); a note's own copy read back from RTF
  (`ownCopyIsLeftAlone`); any link address opening (`linksThatDontOpen`); no-break
  spaces and attachment placeholders kept (`oddCharacters`, which was written
  because planning the mutations showed nothing tested them); code never "touched"
  (`codeStaysPlain`, `unclosedBlock`); a locked note pasted (`locked`); the typing
  style not cleared (`typingStyle`); the system font in the RTF (`copiesBoth`'s
  font-name check, added for the same reason); fences copied (`code`); list
  markers never copied (`listItems`); the selection ignored when picking glyphs
  (`cut`, `selectionInsideASpan`, `onlyMarkers`); `cut` and `copy` adding no RTF
  and no `ownType` (`cut`, `copiesBoth`, `ownCopyIsLeftAlone` and others).
- **Whole suite, 19 Oct:** 1,411 tests, and the only failures are the 8 tests /
  11 issues of "Code keys and indentation in the editor" that "Settings, toasts,
  polish" records as failing on unmodified `origin/main` on this Mac. The macOS
  app builds.
- **Not checked:** anything with another app. The pasteboards in the tests hold
  RTF written by the tests, never what Safari, Pages, Notes, Mail, Word or Google
  Docs put there: HTML in particular (its import runs on the main thread and the
  probe above pasted nothing from it), the "Allow Paste" prompt for pasting from
  another app (a paste from the edit menu or ⌘V is the exempt kind, and this
  runs inside it, but it hasn't been seen), the RTF opened in Pages or Mail
  (fonts, sizes, colours, list indents), Universal Clipboard, pasting a page of
  several thousand lines, the iPhone layout, the Pencil's squeeze, and the
  macOS app (the pure part compiles there; the text view is UIKit). Not built:
  Paste and Match Style, tables, images, and a block quote or rule.
- **Underline and highlight** (19 Oct, after phase 6 merged; the branch was
  rebased onto it). Paste reads `.underlineStyle` and `.backgroundColor`: an
  underline on a link is the browser's and not written; a background is the
  nearest of the six highlights by hue within 45 degrees, and white or a grey
  (the page's own) is none (`RichPaste.highlight(forBackground:)`). Copy writes
  both, the highlight as its colour looks over a white page, since RTF has no
  translucency. Mutation-checked: underline dropped from paste and the
  highlight dropped from copy each fail their test. A quote and a rule are not
  carried either way.
