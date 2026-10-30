# R. Running code in the app

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

Today Run is a redirect (`CodeDestination`, AGENTS.md › Project overview), and
nothing leaves the device except through the system opening a web page. R
adds a second way: the block's code goes to Judge0 through a small proxy of
ours, and the output comes back into the app.

**Run is Pro's** (decided 26 Oct). For a free user the block's ▷ stays where
it is and opens the paywall (P2); Copy stays free. For Pro the redirect stays
as a choice in the Run destination menu, and as the fallback when the network
is down or the day's runs are used up. Every note feature stays free; only
Run, AI and freedom from ads are Pro's.

### The format: where the output appears

Marcus's sketch: a Notes | Run toggle in the top bar; in Run, a split with
the code on the left (a Run button and a strip of boxes beneath it, one
highlighted) and Output and Input tabs on the right. That is option A below;
the others were weighed against it.

| | What it is | For | Against |
|---|---|---|---|
| **A. Run mode (the sketch)** | The toggle swaps the note for a workbench: a second editor showing one block, output and input beside it | Most room for code and output; feels like LeetCode or Programiz | A second code editor (highlighting, indentation, keys row, undo shared with the note, the one-editor-per-note rule): two more PRs and the riskiest part of R. The note is gone while you run, so lecture notes beside the code aren't visible |
| **B. Output block in the note** | Each run writes a ```` ```output ```` block under the code | Cheapest: the output kind exists (`CodeOutputPanel`), and `CodeBlockIdentity` was built to attach a result to its block. Saved, exported to Markdown, printed in the PDF | Every run is an edit (undo, `modifiedAt`, reorders the list); no place for stdin; a long output floods the page |
| **C. Console sheet** | The block's ▷ opens a sheet or popover: Input field, output, Close | Little layout work; works the same on iPhone | Covers the note; nothing stays beside the code; output is lost on close |
| **D. Run panel beside the page** | The sketch's right half: the Notes \| Run toggle opens a panel at the right with Output and Input tabs; the code is edited where it already is, in the note | No second editor: one source of truth, all existing editing works. The note stays visible. The page scales to the narrower width without re-wrapping (the scale is a transform and the line width is pinned; `design/who-owns-scrolling.md`) | Narrows the page while open; needs a sheet fallback where the page would get too small |
| **E. Output drawn inside the block** | The block's frame grows to show output under the code | Closest to Jupyter | Rejected: reserving room in TextKit for a non-text view is the layout surgery LaTeX display blocks needed, and the three view modes would paginate differently |

**Decided (26 Oct): D, with B's Keep in Note, and the page left free.** It
keeps the sketch's toggle, the Output/Input split and the block strip (as the
panel's block chooser), and drops only the second editor. Keep in Note writes
the current result as an output block when a student wants it saved, so a
run is an edit only when asked.

**The page model comes first.** Marcus's concern: pages are objects in the
window that you move around and resize, as in Notability, and a fixed panel
that forces the page to fit would take that away. So the panel never decides
the page's geometry:

- **The panel is a pane, not a frame for the page**: docked at the right,
  its width dragged by its edge (280pt to half the window, remembered), and
  collapsed to a thin edge tab with one tap, so the note gets the whole
  window back without leaving Run.
- **The page keeps its zoom and position** when the panel opens, closes or
  resizes, and stays pinch-zoomable and pannable in the narrower area (W1's
  criterion 6 makes that pan diagonal). The top line on screen stays put.
  Only a page at the default fit-to-window zoom refits to the new width,
  because that's what "fit" means; a pinch takes it off fit, as today.
- **Floating** (the pane lifted off the edge into a movable, resizable card
  over the background) is the next step if the docked pane still feels
  tight. It isn't in 1.0, but R3 builds the panel's content as a
  self-contained view so it can be hosted either way.

### The backend: what runs the code

| | Languages (of our eight) | Cost | Notes |
|---|---|---|---|
| **Judge0 CE, hosted** (RapidAPI) | all eight, with stdin | Basic: $0.0017 a run, no monthly fee; Pro: $44.99 a month for 2,000 a day (Marcus's prices, 26 Oct) | Recommended, on Basic. The key must stay on a server, hence the proxy |
| Judge0, self-hosted on a VPS | all eight | the VPS (a few dollars a month), no per-run cost | Operations work; check Judge0's host requirements before choosing. The proxy hides the switch from the app |
| Compiler Explorer's API | C, C++, Rust, Go, Python; not Java or JavaScript (AGENTS.md), not SQL | free, no key | A community service on fair use; the wrong main path for a product feature, but a possible fallback later |
| Piston | most | self-host | Its public API is reported restricted; unverified, so same as self-hosting Judge0 |
| On the device | Python at best | app size | Rejected again for AGENTS.md's reasons, and it can't do C++ |

**The proxy** is a Cloudflare Worker (free at this scale) in
`server/run-proxy/`. It holds the Judge0 key as a secret, owns the language
table (our language name → Judge0 language id and compiler options), caps
sizes, rate-limits, and returns a trimmed result. The app never knows a
Judge0 id or key, so changing the backend is a proxy change only. Its URL is
`AppInfo.runService: URL?` in `AppSettings.swift`, `nil` until Marcus deploys
it, and **while it is `nil` the app shows no in-app Run at all** (the same
pattern as `AppInfo.privacyPolicy`), so every R PR can merge and ship safely
before the proxy exists.

### What it costs

Prices from RapidAPI's Judge0 CE page, as Marcus read them on 26 Oct.

- **Basic:** $0.0017 per submission, nothing monthly; 10GB of bandwidth a
  month included, then $0.001 per MB. A run is a few KB each way, so
  bandwidth is noise (10GB is over a million runs).
- **Pro:** $44.99 a month with 2,000 submissions a day, then $0.0017 each.
- **Break-even: $44.99 ÷ $0.0017 ≈ 26,500 runs a month, about 880 a day.**
  Below that Basic is cheaper. Move to Pro only when the Basic bill stays
  above $45 for a month; it's a setting in RapidAPI, not a change in the app
  or the proxy.
- **Up front: $0.** Basic is pay-as-you-go, and the proxy fits Cloudflare's
  free Workers plan (100,000 requests a day).
- **Per Pro subscriber** at $4.99 a month, $4.24 after Apple's 15% (the Small
  Business Program, which ROADMAP already lists). The AI features run on the
  device and cost nothing per use, so Judge0 is the only cost that grows:

  | A month of | Runs | Judge0 | Left of $4.24 |
  |---|---|---|---|
  | Lecture weeks only (3 a day, 20 days) | 60 | $0.10 | $4.14 |
  | Steady practice (5 a day) | 150 | $0.26 | $3.98 |
  | Heavy (20 a day) | 600 | $1.02 | $3.22 |
  | At the cap every day (30) | 900 | $1.53 | $2.71 |

  Every row is positive.
- **Free users cost nothing in Judge0**: they have no in-app Run, and there
  is no free trial (decided 26 Oct).
- **A global daily ceiling** in the proxy (a setting, $3 a day ≈ 1,760 runs
  to start) bounds the month at about $90 even if the per-subscription limit
  failed. Raise it as subscribers grow; the proxy's daily count says when.
  When it's reached, Pro users are offered the redirect for the rest of the
  day.
- **RapidAPI has no spending cap that we know of**, so the proxy's ceilings
  are the only guarantee. Also check on the RapidAPI dashboard after the
  first test runs that each run is billed once: `wait=true` makes a run one
  call, where polling a token would add `GET`s that may be billed as
  submissions.

**Judge0 runs programs non-interactively**: stdin is given before the run, not
typed during it. The Input tab is where it goes, and when the code reads input
(`cin`, `scanf`, `getline`, `input(`, `Scanner`, `readLine`, `bufio`) and
Input is empty, the Output tab says so before the student wonders why the
program printed nothing.

### R1. The runner (app side, no UI)

New files, Foundation only and `nonisolated`, so they compile into a Mac CLI
probe (memory: debugging approach):

- `RunJob` (language, code, stdin), `RunResult` (status: ok, compile error,
  runtime error with its signal or exit code, time limit, memory limit,
  service error; stdout, stderr, compile output, time, memory) and
  `RunServiceError` (offline, not subscribed, capped with runs left and
  reset time, too large, service down).
- `CodeRunning` protocol and `RunServiceClient` (`URLSession`, 20s timeout,
  cancellable through the task), against the proxy's contract written in R2's
  README (`POST /run` with `{language, code, stdin, transaction}`, response JSON
  and an `X-Runs-Left` header). Tests stub `URLProtocol`; no network in tests.
- `JavaMain`: Judge0 compiles Java as `Main.java` and runs `Main`, so a
  block whose `public class X` holds `main` is sent with `X` renamed to `Main`
  (whole word, outside strings and comments), and the result says so.
- `CompilerMessages`: finds `file:line:col` in compile output and stderr for
  each language (gcc/clang `main.cpp:5:3:`, javac `Main.java:5:`, Python
  `line 5`, rustc `--> main.rs:5:3`, Go `./main.go:5:3:`), mapped to the
  block's line, for R4's links.
- `ReadsInput`: whether the code reads stdin, per language (the hint above).
- The Pro proof: each request carries the subscription's signed transaction
  (a JWS string) passed in by the caller, so R1 needs no StoreKit; P1
  supplies it. No install id: the limits key on the subscription.

**Done when.** `CodeRunnerTests` covers: a request's JSON; every status mapped;
offline, 429 and 5xx mapped to `RunServiceError`; cancellation; the Java
rename (including a class named in a string or comment, which stays); a
compile-error line per language; `ReadsInput` per language, with a negative
case each. Mutation check on the status mapping.

### R2. The proxy (`server/run-proxy/`)

TypeScript Cloudflare Worker with `wrangler.toml`, `src/index.ts` and tests
(`vitest` with `@cloudflare/vitest-pool-workers`), outside the Xcode project.

- `POST /run`: language in the allow-list (the eight, from
  `languages.json`: language → Judge0 id, compiler options such as
  `-std=c++17`); code and stdin up to 64KB each; forwards to Judge0 with
  `base64_encoded=true&wait=true`, CPU limit 5s, wall 10s, memory 128MB;
  returns stdout, stderr and compile output trimmed to 64KB with a
  "truncated" flag.
- **Pin the Judge0 language ids from its `/languages` list**, newest stable
  compiler per language, and test the table, as `CodeDestination` pins
  Compiler Explorer's ids. A maintenance item, to be noted in ROADMAP's known
  problems beside the Compiler Explorer one.
- **Only Pro runs.** Each request carries the subscription's signed
  transaction (StoreKit 2's JWS). The Worker verifies it against Apple's
  certificate chain, checks the product is Pro and the expiry is in the
  future, and refuses anything else with 402. A verified transaction is
  cached by its original transaction id for an hour, so a run isn't a
  certificate check. Tested against fixture JWSs (valid, expired, wrong
  product, bad signature).
- Limits, all in `wrangler.toml` vars so Marcus changes them without code:
  30 runs a day per subscription (by original transaction id, so a
  reinstall doesn't reset it), per IP per minute, and a **global daily
  ceiling** ($3 ≈ 1,760 runs to start), so the bill can't run away. The 429
  says which limit was hit and when it resets. Use Workers' rate-limiting binding or a Durable Object counter, not
  KV (KV is eventually consistent, so a burst gets through).
- No request bodies logged; nothing stored past the day's counters.
- A shared app header is a speed bump, not security (anything in the app can
  be read out of it); the limits are the protection. App Attest is the later
  hardening, and needs an entitlement, so it's Marcus's and not 1.0's.
- README: the contract (R1 codes against it), and Marcus's three commands
  (`npx wrangler secret put JUDGE0_KEY`, `npx wrangler deploy`, then set
  `AppInfo.runService`). **The session never deploys and never sees the key.**

**Done when.** The Worker's tests cover validation, the limits (including the
global ceiling), Judge0 errors and timeouts mapped, trimming, and that the key
never appears in a response; `npm test` passes.

### R3. The Run panel (after W2)

- `RunSession` (`@Observable`, one per open note, made by `NoteEditor`): the
  chosen block (by `CodeBlockID`), stdin per block, the last result per block
  with the `contentHash` it ran (stale when the code changes: dimmed, "Code
  changed since this run"), running state, runs left.
- `RunPanel` (SwiftUI): the block strip from the sketch (one chip per runnable
  block, "1 · C++", the chosen one in the accent; a tap scrolls the note to
  it); ▷ Run; Output | Input tabs. Output: a status line ("0.02s · 3.1MB",
  "Compile error", "Time limit"), stdout in the code font, stderr and compile
  output below in the error colour, the stdin hint, Copy, Keep in Note.
  Input: a plain monospaced editor (no smart quotes or autocorrect).
  Colours from `CodeOutputPanel` and `design/colour.md`, no glass.
- **Place** (section R › The format): the top bar gets the Notes | Run
  segmented control in its centre (the sketch). Run opens the docked pane at
  the right, 360pt to start, its edge dragged from 280pt to half the window
  (width remembered app-wide), with a collapse to an edge tab. Opening,
  closing and resizing never change a pinched zoom or the top line; a page
  at fit-to-window refits. In a compact width (iPhone, a narrow Split View)
  the panel is a bottom sheet with medium and large detents. Works in text
  and ink mode; it never takes touches outside its own frame.
- **For a free user** the toggle's Run segment carries a small Pro mark and
  opens the paywall (P2) instead of the panel.
- A `-debug-run-stub` launch option (`DebugLaunch`, `#if DEBUG`) answers runs
  with canned results (ok, compile error, time limit, capped), so the panel
  can be seen without a proxy.

**Done when.** Opening, closing and resizing the panel doesn't re-wrap a
line, move the top line or change a pinched zoom (compare `-debug-report`'s
top line, zoom and `visibleLinesAcrossBreaks` with it open, resized and shut,
in all three view modes); screenshots of each stubbed result, light and
dark, 13-inch landscape, 11-inch portrait and a compact Split View (the
sheet); `RunSessionTests`
for staleness, the chosen block surviving edits above it, and stdin kept per
block. **Read:** `design/code-languages-and-keys.md` (output part),
`design/the-page-fills-the-window.md`.

### R4. Wiring Run

- **The gate first:** a free user's ▷, ⌘R and the edit menu's Run open the
  paywall (P2) and do nothing else; `ProStatus` (P1) is the only thing read.
  For Pro, the block's ▷ (`DocumentTextView.Coordinator.run`,
  `CodeBlockOverlay`) runs in the app when the resolved destination is
  in-app, opening the panel on that block; ⌘R the same. Otherwise today's
  redirect, untouched.
