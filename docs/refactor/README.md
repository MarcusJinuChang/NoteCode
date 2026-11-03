# Plan: refactor, then split the repo

Written 2 Nov 2026, with 1.1.0 (4) in App Review, from a read of the whole
codebase, the docs and the last full test run (29 Oct). Run by **Sonnet 5.5
(high) sessions, one per PR, each reviewed by a second Sonnet session**
before Marcus merges. The groundwork it builds on is
`git show f552d11:docs/refactoring.md`.

This file is the index: rules, decisions, Marcus's part, the order and how
to start a session. Briefs are in the stream files, so a session reads this
file's Rules and its own brief, nothing else.

| Stream | File | Ships in |
|---|---|---|
| 0. The ground: hygiene, scripts, baseline | [0-ground.md](0-ground.md) | 1.1.1 |
| 1. Structure: folders, pure moves, dead code | [1-structure.md](1-structure.md) | 1.1.1 |
| T. Tests | [T-tests.md](T-tests.md) | T1–T4 and T9 in 1.1.1, the rest in 1.2.0 |
| F. Fixes | [F-fixes.md](F-fixes.md) | F1–F4 in 1.1.1, F5 on in 1.2.0 |
| Update 2: seams and types | [update-2.md](update-2.md) | 1.2.0, briefs expanded when it starts |
| The split | [split.md](split.md) | after 1.2.0 ships |
| What to do differently | [lessons.md](lessons.md) | — |

## Decisions (2 Nov)

1. **Two updates.** 1.1.1 (about two weeks): the safety net, the folder
   structure, the cheap fixes and the bugs from Marcus's device pass. 1.2.0
   (about three weeks more): the extension seam, the types out of the big
   files, performance. Then the split.
2. **The public repo starts with fresh history.** Today's
   `MarcusJinuChang/NoteCode` becomes the private `NoteCode-AppStore` with
   all history and PRs #1–#123; a new public `NoteCode` starts from one
   clean commit.
3. **Apache-2.0** for the public repo, with a NOTICE that the name and icon
   are not licensed.
4. **The public build** is the notes app without ads, Pro, Run in the app,
   the AI features or the tip jar. It keeps Run through a compiler site
   (`CodeDestination`), which needs no server. The run proxy stays private.
5. **The privacy URL never breaks.** `https://marcusjinuchang.github.io/NoteCode/privacy`
   is compiled into the build in review (`AppInfo.privacyPolicy`), so the
   pages move to a user site before the repo goes private (split.md › S1).
6. **The model stays frozen.** No stored attribute changes in either update;
   `paperStyle` and `runDestination` wait for a version 2.

## Starting a session

**Implement** (one fresh Sonnet 5.5 high session, new worktree off `main`):

    Run /refactor-wp implement <ID>. The brief is in docs/refactor/<file> › <ID>.

**Review** (another fresh Sonnet session, after the PR is open):

    Run /refactor-wp review <PR number> --post

`--post` puts the verdict on the PR as one comment, where the implementing
session (or Marcus) reads it; without it, the verdict stays in chat. The skill is `.claude/skills/refactor-wp/SKILL.md`. The same loop is also
available as the subagents `wp-implementer` and `wp-reviewer`
(`.claude/agents/`), for a session that hands steps out itself; spawn the
implementer with a worktree.

A bug from Marcus's list (F1) uses the same command with the bug's text in
place of an id: `Run /refactor-wp fix "<what goes wrong, and where>"`.

## Rules

Usage is limited and has to last both updates, so:

- **One fresh session per PR**, and a second fresh session reviews it. Don't
  continue a finished session into the next step.
- **Read only what the brief names**: this section, the brief, the design
  note and files it lists. AGENTS.md is loaded already. No sweep of the
  codebase, no subagents inside a session.
- **Refactor PRs change no behaviour**: no stored attribute, settings key or
  default, nothing on screen, no `features.md` edit. A behaviour change found
  on the way goes in the PR description as a finding and becomes its own fix
  PR. Fix PRs (stream F) start with a test that fails without the fix, and
  update their `features.md` row.
- **One PR per brief, off `main`**, titled `<ID>: …`. Never stacked. A brief
  marked *two commits* is a pure move first (checked by
  `scripts/verify-move.sh` once it exists), then the change.
