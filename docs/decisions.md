# Decisions

**What this is.** Every decision that shaped the app, one line each, with
the reason, and the reversal with its reason when there was one.
**Read it when** you are about to re-argue something, or reverse it.
**Last checked:** 7 Nov 2026.

A reversal gets a new line; the old one stays and points to it. "Why then"
is what was true when it was decided; "why now" is what changed. A line
with "reason not recorded" is a debt: fill it from memory if you can.
A decision that needs more than a line gets an entry under
[Entries](#entries), newest first, and its row points there.

| Date | Decision | Why | Status |
|---|---|---|---|
| 25 Jul 2026 | TextKit 2 editor, SwiftData, one continuous page with ink over it | The spec: an Obsidian-style page, not blocks | standing |
| 29 Aug 2026 | Run cut from the MVP | Every route was a paid API, a VPS running untrusted code or a multi-MB WASM runtime with a 4s cold start; nobody runs code in a lecture | reversed 26 Oct |
| 19 Sep 2026 | PaperKit over a bare `PKCanvasView` | Shapes, images and text boxes on the same canvas; PencilKit tools still drive it (`archive/phase-drawing-layer.md`) | standing |
| 19 Sep 2026 | iOS and macOS 27.0 only; visionOS dropped | PaperKit's floor; one less platform to verify | standing |
| 13 Sep 2026 | The toggle switches input ownership, not visibility | Both layers always drawn; one takes touches (AGENTS.md) | standing |
| ~15 Oct 2026 | Sign in with Apple dropped from 1.0 | Reason not recorded. Likely: nothing in the app needed an account once group notes were deferred | standing; see 3 Nov |
| 15 Oct 2026 | No old notes kept working before the release | No users yet; migrations and legacy paths cost sessions | expired 1 Nov (version 1 shipped) |
| 17 Oct 2026 | Model frozen as version 1, pinned by `ModelFreezeTests` | Shipping it; any attribute change is a new schema version (`design/the-model.md`) | standing |
| 18 Oct 2026 | Text behaves as in Obsidian; any text resizable | Marcus, from using the app | standing |
| 26 Oct 2026 | Run returns, Pro only, on hosted Judge0 through our Cloudflare proxy, never on the device | The 1.0 plan records how (decisions 4, 6, 7) and not why the 29 Aug reasons stopped applying. Fill in: was it the paywall needing a feature, or the cost question being answered by Judge0's pay-per-run? | standing; reason incomplete |
| 26 Oct 2026 | Free is the whole notes app; Pro is no ads, Run and AI; $4.99 a month, no trial | `archive/release-1.0/README.md` 7, 8 | standing |
| 30 Oct 2026 | No choice of where code runs; a compiler site is only the panel's way out | One path to verify; the choice confused the privacy story (#118) | standing |
| 31 Oct 2026 | Paper styles removed; text alignment later instead | Built 13 Oct and 24 Oct, removed 15 Oct and 31 Oct; the offset in compressed and print layout was never explained (`design/paper-styles.md`) | standing; see the queue |
| 31 Oct 2026 | iPhone and the Duo in the first release | Device family widened; the layouts existed since 17 Oct | standing |
| 2 Nov 2026 | Two updates (1.1.1, 1.2.0), then a public Apache-2.0 `NoteCode` with fresh history and a private `NoteCode-AppStore` | `refactor/README.md` › Decisions | standing; the two updates became one, 7 Nov |
| 3 Nov 2026 | Friend and own Pro access through App Store subscription offer codes (free, up to a year per code), not a key in the app | No code, no review risk, `ProStatus` already honours the subscription; re-issue yearly. A key in the proxy only if that proves annoying | proposed |
| 3 Nov 2026 | Apple accounts (Sign in with Apple) wait for a feature that needs a server (group notes, comments) | iCloud sync needs no sign-in and gives the user what "an account" feels like | proposed |
| 3 Nov 2026 | One live plan at a time, with an appetite and a cut line; a weekly check (`/weekly`) | `retrospective-2026-11.md` | proposed |
| 6 Nov 2026 | `Text/Core` gets a test-only Swift package, not a real one | Pure tests in seconds with `swift test`, with no `public` and no project edit ([entry](#6-nov-2026-textcore-gets-a-test-only-package-not-a-real-one-accepted-built)) | standing |
| 6 Nov 2026 | 2P4 gets an app seam (`NoteNavigation`), not a UI test | Unit tests in the Fast plan; a UI test runs only under `--full` ([entry](#6-nov-2026-2p4-gets-an-app-seam-not-a-ui-test)) | standing |
| 7 Nov 2026 | In print layout, ink stays clipped to each sheet's body | Print layout previews paper; the PDF matches ([entry](#7-nov-2026-in-print-layout-ink-stays-clipped-to-each-sheets-body)) | standing |
| 7 Nov 2026 | Page breaks push whole paragraphs; existing ink may drift | Typing ~100ms → ~5ms a keystroke; few notes affected a day after launch ([entry](#7-nov-2026-page-breaks-push-whole-paragraphs-existing-ink-may-drift)) | standing; release-notes line |
| 7 Nov 2026 | The next upload is 1.2.0, build 5; 1.1.1 is never released | 1.1.1 never shipped alone, and everything planned for 1.1.1 and 1.2.0 is on `main`, so one update carries both. The live build is tagged `v1.1.0-4` | standing |

## Entries

Newest first: what was asked, what was decided, and where the detail is.

## 7 Nov 2026: page breaks push whole paragraphs; existing ink may drift

Question (F5, PR 226): typing near the top of a long paged note cost about
100ms a keystroke, because page breaks were exclusion paths. Pushing whole
paragraphs past a break with paragraph spacing takes it to about 5ms, but a
paragraph that used to split at a break now starts the next page, so text
in an existing note moves down while its ink stays. The shift adds up down
the note: modelled at about 32pt by page 2, 170pt by page 10 and 340pt by
page 20 for 1–3 line paragraphs, more for longer ones; code and lists
barely move.

Decided (Marcus): merge and accept the drift. 1.1.0 had been live about a
day, so few notes have ink beside paragraphs that cross a break; keeping
the old layout for them would need a new schema version and the slow path
back. Say so in the release notes.

Detail: [design/pages.md](design/pages.md).

## 7 Nov 2026: in print layout, ink stays clipped to each sheet's body

Question (found by T10's `inkAcrossPageBreak` snapshot): a stroke that
crosses a sheet's margins or the gap between sheets is drawn only inside
each sheet's body. Draw it over the margins instead?

Decided (Marcus): keep it clipped. Print layout is a preview of paper, and
the PDF matches what's on screen; paper has no gap, so ink there could only
be dropped or split anyway. The stroke itself is stored whole, so seamless
and compressed modes still show all of it. The snapshot pins this.

## 6 Nov 2026: 2P4 gets an app seam, not a UI test

Question (refactor 2P4): how are navigation, create and delete-with-Undo
tested, when they live in ContentView's and NoteList's private state?

Decided: route A. `NoteNavigation` (`@Observable`, App/NoteNavigation.swift)
owns the selection, the compact path, the columns, the opened search and the
new page, and the create, delete and folder-delete actions; the views hold
one and pass the `ToastCenter` and `ModelContext` in. Landed first as its own
PR with no behaviour change, so the T5 tests drive it as unit tests in the
Fast plan; a UI test would run only under `check.sh --full`. The 2P4 proper
(`NavigationModel`, `NoteActions`) builds on it. Both Undos stay as they are:
the note's reopens, the list's only restores.

Detail: [refactor/2P-page.md](refactor/2P-page.md) › T5 tests for this track.

## 6 Nov 2026: Text/Core gets a test-only package, not a real one (accepted, built)

Question (refactor T11): make `NoteCode/Text/Core` a Swift package so its
pure tests run with `swift test` on the Mac?

Measured: 235 of the folder's ~325 tests compile against Core alone and
pass in a scratch package in 7 to 16 s (22 s clean build), against 20 s of
test time and 199 s of wall clock (build, simulator boot) in Xcode.
Making the app depend on a package would need `public` on 25 types and up
to ~224 members, and a project edit.

Recommended: a root `Package.swift` that compiles the same files in place
under the module name `NoteCode` and runs the same test files, with no
`public` and no project edit; after the 2T text stream settles, and after
`CodeRange`/`CodeLanguage` move into Core and `FenceVisibility` stops reading
`SettingKeys`. Adding the package to the Xcode project stays Marcus's step
(`project.pbxproj`). Marcus accepted option B on 6 Nov.

Built 6 Nov (T11 PR). Two things the measurement did not show, because 2C had
moved files since: Core also needed `CodeBlockTarget` (moved in with
`CodeRange`), the `DocumentStyler` namespace (now declared in
`Text/Core/DocumentLayout.swift` and extended by the editor's half), and
`FormulaValidity`, which asks SwiftMath whether a formula parses. So
`Package.swift` depends on SwiftMath 1.7.3 (the app's version) and compiles
`Formula/FormulaValidity.swift` and `Shared/BoundedCache.swift` in place too;
the clean build is therefore longer than the scratch package's. Run it with
`scripts/core-test.sh`; `check.sh` does first.

Detail and numbers: [refactor/T11-core-package.md](refactor/T11-core-package.md).
