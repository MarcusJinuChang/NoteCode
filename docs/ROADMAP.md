# NoteCode roadmap

Source of truth for status and what is left. Revised 31 October 2026, at 1.0.
What the app contains, feature by feature, is `docs/features.md`. The 1.0 plan
is finished and archived in `docs/archive/release-1.0/`; what is still live for
submission is `docs/release-1.0/R5-submission.md` and `qc-ecosystem.md`.
Feature-by-feature design notes are in `docs/design/` (index in AGENTS.md);
finished plans are in `docs/archive/`. The long per-branch history this file
used to carry is in git (`git log -p docs/ROADMAP.md`).

| | |
|---|---|
| Drawing layer | Done 3 Oct |
| 1.0 | Everything planned is built and merged to `main` (29 Oct, last change #118 on 31 Oct); waiting on the by-hand release steps below |
| App Store submission | Nov 2026 |
| Duo launch | 23 Oct 2026 (runs iOS 27.1) |
| Second version | AI + feedback, Mar 2027 |

## Status (31 Oct)

The 1.0 plan (streams B, O, S, T, W, L, R, P, F), three QC passes and the
fixes after them (#116 to #118) are merged to `main`. Unit tests: all 1,848
tests (211 suites) pass on the iPad Pro 13-inch simulator, iOS 27.0 (31 Oct,
at fb7428e, `-only-testing:NoteCodeTests -parallel-testing-enabled NO`, 494s;
#118 removed the run-site tests). The run proxy's 31 tests and its
typecheck pass. UI tests were not run.

Built, beyond the first release's drawing layer, editor, Home, folders,
Import/Export, Settings and tip jar:

- **LaTeX** (SwiftMath): inline and display formulas drawn in the page,
  editable by a popover, vector in the PDF and thumbnails, handled by Get
  Info, outline, copy and paste.
- **Run in the app (Pro):** a panel beside the page, output kept in the
  note, through `server/run-proxy` on Cloudflare (deployed 28 Oct) and hosted
  Judge0, seven languages. A free reader's Run opens the paywall. There is no
  choice of where code runs any more (#118, 30 Oct): a compiler site is only
  the panel's *Open on a Site Instead* when a run can't happen.
- **Pro and ads:** $4.99 a month subscription (no ads, in-app Run, the AI
  features), a paywall, and banner ads with consent first for free readers.
- **The note window:** one pan on the page, a sheet look, a joined
  list/Home control with the note shrinking into its card, no Liquid Glass.
- **Text:** instant size changes with undo and no alert, a rearranged
  hotbar. **Objects:** selection stays after Insert, smooth resize.
  **Sidebar:** drag to Recently Deleted, a shorter menu.
- Fixes: Home's excerpt, the app icon's pencil, the pixel eraser crash, a
  Run result landing on the wrong block.
- From the ecosystem QC (30 Oct, #116): the paywall's cancel-24-hours line
  and Try Again when the price doesn't load; Help and About › Ad Privacy
  Options where UMP requires it; a notice before the first run in the app.
- Home (#117, 31 Oct): the ad banner stays inside its column, and Home under
  700pt wide (beside the list on a portrait 11-inch) takes the phone layout.

## What is left

### By hand, to release (Marcus)

Done: the run proxy is deployed (28 Oct, `JUDGE0_KEY` set,
`PRO_PRODUCT_IDS` and `ALLOWED_ENVIRONMENTS` in `wrangler.toml`), W-9 sent,
AdMob set up, the subscription created in App Store Connect, the support
address chosen (31 Oct: `notecodesupport@gmail.com`, also the EU trader
contact, in `AppInfo.feedbackAddress` and both pages).

1. **Version and build number.** The App Store Connect version and
   `MARKETING_VERSION` must match; bump `CURRENT_PROJECT_VERSION` above the
   last upload, in both configurations.
2. **Publish the pages** from `main`: `docs/site/privacy.md` and `support.md`
   to `gh-pages`, the support link in its `index.md` (steps in
   `R5-submission.md`). `gh-pages` still has the 17 Oct page saying the app
   collects nothing and has no ads, and the build links it.
3. **Ask RapidAPI/Judge0 how long submissions are kept**; edit the policy's
   Judge0 sentence, and drop "Other User Content" only if they keep nothing.
4. **App Store Connect:** Paid Applications Agreement Active; EU trader
   status verified (or the EU out of Availability); Small Business Program;
   the three tips and the subscription with real review screenshots, attached
   to the version; privacy label and review notes from `R5-submission.md`;
   description (Terms of Use link, no sync yet), name, subtitle, keywords,
   13-inch screenshots; age rating (ads) and AdMob's content ceiling to match.
5. **Upload and TestFlight**, signed in with a sandbox tester, and the iPad
   added as an AdMob test device first. Walk `docs/ipad-test-checklist.md`
   on that build: purchases, Run (the proxy needs a sandbox transaction; an
   Xcode build gets 402) and real ad units can't be checked any other way.
6. **After it's live:** link the app in AdMob; `app-ads.txt` needs a
   developer-site root (a `MarcusJinuChang.github.io` user-site repo), which
   the `/NoteCode/` project page can't serve.

Keep `Sandbox` in the proxy's `ALLOWED_ENVIRONMENTS` after release: App Review
and TestFlight buy in the sandbox on the production build.

### Verification debt (built, never seen on the real thing)

The whole list, in walking order, is `docs/ipad-test-checklist.md`. Most
likely to be wrong, because every check so far was the simulator or a unit
test: drag and drop in the list, the Pencil with the new single pan, ink-mode
gestures, the Run panel and the sandbox purchase, the formula popover,
hardware-keyboard chords, export and import in Files, a physical Duo.

### Known problems

- The tests build with ~400 Swift 6 isolation warnings (`SyntaxTheme`
  accessed from nonisolated autoclosures, `CaretTarget: Equatable`) and 94
  `UIWindow(frame:)` deprecations. They become errors in Swift 6 mode.
- `FileDocument` is deprecated in iOS 27 (`ExportFolderDocument`).
- Typing three hyphens by hand in prose turns into "—-" while autocorrect is
  on (smart dashes), so it doesn't become a rule; Style ▾'s rule and
  autocorrect off both work (features.md › Autocorrect).
- Weight and italic are not drawn in syntax colours (`ColorRun` carries
  colour only).
- Pinned Compiler Explorer compiler ids are a maintenance item.
- So are the Judge0 CE language ids in `server/run-proxy/languages.json`
  (read from ce.judge0.com on 26 Oct; the site has no "latest" alias).

## After 1.0

The ranked gaps are from the cohesion QC (#111, effort in brackets; its
first two, the Privacy Policy link and "No ads" with no ads, were fixed by R5
and P3); the rest are items the QC and R5 left unbuilt.

The support address (XS), ranked first here before, is set for 1.0.1.

1. **iCloud sync or backup.** Only Export All today; a lost iPad loses every
   note not in an iCloud device backup (L). The model is shaped for CloudKit.
2. **Text-anchored ink.** Typing above a drawing leaves the ink behind (L).
3. **Run for free students** is Pro only with no trial: a free student's Run
   opens the paywall, and only Copy gets a block to a compiler (S, policy
   call).
4. **The macOS editor** is a plain `TextEditor` (L). iPhone and the Duo
   ship in 1.0.1 (31 Oct).
5. **An annual plan and a student price** (QC §3: ~$39.99 a year; a semester
   price or offer code). A product in App Store Connect and `ProStatus`.

6. **Text alignment** (left, centre, right, justified), which comes in place
   of the paper styles removed for 1.0 (31 Oct). Alignment moves lines, so
   it has to meet the ink anchoring in 2 (M).

Unbuilt from the QC and R5:

- **`server/run-proxy`: wrangler 4 and `@cloudflare/vitest-plugin`.** It
  is on wrangler 3.90 and `@cloudflare/vitest-pool-workers` 0.5; upgrade both
  and re-run its tests.
- **App Attest on the proxy**, so only the app can call it (QC After 1.0).
- **Apple platform hooks** (QC §4): Spotlight indexing, App Intents (New
  Note, Open Last Note), a widget, a Share extension.
- **PDF import and annotation**, and handwriting to text beyond Scribble.
- **`Page.paperStyle`** is unused since the paper styles came out (31 Oct)
  and kept only so version 1's hashes hold; drop it with the next one.
- **`Page.runDestination` and `Folder.runDestination`** are unused since
  #118 and kept only so version 1's hashes hold; drop them before the
  release freezes the schema, or in version 2.

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
- Running code is Pro, through our own proxy (1.0 plan, Decision on R). A
  free reader's Run opens the paywall; there is no choice of where code runs
  (#118), and a compiler site is only the panel's way out when a run can't
  happen.
- Room around text and code is line height, never paragraph spacing, so the
  three view modes paginate alike.

## Deferred work

Referenced by name from the code.

| Where | What |
|---|---|
| `PageLayout.swift` | **A4.** A different width re-wraps text, so it would be a per-note property chosen at creation, like orientation. |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are exclusion paths, so TextKit 2 lays out everything below an edit (34ms a keystroke near the top of a 250-line note, simulator). If the iPad lags, push whole paragraphs with paragraph spacing, computed lazily. |
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
