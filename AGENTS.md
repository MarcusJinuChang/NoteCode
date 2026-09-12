# AGENTS.md

## Project overview

An iPad note-taking app for computer science coursework. A single continuous,
scrollable document (Obsidian-style) where:

- Regular text is typed and formatted like a normal markdown note.
- Triple-backtick fences (` ``` `) anywhere in the flow become syntax-highlighted
  code blocks — not separate files, just inline sections of the same page. Each
  block carries a run and a copy button in its top-right corner, and run hands
  the block to a free online compiler rather than executing anything locally.
- A drawing layer (Notability-style) sits over the same page and can be toggled on
  to draw handwritten notes/diagrams with Apple Pencil, then toggled back to
  text/code editing without losing scroll position or leaving the page.

Primary use case: CS133 (C++) and general algorithm practice (Java/Python), so
code blocks need to support at least C++, Java, and Python.

Running code in-app is deliberately out of scope. Every option needed either a
paid API, a self-hosted sandbox on a VPS, or a multi-megabyte WebAssembly
runtime with a four-second cold start — all for a feature whose value is lowest
exactly when the app is being used, since nobody runs code during a lecture.

The run button is a redirect, not an execution: `CodeDestination` opens a free
online compiler, and nothing in the app ever runs a program. Two ways the code
gets there, and the difference decides how the button behaves:

- **In the link.** Compiler Explorer encodes a whole session in the URL path, so
  the student lands on a finished run. Verified against the live site; the
  compiler ids are pinned and are a maintenance item, since the site has no
  "latest" alias and 1,197 compilers.
- **On the pasteboard.** Programiz and OnlineGDB keep the editor's contents in
  the browser, with no way to be handed a program, so the code is copied and the
  student pastes on arrival. This is the fallback for every other site, which is
  what makes an arbitrary custom URL a usable destination.

Compiler Explorer does not get Java: its executor compiles into a fixed
filename, so `public class Main` fails there with an error about the file name.
A destination that can't take a language hands the block to one that can rather
than failing, which is why `RunRequest` reports where it actually went.

The destination resolves through levels, most specific first — page, then
app-wide. Folders slot in between as one more element of the array `resolve`
walks, not another branch.

## Tech stack

- **Swift + SwiftUI** — app shell, navigation, state management.
- **TextKit 2** (`NSTextLayoutManager`) — custom text editor that detects code
  fences as you type and renders that span as a distinct, non-plain-text region.
- **PencilKit** (`PKCanvasView`) — transparent overlay canvas for ink, sharing
  scroll position with the text layer. Only one of (text layer, drawing layer)
  should own touch input at a time, controlled by the toggle.
- **SwiftData** — persistence for documents (text content + serialized
  `PKDrawing` data per page). iCloud sync is a later-stage concern, not MVP.

## Conventions

- Prefer SwiftUI-native state (`@State`, `@Observable`) over introducing
  Combine unless a specific async stream genuinely needs it.
- Keep the text/code parsing logic (fence detection, language tagging)
  separate from rendering — parsing should be pure and testable without
  SwiftUI in the loop.
- Drawing data (`PKDrawing`) is serialized independently per page and should
  never be re-encoded on every keystroke of the text layer — only on drawing
  layer changes.
- When several settings have to move together, they live in one type with one
  `apply(to:)` rather than being set individually at the call site, so they
  cannot drift apart. `TextRewritingPolicy` is the reference example.

## Architecture notes

- A "page" is the persistence unit: text content + an array of drawing
  strokes anchored to scroll position, not a list of discrete blocks.
- The toggle switches *input ownership*, not *view visibility* — both layers
  are always rendered/visible; only one accepts touches at a time.
- Code fence detection should be resilient to incomplete fences while typing
  (i.e. don't require the closing ``` to exist before showing highlighting).

## Page geometry, orientation, and zoom

