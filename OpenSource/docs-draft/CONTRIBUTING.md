<!-- Draft for the public repo (docs/refactor/split.md › S3). scripts/export-public.sh
     copies it to the export's CONTRIBUTING.md. -->

# Contributing to NoteCode

Thank you for looking. Issues and pull requests are welcome. For anything
larger than a fix, open an issue first, so we can agree on the shape before you
spend time on it.

## Before you start

- [docs/features.md](docs/features.md) lists every feature, how it works and
  its status. Check it before writing code, so you know whether a thing exists.
- Each area has a design note in [docs/design/](docs/design/) with the
  decisions and what was measured. Read the one for the area you are changing.
- [docs/decisions.md](docs/decisions.md) records what was decided and what was
  reversed, and why.

## Building and testing

Requirements: Xcode with the iOS 27 SDK, and the `iPad Pro 13-inch (M5)`
simulator (or set `NOTECODE_SIM` to another simulator's name). See the README
for signing.

| Script | Does |
|---|---|
| `scripts/check.sh` | Lint, the text core's `swift test`, then a build and the Fast test plan (every unit test but the `.perf` ones). Run it before a pull request |
| `scripts/check.sh --full` | Also the Full plan and the UI tests, from a clean build, and compares the warning count with `docs/refactor/baseline.md` |
| `scripts/check.sh --only <Suite>` | Just those suites |
| `scripts/core-test.sh` | `swift test` on the Mac for `NoteCode/Text/Core`, with no simulator |
| `scripts/lint-traps.sh` | Greps for the known traps (below); exceptions go in `scripts/lint-allow.txt` with a reason |
| `scripts/perf.sh --compare docs/refactor/baseline.md` | The cost tests; fails if one is more than 10% worse than its recorded line |
| `scripts/debug-launch.sh` | Relaunches the Debug build with `-debug-` arguments and prints what is on screen |
| `scripts/make-icons.swift` | Draws the app icons; edit it, never the PNGs |
| `scripts/refresh-ce-ids.sh` | Checks the pinned Compiler Explorer compiler ids |

Raw `xcodebuild`, if you need it:

    xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode \
      -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
      -parallel-testing-enabled NO

Tests use Swift Testing (`@Suite`, `@Test`), not XCTest. Suites that touch UIKit
are wrapped in `#if canImport(UIKit)` and marked `@MainActor`. A test waits
with `await`, never a sleep or a run-loop spin.

Anything involving ink needs a real iPad with Apple Pencil: latency and palm
rejection in the simulator are not representative. Say in the pull request
what you checked on a device.

### Debug launch options

Debug builds take `-debug-` arguments that put the app in a known state and
report what is on screen, for example:

    scripts/debug-launch.sh --device "iPad Air 13-inch (M4)" -- \
      -debug-note pages -debug-orientation landscape -debug-mode print \
      -debug-page 4 -debug-report

`-debug-note pages|code|empty` opens a built-in note in an in-memory store, so
the simulator's own notes are untouched; `NoteCode/Debug/DebugLaunchOptions.swift`
lists the rest.

## How the code is laid out

`NoteCode/` is an Xcode synchronized group: a file's folder is its place in
the target, and nothing is listed in the project. Tests mirror it in
`NoteCodeTests/`.

| Folder | Holds |
|---|---|
| `App/` | The scene, `AppExtensions`, navigation, commands, Welcome |
| `Model/` | `Page` and `Folder` (SwiftData), `Storage` |
| `Library/` | Home, the note list, folders, search, templates, thumbnails, Recently Deleted |
| `NotePage/` | A note's page: the scroll view that owns the layers, the editor, header, hotbar, `EditorFeature` |
| `Text/Core/` | The pure core: parser, snapshot, formatting, layout planning. No UIKit or SwiftUI |
| `Text/Editor/`, `Text/Layout/` | The TextKit 2 text view and its layout fragments |
| `Code/` | Code-block overlay and bars, languages, keys row, indent, highlighter, `CodeDestination` |
| `Ink/` | Canvas, codec, capture, tools, selection |
| `Formula/` | LaTeX |
| `InOut/` | PDF, Markdown import and export |
| `Settings/` | `SettingKeys` and the settings pages |
| `Debug/` | The `-debug-` launch options (Debug builds only) |

### How a feature plugs in

The app is the general app plus an edition. `NoteCodeScene` is the whole app;
an edition's `@main` hands it an `AppExtensions` (`App/AppExtensions.swift`).
This repository's edition hands it `.none`. The App Store edition adds its
features through the same doors, from code that is not in this repository:

- app-level things through a member of `AppExtensions`, whose default does
  nothing;
- things in a note's editor through an `EditorFeature`
  (`NotePage/EditorFeature.swift`): actions, a top-bar item, a side panel, Run.
  `EditorServices` is everything a feature may ask of the text view.

So a change to general behaviour belongs here, and a new door (a member, a
service) can be added here when a feature needs one.

## Rules that keep it working

These are traps that have each cost a bug. `scripts/lint-traps.sh` catches the
ones a grep can see.

- Never read `.layoutManager` on the text view: it silently drops the view to
  TextKit 1. Position anything from TextKit 2's viewport, never by laying out
  the whole document.
- Parse `(textView.text ?? "").nativeUTF8`, not `textView.text`, which costs a
  message send per character.
- Keep parsing pure: `Text/Core` compiles without UIKit (`swift test`).
- Walk a `MarkupOrderedSet` with `for … in`, and build one with a single
  `append(contentsOf:)`; indexing, `map` and per-element inserts are linear
  each, so quadratic over the set.
- Never read `PKInk.inkType` from a stroke the canvas made; use
  `InkContent.inkIdentifier`. The pixel eraser's ink has no case and traps.
- Ink is saved only for changes the reader made (`PageView.onInkChanged`).
  Showing or moving ink for the app's own reasons must not save it.
- Exactly one of the text layer and the ink layer takes touches at a time.
- The stored model's version 1 is frozen by its hashes (`ModelFreezeTests`):
  a changed attribute is a new schema version. Read
  `docs/design/the-model.md` first.
- When several settings must move together, they are one type with one
  `apply(to:)` (`TextRewritingPolicy` is the example).
- Prefer `@State` and `@Observable` over Combine.

## Pull requests

- One change per pull request, based on the newest `main`.
- Say what changed and why, and how you checked it: `scripts/check.sh`'s last
  lines, and what you tried on a device.
- A behaviour fix comes with a test that fails without it.
- If you add, change or remove a feature, update its rows in
  `docs/features.md` in the same pull request.
- By contributing you agree that your contribution is licensed under the
  Apache License 2.0, as the rest of the code is (section 5 of the licence).
