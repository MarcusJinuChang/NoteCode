# Plan: Full Release 1.0

Written 26 Oct 2026 from Marcus's 1.0 list, read against `ROADMAP.md`,
`features.md`, `feedback-plan.md`, `design/latex.md`, `design/object-system.md`
and the code. Run by **Sonnet 5.5 (high) sessions, one per PR**. It replaces
`feedback-plan.md` as the working plan; both move to `docs/archive/` in F1.

This file is the index: rules, decisions, Marcus's part and the order. Each
stream's briefs are in their own file, so a session reads only this file's
Rules and its own brief.

| Stream | File | PRs |
|---|---|---|
| B. Bugs and the app icon | [B-bugs.md](B-bugs.md) | B1 Home excerpt, B2 icon pencil |
| O. Objects | [O-objects.md](O-objects.md) | O1 popup on insert, O2 resize cost |
| S. Sidebar | [S-sidebar.md](S-sidebar.md) | S1 drag to Recently Deleted, S2 shorter menu |
| T. Text size and hotbar | [T-text.md](T-text.md) | T1 instant size, no alert; T2 hotbar |
| W. Note window | [W-window.md](W-window.md) | W1 spike, W2 page on a background, W3 home/sidebar control and animation, W4 no glass |
| L. LaTeX | [L-latex.md](L-latex.md) | L1 … L7, all in 1.0 |
| R. Running code | [R-run.md](R-run.md) | R1 runner, R2 proxy, R3 panel, R4 wiring, R5 policy |
| P. Pro and ads | [P-pro.md](P-pro.md) | P1 subscription, P2 paywall and AI gate, P3 ads |
| F. Finish | [F-finish.md](F-finish.md) | F1 |

## Starting a session

Paste this, with the step's id and file:

    Implement <ID> of the NoteCode 1.0 plan. Read docs/release-1.0/README.md
    › Rules, then docs/release-1.0/<file> › <ID>, and only the design notes
    and files that brief names. Open a PR to main titled "<ID>: …", and end
    by giving me that step's iPad checklist lines in chat.

## Rules

Usage is limited and has to last to the release, so:

- **One fresh session per PR.** Don't continue a finished session into the
  next step.
- **Read only what the brief names**: this section, the brief, the one design
  note it lists, the files it lists. No sweep of the codebase, no reading every
  design note, no subagents. AGENTS.md is loaded already.
- **Tests: only the suites the brief names** (`-only-testing:NoteCodeTests/<Suite>`,
  `-parallel-testing-enabled NO`), plus a build. The full suite runs once, in F1.
- **No simulator UI automation** past one launch and a screenshot with the
  debug launch options. Touch, Pencil, drag and drop and feel are Marcus's,
  on the iPad, from the checklist lines the session hands back in chat (not
  in the repo).
- **Measure before optimising** (T1, O2): one `sample` or timing run, the
  number in the PR, the fix, the number again.
- **Stop and ask** when the acceptance criteria can't be met as written.
- **Don't edit this README or another stream's file.** Where the build
  differs from the brief, say so in the PR; F1 brings the docs up to date.
  Your own design note and `features.md` rows are updated in the PR, as
  AGENTS.md says.
- AGENTS.md's house rules: stage files by name; never touch
  `project.pbxproj` or `Info.plist` (stop and ask); PR description for anyone
  viewing the project; PRs target `main`, never a stacked branch.

## Decisions (26 Oct)

Numbered as the briefs refer to them.

1. **Headings are size presets** of the same size system, derived from the
   body size, so a size change scales them in one pass (T1).
2. **Home and sidebar are one joined control** at the top left, with two new
   icons drawn in code (W3).
3. **No text size or line spacing alert**, anywhere. A size change is
   undoable instead (T1).
4. **Run's output appears in a panel beside the page (option D)**, with Keep
   in Note, and the page stays free to move and zoom (R-run.md › The format).
5. **Nothing to merge first.** `claude/admiring-merkle-a364ab` (PDF code
   colours on a dark device) and `claude/vibrant-mestorf-90734c` (the Mac's
   Home button placement) are already in `main` by another route, and
   `claude/roadmap-pro-plan` (ROADMAP step 21) is superseded by P-pro.md.
   All three can be deleted.
6. **Judge0 CE, hosted, pay-per-use Basic plan**, behind our proxy
   (R-run.md › What it costs).
7. **Free is the whole notes app**, with no limit on notes or pages. **Pro**
   is no ads, in-app Run and the AI features; free users have none of them
   (P-pro.md).
8. **Pro is $4.99 a month.** No yearly plan, no free trial. More AI features
   and a higher price come after 1.0.
9. **Nothing in LaTeX is cut**: L1 to L7 ship in 1.0. It is one of the main
   reasons for this release.

## Wave 0: Marcus, by hand

- **SwiftMath 1.7.3** added to the NoteCode target, as `design/latex.md` ›
  "Adding the package" says (it touches `project.pbxproj`). L2 onwards wait
  for it; L1 doesn't.
- **For R:** a RapidAPI account on Judge0 CE's Basic plan (pay per run, card
  on file, nothing up front), and a Cloudflare account with `wrangler`
  logged in. The key goes into the Worker as a secret by you, never into a
  session or a commit.
- **For P** (start now: Apple and Google review on their own clocks):
  - App Store Connect: the Paid Applications agreement (already needed for
    tips) and a subscription group "NoteCode Pro" with one product,
    `com.marcus.NoteCode.pro.monthly`, at $4.99, with its display name and
    description. Submitted with the build.
  - AdMob: an account, the iOS app, and two banner ad unit ids. Until the
    app is live and linked, AdMob serves limited ads; sessions use Google's
    test ids throughout.
  - The **Google Mobile Ads** Swift package added to the NoteCode target
    (`project.pbxproj`).
  - `Info.plist` gains `GADApplicationIdentifier`,
    `NSUserTrackingUsageDescription` and Google's `SKAdNetworkItems`. Your
    working tree has an uncommitted `Info.plist` change, so you make these
    edits, or tell P3's session it may. (That change also drops
    `ITSAppUsesNonExemptEncryption`; check it's set elsewhere before an
    upload.)

## Order

Streams are file-disjoint so their sessions can run at once; within a
stream, one PR at a time. Three or four sessions at once is the comfortable
most for the usage limit.

- **Wave 1:** B1 → B2, O1 → O2, S1 → S2, T1 → T2, W1, L1, R1, R2, P1.
- **Wave 2:** W2 → W3 → W4, L2 → L7 (L2 after the package; L3 after T1),
  R3 (after W2) → R4 (after P1), P2 → P3 (after W3 and the package).
- **Wave 3:** R5 (policy for Run and ads together, after R4 and P3), F1.

Overlaps to watch: T1 deletes the alert block in `PageDetailView`, which W2
also edits, so T1 merges before W2. T2 removes glass from `TextOptionsRow`,
W4 from the rest. L3 and T1 both touch styling. R3 sits beside the page W2
restructures. P3's banner and W3's transition both touch `HomeView`.

If usage runs low, the home animation (W3) and R4's compile-error links wait
for 1.1. Nothing in L, R or P is cut.
