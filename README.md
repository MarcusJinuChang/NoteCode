# NoteCode

An iPad note-taking app for CS coursework — a single continuous, markdown-style
document where regular notes, syntax-highlighted code blocks, and Apple Pencil
drawings all live on the same page.

## What it does (planned)

- Continuous, scrollable notes with Obsidian-style markdown formatting
- Triple-backtick code fences become syntax-highlighted code blocks, with any
  language highlight.js recognises — with run and copy in each block's corner,
  where run opens a free online compiler rather than executing anything
- A PaperKit drawing layer toggles on and off without losing scroll position
  or leaving the page
- Letter-sized pages, portrait or landscape per note, shown seamless, compressed
  or in print layout, with pinch to zoom — line breaks never change with the
  device, its orientation, or the zoom, and print layout is the printed page

## Stack

Swift, SwiftUI, TextKit 2, PaperKit, SwiftData

## Status

In development. The text engine, run and copy on code blocks, pages and view
modes, pinch zoom, the note page and drawing — with a finger or the Pencil,
saved with the note — all work. Submission is planned for November 2026 — see
[docs/ROADMAP.md](docs/ROADMAP.md).

## Planning docs

The roadmap and phase plans live in [docs/](docs/) as markdown. 
The published artifact versions are renderings of those files.