- Each run sends `ProStatus`'s signed transaction; a 402 (the subscription
  ended without the app noticing) refreshes `ProStatus` and opens the paywall.
- `RunDestinationMenu` gains **In NoteCode** above the sites, resolved
  through the existing page → folder → app levels
  (`Page.runDestinationLevels`); the default when `AppInfo.runService` is set.
  Stored as a new raw value beside `programiz`, `onlinegdb` and `godbolt`;
  check that it needs no schema change (a string attribute), and stop and
  ask if it does.
- Offline, capped or service down: the panel says which, with one button to
  open the block at the page's site instead (the redirect).
- Keep in Note: inserts or replaces the ```` ```output ```` block directly under
  the code, through the text view's `replace(_:withText:)` (one undo step;
  a following output block is replaced, never duplicated).
- Compile-error links: a tap on "line 5" in the output puts the caret on that
  line of the block in the note.

**Done when.** Tests: a free user's ▷ opens the paywall and makes no
request; a 402 opens it too; the destination resolves to in-app and back; ▷ with a
stubbed runner fills the panel; Keep in Note inserts once, replaces on the
second run, and undoes in one step; a link lands the caret on the right line;
with `runService` `nil` nothing in-app is visible. iPad checklist lines: run
each of the eight languages once, a program with input, a compile error's
link, airplane mode.

### R5. Policy and docs, for Run and ads together

Sending code to a server and showing ads both change promises the app makes,
so they change in one PR, after R4 and P3:

- `docs/site/privacy.md` and `support.md`: on an explicit Run, the block's
  code and its input go to our proxy and to Judge0 to be run; the proxy keeps
  nothing but a day's count per subscription. Find out whether hosted Judge0
  retains submissions and say so; if it does, the App Store privacy label
  gains "Other User Content, not linked, not used for tracking" (Marcus sets
  the label in App Store Connect; the PR lists what to choose).
- **Ads (P3):** the page and the label also cover what Google's SDK collects
  (device identifiers, advertising data, product interaction, diagnostics,
  coarse location from the IP; check Google's current list), that it is used
  for tracking only when the reader allows it (non-personalised ads
  otherwise), and that Pro has no ads. The label list for Marcus covers Run
  and ads together. AGENTS.md › Shipping's "nothing is collected or
  tracked" is rewritten, with a note that the SDK brings its own privacy
  manifest.
- AGENTS.md: the overview's "Running code in-app is deliberately out of
  scope" and "nothing in the app ever runs a program" paragraphs rewritten
  (in-app run through the proxy; the redirect remains), and Shipping ›
  Exempt encryption's reason (HTTPS through `URLSession` is still exempt, so
  `ITSAppUsesNonExemptEncryption` stays `NO`).
- ROADMAP: "Running code in-app stays out of scope" removed from Decisions
  standing; the Judge0 ids added to Known problems. `features.md` rows.
- `AppStoreReadinessTests` still pass (and gain a check that the privacy page
  mentions running code, if it reads the page).
- App Review notes for Marcus to paste: Run sends code to a server to compile
  and run it; nothing is downloaded and executed on the device.
