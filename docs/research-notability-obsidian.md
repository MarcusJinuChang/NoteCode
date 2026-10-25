# Notability and Obsidian deep dive

Roadmap step 3. Researched 16 Oct 2026, about an hour, desk research only: no
code changed, nothing committed. Feeds step 10's format decision and the
question of what else belongs before the November submission.

**How far to trust it.** Vendor pages (Ginger Labs' support site, Obsidian's
changelog and help) were read through a fetch tool that summarises. The claims
the recommendations hang on were re-checked against the raw source:

- Obsidian 1.14's highlight colours: read from the raw changelog HTML.
- How GitHub renders each colour, size and highlight syntax: **run on
  16 Oct** through GitHub's own `POST /markdown` endpoint (mode `gfm`).
- Code font advance (0.6182 em) and the columns table: measured with AppKit's
  `NSFont.monospacedSystemFont` on the Mac. The iPad should match; not checked.
- Contrast ratios: computed.

I did not use either app. Section 5 lists what is unverified and a 15-minute
hands-on check that closes most of it.

## Summary

1. **Biggest gaps**, by value to a CS student: PDF import and annotation,
   handwriting search, audio synced to notes, then (smaller) tables and block
   quotes, a page jump, Spotlight and a New Note shortcut. Almost all are
   post-submission work. The exception is **handwriting search**: iOS 27 now
   ships `PKStrokeRecognizer` (on-device recognition, search with bounds,
   indexable text), which turns a big feature into a spike. Because it may
   store a field, it has to be decided before step 13 freezes the model.
2. **Colour: `<span style="color:#RRGGBB">…</span>`**, parsed as a one-level
   wrapper around the existing inline spans. It is the only convention that
   Obsidian renders with no plugin *and* that degrades to clean plain text on
   GitHub (tested). **Size** is the same span with `font-size:Nem`, in a few
   fixed steps, behind the ink prompt that text size already has. Highlight, if
   wanted, is Obsidian's new `==🟡text==`. Colour moves no lines; size does.
