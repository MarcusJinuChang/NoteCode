# NoteCode development timeline

Reconstructed 2 Nov 2026 from git history (450 commits on `main`), the merged
pull requests (#1 to #123) and the plans in `docs/archive/`. It says *when*
and *in what order*; *why* lives in the design notes (`docs/design/`, indexed
in AGENTS.md) and the archived plans. Status and what is left are in
`docs/ROADMAP.md`.

## At a glance

| When | Phase | PRs |
|---|---|---|
| 25 Jul | Project created from Xcode's SwiftData template | — |
| 15–22 Aug | Phases 0–2: page model, fence parser, TextKit 2 editor, syntax colour | #1–#4 |
| 29 Aug–12 Sep | Text model restructure, performance, Run/Copy buttons | #5–#11 |
| 13 Sep | The note page: hotbar, text/ink modes, Letter pages, view modes, zoom, debug launch | #12–#14 |
| 19 Sep–3 Oct | Drawing layer on PaperKit, ink persistence, device pass | #15–#22 |
| 3–8 Oct | Organising and shipping basics: folders, pins, search, print/PDF, lock, privacy manifest | #23–#30 |
| 8–13 Oct | UI design v2, nine phases | #31–#45 |
| 12–15 Oct | v3: finish v2 for TestFlight, eight phases | #46–#55 |
| 15–18 Oct | Roadmap steps 5–10, model frozen, iPhone and Duo, tip jar | #56–#72 |
| 18–20 Oct | Text system overhaul, six phases | #73–#80 |
| 24–25 Oct | Feedback streams | #81 |
| 26–29 Oct | 1.0 plan: streams B, O, S, T, W, L, R, P in two waves | #82–#109 |
| 29 Oct–1 Nov | QC passes, submission prep, release fixes and polish | #110–#123 |
| 1 Nov | Submitted to App Review (iPad, iPhone, Duo) | — |

## July–August: the editor

- **25 Jul.** Initial commit from the Xcode template; navigation stack and
  signing set up the same day.
- **15 Aug — Phase 0** (#1). The template's model replaced by a `Page`
  scaffold: a page is text plus ink, not a list of blocks.
- **21–22 Aug — Phases 1–2** (#2–#4). A pure fence parser and a TextKit 2
  editor that draws a fenced span as a code region while it is still being
  typed; editing hardened at region boundaries; syntax colour through
  HighlightSwift.
- **29–30 Aug** (#5–#8). Code blocks get identity and the text gets a
  document AST (`DocumentNode`). Fixes: a storage crash, language-gated
  highlighting, merged code panels. Restyling had cost 600ms a keystroke
  (#7), the first of many performance passes; colour carried onto the
  character being typed (#8).

## September: the page and the ink

- **5 Sep — in-app execution dropped** (#9). Every option needed a paid API,
  a VPS sandbox or a slow WebAssembly runtime; Run would open a compiler site
  instead. The planning docs moved into the repo. (Reversed for 1.0, below.)
- **11–12 Sep** (#10, #11). Panel seams and colour alignment fixed;
  per-orientation page width settled as two display scales; Run and Copy on
  every code block.
- **13 Sep — the note page** (#12–#14). The hotbar, text and ink modes
  (input ownership, not visibility), fixed page geometry, outline;
  Letter-sized pages, three view modes (seamless, compressed, print), pinch
  zoom; the debug launch options. The view-switch bug of this day is why the
  debug report exists, and Xcode's cloned simulators stopped launching
  (`-parallel-testing-enabled NO` since).
- **19–20 Sep — PaperKit** (#15). Chosen over a bare `PKCanvasView` on
  19 Sep; the drawing layer built on iOS and macOS 27. visionOS dropped.
- **23–26 Sep** (#16–#20). Page breaks, a hotbar freeze, finger drawing,
  orientation at creation; the edit menu's plural delegate; ink saved with
  the note (#18); sharper rendering, cheaper typing, code-block bars moved
  under the ink (#19); a simulator device pass (#20).

## Early October: a usable app

- **2–3 Oct** (#21–#25). Pinned hotbar arrows, eraser sizes, custom colours,
  Pencil gestures. **Drawing layer declared done 3 Oct.** Folders on a
  versioned model, pinning and sorting, Get Info.
- **7–8 Oct** (#26–#30). Autocorrect for prose but not code, search and find
  in note, the privacy manifest, print and PDF, text lock.
- **8 Oct.** Builds sign with the paid team (N454V8HV9J) again (#37).

## 8–13 October: UI design v2

Brief written 7 Oct (`docs/archive/ui-design-v2-implementation.md`), one
phase per PR:

| Phase | PR | What |
|---|---|---|
| 1 | #31 | Accent and syntax colours |
| 2 | #34, #36 | The page against its surround; keyboard covers rather than resizes (#33) |
| 3 | #35 | The note header |
| 4 | #39 | Hotbar text tools, floating ink options row |
| 5 | #40 | Backticks shown only while a block is edited |
| 6 | #42 | Settings |
| 7 | #43 | The app icon, drawn by a script |
| 8 | #44 | Note list and first run |
| 9 | #45 | Shortcuts, edit menu, pointer |

Alongside: **ink bent at page breaks** (#38, 10 Oct) cost too much per
stroke and was reworked in #41 the next day, which also moved stroke capture
off the main thread (`InkCapture`) and set the `MarkupOrderedSet` rules in
AGENTS.md.

## 12–15 October: v3, finishing v2 for TestFlight

Brief 12 Oct (`docs/archive/ui-design-v3-implementation.md`), target
TestFlight 17 Oct, iPad only.

| Phase | PR | What |
|---|---|---|
| 1 | #46 | Recently Deleted, folder identity, Duplicate |
| 2 | #48 | Title screen, Home, thumbnails, reopen at the last page |
| 3 | #49 | Writing with Markdown markers hidden |
| 4 | #50, #51 | Code: languages, keys row, indentation |
| 5 | #52 | Insert into ink, note templates |
| 6 | #53 | Outline, page badge, per-note text size, text options row |
| 7 | #54 | Share, Export All, Import, one editor per note |
| 8 | #55 | Settings rows, toasts, Reduce Motion |

- **15 Oct.** No old notes to preserve before the App Store release: old-note
  support cleared out (#57).

## 15–18 October: roadmap steps, the model frozen, iPhone

- Link taps (#56); editable accent and Add Page (#58); nested folders by
  drag and drop (#59); the page fills the window (#60); room around code
  blocks (#61); coloured and sized text (#62–#64; #62/#63 first merged into
  dead stacked branches, recovered by #64); PDF colours on a dark device
  (#65); caret height (#66); page follows the hotbar's dock (#67).
- **17–18 Oct — model frozen as version 1** (#68), pinned by
  `ModelFreezeTests`.
- iPhone and folded Duo layouts (#69, #71); the list's foot with a StoreKit
  tip jar (#70); privacy policy filled in (#72).

## 18–20 October: text system overhaul

Plan 18 Oct (`docs/archive/text-system-overhaul.md`): text should behave as
in Obsidian, with any text resizable.

| Phase | PR | What |
|---|---|---|
| 1 | #73 | Any size for any text, one size control |
| 2 | #74 | A nesting inline parser |
| 3 | #75 | Formatting per character |
| 4 | #77 | A typing style |
| 5 | #79 | Paste and copy with formatting |
| 6 | #78 | Underline, highlight, quotes, rules, H4–H6 |

- **19 Oct.** macOS build fixed (#76); AGENTS.md split into `docs/design/`.
- **23 Oct.** The Duo launched (iOS 27.1).

## 24–25 October: feedback streams

#81 (`docs/archive/feedback-plan.md`): the Select tool, drawn icons, paper
styles, the on-device assistant (Explain Code, Summarise Note), one list.

## 26–29 October: the 1.0 plan

Plan 26 Oct, one file per stream (`docs/archive/release-1.0/`). Run in the
app came back as a Pro feature, executed on hosted Judge0 through our proxy,
never on the device.

| Stream | PRs | What |
|---|---|---|
| B — bugs | #85, #86, #92, #93 | Home excerpt, icon pencil, pixel eraser crash (28 Oct) |
| T — text | #82, #95 | Instant undoable size changes, hotbar rearranged |
| L — LaTeX | #83, #96, #102, #105–#108 | Parser to PDF; SwiftMath added 28 Oct |
| W — window | #84, #99, #101, #104 | Scroll owned by `PageView`, sheet look, no Liquid Glass |
| S — sidebar | #87, #94 | Drag to Recently Deleted, shorter menu |
| O — objects | #88, #97 | Selection after Insert, smooth resize |
| R — run | #89, #90, #100, #103 | Runner layer, Cloudflare proxy (deployed 28 Oct), Run panel, wiring |
| P — Pro | #91, #98, #112 | Subscription, paywall and AI gate, banner ads with consent; Google Mobile Ads added 28 Oct |

Wave 1 merged 28–29 Oct; wave 2 (#94–#108) through the integration branch
#109 on 29 Oct.

## 29 October–1 November: release

- **QC** (29 Oct): ecosystem and readiness (#110), cohesion (#111), bugs
  (#113). R5: privacy policy, support page, submission text (#114). F1:
  finish 1.0 (#115).
- **30 Oct.** Ecosystem QC fixes: paywall, ad privacy, first Run (#116).
  The choice of where code runs removed (#118): a compiler site is only the
  fallback when a run can't happen.
- **31 Oct.** Home ad width and narrow layout (#117); docs cleanup (#119);
  support address (#120); paper styles removed; device family widened to
  iPhone and iPad.
- **1 Nov.** Polish batch (#121); ads wait for the store before asking for
  consent (#122); iPhone and the Duo named in 1.0.1 (#123). **Submitted to
  App Review**, released automatically on approval.
- **2 Nov.** Open: an App Store rating prompt after a note closes (#124).

## Pace

| Month | Days with commits |
|---|---|
| July | 1 |
| August | 4 |
| September | 9 |
| October | 24 |
| November (to the 2nd) | 1 |

From #25 (3 Oct) on, nearly every change was one PR off `main`, written by
an agent from a brief; the briefs and plans are in `docs/archive/`.
