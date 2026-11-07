# NoteCode roadmap

Source of truth for status and what is left. Revised 2 November 2026, with
1.0 in App Review. What the app contains, feature by feature, is
`docs/features.md`. The 1.0 plan is finished and archived in
`docs/archive/release-1.0/`; what is still live during review is
`docs/release-1.0/R5-submission.md` and `qc-ecosystem.md`. How the app got
here, phase by phase: `docs/timeline.md`.
Feature-by-feature design notes are in `docs/design/` (index in AGENTS.md);
finished plans are in `docs/archive/`. The long per-branch history this file
used to carry is in git (`git log -p docs/ROADMAP.md`).

| | |
|---|---|
| Drawing layer | Done 3 Oct |
| 1.0 | Built and merged to `main` (29 Oct; polish and fixes to #123, 1 Nov) |
| App Store submission | Submitted 1 Nov as 1.1.0 (4), iPad, iPhone and Duo; **approved 5 Nov**, releasing automatically (expected on the store 6 Nov) |
| EU storefronts | Waiting on Apple to verify EU trader status |
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

### The refactor (planned 2 Nov)

Two updates and then a split, run by Sonnet sessions with a reviewing
session per PR: **1.1.1** (the safety net, feature folders, the cheap fixes
and the bugs from the device pass) and **1.2.0** (the extension seam, types
out of the large files, performance). After 1.2.0 ships, the repo splits
into a public, open-source `NoteCode` (Apache-2.0, fresh history, no ads or
Pro) and the private `NoteCode-AppStore`. Plan, decisions and order:
[refactor/README.md](refactor/README.md).

### Approved 5 Nov, releasing (Marcus)

App Review approved 1.1.0 (4) on 5 Nov; items 1 and 4 below are history
once it is on the store, and "After it's live" starts.

Submitted 1 Nov as **1.1.0 (4)** with NoteCode Pro, its subscription and
the three tips attached; automatic release on approval. Done before
submitting: the run proxy deployed (28 Oct), W-9, AdMob, the pages on
`gh-pages` (privacy and support, 31 Oct), the support address
(`notecodesupport@gmail.com`), and App Store Connect (metadata, screenshots
for iPad, iPhone and the Duo, privacy label, review notes, age rating 13+ to
match AdMob's T ceiling). Not on Apple Silicon Macs or Vision Pro.

While it is in review:

1. **Answer App Review** if it comes back; review notes and the label are in
   `R5-submission.md`. A rejected build needs the build number bumped before
   it is uploaded again.
2. **EU trader status** is with Apple; the EU storefronts follow once it
   clears.
3. **Judge0's retention** (settled 3 Nov): it keeps submissions and deletion
   is off on the hosted service, so "Other User Content" stays on the label
   and the policy's sentence says Judge0 keeps them (docs/design/shipping.md).
4. **The TestFlight sandbox pass** wasn't done before submitting. Walk
   `docs/ipad-test-checklist.md` on build 4 signed in with a sandbox tester:
   purchases, Run (an Xcode build gets 402 from the proxy) and real ad units
   can't be checked any other way.

After it's live:

5. Link the app in AdMob; `app-ads.txt` needs a developer-site root (a
   `MarcusJinuChang.github.io` user-site repo), which the `/NoteCode/`
   project page can't serve.
6. The model's version 1 is now shipped: any change to a stored attribute
   is a new schema version (`docs/design/the-model.md`).

Keep `Sandbox` in the proxy's `ALLOWED_ENVIRONMENTS` after release: App Review
and TestFlight buy in the sandbox on the production build.

### Verification debt (built, never seen on the real thing)

The whole list, in walking order, is `docs/ipad-test-checklist.md`. Most
likely to be wrong, because every check so far was the simulator or a unit
test: drag and drop in the list, the Pencil with the new single pan, ink-mode
gestures, the Run panel and the sandbox purchase, the formula popover,
hardware-keyboard chords, export and import in Files, a physical Duo.

### Known problems

- The build prints 12 warnings (docs/refactor/baseline.md › Warnings, the
  `WARNINGS` line `scripts/check.sh` ratchets): five main-actor isolation
  warnings that become errors in Swift 6 mode, four deprecations (two
  `UIWindow(frame:)` left in tests, `traitCollectionDidChange`, the ad
  banner's size), an unnecessary effect marker in TipJarTests, unreachable
  code after a `throw` in ListDragUITests, and AdConsent's "consider using
  asynchronous alternative". Update 2's 2W takes them to zero.
- Typing three hyphens by hand in prose turns into "—-" while autocorrect is
  on (smart dashes), so it doesn't become a rule; Style ▾'s rule and
  autocorrect off both work (features.md › Autocorrect).
- Weight and italic are not drawn in syntax colours (`ColorRun` carries
  colour only).
- The first-Run notice (`RunDisclosure.message`) says Judge0 keeps code
  "for a while"; it keeps it, with no way to delete it. A fix for 1.1.1, in
  the policy's words.
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
| `PageView.swift` | **Typing cost on long paged notes (F5, measured 6 Nov, fixed 6 Nov).** Page breaks were exclusion paths, so TextKit 2 laid out everything below an edit: 15-18ms a keystroke near the top of 250 lines, 92-100ms on 40 pages, against 1ms with no paths. Now a paragraph that would cross a break is pushed whole to the next page with paragraph spacing (`PagePaginator`, `PageBreakRule`), which moves where breaks fall (a product decision, approved) and leaves a paragraph taller than a page on exclusion paths, so such a note still pays the old cost. Numbers and the design: `docs/design/pages.md` › Page breaks are pushed paragraphs. Still to check on the iPad: how typing feels, and whether the simulator's numbers hold. |
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
