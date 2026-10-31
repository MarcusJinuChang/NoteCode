# NoteCode

An iPad note-taking app for CS coursework — a single continuous, markdown-style
document where regular notes, syntax-highlighted code blocks, math, and Apple
Pencil drawings all live on the same page.

## What it does

- Continuous, scrollable notes with Obsidian-style Markdown: headings, lists,
  checklists, links, quotes, colours and sizes, with the markers hidden away
  from the caret
- Triple-backtick fences become syntax-highlighted code blocks (C++, Java,
  Python, C, JavaScript, Rust, Go, SQL), with Run and Copy in each block's
  corner. Run is part of NoteCode Pro: the block runs on our run service
  (`server/run-proxy`, a Cloudflare Worker in front of hosted Judge0) and the
  output shows in a panel beside the page; nothing is executed on the iPad
- Inline and display LaTeX, drawn in the page and in the PDF
- A PaperKit drawing layer toggles on and off without losing scroll position
  or leaving the page
- Letter-sized pages, portrait or landscape per note, shown seamless, compressed
  or in print layout, with pinch to zoom — line breaks never change with the
  device, its orientation, or the zoom, and print layout is the printed page
- Home, folders, search, Recently Deleted, Markdown import and export, PDF
  sharing; on-device Explain Code and Summarise Note (Pro, Apple Intelligence)
- Free with banner ads; NoteCode Pro ($4.99 a month) adds Run and the AI
  features and removes the ads

## Stack

Swift, SwiftUI, TextKit 2, PaperKit, SwiftData; HighlightSwift, SwiftMath and
Google Mobile Ads. The run proxy is TypeScript on Cloudflare Workers.

## Status

1.0 is built and merged; App Store submission is planned for November 2026,
after the by-hand release steps and a walk through the app on a real iPad.
See [docs/ROADMAP.md](docs/ROADMAP.md).

## Docs

- [docs/ROADMAP.md](docs/ROADMAP.md): status, what is left, after 1.0
- [docs/features.md](docs/features.md): every feature, how it works, its status
- [docs/ipad-test-checklist.md](docs/ipad-test-checklist.md): what still has
  to be seen on a real iPad
- [docs/design/](docs/design/): per-feature design notes (index in
  [AGENTS.md](AGENTS.md))
- [docs/release-1.0/](docs/release-1.0/): submission text and the App Review
  analysis; [docs/site/](docs/site/): the privacy and support pages
- [docs/archive/](docs/archive/): finished plans
