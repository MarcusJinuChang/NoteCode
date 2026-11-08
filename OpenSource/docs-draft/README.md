<!-- Draft for the public repo (docs/refactor/split.md › S3). scripts/export-public.sh
     copies it to the export's README.md. It assumes S2's layout: Config/Local.xcconfig
     and a project without the ad SDKs. -->

# NoteCode

A note-taking app for iPad and iPhone, made for computer science coursework.
A note is one continuous, scrollable document, written in Markdown, where prose,
syntax-highlighted code blocks, LaTeX and Apple Pencil drawings share the same
page.

This repository is the open-source edition: the whole notes app. The edition
on the App Store is built from this code plus a private part that adds a
subscription, running code on a hosted service, the on-device assistant and
ads.

## What it does

- **Writing.** Obsidian-style Markdown: headings, lists, checklists, links,
  quotes, colours and sizes. The markers hide when the caret is elsewhere.
- **Code.** A triple-backtick fence anywhere in a note becomes a
  syntax-highlighted block (C++, C, Java, Python, JavaScript, Rust, Go and
  SQL), with optional line numbers, a keys row for the symbols code needs, and Copy.
  The highlighting starts before the closing fence is typed. In this edition,
  Run opens the block on a free online compiler: Compiler Explorer, with the
  code in the link, or Programiz, with the code on the pasteboard. Nothing is
  compiled or run on the device.
- **Maths.** Inline `$…$` and display `$$…$$` formulas, drawn in the line and in
  the PDF.
- **Ink.** A PaperKit drawing layer lies over the same page. A toggle hands
  touches to it or back to the text, without moving the page.
- **Pages.** Letter-sized pages, portrait or landscape per note, shown
  seamless, compressed or in print layout, with pinch to zoom. Line breaks
  never change with the device, its orientation or the zoom.
- **Library.** Home, folders, search, templates, thumbnails, Recently Deleted,
  Markdown import and export, PDF sharing.

Notes are stored on the device with SwiftData. This edition makes no network
requests of its own: the only things that leave the app are a compiler site
you choose to open and a mail you choose to send.

## Building it

You need a Mac with Xcode and the iOS 27 SDK.

1. Clone the repository and open `NoteCode.xcodeproj`. Xcode fetches the two
   Swift packages, HighlightSwift and SwiftMath.
2. Create `Config/Local.xcconfig`, which git ignores, with your own team and
   bundle id prefix:

   ```
   DEVELOPMENT_TEAM = <your team id>
   BUNDLE_ID_PREFIX = <a reverse domain of yours>
   ```

   The simulator needs neither; a device needs both.
3. Run the `NoteCode` scheme on an iPad simulator, or on an iPad for anything
   with Apple Pencil: ink latency and palm rejection in the simulator are not
   what a real Pencil gives.

## Testing it

```
scripts/check.sh            # lint, then a build and every unit test but the slow ones
scripts/check.sh --full     # also the slow tests and the UI tests
scripts/core-test.sh        # the pure text core on the Mac, no simulator
```

The tests use Swift Testing. [CONTRIBUTING.md](CONTRIBUTING.md) has the rest:
the scripts, the debug launch options, and how the code is laid out.

## How it is built

Swift and SwiftUI for the app; a TextKit 2 text view
(`NSTextLayoutManager`) for the editor, whose fence detection and Markdown
parsing are pure Swift with no UIKit (`NoteCode/Text/Core`); PaperKit for
ink; SwiftData for storage. The design notes behind each part are in
[docs/design/](docs/design/), and [docs/features.md](docs/features.md) lists
every feature with its status.

## Licence

The code is licensed under the Apache License 2.0 ([LICENSE](LICENSE)). The
name "NoteCode" and the app icon are not; see [NOTICE](NOTICE). The
third-party licences are in `NoteCode/Acknowledgements.txt`.
