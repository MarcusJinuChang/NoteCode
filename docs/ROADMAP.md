# NoteCode roadmap

Source of truth. The published version at
<https://claude.ai/code/artifact/2490317a-7eaf-44ae-9389-f0fb92d7471a>
is a rendering of this file — edit here, ask for the artifact to be regenerated.

Revised 25 September 2026.

| | |
|---|---|
| Drawing layer due | **10 Oct 2026** (hard stop) |
| Using it day to day | now — ink is saved as of 23 Sep |
| App Store submission | Nov 2026 |
| Second version | AI + feedback, Mar 2027 |

## Where things stand (25 Sep)

Everything up to the drawing layer's toggle is built and merged: the TextKit 2
editor with code blocks, run and copy, Letter-sized pages in three view modes
with pinch zoom, the note page and its hotbar, and a PaperKit canvas that a
finger or the Pencil draws on, with ink undo of its own. 17 pull requests.

- **Ink is saved** (23 Sep, branch `ink-persistence`): half a second after
  drawing pauses, and at once when the note closes or the app leaves the
  screen. It survived a force-quit on the simulator. 410 tests.
- **The iPad pass has started.** First findings (25 Sep): ink and the line
  being typed were drawn at a lower density than the screen, and typing
  stuttered now and then. Both density bugs are fixed and measured on the
  simulator, and a keystroke costs about a third less (branch
  `rendering-sharpness`). Typing near the top of a long note still costs
  about two frames; the rest of that is pagination by exclusion paths.
  Latency, palm rejection and Pencil-versus-finger routing are still to
  judge on the device.
- **Nothing is started for signing in and shipping.** Builds still sign with
  the free Personal Team, whose profiles last seven days. As of 11 Sep the
  paid Developer Program membership wasn't showing on the account. That has
  to be sorted before TestFlight — and before the app can stay on the iPad for
  more than a week at a time.

## Plan

Not set in stone. Once the drawing layer is done, the before-November list
gets planned properly — what fits and in what order — along with a proper UI
design. Using the app for real can start now that ink is saved, and what that
turns up feeds both.

### Now — the drawing layer on PaperKit (to 10 Oct)
See [phase-drawing-layer.md](phase-drawing-layer.md) for the build plan.

| Step | Planned | Status |
|---|---|---|
| 1. Spike | 6–7 Sep | Done |
| 2. Geometry | 8–14 Sep | Done, and grew into pages and view modes |
| 3. The toggle | 15–21 Sep | Done. Left over: code-block buttons and the canvas overlap — see step 3 in the phase doc |
| 4. Saving ink | 22–28 Sep | Done 23 Sep; gate passed on the simulator |
| 5. Device pass | 29 Sep – 10 Oct | Started early, 25 Sep: rendering density fixed, typing cost cut |

**Fallback if it runs long:** the phase doc's cut list — stop adding pages for
ink, then PencilKit's canvas instead of PaperKit's. Saving is never cut.

### Before November — candidates
In the order given, which isn't yet a priority order. Notes only where the
code already has something to say.

1. **Scrolling direction, as a setting** — pages below each other, or side by
   side. The text view scrolls itself, and only vertically: `UITextView`
   forces its content width back to its own (measured 12 Sep). Side-by-side
   pages changes who owns scrolling rather than adding a setting.
2. **Text locking.**
3. **Infinite canvas.** Notes are Letter pages, and ink is stored in page
   coordinates. An unbounded canvas is probably a second kind of note rather
   than a mode of this one.
4. **Note search.** Text is plain in `Page.content`. PaperKit's
   `PaperMarkup.indexableContent` may reach text boxes in ink (untested).
5. **Favouriting / pinning / starring** notes and folders. Folders come first
   — not built yet, see the deferred table.
6. **Note sorting.** The list sorts by date modified, and nothing else.
7. **Note info / properties.**
8. **Printing.** Print layout is already the printed page — see the deferred
   table.
9. **UI polish**, from the UI design.
10. **Accounts and Sign in with Apple.** No backend: as the only login option
    it also sidesteps Apple's rule requiring it alongside third-party sign-in.
11. **TestFlight.** Needs the paid team (see above) and a privacy manifest.
12. **App Store submission.** First submissions bounce on formality, so leave
    review-cycle buffer, not zero margin.

Folders, 5, 6 and 7 all change the `Page` model. Doing them as one migration is
cheaper than four.

### Later
- Note templates
- Note locking
- Note combination / sealing
- Theme and colour selection
- Code sort
- Code syntax
- Group notes and group comments. Both need a server, which nothing else in
  the app does.
- AI — the second version, Dec 2026 to Mar 2027. One or two features tied to
  the actual use case (explain this code block, summarise this page), built on
  real TestFlight usage.
- The macOS editor
- iCloud sync

Scrolling direction, sorting and note info are on both lists: November
candidates that can slip to here.

## Done so far

**Foundations (Jul–Aug).** Swift and SwiftUI basics before touching NoteCode.

**Walking skeleton (Aug).** The `Page` model, a page list, a page editor, and
`Storage` — which degrades to an in-memory store and says so, rather than
crashing on launch when the disk store fails.

**Custom text engine (Aug – early Sep).** Built before the drawing layer, out
of the original order, because it was the phase most likely to sink the
schedule.

