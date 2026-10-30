# L. LaTeX

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## L1–L7. LaTeX

Built exactly as `design/latex.md` › "Build steps (one PR each)" says; every
"Provisional" decision there is taken as decided unless Marcus edits it in
wave 0. One session per step, brief = that step's paragraph plus the
sections of `latex.md` it names.

- **L1 parser** (pure, no package): any time.
- **L2 validity and aliases**: after the package is in.
- **L3 inline layout**: after T1 merges.
- **L4 display blocks**, **L5 editing** (popover, Backspace, undo),
  **L6 PDF and thumbnails**: in order.
- **L7 info, outline, copy, paste**: last in the stream. Ships in 1.0;
  nothing in L is cut (decided 26 Oct).

Each step's tests are listed in `latex.md`. `features.md` gets a LaTeX row at
L3 and is completed at L6. The app-size growth (the 7.1MB font bundle) goes in
the L2 PR description.
