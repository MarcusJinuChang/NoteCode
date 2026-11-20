# NoteCode roadmap

**What this is.** Status, what is known to be wrong, and the ranked list of
what comes next. **Read it when** you want to know whether something is
planned, or want something to work on. **Last checked:** 17 Nov 2026.

What the app contains, feature by feature, is [features.md](features.md); the
design notes behind each part are in [design/](design/) (indexed in
[AGENTS.md](../AGENTS.md)); how the app got here, phase by phase, is
[timeline.md](timeline.md). Finished plans are in [archive/](archive/).

| | |
|---|---|
| Drawing layer | Done 3 Oct 2026 |
| 1.0 | Built and merged 29 Oct 2026 |
| First release | 1.1.0, on the App Store from 6 Nov 2026 (iPad, iPhone and the Duo) |
| Refactor | Finished 7 Nov 2026: feature folders, the edition seam, the pure core, the test net |
| 1.2.0 | Uploaded 7 Nov 2026, released 14 Nov 2026; this repository is its open-source edition |

## Where it stands

The whole notes app is built and released: Markdown writing with hidden
markers, inline code blocks in eight languages with highlighting while you
type, LaTeX formulas, PaperKit ink on the same page, Letter pages in three
view modes with zoom, Home, folders, search, templates, Recently Deleted,
Markdown import and export, and PDF.

The November refactor (2–7 Nov) put the files into feature folders, split
the large types (`PageView`, `NoteEditor`, `DocumentTextView`'s Coordinator,
`PageDetailView`), moved the pure text logic into `Text/Core` with its own
`swift test`, replaced test sleeps with awaited hooks, and drew the line
between the general app and an edition (AGENTS.md › How a feature plugs in).
This repository is the general app with nothing added.

## What is left

### Verification debt (built, never seen on the real thing)

The whole list, in walking order, is
[ipad-test-checklist.md](ipad-test-checklist.md). Most likely to be wrong,
because every check so far was the simulator or a unit test: drag and drop
in the list, the Pencil with the single pan, ink-mode gestures, the formula
popover, hardware-keyboard chords, export and import in Files, a physical
Duo.

### Known problems

- The build's warnings are counted by `scripts/check.sh` against the
  `WARNINGS` line in [refactor/baseline.md](refactor/baseline.md); new code
  must not add one.
- Pinned Compiler Explorer compiler ids are a maintenance item
  (`scripts/refresh-ce-ids.sh`): a retired id still shows the code, with the
  compiler pane complaining.
- A paragraph taller than a page still breaks with exclusion paths, so
  typing in such a note pays the old cost
  ([design/paged-typing-cost.md](design/paged-typing-cost.md)).

## After 1.0

Ranked; effort in brackets.

1. **iCloud sync or backup.** Only Export All today; a lost iPad loses every
   note not in an iCloud device backup (L). The model is shaped for CloudKit.
2. **Text-anchored ink.** Typing above a drawing leaves the ink behind (L).
3. **macOS.** Not a platform of the app target since 1.2.0; the old Mac editor
   (still in `PageDetailView.swift`) was a plain `TextEditor` with no fences or
   ink (L).
4. **Text alignment** (left, centre, right, justified), which comes in place
   of the paper styles removed for 1.0 (31 Oct). Alignment moves lines, so
   it has to meet the ink anchoring in 2 (M).

Unranked:

- **Apple platform hooks:** Spotlight indexing, App Intents (New Note, Open
  Last Note), a widget, a Share extension.
- **PDF import and annotation**, and handwriting to text beyond Scribble.
- **`Page.paperStyle`, `Page.runDestination` and `Folder.runDestination`**
  are unused and kept only so version 1's hashes hold; drop them with the
  next schema version.

Then: **our own object system** (tap- and pen-first, rectangular selection;
its storage is the one format change planned), **more shapes** (logic
gates).

Not in any order (AGENTS.md › Open questions for the unscheduled ones):
infinite canvas, side-by-side pages, A4, group notes, Face ID note locking,
note combining, code sort.

## Decisions standing

- Version 1 of the model has shipped: every change to stored data needs a
  schema version (AGENTS.md › The model).
- Nothing is compiled or run on the device. Run opens a free online compiler
  (`CodeDestination`): Compiler Explorer with the code in the link, or
  Programiz with the code on the pasteboard.
- Room around text and code is line height, never paragraph spacing, so the
  three view modes paginate alike.
- A paragraph that would cross a page break is pushed whole to the next page
  ([design/pages.md](design/pages.md), "Page breaks are pushed paragraphs").

## Deferred work

Referenced by name from the code.

| Where | What |
|---|---|
| `PageLayout.swift` | **A4.** A different width re-wraps text, so it would be a per-note property chosen at creation, like orientation. |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are pushed paragraphs (`PagePaginator`, `PageBreakRule`); a paragraph taller than a page is left on exclusion paths, so such a note still pays the old cost. Numbers and the design: [design/paged-typing-cost.md](design/paged-typing-cost.md). |
| `Page.swift` | **Text-anchored ink.** Anchor each stroke to an `NSTextLocation` plus an offset and translate on relayout. Its own phase. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** Retired ids still show the code with the compiler pane complaining. |
| `PageDetailView.swift` | **macOS.** Not a platform since 1.2.0; the old Mac editor left here is a plain `TextEditor`, with no fences, highlighting or ink. |
| `Storage.swift` | **iCloud sync.** No migration of its own needed. |
| Layout | **iPhone Duo.** Runs iOS 27.1; keep controls out of the fold. Pencil support on iPhone is the USB-C Pencil, so ink relies on a finger. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms.
- **Isolate risk.** Spike the hard part standalone.
- **Settings travel together** in one type with one `apply(to:)`
  (`TextRewritingPolicy`, `EditorSettings`).
- **Degrade, don't crash.** `Storage` falls back to memory and says so.
- **Check what's on screen, not what the code computed.** A passing test of
  scroll offset against page geometry hid a wrong page on screen.
