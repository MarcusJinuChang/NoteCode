# NoteCode roadmap

Source of truth. The published version at
<https://claude.ai/code/artifact/2490317a-7eaf-44ae-9389-f0fb92d7471a>
is a rendering of this file — edit here, ask for the artifact to be regenerated.

Revised 11 September 2026.

| | |
|---|---|
| Drawing layer due | **10 Oct 2026** (hard stop) |
| App Store submission | Nov 2026 |
| Second version | AI + feedback, Mar 2027 |

## What changed since July

Two things went differently from the original plan, and both were right.
The custom text engine got built *before* the drawing layer — TextKit 2, fence
detection, syntax highlighting, and per-block run and copy buttons are all
working. And in-app code execution was dropped: every option needed a paid API,
a VPS sandbox, or a multi-megabyte WASM runtime with a four-second cold start,
for a feature nobody uses during a lecture. Running a block is now a redirect to
a free online compiler, which cost days rather than weeks and needs no backend
at all.

The consequence: the hardest remaining feature is also the last one.

## Phases

### Done — Foundations (Jul–Aug)
Swift and SwiftUI basics before touching NoteCode itself.

### Done — Walking skeleton (Aug)
The `Page` model with `content` and a `drawingData` placeholder. A page list, a
page editor, and `Storage` — which degrades to an in-memory store and says so,
rather than crashing on launch when the disk store fails.

### Done — Custom text engine (Aug–early Sep)
Built early, out of the original order. This was the phase most likely to sink
the schedule, so taking it first was the right instinct.

- A real `UITextView` on TextKit 2 (`DocumentTextView`)
- Pure, unit-tested fence parsing (`DocumentParser`)
- Fragment-level code panels (`CodeBlockLayoutFragment`) — `.backgroundColor`
  paints per glyph and leaves a ragged right edge
- Async syntax colouring via HighlightSwift, restyling only the changed block
- Debounce went from a guessed 200ms to a measured 20ms

### Cut, then partly back — Run button
Cut as *execution*, which is what freed the two weeks the drawing layer is now
spending. It returned as a redirect, at a fraction of the cost: every code block
carries run and copy in its top-right corner, and run opens a free online
compiler instead of running anything.

- `CodeDestination` — where a block goes, and how it gets there. Compiler
  Explorer takes the whole program in the URL, so the student lands on a
  finished run; Programiz and OnlineGDB can't be prefilled, so the code goes on
  the pasteboard and they paste on arrival.
- Per-note choice today, app-wide default behind it. Folders slot in between
  when they exist — `RunDestinationPreference.resolve` walks the levels in
  order, so that is one more array element rather than another branch.
- The buttons are TextKit 2 viewport-positioned overlays (`CodeBlockOverlay`),
  not attachments, and the text view has to be stopped from eating their taps.

### Now — Drawing layer (6 Sep – 10 Oct) — flagged risk
See [phase-drawing-layer.md](phase-drawing-layer.md) for the build plan.

The canvas goes inside the text view's content, not beside it, so both layers
share one `contentOffset` with no sync code. An `EditorMode` enum owns all six
settings the toggle moves at once. The zoom container gets built in the
geometry step rather than retrofitted later.

**Fallback if it runs long:** drop `PKToolPicker` for a fixed pen/eraser/colour
toolbar. That removes the keyboard-versus-picker fight and keeps the feature.

### Next — Sign in and ship (10 Oct – Nov)
Sign in with Apple (no backend; as the only login option it sidesteps Apple's
rule requiring it alongside third-party sign-in). Apple Developer Program
enrolment, TestFlight beta, privacy manifest, submission.

This date is what the drawing layer's hard stop exists to protect. First
submissions bounce on formality — you want review-cycle buffer, not zero margin.

### Later — AI and feedback (Dec – Mar 2027)
One or two AI features tied to the actual use case — explain this code block,
summarise this page — rather than AI for its own sake, built on real TestFlight
usage. Most of the deferred list below is fair game here too.

## Deferred work

Referenced by name from `TextRewritingPolicy.swift` and `DocumentTextView.swift`.

| Where | What |
|---|---|
| `TextRewritingPolicy.swift` | **Per-region text rewriting.** All five keyboard traits are `.code` everywhere, so prose loses autocorrect. Plan: `.prose` outside a fence, `.code` inside, with `reloadInputViews()`. |
| `DocumentStyler.swift` | **Markers that recede.** Markdown markers stay visible in `tertiaryLabel`. Hiding them when the caret is elsewhere is the Obsidian behaviour. |
| Page geometry | **Zoom + a base width per orientation.** Zoom is now scheduled into the drawing layer. Settled 2026-09-11: per-orientation width means two *display scales* over one canonical layout width, not two layout widths — line breaks never change, so rotation cannot drift ink. |
| `Page.swift` | **Text-anchored ink.** Wanted for its own sake, not just as a drift fix. Anchor each stroke to an `NSTextLocation` plus an offset, translate the group on relayout. Its own phase. |
| `ContentView.swift` | **Folders.** A flat date-sorted list does not survive a semester. Touches the model, so settle it before more migrations pile up. Brings a folder-level run destination with it. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** `g142` and `python313`, chosen because the site has 1,197 compilers and no "latest" alias. A retired id still shows the code with the compiler pane complaining, so this is a maintenance item, not a risk. |
| Responder chain | **One undo stack, or two.** The canvas's chain runs through the text view, which vends its own undo manager — verify on device. |
| `PageDetailView.swift` | **The macOS editor.** Still a plain `TextEditor` — no fences, no highlighting, no ink. |
| `Storage.swift` | **iCloud sync.** CloudKit via SwiftData, deferred past MVP by design. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms. Do the same before choosing how often ink gets serialised.
- **Isolate risk.** Spike the hard part standalone. A failed spike costs an
  afternoon; a failed integration costs a week.
- **Settings travel together.** `TextRewritingPolicy` groups five traits into
  one type with one `apply(to:)` so they cannot drift. The drawing toggle has
  six and should use the same shape.
- **Degrade, don't crash.** `Storage` falls back to an in-memory store and says
  so. Corrupt drawing data should give an empty canvas and a warning, and must
  never overwrite what's on disk.