The document should lay out at a fixed page width, not at the device width.
Ink is stored in page coordinates, so anything that reflows the text while
leaving strokes where they are — rotation, Split View, a different device —
points annotations at the wrong words, and there is no repairing it after the
fact. A fixed column means rotation changes the margins, not the line breaks.

Wanted, not yet built:

- **A base width per orientation** — portrait narrower, landscape wider, so
  neither orientation wastes the screen.
- **Pinch to zoom in and out**, the way Notability does it.

Those two requirements pull against ink stability in different amounts, and
the difference decides how much work they are:

- If "a base width per orientation" means two *display scales* over one
  canonical layout width, nothing re-wraps, ink never drifts, and it is the
  same mechanism as pinch zoom — essentially free once zoom exists.
- If it means two *layout widths*, the text re-wraps on every rotation and ink
  drift stops being an edge case. That version is only safe on top of
  text-anchored strokes: anchor each stroke to an `NSTextLocation` plus an
  offset from that paragraph's fragment origin, then translate the stroke group
  on relayout (`PKDrawing.strokes` is mutable and `PKStroke` has a `transform`).

**Decided, then reversed on measurement:** the zoom container was to be built
before the drawing layer. Measured first, on 12 Sep, it cost TextKit 2 its lazy
layout — see "Who owns scrolling".

**Decided 2026-09-11:** "a base width per orientation" means two *display
scales* over one canonical layout width — not two layout widths. Line breaks
are a function of that one width, so every iPad size, both orientations, Split
View and Stage Manager all wrap identically, a note authored on one device
opens the same on another, and ink stays on the words it was drawn over. It is
also the same mechanism as pinch zoom, so it costs almost nothing once the zoom
container exists.

What that buys is paid for in one place: landscape shows the same text larger
rather than showing more of it. Filling the extra width is then a choice
between raising the display scale and letting the margins grow, and both are
safe for ink, so "neither orientation wastes the screen" becomes a preference
rather than a risk. Below some width — a narrow Split View — scaling down to
fit stops being readable, so the scale wants a floor with horizontal scrolling
past it rather than shrinking indefinitely.

**Built 12 Sep** (`CanvasGeometry`, `PageView`): the page lays out at 700pt and
is drawn at the page area's width over 700, held between 0.75 and 1.25 — margins
grow past the ceiling, and the page scrolls sideways below the floor. The hotbar
reserves room on both sides whichever edge it is on, so the scale is a function
of the window alone and moving the bar never resizes the text.

`GeometrySpike` (branch `spike/page-geometry`) answered this and the question is
now closed. Keep the branch for the drift demonstration it also gives.

**Also decided:** text-anchored ink is wanted for its own sake, not only as a
mitigation. That changes the calculus — once strokes are anchored to text, two
layout widths stop being dangerous, so the orientation question becomes a
preference rather than a risk. Sequencing still matters: anchoring is its own
phase and does not fit before the App Store submission.

## Who owns scrolling

The `UITextView` scrolls itself, and the canvas is a subview of its content, so
both layers share one `contentOffset` with no synchronisation code at all.

That was going to change for pinch zoom: an outer scroll view owning scroll and
zoom, with a non-scrolling text view and the canvas in one shared container.
Measured on 12 Sep before building it, a text view with scrolling disabled has
the whole document as its TextKit 2 viewport — 477ms per keystroke on a 500-line
note against 11ms scrolling, and 5.5 seconds at 2000 lines. So instead:

- The display scale is a transform on the scrolling text view, which leaves the
  viewport alone (9ms per keystroke on the same note).
- `PageView`, around it, scrolls only sideways, when the page is wider than its
  area.
- The text container's width is pinned, never tracked. A text view first sized
  while scaled below 1x takes its line width from the shrunken frame, and
  portrait and landscape then break lines differently.
- Text is drawn at the density it is shown at, by raising `contentScaleFactor`
  through the text view's subviews after each layout pass.
- Pinch zoom, when it is built, is a user factor on the same transform.

## The note page

Laid out from the 12 September mockup.

