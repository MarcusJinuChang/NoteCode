# NoteCode roadmap

Source of truth for status and what is left. Revised 29 October 2026, at 1.0.
What the app contains, feature by feature, is `docs/features.md`. The 1.0 plan
is finished and archived in `docs/archive/release-1.0/`; what is still live for
submission is `docs/release-1.0/R5-submission.md` and `qc-ecosystem.md`.
Feature-by-feature design notes are in `docs/design/` (index in AGENTS.md);
finished plans are in `docs/archive/`. The long per-branch history this file
used to carry is in git (`git log -p docs/ROADMAP.md`).

| | |
|---|---|
| Drawing layer | Done 3 Oct |
| 1.0 | Everything planned is built and merged to `main` (29 Oct); waiting on the by-hand release steps below |
| App Store submission | Nov 2026 |
| Duo launch | 23 Oct 2026 (runs iOS 27.1) |
| Second version | AI + feedback, Mar 2027 |

## Status (29 Oct)

The 1.0 plan (streams B, O, S, T, W, L, R, P, F) and three QC passes are
merged to `main`. Unit tests: all 1,858 tests (211 suites) pass on the iPad Pro 13-inch simulator (29 Oct, `-only-testing:NoteCodeTests -parallel-testing-enabled NO`, about 500s). UI tests were not run.

Built, beyond the first release's drawing layer, editor, Home, folders,
Import/Export, Settings and tip jar:

- **LaTeX** (SwiftMath): inline and display formulas drawn in the page,
  editable by a popover, vector in the PDF and thumbnails, handled by Get
  Info, outline, copy and paste.
- **Run in the app (Pro):** a panel beside the page, output kept in the
  note, through `server/run-proxy` on Cloudflare and hosted Judge0. The free
  Run button is still a redirect to a compiler site.
- **Pro and ads:** $4.99 a month subscription (no ads, in-app Run, the AI
  features), a paywall, and banner ads with consent first for free readers.
- **The note window:** one pan on the page, a sheet look, a joined
  list/Home control with the note shrinking into its card, no Liquid Glass.
- **Text:** instant size changes with undo and no alert, a rearranged
  hotbar. **Objects:** selection stays after Insert, smooth resize.
  **Sidebar:** drag to Recently Deleted, a shorter menu.
- Fixes: Home's excerpt, the app icon's pencil, the pixel eraser crash, a
  Run result landing on the wrong block.

## What is left

### By hand, to release (Marcus)

1. **Bump the build number** in `project.pbxproj` for the upload.
2. **Publish the pages:** `docs/site/privacy.md` and `support.md` to the
   `gh-pages` branch (steps in `R5-submission.md`), then set
   `AppInfo.feedbackAddress` (`nil` now; the privacy link is already set).
3. **Deploy the run proxy** and set `PRO_PRODUCT_IDS` (it fails closed until
   then); `server/run-proxy/README.md`.
4. **App Store Connect:** Paid Applications agreement, the three tip products
   and the `com.marcus.NoteCode.pro.monthly` subscription submitted with the
   build; privacy label and review notes from `R5-submission.md`; screenshots,
   description; Small Business Program.
5. **Walk `docs/ipad-test-checklist.md`** on the iPad.

### Verification debt (built, never seen on the real thing)

The whole list, in walking order, is `docs/ipad-test-checklist.md`. Most
likely to be wrong, because every check so far was the simulator or a unit
test: drag and drop in the list, the Pencil with the new single pan, ink-mode
gestures, the Run panel and the sandbox purchase, the formula popover,
hardware-keyboard chords, export and import in Files, a physical Duo.

### Known problems

- The `Code keys and indentation in the editor` suite failed on 14 Oct with
  a hardware keyboard attached to the Mac (it reads the real
  `GCKeyboard.coalesced`) and passed on 19 Oct without one. Fix by injecting
  the keyboard check so it can't depend on the machine.
- The tests build with ~400 Swift 6 isolation warnings (`SyntaxTheme`
  accessed from nonisolated autoclosures, `CaretTarget: Equatable`) and 94
  `UIWindow(frame:)` deprecations. They become errors in Swift 6 mode.
