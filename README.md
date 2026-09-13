# NoteCode

An iPad note-taking app for CS coursework — a single continuous, markdown-style
document where regular notes, syntax-highlighted code blocks, and Apple Pencil
drawings all live on the same page.

## What it does (planned)

- Continuous, scrollable notes with Obsidian-style markdown formatting
- Triple-backtick code fences become syntax-highlighted code blocks, with any
  language highlight.js recognises — and copy or share to run them elsewhere
- A PencilKit drawing layer toggles on and off without losing scroll position
  or leaving the page
- Letter-sized pages, portrait or landscape per note, shown seamless, compressed
  or in print layout, with pinch to zoom — line breaks never change with the
  device, its orientation, or the zoom, and print layout is the printed page

## Stack

Swift, SwiftUI, TextKit 2, PencilKit, SwiftData

## Status

In development. The text engine is working — fence detection, syntax
highlighting, and copy/share on a code block. The drawing layer is next; see
AGENTS.md for the geometry and scrolling decisions it depends on.

## Planning docs

The roadmap and phase plans live in [docs/](docs/) as markdown — that is the
source of truth. The published artifact versions are renderings of those files.