- **Header.** ☰ opens the note list, which slides over the page
  (`.prominentDetail`) instead of narrowing it, so opening the list never
  re-wraps the note. The title sits below; the run destination and account
  icons sit on the right. Account is a placeholder until Sign in with Apple.
- **Hotbar.** One bar, dragged by its grip to the left, bottom or right edge,
  snapping to whichever is nearest (`HotbarDock.nearest`). Undo, redo and the
  text/draw toggle never move; after the divider come the current mode's tools.
  The page keeps both side edges clear, whichever one the bar is on, so moving
  it never resizes or shifts the page.
  It replaces `PKToolPicker` — see docs/phase-drawing-layer.md.
- **Formatting is markdown in the source.** A button computes a `TextEdit` in
  `MarkdownFormatting`, which is pure and defers to the parsers, so a button
  never writes markers the styler won't draw. `NoteEditor` applies the edit
  with `replace(_:withText:)`, the path typing takes, so it is undoable and
  restyles like typed text. Assigning `.text` loses undo, the selection, and
  the delegate callback that writes the change back to the page.
- **`NoteEditor` is the bridge.** SwiftUI owns the hotbar and UIKit owns the
  text view, and neither can reach the other. The hotbar talks to `NoteEditor`,
  and the text view registers with it.

## Organising notes

A flat, date-sorted list of pages does not survive a semester of coursework.
Folders are wanted: pages grouped by class — CS133, algorithm practice — rather
than one undifferentiated stream.

Not yet built, and it touches the model, so it is worth settling before the
drawing layer adds a second thing to migrate. The likely shape is a `Folder`
`@Model` with a to-many relationship to `Page` and a nullable inverse, so a page
can sit at the top level while folders are optional.

## Build/test

Scheme `NoteCode`; targets `NoteCode`, `NoteCodeTests`, `NoteCodeUITests`.
One SwiftPM dependency: HighlightSwift 1.1.0.

    xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'

Tests use Swift Testing (`@Suite` / `@Test`), not XCTest. Suites that touch
UIKit are wrapped in `#if canImport(UIKit)` and marked `@MainActor`.

Run on a physical iPad with Apple Pencil for anything involving ink — latency
and palm rejection in the simulator are not representative.

## Implementation requirements

- TextKit 2 fence-to-code-region conversion — changes here need manual testing
  against fast typing, pasting, and mid-fence edits.
- Overlay touch handoff between `PKCanvasView` and the text view — exactly one
  layer accepts touches at any moment.
- Reading `.layoutManager` anywhere on the text view silently downgrades it to
  TextKit 1 and leaves `textLayoutManager` nil, with no error to say why.
- A button inside a `UITextView` is not simply a button. When one of the text
  view's own recognisers claims the touch, UIKit cancels the one the button was
  tracking and it never fires, so `DocumentUITextView` refuses to let those
  recognisers begin on an action bar. Changes near this need a real tap test —
  `sendActions` in a unit test cannot see the conflict.
- The action bars are positioned from TextKit 2's *viewport*, never from the
  whole document. Asking for a fragment further down forces layout all the way
  to it, which is the lazy layout the editor is built on.

## Open questions

Things that are decided in someone's head but not in the code. Move them up
into a section above once they are settled.

- Orientation widths: two display scales, or two layout widths? Run
  `GeometrySpike` on `spike/page-geometry` to see both before deciding.
- Where text-anchored ink lands in the schedule. Wanted for its own sake, but
  it is a phase, not a step, and November is committed.
- Folders: does a page live in exactly one folder, or can it be in several?
  One-to-many is far simpler and probably right for coursework.
- Undo: text and ink in one shared undo stack, or two separate ones? The
  hotbar's arrows go through `NoteEditor`, which picks the stack, so this is a
  choice rather than something the responder chain settles. PencilKit may
  still register ink on the text view's stack through that chain — verify on
  device before choosing.
- Per-region text rewriting: `TextRewritingPolicy` is `.code` everywhere today,
  costing prose its autocorrect. Switching per region is designed but unbuilt.