- A real `UITextView` on TextKit 2 (`DocumentTextView`)
- Pure, unit-tested fence parsing (`DocumentParser`)
- Fragment-level code panels (`CodeBlockLayoutFragment`) — `.backgroundColor`
  paints per glyph and leaves a ragged right edge
- Async syntax colouring via HighlightSwift, restyling only the changed block
- Debounce went from a guessed 200ms to a measured 20ms

**Run and copy (11 Sep).** In-app execution was cut: every option needed a
paid API, a VPS sandbox, or a multi-megabyte WASM runtime with a four-second
cold start, for a feature nobody uses during a lecture. It came back as a
redirect. Every code block carries run and copy in its top-right corner, and
run opens a free online compiler.

- `CodeDestination` — where a block goes, and how. Compiler Explorer takes the
  whole program in the URL, so the student lands on a finished run; Programiz
  and OnlineGDB can't be prefilled, so the code goes on the pasteboard.
- Per-note choice, app-wide default behind it. Folders slot in between when
  they exist — `RunDestinationPreference.resolve` walks the levels in order.
- The buttons are TextKit 2 viewport-positioned overlays (`CodeBlockOverlay`),
  not attachments, and the text view has to be stopped from eating their taps.

**The note page and pages (12–23 Sep).** Laid out from the 12 September
mockup: a title header with the note list behind ☰, and one hotbar docked
left, bottom or right carrying undo, redo, the text/draw toggle and the current
mode's tools. It replaced `PKToolPicker`. Notes are Letter-sized pages,
portrait or landscape, chosen when the note is made; a view menu shows them
seamless, compressed or as print layout; pinch zoom is a transform on the
scrolling text view, which measured 40 times cheaper per keystroke than a zoom
container.

**The drawing layer, steps 1–3 (19–23 Sep).** PaperKit's canvas inside the
text view's content, so both layers share one scroll position. Ink is stored in
print coordinates and shown on the same words in every mode. A finger draws
unless the canvas is locked to the Pencil, and ink has an undo stack separate
from the text's.

## Deferred work

Referenced by name from `TextRewritingPolicy.swift` and `DocumentTextView.swift`.

| Where | What |
|---|---|
| `TextRewritingPolicy.swift` | **Per-region text rewriting.** All five keyboard traits are `.code` everywhere, so prose loses autocorrect. Plan: `.prose` outside a fence, `.code` inside, with `reloadInputViews()`. |
| `DocumentStyler.swift` | **Markers that recede.** Markdown markers stay visible in `tertiaryLabel`. Hiding them when the caret is elsewhere is the Obsidian behaviour. |
| `PageLayout.swift` | **Printing** (before-November item 8). Print layout is the printed page exactly — `sheet(ofPage:)` times 72/96. A `UIPrintPageRenderer` drawing each sheet's rect of the text view is what's left. A4 is one more paper size. Ink renders through `PaperMarkup.draw(in:frame:options:)`, which is async; whether it stays vector in a PDF context is untested. PencilKit's `draw(in:)` crashed there (18 Sep). |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are exclusion paths, and TextKit 2 then lays out everything below an edit: 34ms a keystroke near the top of a 250-line note on the simulator. If it lags on the iPad, push whole paragraphs with paragraph spacing instead, computed lazily. |
| `PageView.swift` | **Diagonal panning when zoomed in.** The text view scrolls vertically and `PageView` sideways, so a pan picks one. |
| `Page.swift` | **Text-anchored ink.** Wanted for its own sake, not just as a drift fix. Anchor each stroke to an `NSTextLocation` plus an offset, translate the group on relayout. Its own phase. |
| `ContentView.swift` | **Folders.** A flat date-sorted list does not survive a semester. Touches the model, so do it with favourites, sorting and note info (before-November items 5–7), which need it. Brings a folder-level run destination with it. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** `g142` and `python313`, chosen because the site has 1,197 compilers and no "latest" alias. A retired id still shows the code with the compiler pane complaining, so this is a maintenance item, not a risk. |
| `PageDetailView.swift` | **The macOS editor.** Still a plain `TextEditor` — no fences, no highlighting, no ink. |
| `Storage.swift` | **iCloud sync.** CloudKit via SwiftData, deferred past MVP by design. |
| Layout | **iPhone Duo.** Apple's foldable, out 23 Oct 2026, runs standard iOS 27.1, so it's covered by the iPhone target. Apple asks apps to resize with the scene rather than the screen, keep controls out of the fold (`reservedRegions`), and let bars run vertically down the side. Testing needs Xcode 27.1, which carries the Duo simulator. It takes the USB-C Apple Pencil (one report says not until after launch), so ink on any iPhone relies on a finger drawing, which works on PaperKit as of 23 Sep. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms. Ink got the same treatment: 1,000 strokes read back in 29ms, so
  reading as a note opens is fine.
- **Isolate risk.** Spike the hard part standalone. A failed spike costs an
  afternoon; a failed integration costs a week.
- **Settings travel together.** `TextRewritingPolicy` groups five traits into
  one type with one `apply(to:)` so they cannot drift. `EditorMode` does the
  same for the drawing toggle.
- **Degrade, don't crash.** `Storage` falls back to an in-memory store and says
  so. Unreadable ink gives an empty canvas and a warning, and is never written
  over.
- **Check what's on screen, not what the code computed.** The view-switch bug
  of 13 Sep passed a test comparing the scroll offset to page geometry while
  the screen showed the wrong page. The debug launch options report where
  TextKit actually put the lines.
