# AGENTS.md

## Project overview

An iPad note-taking app for computer science coursework. A single continuous,
scrollable document (Obsidian-style) where:

- Regular text is typed and formatted like a normal markdown note.
- Triple-backtick fences (` ``` `) anywhere in the flow become syntax-highlighted,
  runnable code blocks — not separate files, just inline sections of the same page.
- A drawing layer (Notability-style) sits over the same page and can be toggled on
  to draw handwritten notes/diagrams with Apple Pencil, then toggled back to
  text/code editing without losing scroll position or leaving the page.

Primary use case: CS133 (C++) and general algorithm practice (Java/Python), so
code blocks need to support at least C++, Java, and Python.

## Tech stack

- **Swift + SwiftUI** — app shell, navigation, state management.
- **TextKit 2** (`NSTextLayoutManager`) — custom text editor that detects code
  fences as you type and renders that span as a distinct, non-plain-text region.
- **PencilKit** (`PKCanvasView`) — transparent overlay canvas for ink, sharing
  scroll position with the text layer. Only one of (text layer, drawing layer)
  should own touch input at a time, controlled by the toggle.
- **Piston API** (https://github.com/engineer-man/piston) — remote code
  execution for the "run" action on a code block. No local interpreters —
  send code + language, get stdout/stderr back.
- **SwiftData** — persistence for documents (text content + serialized
  `PKDrawing` data per page). iCloud sync is a later-stage concern, not MVP.

## Conventions

- Prefer SwiftUI-native state (`@State`, `@Observable`) over introducing
  Combine unless a specific async stream genuinely needs it.
- Keep the text/code parsing logic (fence detection, language tagging)
  separate from rendering — parsing should be pure and testable without
  SwiftUI in the loop.
- Never block the main thread on a Piston API call — always async/await,
  and show a loading state on the code block while a run is in flight.
- Drawing data (`PKDrawing`) is serialized independently per page and should
  never be re-encoded on every keystroke of the text layer — only on drawing
  layer changes.

## Architecture notes

- A "page" is the persistence unit: text content + an array of drawing
  strokes anchored to scroll position, not a list of discrete blocks.
- The toggle switches *input ownership*, not *view visibility* — both layers
  are always rendered/visible; only one accepts touches at a time.
- Code fence detection should be resilient to incomplete fences while typing
  (i.e. don't require the closing ``` to exist before showing highlighting).

## Build/test

- Open in Xcode, run on iPad simulator or a physical iPad with Apple Pencil
  for realistic latency testing (simulator ink input isn't representative).
- No CI/build commands defined yet — update this section once a scheme and
  test target exist.

## Known tricky areas (flag before touching)

- TextKit 2 fence-to-code-region conversion — this is the hardest and most
  failure-prone part of the app. Changes here need manual testing against
  fast typing, pasting, and mid-fence edits.
- Overlay touch handoff between `PKCanvasView` and the text view — easy to
  accidentally let both layers capture touches at once.