3. **More room for code:** the measured problem is columns. At the default
   17pt, portrait fits **63** monospaced columns and landscape 86, so an
   80-column line wraps in portrait at *every* text size. Recommend code at 85%
   of body (GitHub's ratio) plus a draw-only wrap mark, now, while changing
   layout is free. Do **not** build sideways scrolling or a wrap toggle: both
   put hidden scroll state between the words and the ink.
4. **Roadmap:** split step 10 into colour and code room, then size; add a
   handwriting-search spike before step 13; move PDF notes to the head of the
   post-submission list. Section 4.

---

## 1. What a CS student would miss

### 1.1 Where the two apps are

**Notability** (Ginger Labs), version 16.13 is the newest on its
[release list](https://support.gingerlabs.com/hc/en-us/articles/9414165465882-Latest-iOS-App-Updates);
dated entries run to 16.9.1 in Aug 2026
([App Update History](https://support.gingerlabs.com/hc/en-us/articles/5293937538586-App-Update-History)).

- **Notability Cloud**, its own sync and file format on iOS, Android, Mac and
  web (announced Aug 2025, 15.0.0). It is free and enables live collaboration
  and shared libraries
  ([FAQ](https://support.gingerlabs.com/hc/en-us/articles/9598417028378-Notability-Cloud-FAQ)).
- **Typed notes are rich text.** The Cloud tier added quote blocks (`> ` then a
  space) and **code blocks** (16.8.1, Aug 2026; three backticks then a space).
  Both are Cloud-only
  ([Code Blocks](https://support.gingerlabs.com/hc/en-us/articles/11089433943962-Code-Blocks),
  [Text and Text Boxes](https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes)).
- **AI ("Learn")**, since 15.0.0: quizzes, flashcards (spaced repetition from
  16.9.1), chat across all notes, Finish My Notes from recording transcripts.
  Wikipedia says it runs on Claude and Gemini
  ([Wikipedia](https://en.wikipedia.org/wiki/Notability_(application))).
- **Pricing:** tiers plus a one-time "Classic" purchase that came back in
  16.6.1 (Jul 2026). Context for roadmap step 2.
- An Android app launched around Mar 2026 (Wikipedia, citing a Reddit post).

**Obsidian** 1.14 (desktop **5 Oct 2026**), mobile 1.14.4 the same day
([desktop](https://obsidian.md/changelog/2026-10-05-desktop-v1.14.4/),
[mobile](https://obsidian.md/changelog/2026-10-05-mobile-v1.14.4/)).

- **Highlight colours** (below), a kanban view in Bases, and opening single
  Markdown files from outside a vault.
- **Mobile:** Quick Capture (Lock Screen, Control Center, widgets, Shortcuts),
  system text scaling (Dynamic Type), iPad Split View and Stage Manager sizing
  fixes. 1.12 (Feb) added a CLI.
- **Core plugins** include Audio recorder (records into a note, no timeline
  sync), Canvas, Backlinks, Graph, Slides, File recovery, Templates, Daily
  notes, Properties, Footnotes
  ([Core plugins](https://obsidian.md/help/plugins)).
- **Markdown beyond NoteCode's:** tables, callouts (`> [!note]`), Mermaid,
  MathJax, embeds
  ([Advanced syntax](https://obsidian.md/help/advanced-syntax)).
- **No Pencil in the core app.** Ink exists only as community plugins
  (InkedMark, Blackboard, Etch, FineNotes, Apple Pencil for Obsidian), and a
  forum request asks for plugin access to Pencil double-tap
  ([search results](https://community.obsidian.md/plugins/inkedmark),
  [forum](https://forum.obsidian.md/t/expose-apple-pencil-double-tap-native-pencil-interactions-to-mobile-plugins/118705)).
  The pairing of Markdown text and ink on one page is NoteCode's own ground.

NoteCode's document model today: paragraph, heading, list item and code block,
with flat inline spans (`DocumentNode.swift`, `InlineParser.swift`). There is
no block quote, table, callout, footnote or note-to-note link.

### 1.2 Ranked misses

Value is for a CS student taking lecture and practice notes on an iPad. Cost is
to NoteCode as it stands.

| # | Feature | Notability | Obsidian | Value | Cost | When |
|---|---|---|---|---|---|---|
| 1 | **PDF and slide import, annotate** | Imports PDF, PowerPoint, spreadsheets; hold-to-snap text highlighting; PDF outlines (16.1.3); side margins on import (16.9) | Embeds only; annotation by plugins (Annotator, Etch) | Very high: slides and problem sets arrive as PDFs | High. A fixed-page note kind, unlike the reflowing text note. Ink on a PDF never reflows, so it is *easier* on ink than text | After submission, first |
| 2 | **Handwriting search** | Search over handwriting (plan-gated; the free tier lacks it per [Paperlike](https://paperlike.com/blogs/paperlikers-insights/app-review-goodnotes-vs-notability)) | Plugins only | High: diagrams and formulas are handwritten, and "Ink isn't searched" | **Now low**: `PKStrokeRecognizer`, iOS 27 | **Spike before November** |
| 3 | **Audio synced to notes** | Note Replay: tap writing to jump, annotate during playback ([article](https://support.gingerlabs.com/hc/en-us/articles/206060617-Recording-and-Playing-Audio)); iOS/Android only, plan tier unclear | Audio recorder core plugin, no sync | High for lectures | High: microphone permission, a timeline on ink and edits, storage | With step 18 (AI), where a transcript feeds summaries |
| 4 | **Cross-device access** | Cloud on iOS/Android/Mac/web | Plain files + Sync | High | Already step 14 (+ iPhone step 11) | As planned |
| 5 | **Block quotes** | 16.8.1, Cloud | Yes, plus callouts | Low-medium | Small: a block kind, a bar in a fragment, a hidden `> ` | Optional with step 10 |
| 6 | **Tables** | Not found | Yes | Medium: truth tables, Big-O comparisons | High: hidden pipes plus proportional text cannot align columns; needs rendered blocks | With LaTeX (16) if at all |
| 7 | **Page jump / thumbnails** | Page Manager and Navigator, jump shortcuts (16.2) | Outline only | Medium | Small: tap the "2 / 5" badge for a picker | Anytime |
| 8 | **Spotlight and a New Note shortcut** | Widgets, Home tab | Quick Capture (1.14 mobile) | Medium: a note opened before class starts | Small (App Intents, `CSSearchableItem`); recognised ink text feeds Spotlight | Near step 12 |
| 9 | **More code languages** | 27 including Bash/Shell, C#, Kotlin, Swift, TypeScript, Haskell, OCaml, Racket | via highlight | Medium-low | Tiny as Copy-only, as SQL already is | With step 10's code work |
| 10 | **Paper (grid, dots, ruled)** | Rule, Grid, Dot, one style per note | n/a | Medium for diagrams | Step 15; per-note is the right scope | After submission |
| 11 | **Version history** | 7 to 90 days by plan; Cloud | File recovery snapshots | Medium | Medium; sync (14) comes first | After step 14 |
| 12 | **Note links and backlinks** | n/a | `[[…]]`, backlinks, graph | Medium-low | Medium: resolve, rename, index | Later |
| 13 | **Flashcards, quizzes, AI chat** | Learn | Plugins | Medium | Step 18; Notability has shipped it since Aug 2025 | March |
| 14 | **Drawing aids** (ruler, shape snap, tape, mirror ink) | Yes | n/a | Medium for graphs and trees | Unknown. PaperKit may already have some | Verify in the app first |
| 15 | **Mermaid** | n/a | Yes | Medium | High (a web view) | Not planned |
| 16 | Live collaboration, comments | Cloud | Sync/Publish | Low for solo notes | Needs a server | "Not in the order" |
| 17 | Presentation, laser, slides, canvas, graph, Bases | Laser pointer | Slides, Canvas, Graph, Bases | Low | n/a | Skip |

Rows 1 to 3 are where Notability is ahead. Row 2's cost has fallen sharply
and row 9 is nearly free. Everything else is either already in the roadmap or
low value for this use.

### 1.3 Handwriting search is now cheap

WWDC26 "Read between the strokes with PencilKit"
([session](https://developer.apple.com/videos/play/wwdc2026/203/)) adds, in
iOS 27, an on-device `PKStrokeRecognizer` actor:

- `recognizedText()` for a drawing or a subset of stroke IDs.
- `indexableContent`, one string of all candidates, "suits Spotlight", with a
  `recognizerVersion` to store beside it and re-index on change.
- `search(_:)`, returning `bounds` for where the word likely is, which "works
  with `UIFindInteraction`".
- 29 languages, offline, shipped with the OS. The simulator handles only
  Latin-script languages.
- Strokes convert to and from Bézier paths, and `PKStroke` is now
  `Identifiable`.

NoteCode already has a Find interaction, a note search and a Spotlight-shaped
hole. Two things need a spike (about a day):

1. Can the stored ink, which `InkPages` cuts into per-page pieces, be handed
   to the recognizer as a `PKDrawing`? A word crossing a page break may be
   recognised as two halves. A crossing is rare, but check it.
2. **Compute at search time, or store `indexableContent`?** Computing per note
   is too slow for the list's search across all notes. Storing needs a field
   (text and `recognizerVersion`), and **a new field has to land before
   step 13**. Keeping the cache outside the model (a file in Caches, like
   thumbnails) avoids the change but loses the index on reinstall and cannot
   follow a note to another device.

**Spike result (17 Oct, branch `claude/inspiring-bassi-c99728`,
`docs/spike-handwriting-search.md` there; simulator, synthetic strokes only):**

- **Feasible, with a rebuild.** `PKDrawing(strokes:)` crashes on any stroke read
  from a `PaperMarkup`; rebuilding each stroke with the iOS 27 initializer that
  takes an `id` works. Fed as stored, 11 of 12 words crossing a page break were
  lost; fed rebuilt (seamless coordinates, the piece that keeps the stroke's id,
  mask off), all 15 test words read as in uncut ink.
- **Fast enough off the main actor:** about 1.7 ms a stroke (1,000 strokes 1.8 s,
  5,000 strokes 8.5 s). Query only after two answers agree: `indexableContent`
  was sometimes nil right after `updateDrawing`, and nil also means "nothing
  recognised".
- **Find works on screen:** the ink match drew in orange over the handwriting and
  the page scrolled to it. Mixed text-and-ink queries, compressed/print layout
  and zoom are unit-tested only.
- **Recommendation stands: store `Page.inkText` and `Page.inkTextVersion` before
  step 13.** Guard: unmask only a mask that is a single page-cut rectangle, or
  erased ink can come back into the index.
- **Open, for a human:** PaperKit's real pixel eraser could not be driven, so
  whether it edits masks in place is unknown. `InkCapture` notices a changed
  stroke by its bounds, so a hole carved in a stroke's middle may not be saved,
  which would bring erased ink back on reopen with or without search. A
  five-minute check is in the spike doc. Real handwriting, the Pencil and iPad
  timings are untried.

### 1.4 Recommendation

- **Before November:** (a) the handwriting-search spike, with its store-or-compute
  answer in hand before step 13; (b) copy-only languages (Bash/Shell, TypeScript,
  C#, Kotlin, Swift, Haskell) when step 10 touches code blocks, since each is a
  `CodeLanguage` case with `canRun` false; (c) the badge-to-page-picker, if
  there is a spare afternoon. None displaces a numbered step; (a) is the only
  one with a deadline, because of step 13.
- **Not before November:** PDF notes, audio, tables and note links. Each is
  larger than the gap between now and the submission, and none is needed to
  pass review.
- **Strategic note:** PDF import is the one feature that would change who the
  app is for. Slides and problem sets are how a course hands out work. Decide
  after TestFlight 1 whether it goes ahead of paper (15) and LaTeX (16).

---

## 2. Text colour and size anywhere

### 2.1 How Obsidian stores them

The core app has **no text colour and no per-run size**. Its help lists
highlight, bold, italic, strikethrough, inline code and comments, with
"colored text, underline, and font size" outside the page
([Basic formatting syntax](https://obsidian.md/help/syntax)). 1.14 added
"Increase/Decrease font size" commands, and those are app-wide.

What exists:

| Convention | What it writes | Renders with no plugin? | Evidence of use |
|---|---|---|---|
| **1.14 highlight colours** (native) | `==🔴text==`, also 🟠 🟡 🟢 🔵 🟣; `==` offers a colour list | Yes in desktop 1.14. The mobile 1.14.4 notes do not mention it. Older versions show the emoji inside a plain highlight | [Changelog, 5 Oct 2026](https://obsidian.md/changelog/2026-10-05-desktop-v1.14.4/); 11 days old |
| **Inline HTML span** | `<span style="color:#e0313a; font-size:1.25em">word</span>` | **Yes**, desktop and mobile | The standard forum answer ([thread](https://forum.obsidian.md/t/colored-text-span-or-font/73177)). HTML Font Toolbar writes exactly this, with colour and `em` sizes from Small to XXL (≈3k downloads, desktop only, Obsidian 1.12+) |
| **`<mark>` with a style** | `<mark style="background:…">` | Yes | **Highlightr, 737,656 downloads**, last updated about 4 years ago ([stats](https://www.obsidianstats.com/plugins/highlightr-plugin)) |
| **Fast Text Color** | `~={id}text=~` (id looked up in a theme) | **No**: the delimiters show | ≈92k downloads, desktop and mobile ([listing](https://community.obsidian.md/plugins/fast-text-color)) |
| **Colors** (a fork) | `~={#ff8800}text=~` | No | 1,010 downloads, needs 1.13 ([stats](https://www.obsidianstats.com/plugins/colors)) |
| **Style Obmd** | `=={r}text==` and `**{b}text**` | The highlight or bold stays; the `{r}` token is not said to hide (inferred: it shows) | 578 downloads |
| **Hilo** | `=={slug}text==` | Same (inferred) | listing says it rewrites old `<mark style>` highlights |
| **Editing Toolbar** | font and background colour commands | Markup not confirmed | ≈1.4M downloads (listing) |
| **Extended Markdown Syntax** | underline, sup/sub, spoiler, custom highlight colours without HTML | No | listing |

The pattern: the most-installed highlight plugin writes an HTML tag; the
plugins that invent delimiters are small, and their notes show stray
punctuation without the plugin. Obsidian's own answer to colour, 1.14, is a
new `==` form that is **highlight only** (a background), written as an emoji.

Mixing Markdown and a span is unreliable in Obsidian's Live Preview. A forum
thread ([52069](https://forum.obsidian.md/t/markdown-code-for-color-and-bold-not-working-together/52069))
shows `**<span…>x</span>**` losing the bold and `<span…>**x**</span>` showing
the asterisks. A later reply says both worked after an OS update, with no
cause given. I did not test 1.14.

### 2.2 How Notability does it

- **Colour, size, font:** the typing toolbar above the keyboard has font,
  style, colour and size controls. Up to three favourite styles (font, size,
  emphasis) save as presets with a heart. Custom colours: up to eight in the
  toolbar, by wheel or **hex**. Defaults live in Settings › Typing. Fonts
  installed on the iPad appear in its list
  ([Text and Text Boxes](https://support.gingerlabs.com/hc/en-us/articles/206059387-Text-and-Text-Boxes),
  [Custom Colors](https://support.gingerlabs.com/hc/en-us/articles/360019098351-Custom-Colors),
  [Settings](https://support.gingerlabs.com/hc/en-us/articles/206061497-Settings)).
- **Mixed sizes on one line** needed a rendering fix in 16.8.1. A sign that
  line height with mixed sizes is a known hazard in this kind of app.
- **Highlight:** the Smart Highlighter snaps to typed or PDF text on a
  long-press, then you drag to extend. It has its own colours (add up to eight
  more). The page says highlights "can be edited, styled, and erased like
  regular ink", which implies ink strokes laid over the text
  ([Highlighter](https://support.gingerlabs.com/hc/en-us/articles/4968218861978-Highlighter)).
  I could not confirm whether they move with the text on reflow.
- **Storage is proprietary rich text.** No Markdown export is documented for
  typed notes; Markdown shortcuts exist only for quote and code blocks.

Not found in Notability's help: a statement of bold/italic/underline controls.
They are probably the "emphasis" menu.

### 2.3 What reads cleanly elsewhere

Tested against GitHub's renderer on 16 Oct 2026 (`POST api.github.com/markdown`,
mode `gfm`; unauthenticated, one `curl` per input). It returns sanitised HTML, so
this shows what survives, not how a browser paints it.

| Input | GitHub's output | Verdict |
|---|---|---|
| `<span style="color:#D63A2F">x</span>` | `<span>x</span>`, style stripped | **Clean**: plain text, no stray characters |
| `<span style="font-size:1.5em">x</span>` | style stripped | Clean |
| `<span class="red">x</span>` | class stripped | Clean, but only the text survives |
| `<font color="…">x</font>` | tag removed, text kept | Clean |
| `<big>` / `<small>` / `<u>` | tags removed, text kept | Clean, but obsolete HTML |
| `<mark>x</mark>` | kept | A highlight (the tag survives; I did not look at its colour) |
| `**x**` inside a span, or a span inside `**` | both nest correctly | Fine in GitHub |
| `==x==`, `==🔴x==` | **literal text** | Not clean: `==🔴x==` shows |
| `$\color{red}{x}$` | handed to GitHub's math renderer | Colours in a browser, but it uses LaTeX's `$`, which step 16 needs |

So `==` highlights read well only in Obsidian (and Bear, iA Writer, and
Typora/Pandoc when enabled; GitHub and GitLab ignore it
([macmdviewer](https://macmdviewer.com/blog/markdown-highlight-text))).
Spans with a `style` are the only form that renders in Obsidian **and** leaves
a readable note on GitHub, which matters for a CS student who pushes notes to
a course repo.

### 2.4 NoteCode's constraints, from the code and AGENTS.md

- **Markers are hidden by a layout swap** (`MarkdownLayout`): each marker
  character becomes U+2060, same length. A marker is any contiguous run the
  parser reports as a span's leading or trailing range, so a long variable tag
  is as hideable as `**`. A link's `](url)` already is one.
- **Parsing is per line** and the inline list is **flat and contiguous**.
  `InlineParser` says: "Spans don't nest", and calls HTML "a famous tar pit".
  So a coloured bold word is *impossible today*: colour needs one level of
  nesting, which is the main engineering cost.
- **Colour moves no lines.** It sets a foreground attribute; the tag's
  characters lay out at zero width. That is the property step 10 wants first.
  Verify at a wrap boundary, like `MarkdownLayoutTests`.
- **Size does move lines**, so every size change re-wraps and shifts ink until
  step 17. Fonts must come from `NoteTypography.font(for:)`: a plain
  `systemFont(ofSize:)` has no leading and made every line 1.7pt shorter (the
  Phase 9 finding).
- **Search and word counts see the tag text.** `NoteSearch` runs over the raw
  text, so typing "span" or "style" would match every coloured note. Note info
  goes through the parser, so it should be fine.
- **A colour has to look right in both appearances.** The pen palette's stored
  light values, used as text, give: Orange 2.5:1, Yellow 2.0:1, Green 3.2:1 on
  white; Purple 3.2:1 and Ink 1.0:1 on black. No single hex is readable on
  both a white and a black page, so NoteCode must adapt per appearance, as
  `AccentPalette.textHex` already does (4.5:1, "tested for eleven colours"), and
  accept a fixed hex in other readers.
- **CS prose is full of the characters these syntaxes use.** `vector<int>`,
  `a==b`, `x < y`, `$HOME`, `~/bin`. A plain `==x==` form would highlight
  `b and c` in `a==b and c==d` written outside backticks. The emoji form
  cannot. A span form that accepts only its exact tag shape cannot collide.

### 2.5 Options considered

| Option | For | Against |
|---|---|---|
| **A. `<span style="color:#RRGGBB">`** | Renders in Obsidian with no plugin; clean on GitHub; no prose collisions; same family as HTML Font Toolbar | Long tag (~30 chars, hidden anyway); needs one level of nesting; fixed hex in a dark theme |
| B. Plugin delimiters (`~={#hex}x=~`) | Short | Stray punctuation everywhere without a plugin; Obsidian-plugin-specific |
| C. `<font color>` | Clean on GitHub | Obsolete; no size |
| D. `$\color{red}{x}$` | Renders on GitHub and Obsidian | Collides with step 16's `$`; italic math font |
| E. Colour stored outside the text (a model side table) | No tag text | Breaks "Markdown export equals content" and drifts on edits; reverses the Markdown-in-the-note decision |
| F. Rich text | Easy colour | Rebuilds styler, formatting, lists, markers, search, export |

### 2.6 Recommendation

**Colour: option A.**

- Wire format: `<span style="color:#RRGGBB">text</span>`, exactly this shape.
  Written uppercase, read case-insensitively. Any other `<span …>` (a class, a
  named colour, extra properties) is **plain visible text**, so imported HTML is
  never half-hidden.
- **Parse as a wrapper pass over the line, before `InlineParser`**: find the tag
  pair, run the existing parser on the interior. This allows exactly one level
  (colour outside bold, italic, code, strike, link). A fit with the flat list,
  not prototyped: emit the open and close tags as marker-only inline nodes and
  tag the nodes between them with the style. `layouts(for:)`'s
  leading/trailing-marker model then needs no change.
- **One span per line.** A selection over several lines gets one span each; a
  list item's `- ` or a heading's `# ` stays outside; code lines are skipped.
- **A text palette of about six hues** at mid-tone hexes, drawn per appearance
  by the `AccentPalette.textHex` method. Candidates, contrast on white / on
  black: Red `#E5484D` 3.9 / 5.4, Orange `#E5750A` 3.1 / 6.9, Amber `#B88700`
  3.2 / 6.5, Green `#2F9E44` 3.4 / 6.1, Blue `#3B82F6` 3.7 / 5.7, Purple
  `#9061F9` 4.0 / 5.3. "Default" removes the span. Don't reuse the pen's inks.
- **Also touch:** the hotbar's colour chip (caret state), `NoteSearch`
  (skip tag runs), thumbnails and the PDF (same typography and tag hiding).
- **Don't** reuse `$\color`, plugin delimiters or rich text.

**Highlight (optional, after colour): `==🟡text==`**, emoji required. Short
(four units plus two), Obsidian-native in 1.14, immune to the `a==b` problem,
and avoids the dark-theme trap of a fixed hex background behind theme-coloured
text, which `<mark style="background:#…">` has in Obsidian's dark themes. Known
cost: GitHub shows the `==🟡` literally. If GitHub matters more than Obsidian,
use `<mark style="background:rgba(…,.4)">` instead, which survives GitHub as a
plain mark and is translucent enough for both themes.

**Size: the same span, `font-size:Nem`**, written as one tag beside the colour
(`style="color:#E5484D;font-size:1.25em"`, the order HTML Font Toolbar uses) so
colour and size never nest.

- A fixed vocabulary of three sizes (about 0.85, 1.25 and 1.5em). NoteCode
  snaps to the system font of the nearest Dynamic Type category through
  `NoteTypography.font(for:)`, so the leading is the system's.
- It re-wraps, so it takes the text-size stepper's ink rule: a note with ink
  asks once each time it is opened.
- **Sequence: 10a colour, then 10b size.** Size is the part that can slip.
  The Obsidian downloads point the same way: colour and highlight tools reach
  92k to 737k, the one plugin that writes `em` sizes about 3k. Headings,
  already there, cover most of "bigger".
- Rejected for size: `<big>`/`<small>` (stripped on GitHub, obsolete); custom
  delimiters; a per-note-only size, which is today's stepper.

---

## 3. More room for code blocks

"More room for code blocks" is undefined. The readings, and the evidence for
which is real:

- **Columns:** more characters per line. Measured below.
- **Padding:** the panel starts 5pt inside the container and the first glyph
  touches its edge (AGENTS.md › Code-block fences). This is a plausible
  meaning, and it competes with columns.
- **Height or spacing** around blocks.
- **A bigger surface** for reading or editing one block.

Ask Marcus which. The recommendation below assumes columns and padding.

### 3.1 What each app does

| App | Width | Long lines | Code size | Evidence |
|---|---|---|---|---|
| **Notability** | Not documented | **Not documented** (nothing found in forums either) | Not documented | [Code Blocks](https://support.gingerlabs.com/hc/en-us/articles/11089433943962-Code-Blocks) covers languages (27), `` ``` `` + space, last language remembered, "keeps spacing and font intact". Cloud only |
| **Obsidian** | The note column | **Reported to wrap** in Live Preview and Reading view, with no setting; CSS snippets only (forum posts from 2022 to 2023, not re-checked on 1.14). `--code-white-space` and `--code-size` exist ([variables](https://docs.obsidian.md/Reference/CSS+variables/Editor/Code)) but the docs give no defaults | Not verified | Feature request ([33718](https://forum.obsidian.md/t/live-preview-better-treatment-of-code-blocks-code-wrap-horizontal-scroll-and-smart-indent/33718), 2022): nobody argued for keeping wrapping, and no developer replied. Live Preview is a div per line, which is why sideways scroll is hard. Plugin and forum reports say a copy button shows in Reading view, and in Live Preview only while the caret is outside the block |
| **GitHub** | Page column | **Scrolls sideways**: `pre { overflow:auto }`, `pre > code { white-space: pre }` | **85% of body** (`pre { font-size: 85% }`) | [github-markdown-css](https://github.com/sindresorhus/github-markdown-css), read on 16 Oct |
| **Notion** | Page column | Scrolls; **Wrap code** is a per-block toggle | n/a | [Code blocks](https://www.notion.com/help/code-blocks) |
| **NoteCode** | 672pt portrait, 912pt landscape | **Wraps** at the page text width | **100% of body** (17pt default) | `NoteTypography.code`: "monospaced at body's size, so a line of code is as tall as a line of prose" |

None of these is a fixed-page document with ink over it, and Notability's
answer is unknown. Obsidian's users ask for scrolling, and GitHub and Notion
scroll. NoteCode is the only one at 100% of body size.

### 3.2 NoteCode's numbers

SF Mono advances 0.6182 em, so:

| Code size | Portrait (672pt) | Landscape (912pt) | Portrait, 0.5in margins (720pt) |
|---|---|---|---|
| 17pt (today) | **63** columns | 86 | 68 |
| 15pt | 72 | 98 | 77 |
| 14.45pt (85% of 17) | 75 | 102 | n/a |
| 14pt | 77 | 105 | 83 |

An 80-column line (the usual C++ and Python limit, and CS133 style guides)
wraps in portrait at every code size the text ladder reaches. With today's
page it fits only in landscape, and only at 17pt and below.

### 3.3 The rules each option must meet

From AGENTS.md › Page geometry and Pages: line breaks are a function of the
page width only, so the same note wraps the same on every device and the
ink stays on its words; ink is stored in page coordinates; and "anything that
re-wraps text moves ink off its words". Also decided 15 Oct: **no old notes are
kept working until the release**, so a layout change costs nothing for the
store but TestFlight testers' notes shift. After the release every change costs
every user their ink.

| Option | More room? | Cost against the rules |
|---|---|---|
| **1. Code at 85% of body** | +12 columns portrait, +16 landscape | Passes: still a function of page width and the note's size, no new stored field. Changes the wrap of every existing code block once. Changes the "code line as tall as prose" rule, so pagination shifts and any test that pins code line height changes. **Free now, expensive after release** |
| **2. Panel padding** | Costs about 1 column per 10pt | Passes (a constant). The same one-off re-wrap. Set it together with option 1 |
| **3. Hanging indent plus a margin wrap mark** for continuation lines | None, but 63 columns becomes legible | Hanging indent re-wraps (a constant, once); the mark is draw-only in the margin, like the line numbers. Fixes the real complaint with wrapping: a continuation reads as a new line |
| **4. Narrower page margins** (0.75 to 0.5in) | +5 columns portrait | Passes, but touches **every** note's wrap and the printed page. A one-line constant; not recommended for code alone |
| **5. Landscape pages for code-heavy notes** | 86 columns | Already built. Cost: prose lines get long (130+ characters). Could be the Lab and Problem templates' default |
| **6. Bleed the code panel and text into the side margins** | About +9 columns at 17pt if a block may use 48pt of each 72pt margin | Passes only as a fixed amount of the page, but the text container is the page's text width. This means a full-width container with indents on all prose, new exclusion paths and caret/selection checks. Highest risk to the layout everything else leans on |
| **7. Sideways scroll inside a block** | Unlimited | **Fails.** A hidden per-block scroll offset moves the words under the ink every time it changes, which is worse than a reflow because it is continuous and invisible to the stored ink. TextKit also has no per-paragraph scrolling, so selection, caret, Find and the action bars all have to learn it |
| **8. A wrap toggle** (Notion) | Unlimited | "Off" is option 7 |
| **9. Expand a block** into a sheet at full width, scrolling there | Unlimited for reading and editing | Passes: not on the page. Moderate work (a second text view over the block's range, written back with one undo step, the code-keys row reused). A fallback if TestFlight shows complaints |

### 3.4 Recommendation

1. **Before the release, in step 10:** options **1, 2 and 3** together, so the
   one-off re-wrap happens once. Derive code size from the note's size (a
   ratio, not a stored setting), so no field is added before step 13; if a
   per-note override is ever wanted it must also land before step 13. Update
   the tests that pin code geometry.
2. **Make Lab and Problem templates landscape** (option 5), if the New Notes
   setting allows a template to choose.
3. **Reject 7 and 8** on the ink contract. If readers still want unwrapped
   code, build 9.
4. **Ask Marcus** whether "room" meant columns or padding. If it meant
   something else (say, space around blocks), only option 2 carries over.

---

## 4. Roadmap changes

Against `docs/ROADMAP.md › Plan`.

1. **Step 10 becomes three:**
   - **10a Colour**, as the span, plus the **code room** changes (section 3.4)
     and copy-only languages. Both change stored text or layout, which is why
     they sit before the release.
   - **10b Size**, same span, behind the ink prompt. The first to slip.
   - **10c Highlight** `==🟡`, optional. Add block quotes here if wanted: the
     same parser and fragment machinery.
2. **New: handwriting search spike** (about a day) between 10 and 13. Its answer
   (store recognised text or compute it) decides whether the model gains a
   field. **Step 13 waits for it.**
3. **Step 13 must follow 10 and the spike.** Any new stored field lands before
   it. So far that is at most a recognised-text field and `recognizerVersion`.
4. **After the submission,** put **PDF notes** at the head of the list, ahead of
   paper (15) and LaTeX (16), and decide it after TestFlight 1. It is a second
   note kind, like the infinite-canvas question in AGENTS.md › Open questions.
5. **Audio recording** pairs with step 18: a lecture transcript is the input a
   summary needs. Notability ships both already, so March's AI is catch-up
   unless it is code-aware and on-device.
6. **Step 12** (list foot) can take Spotlight and a New Note shortcut.
7. **Step 14** has a question this research raises: Obsidian's model is plain
   files, NoteCode's is a SwiftData store. The sync decision decides whether a
   NoteCode vault could ever open in Obsidian directly.
8. **Step 16 (LaTeX)** keeps `$` to itself: GitHub and Obsidian both render
   `$…$`, which is another reason colour is not `$\color`.
9. **Step 2 context:** Notability charges (tiers and a one-time Classic purchase
   again since Jul 2026). Nothing here changes the tip-jar proposal.

Nothing in this research argues for displacing step 11 (iPhone and Duo) or
step 13.

## 5. Not verified, and a 15-minute check

Not verified:

- **Notability:** code block wrap, scroll and font size; typed-text bold, italic
  and underline; whether highlights move with text; whether any Markdown is
  exported.
- **Obsidian:** how 1.14 renders a span mixed with bold in Live Preview; whether
  the iPad app has the highlight colours yet; the default code `white-space`.
- **GitHub:** the colours of `<mark>` and `$\color`.
- **NoteCode:** whether PaperKit already has a ruler or shape snap; and, from
  the handwriting spike, real handwriting, the Pencil and iPad timings.

A hands-on pass, with both apps free to try:

1. **Obsidian 1.14.4 on the iPad:** paste these lines and look in Live Preview
   and Reading view. `<span style="color:#E5484D">red</span>`,
   `<span style="color:#E5484D">**red bold**</span>`,
   `**<span style="color:#E5484D">bold red</span>**`,
   `<span style="font-size:1.5em">big</span>`, `==🟡yellow==`.
2. **Notability Cloud (free):** make a code block, type a 120-character line,
   note wrap or scroll and the size; pinch to zoom; try a colour and a size on a
   selected word; export the note and see what comes out.
3. **NoteCode:** check for a ruler and shape snap with the Pencil.

## Sources

Notability
- [Latest iOS App Updates](https://support.gingerlabs.com/hc/en-us/articles/9414165465882-Latest-iOS-App-Updates) · [App Update History](https://support.gingerlabs.com/hc/en-us/articles/5293937538586-App-Update-History)
- [Code Blocks](https://support.gingerlabs.com/hc/en-us/articles/11089433943962-Code-Blocks) · [Text and Text Boxes](https://support.gingerlabs.com/en-us/articles/16300260-text-and-text-boxes) · [Text and Text Boxes (older)](https://support.gingerlabs.com/hc/en-us/articles/206059387-Text-and-Text-Boxes)
- [Highlighter](https://support.gingerlabs.com/hc/en-us/articles/4968218861978-Highlighter) · [Custom Colors](https://support.gingerlabs.com/hc/en-us/articles/360019098351-Custom-Colors) · [Settings](https://support.gingerlabs.com/hc/en-us/articles/206061497-Settings)
- [Notability Cloud FAQ](https://support.gingerlabs.com/hc/en-us/articles/9598417028378-Notability-Cloud-FAQ) · [Getting Started](https://support.gingerlabs.com/en-us/articles/16300108-getting-started-with-notability) · [Recording and Playing Audio](https://support.gingerlabs.com/hc/en-us/articles/206060617-Recording-and-Playing-Audio) · [Compare plans](https://notability.com/pricing/compare)
- [Wikipedia](https://en.wikipedia.org/wiki/Notability_(application)) · [Paperlike review](https://paperlike.com/blogs/paperlikers-insights/app-review-goodnotes-vs-notability)

Obsidian
- [1.14 desktop changelog](https://obsidian.md/changelog/2026-10-05-desktop-v1.14.4/) · [1.14 mobile](https://obsidian.md/changelog/2026-10-05-mobile-v1.14.4/) · [Basic syntax](https://obsidian.md/help/syntax) · [Advanced syntax](https://obsidian.md/help/advanced-syntax) · [Core plugins](https://obsidian.md/help/plugins) · [Code CSS variables](https://docs.obsidian.md/Reference/CSS+variables/Editor/Code)
- Colour: [span or font](https://forum.obsidian.md/t/colored-text-span-or-font/73177) · [mixing bold and span](https://forum.obsidian.md/t/markdown-code-for-color-and-bold-not-working-together/52069) · [Fast Text Color](https://community.obsidian.md/plugins/fast-text-color) · [Colors](https://www.obsidianstats.com/plugins/colors) · [Style Obmd](https://community.obsidian.md/plugins/style-obmd) · [HTML Font Toolbar](https://community.obsidian.md/plugins/html-font-toolbar) · [Highlightr](https://www.obsidianstats.com/plugins/highlightr-plugin) · [Hilo](https://community.obsidian.md/plugins/hilo) · [Editing Toolbar](https://community.obsidian.md/plugins/editing-toolbar)
- Code: [code block wrapping](https://forum.obsidian.md/t/how-to-disable-line-wrapping-in-code-blocks/69900) · [feature request](https://forum.obsidian.md/t/live-preview-better-treatment-of-code-blocks-code-wrap-horizontal-scroll-and-smart-indent/33718)
- Pencil: [InkedMark](https://community.obsidian.md/plugins/inkedmark) · [Pencil double-tap request](https://forum.obsidian.md/t/expose-apple-pencil-double-tap-native-pencil-interactions-to-mobile-plugins/118705)

Other
- GitHub: [`POST /markdown`](https://docs.github.com/en/rest/markdown/markdown) (the test) · [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) · Notion [code blocks](https://www.notion.com/help/code-blocks) · [`==` support](https://macmdviewer.com/blog/markdown-highlight-text)
- Apple: WWDC26 [Read between the strokes with PencilKit](https://developer.apple.com/videos/play/wwdc2026/203/) · [Unwrap PaperKit](https://developer.apple.com/videos/play/wwdc2026/372/) · WWDC25 [Meet PaperKit](https://developer.apple.com/videos/play/wwdc2025/285)

NoteCode files read: `docs/ROADMAP.md`, `AGENTS.md`, `DocumentNode.swift`,
`InlineParser.swift`, `DocumentStyler.swift` (inline layout), `MarkdownLayout.swift`,
`NoteTypography.swift`, `PageLayout.swift`, `InkTool.swift` (pen palette).