- `FileDocument` is deprecated in iOS 27 (`ExportFolderDocument`).
- Typing three hyphens by hand may be turned into an em dash by smart
  punctuation before it becomes a rule. Untried.
- Weight and italic are not drawn in syntax colours (`ColorRun` carries
  colour only).
- Pinned Compiler Explorer compiler ids are a maintenance item.
- So are the Judge0 CE language ids in `server/run-proxy/languages.json`
  (read from ce.judge0.com on 26 Oct; the site has no "latest" alias).

## After 1.0

The ranked gaps are from the cohesion QC (#111, effort in brackets; its
first two, the Privacy Policy link and "No ads" with no ads, were fixed by R5
and P3); the rest are items the QC and R5 left unbuilt.

1. **Support address.** `AppInfo.feedbackAddress` is `nil`, so a student has no
   way to report a bug or ask for a feature (XS). Possibly switch the support
   email to notecodesupport@gmail.com (the page, `support.md` and the setting).
2. **iCloud sync or backup.** Only Export All today; a lost iPad loses every
   note (L). The model is shaped for CloudKit.
3. **Text-anchored ink.** Typing above a drawing leaves the ink behind (L).
4. **Run for free students** is Pro only with no trial; a free student sees
   the paywall on first tap (S, policy call).
5. **The macOS editor** is a plain `TextEditor`, and iPhone is built but not
   turned on (L).

Unbuilt from the QC and R5:

- A **disclosure the first time Run is used** (QC item 7): what is sent and to whom.
- A **Settings › Privacy Options row** to reopen the consent form (QC item 5).
- **`server/run-proxy`: wrangler 4 and `@cloudflare/vitest-plugin`.** It
  is on wrangler 3.90 and `@cloudflare/vitest-pool-workers` 0.5; upgrade both
  and re-run its tests.

Then, in the old order (AGENTS.md › Open questions for the unscheduled ones):
**our own object system** (tap- and pen-first, rectangular selection; its
storage is the one format change after release), **more shapes** (logic
gates), **more AI features and a higher Pro price**.

Not in any order: infinite canvas, side-by-side pages, A4, sign-in and group
notes, Face ID note locking, note combining, code sort.

## Decisions standing

- No old notes are kept working until the release; after it every change to
  stored data needs a schema version (AGENTS.md › The model).
- Tips are consumable In-App Purchases that unlock nothing, not an outside
  link (guideline 3.1.1).
- Running code in-app is Pro, through our own proxy (1.0 plan, Decision on R); the free run button stays a redirect to a compiler site.
- Room around text and code is line height, never paragraph spacing, so the
  three view modes paginate alike.

## Deferred work

Referenced by name from the code.

| Where | What |
|---|---|
| `PageLayout.swift` | **A4.** A different width re-wraps text, so it would be a per-note property chosen at creation, like orientation. |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are exclusion paths, so TextKit 2 lays out everything below an edit (34ms a keystroke near the top of a 250-line note, simulator). If the iPad lags, push whole paragraphs with paragraph spacing, computed lazily. |
| `PageView.swift` | **Diagonal panning when zoomed in.** The text view scrolls vertically and `PageView` sideways, so a pan picks one. |
| `Page.swift` | **Text-anchored ink.** Anchor each stroke to an `NSTextLocation` plus an offset and translate on relayout. Its own phase. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** Retired ids still show the code with the compiler pane complaining. |
| `PageDetailView.swift` | **The macOS editor.** No fences, highlighting or ink. |
| `Storage.swift` | **iCloud sync.** No migration of its own needed. |
| Layout | **iPhone Duo.** Runs iOS 27.1; keep controls out of the fold. Pencil support on iPhone is the USB-C Pencil, possibly not at launch, so ink relies on a finger. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms.
- **Isolate risk.** Spike the hard part standalone.
- **Settings travel together** in one type with one `apply(to:)`
  (`TextRewritingPolicy`, `EditorMode`).
- **Degrade, don't crash.** `Storage` falls back to memory and says so.
- **Check what's on screen, not what the code computed.** A passing test of
  scroll offset against page geometry hid a wrong page on screen.
