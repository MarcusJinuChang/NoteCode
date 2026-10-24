# NoteCode roadmap

Source of truth for status and what is left. Revised 19 October 2026.
What the app contains, feature by feature, is `docs/features.md`; the current
working plan is `docs/feedback-plan.md`.
Feature-by-feature design notes are in `docs/design/` (index in AGENTS.md);
finished plans are in `docs/archive/`. The long per-branch history this file
used to carry is in git (`git log -p docs/ROADMAP.md`).

| | |
|---|---|
| Drawing layer | Done 3 Oct (deadline was 10 Oct) |
| TestFlight 1 | Planned Sat 17 Oct, iPad only. Whether it went out is not recorded in the repo |
| App Store submission | Nov 2026, with the iPhone and Duo layouts |
| Duo launch | 23 Oct 2026 (runs iOS 27.1) |
| Second version | AI + feedback, Mar 2027 |

## Status (19 Oct)

Everything planned for the first release is **built and merged to `main`**
(80 PRs). Roughly 30,000 lines of app code in 110 files and 25,000 lines of
tests. On 19 Oct all 1,484 unit tests (167 suites) pass on the iPad Pro
13-inch simulator; UI tests were not run.

Built:

- Drawing layer on PaperKit: Pencil/finger ink, separate ink undo, Letter
  pages in three view modes, pinch zoom, ink cut cleanly across page breaks,
  PDF export.
- Editor on TextKit 2: code blocks with Run (redirect to a free compiler) and
  Copy, eight languages, hidden Markdown markers, lists, checklists, links.
- v3: Home and title screen, thumbnails, reopening at the last page,
  Recently Deleted, nested and draggable folders, search, outline, templates,
  Import / Export All, Settings, tip jar.
- Page fills the window, accent colour, Add Page.
- iPhone and Duo layouts (compact-width stack, fold avoidance), checked in
  the simulator only.
- Text overhaul, phases 1-6: any text size, per-character formatting, a
  nesting parser, a typing style, paste and copy with formatting, underline,
  highlight, quotes, rules and H4-H6.
- Model frozen as schema version 1 (guarded by `ModelFreezeTests`).

## What is left

### Blocking the App Store submission

1. **Turn on iPhone.** The NoteCode target still has
   `TARGETED_DEVICE_FAMILY = 2` (iPad only) although the iPhone layout is
   built. Changing it touches `project.pbxproj`, which carries Marcus's local
   signing edit; do it by hand, not by an agent.
2. **Host the pages** in `docs/site/` (`privacy.md`, `support.md`), fill the
   `DATE` and `EMAIL ADDRESS` placeholders, then set `AppInfo.privacyPolicy`
   and `AppInfo.feedbackAddress` (`AppSettings.swift`, both `nil` now). Each
   footer row appears only when its value is set.
3. **App Store Connect:** Paid Applications agreement with banking and tax;
   the three tip products (`com.marcus.NoteCode.tip.small|medium|large`)
   submitted with the build; Small Business Program; screenshots, description,
   privacy label ("nothing collected"), review notes.
4. **Bump the build number** for every upload (build 2 is current).

### Verification debt (built, never seen on the real thing)

These are the things most likely to be wrong, because every check so far was
the simulator or a unit test. Do these on the iPad before submitting:

- **Folder and note drag-and-drop.** The simulator never delivered a drop, so
  `ListDrop` is tested as rules only. If drops do nothing on the iPad, the
  fallback is `dropDestination(for:)` (see design/organising-notes.md). Moves
  from the folder menu work regardless.
- **Text overhaul "done means" list** (archive/text-system-overhaul.md): the
  six on-screen checks, including `.md` opening in Obsidian and a mixed-size
  note's PDF.
- **Page-fills-window chrome:** header, floating bottom bar, side-bar strip,
  Reduce Motion.
- **Pencil:** latency, palm rejection, squeeze/double-tap, the lasso on cut
  strokes, Insert (photo, shapes) and dragging inserted objects.
- **Hardware keyboard:** the whole shortcut table (the simulator can't send
  chords), Tab / Shift-Tab, the code-keys row hiding.
- **Export / import:** `fileExporter` writing a folder in Files, Import's
  picker, a second window ("Open in Another Window").
- **Tip jar** with a real sandbox purchase in TestFlight.
- **A physical Duo** after 23 Oct (fold avoidance was simulator-only).
- Light/dark and Increase Contrast sweeps; iPad 11-inch and portrait for the
  newer features.

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

## After the submission

In this order (see AGENTS.md › Open questions for the unscheduled ones):

1. **iCloud sync.** Needs Signing & Capabilities; the model is already
   shaped for CloudKit. Important once the iPhone app exists.
2. **Paper styles** (dots, grid), postponed after breaking on page geometry.
3. **LaTeX** (SwiftMath, always rendered, never caret-dependent).
4. **Text-anchored ink**, before our own object system.
5. **AI for March:** one or two features (explain this code block, summarise
   this page) on Apple's on-device Foundation Models, so the app still
   collects nothing.
6. **Our own object system** (tap- and pen-first, rectangular selection),
   replacing PaperKit's shapes. Its storage is the one format change after
   release.
7. **More shapes**, logic gates among them.
8. Ads plus a Pro subscription (removes ads, carries the AI features); needs
   an ad SDK, a tracking prompt, a new privacy label and a new
   `privacy.md`, so it lands with Pro.

Not in any order: infinite canvas, side-by-side pages, A4, the macOS editor
(still a plain `TextEditor`), sign-in and group notes, Face ID note locking,
note combining, code sort.

## Decisions standing

- No old notes are kept working until the release; after it every change to
  stored data needs a schema version (AGENTS.md › The model).
- Tips are consumable In-App Purchases that unlock nothing, not an outside
  link (guideline 3.1.1).
- Running code in-app stays out of scope; Run is a redirect.
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
