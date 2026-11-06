# F. Fixes

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. These change behaviour on purpose, so each
one:
- starts with a test that fails without the fix, and says so in the PR;
- updates its `features.md` row if the row's "how it works" changes.

## F1. Bugs from the device pass

Marcus walks `docs/ipad-test-checklist.md` on build 4 (0A) and lists what
goes wrong. Each bug is one session:

    Run /refactor-wp fix "<what goes wrong, where, and how to make it happen>"

**Do.** Reproduce it first, in a test if the bug can be reached from one,
otherwise with the debug launch options (AGENTS.md › Debug launch options).
Find the cause, not just the place it shows. Fix it, and confirm the test now
passes.

**Done when.** The test passes and fails without the fix. Marcus gets the
device line that checks it, in chat. If the bug only shows on the iPad (ink
latency, Pencil, drag and drop), say what was checked in the simulator and
what wasn't.

## F2. Settings › Autocorrect doesn't reach an open note

**Bug.** `DocumentTextView.makeUIView` calls
`coordinator.setRewritesProse(rewritesProse, in:)` (DocumentTextView.swift:106),
and `updateUIView` never does. So turning Autocorrect off from Settings while
a note is open (••• › Settings) probably changes nothing until the note is
reopened. Found by reading the code on 2 Nov; not yet seen on the iPad.

**Do.** Write the test first: host a `DocumentTextView`, change
`rewritesProse`, update it, and check the prose policy the text view ends up
with. Then apply the setting in `updateUIView`. `setRewritesProse` already
returns early when nothing changed. While there, check every other setting
`makeUIView` applies (`setRendersMarkdown`, `setTypography`,
`codeSettings.apply`, `markerDimming.apply`) for the same gap, and list each
one's answer in the PR. Fix only those with the same gap, each with its own
test.

**Done when.** The tests pass and fail without the fix. Device line for
Marcus: open a note, turn Autocorrect off in ••• › Settings, type a misspelt
word in prose. It stays as typed.

## F3. A note's text view is never freed (after F2: same file)

**Bug.** The Coordinator owns the code-block overlay, and the overlay's
`onRun` closure (DocumentTextView.swift:496–499) captures `self`, the
Coordinator, strongly (only `textView` is weak). If that holds, every note
opened keeps its Coordinator, overlay and whatever they hold for the rest of
the session. Read from the code; not yet measured.

**Do.**
1. **Write the leak test first** (this is T7). Open a note through the
   harness, close it the way the app does, and check that weak references
   to the Coordinator, its overlay, the `NoteEditor` and the `PageView` are
   nil afterwards.
2. **Fix the capture**, if the test fails.
3. **Check every other closure stored on a long-lived object.** That
   covers the Coordinator, the overlay, `NoteEditor`'s closure slots and
   `DocumentUITextView`'s ten hooks. Most use a weak-capture preamble
   already; list the ones that don't. Fix each with the same test.

**Done when.** The leak test passes, and fails on today's `main`. If it
passes on `main` too, the cycle isn't real: say so, and keep the test.

## F4. Two costs that grow with the note (two PRs; perf)

**F4a. Search runs with nothing to search.** `NoteSearch.results`
(NoteSearch.swift:192–194) reads every note's `content` on every render of
the list, even when the search field is empty, so the list's cost grows with
the number of notes. **Do:** with an empty query, return what it returns
today without reading any content. Write a test that the results are
identical for an empty query and for a few real ones. Then time the list's
search call over 500 notes, before and after.

**F4b. Line numbers are O(lines²) per block.** `lineNumber(of:)`
(DocumentTextView.swift:1267, from 2 Nov) counts lines from the block's
start for every fragment. **Do:** compute each block's line starts once per
edit, then look each line up. Write a test that the numbers are identical on
a long block, including wrapped lines and an edit mid-block. Use
`LineNumbersTests`' cost test before and after.

**Done when.** The results are identical and the costs are lower. Put both
numbers in each PR, and the new budget in `docs/refactor/baseline.md`.

## Update 2 (expanded into briefs when it starts)

- **F5. Typing near the top of a long paged note** costs 34ms a keystroke,
  because page breaks are exclusion paths and TextKit lays out everything
  below an edit (ROADMAP › Deferred work, `PageView.swift`). Measure on the
  iPad first.
- **F6. `modifiedAt` is written on every keystroke** (PageDetailView.swift:273),
  and it is the note list's `@Query` sort key, so every live list re-sorts.
  Fixed: `ModifiedAtBatcher` writes it after about 2s idle, and when the
  note closes or the app leaves the screen. The list reorders after a pause.
- **F7. Thumbnails read `drawingData` on the main actor**
  (NoteThumbnail.swift:253, HomeView.swift:355). That is external storage,
  so it means file reads on the main thread.
- **F8. Every list's `@Query` loads every note's content,** deleted notes
  included, and filters in memory (NoteList.swift:76, HomeView.swift:55,
  RecentlyDeletedView).
- **Known problems Marcus may pick:**
  - Compiler Explorer's pinned ids go stale (refreshed 6 Nov, `scripts/refresh-ce-ids.sh`; rerun when a new gcc, Python, Rust or Go ships).
  - Syntax colours carry no weight or italic. That one is a feature,
    not a fix.