- **Moving code to another file breaks `private`.** Loosen it to `internal`
  member by member, and list them in the PR. A section that needs more than
  about five is a type, not an extension: stop and say so.
- **Tests: the suites the brief names plus a build**
  (`-only-testing:NoteCodeTests/<Suite>`, `-parallel-testing-enabled NO`).
  Once `scripts/check.sh` exists, run it before opening the PR; the full
  suite runs once a wave on `main` (Marcus or an agent, `check.sh --full`).
  Keep tool output short: summaries, not logs.
- **Traps** (AGENTS.md › Implementation requirements). Before touching an
  area, read its line there. The ones a refactor breaks most easily:
  `.layoutManager`; `nativeUTF8`; walking and building a `MarkupOrderedSet`;
  ink saved only from `onInkChanged`, `commitInk()` before reading ink and
  `await` in tests; `PKInk.inkType`; `drawingData` after a deletion, and
  deletions saving at once; fences detected while typing (fast typing, paste,
  mid-fence edits); one layer owns touches; action bars placed from the
  viewport, and their buttons need a real tap test; `DocumentUITextView`'s
  stored properties Optional (its initialiser skips property initialisers);
  settings that move together in one type with `apply(to:)`.
- **Performance.** A brief marked *perf* runs the perf suites before and
  after and puts both numbers in the PR. More than 10% worse is a stop.
- **No simulator UI automation** past one launch with the debug launch
  options and a screenshot. Touch, Pencil, drag and drop and feel are
  Marcus's, on the iPad, from the checklist lines the session gives in chat
  (not in the repo).
- **Stop and ask** when the acceptance criteria can't be met as written.
- **Don't edit this README or another stream's file.** Where the build
  differs from the brief, say so in the PR. Marcus updates the plan between
  waves.
- AGENTS.md's house rules: stage files by name, never `git add -A`; never
  touch `project.pbxproj` or `Info.plist` (stop and ask); the PR description
  is for anyone viewing the project.

## Marcus's part

Now, alongside wave 1:

- **The device pass (0A).** Walk `docs/ipad-test-checklist.md` on build 4
  from TestFlight, signed in with a sandbox tester: purchase, Run and real ad
  units can't be checked any other way (ROADMAP › In App Review, 4). Every
  bug goes in one list; each becomes an F1 session.
- **Hygiene (0B)** with a session's help: say yes to the worktree and branch
  list it shows you, and turn on *Automatically delete head branches* in the
  repo's settings.
- **Optional:** run `/fewer-permission-prompts` once, so sessions don't stop
  on `xcodebuild` and `git` prompts.

Before the split (required), sooner is better:

- **Make build 4 reproducible (0F).** The version, build number, platforms
  and signing that went to App Review exist only in your working tree; a
  session's worktree builds version 1.0 (1). Commit them, or better, put
  them in an xcconfig, and tag `v1.1.0-4`.

Each wave: merge the reviewed PRs, do the device lines the sessions gave
you, run `scripts/check.sh --full` on `main` (or ask a session to).

## Order

Within a wave, steps on different files run at once; two sessions at a time
is the comfortable most for the usage limit.

**Update 1 (1.1.1)**

- **Wave 1:** 0B → 0C1 → 0C2, then 0D. Alongside: T1, F2.
- **Wave 2:** 1A alone (nothing else open while files move). Needs T1 (the
  test paths) and 0D (a baseline taken before the move).
- **Wave 3:** 1B1–1B9 two at a time; T3 → T4; F3 (after F2: same file);
  2S1 (after T1: same file).
- **Wave 4:** 1C, 1D, F4, T9, and F1 as the device list arrives.
- **Release:** `check.sh --full`, perf against the baseline, Marcus's device
  lines, then build number, archive and submit.

Overlaps to watch: F2, F3 and F4's line numbers all touch
`DocumentTextView.swift`, one at a time. T1 and 2S1 both edit
`SettingsTests.swift`. T3 touches every test file's `@Suite` line, so it
runs alone among test-heavy steps, after 1A has moved the tests.

**Update 2 (1.2.0)** and **the split**: see their files. Update 2's briefs
are expanded from update-2.md when it starts, against the code as 1.1.1
left it.
