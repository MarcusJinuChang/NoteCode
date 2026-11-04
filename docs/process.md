# How a feature gets built

**What this is.** The stages a feature goes through, what each one needs
before the next starts, how Claude sessions fit, and which skills to reach
for. Then the queue after 1.0, with reasons. **Read it when** starting a
feature, or when a plan feels like it is growing. **Last checked:** 3 Nov
2026.

The shape is Shape Up's (basecamp.com/shapeup, free to read): a fixed
appetite, scope cut up front, and a cool-down between plans. It is the one
process book worth your time for this project.

## The stages

| Stage | What exists at the end | Gate to the next | Your time |
|---|---|---|---|
| **Idea** | One line in `NOW.md` › Queue or Parked | You rank it | a minute |
| **Shaped** | A design note (or a section of one): the problem in your words, what exists, the one risk, the appetite, "not in this" | You can say the goal in a sentence and the cut line in another | one session, you reading the result |
| **Planned** | `plans/<name>.md` from the template, under 150 lines | You read it whole and approve; the appetite's dates are in it | 20 minutes |
| **Building** | One PR per step, one fresh session per PR, a second session reviews; at most three open | Every step's PR merged with its device lines reported in chat | the reviews, and merging |
| **On the iPad** | The device lines ticked in `ipad-test-checklist.md`; a TestFlight build | Everything in the plan seen working, or filed as a fix | 30 minutes per week there was a merge |
| **Shipped** | `features.md` rows, the design note, a timeline line, the plan in `archive/`, `NOW.md` updated | `/weekly` confirms | 10 minutes |

Rules that hold at every stage:

- **One live plan.** Shaping the next can overlap the last week of the
  current one; building it cannot.
- **Appetite is 1, 2 or 3 weeks**, chosen before the steps are written.
  Your budget (memory, 21 Aug): two to three hours on a Friday or weekend
  day, under an hour on a weekday. A week is about eight hours of you.
- **Steps are PR-sized:** under about 400 changed lines, one session, one
  area. A step that needs two areas is two steps.
- **Done when is on screen.** "The test passes" is not a done-when; "the
  heading keeps its size after a view-mode switch" is.
- **A decision is a line in `decisions.md`** the day it is made, including
  a cut.
- **Nothing is scheduled that depends on something unshipped.** The queue's
  "needs first" column is the dependency; it is checked, not assumed.

## When the appetite runs out

Ship what is on the iPad. Archive the plan with its "Left out" section
filled. Park the rest in `NOW.md`. Do not extend, and do not start the
next plan the same day: take the cool-down (a week with no plan) to walk
the checklist, fix what it finds, and let the next idea settle before
shaping it.

## Sessions

- **Effort scales with irreversibility.** Sonnet 5.5 high builds a step.
  Opus or Fable shapes a feature, reviews a design, runs a retrospective
  or the weekly. Haiku looks things up.
- **Plan mode for anything over one PR.** Approve the plan before code.
- **One fresh session per PR, in a worktree; a second session reviews.**
  The `refactor-wp` skill's implement/review pair is the pattern; a
  general `/build-step` and `/review-pr` can be copied from it when the
  refactor is done.
- **Ask for the analysis first** (requirements with evidence, trade-offs,
  risks, acceptance criteria, staging). It is in memory; "analysis first"
  is enough to call it up.
- **No subagents unless you ask**, and one session per decision (memory,
  23 Sep). Four sessions at once is the November ceiling.
- **Keep AGENTS.md under 300 lines.** A session reads it every time; a
  design note only when its step names it.
- **Remote Control** from the phone is for reading a session's report
  between classes and saying yes or no, not for steering a build.
- **Give the session the device result.** "I tried it; the lasso lets go
  when I switch tools" is worth more than any simulator run.

## Skills

Installed now, by moment:

| When | Use |
|---|---|
| Monday | `/weekly` (this repo): rewrites `NOW.md`, archives, flags stale files |
| Shaping | `/plan-feature <name>` (this repo): the analysis and a plan from the template. `engineering:architecture` when choosing between technologies (its ADR becomes a `decisions.md` line). `product-management:write-spec` when the feature has a user-facing surface you want described fully |
| Building | `/refactor-wp implement <ID>` for refactor steps; the same shape for plan steps once copied |
| Before merging | `/code-review high` on the PR; `/code-review ultra` for anything touching the editor or ink; `/simplify` on your own branches |
| Tests | `engineering:testing-strategy` once per plan, to say which suites a step needs |
| Debugging | `engineering:debug`, with the debug launch options (AGENTS.md) and the probe habit (memory: several interventions in one run before fixing) |
| Release | `engineering:deploy-checklist` with `release-1.0/R5-submission.md` |
| Design retouch | `design:design-critique` on screenshots; `design:accessibility-review`; `liquid-glass` for the glass question; `figma:figma-swiftui` if you draw in Figma |
| Debt | `engineering:tech-debt` after 1.2.0, to re-rank what the refactor left |
| Docs | `engineering:documentation` for a design note's first draft |
| Learning | `anthropic-skills:learn` after a session, to have what it did explained as a lesson; the `claude-code-guide` agent for "can Claude Code do X" |
| Memory | `anthropic-skills:consolidate-memory` monthly: the project's memory is 25 files and some are stale |
| Waiting | `/loop` to watch a PR's CI or a session; `/schedule` for a routine (the weekly, Monday 8am, in the cloud, if you want it to run without you) |
| Config | `update-config` for hooks (below) |

## Automation worth adding, in order of payoff

1. **CI on every PR** (GitHub Actions, macOS runner, `scripts/check.sh`).
   Eight minutes by hand gets skipped; eight minutes on a runner doesn't
   (`refactor/lessons.md` 6).
2. **A PreToolUse hook that refuses `git add -A`, `project.pbxproj` and
   `Info.plist`.** Turns three paragraphs of AGENTS.md into a check.
3. **`scripts/check-docs.sh`**: every doc has its three header lines; no
   file over its cap; every `features.md` detail link resolves; no live
   plan past its appetite; no "Last checked" over 30 days.
4. **A Stop hook** that lists `features.md` rows for the files a session
   changed, so the row is updated in the same PR.
5. **A pull request template** with: what changed, why, device lines in
   chat (not here), docs rows touched.

## Learning, in the order it will pay

1. **Shape Up** (free online): appetite, shaping, the betting table,
   cool-down. Read the first two parts; skip the rest.
2. **Claude Code's docs** (code.claude.com/docs): CLAUDE.md, plan mode,
   hooks, skills, subagents, worktrees. One evening; most of what you use
   is there.
3. **WWDC: "Meet TextKit 2" (2021) and "What's new in TextKit and text
   views" (2022)**, and **PencilKit's sessions**: the two subsystems you
   will be asked about in an interview.
4. **A Philosophy of Software Design** (Ousterhout): deep modules and
   information hiding, which is what `refactor/lessons.md` 3 and 4 are
   about.
5. **Swift Testing's docs**, since the suite is 1,873 tests and growing.

## The queue, reasoned

What exists, the one risk, the prerequisite, the first step, the appetite.

**2. Pro for you and friends.** Subscription offer codes in App Store
Connect give a custom code a free period of up to one year, up to 25,000
redemptions, with no app code: `ProStatus` already honours the subscription.
Make one custom code, hand it out, re-issue each year. A key typed into the
app and honoured by the proxy is the alternative: real code in Settings,
the paywall, the AI gate, the ad gate and the Worker, a path around StoreKit
that App Review can question, and it needs the extension seam (2X) first.
Take the codes; revisit only if the yearly re-issue annoys. An hour, no
plan file. (Apple's help: developer.apple.com/help/app-store-connect/
manage-subscriptions/set-up-offer-codes.)

**3. Model version 2 and the object system.** `design/object-system.md`
has the design and two spikes; the roadmap calls its storage "the one
format change after release". Bundle with dropping `paperStyle` and
`runDestination` so there is one migration. Needs 1.2.0: 2X and 2T rewrite
the files the object code lives in. The risk is the migration on real
notes: test it on notes exported from your iPad, not on seeded ones. First
step: re-read the spikes against the post-refactor code and decide the
storage format as a `decisions.md` line before any step. Three weeks.

**4. iCloud sync.** The model is shaped for CloudKit; no migration of its
own. The risk is `drawingData` in external storage and ink bytes under
sync, and that a synced schema is far harder to change than a local one,
which is why version 2 lands first. Two weeks, then a week on two devices
(iPad and the Mac simulator) before it is called done.

**5. Paper styles and text alignment.** Removed twice; the offset in
compressed and print layout was never explained. Step 1 is a one-session
probe to find that cause with several interventions in one run (memory:
the debugging approach), not a rebuild. Alignment moves lines, so it meets
ink anchoring: decide first whether text-anchored ink comes with it or
whether alignment leaves ink behind, as typing does today. Two weeks after
the probe.

**6. The Mac and the iPad + Mac pair.** The Mac editor is a plain
`TextEditor`: no fences, colour or ink. The editor is `UITextView` on
TextKit 2, so Mac Catalyst gets it, and PaperKit, nearly as is; a native
`NSTextView` port is a rewrite. A one-day spike of Catalyst decides
(`engineering:architecture`, one `decisions.md` line). "Dual" is sync plus
the Mac app, so it needs 4. Three weeks after the spike.

**7. Infinite canvas.** AGENTS.md's open question: ink is stored in page
coordinates, so an unbounded canvas is probably a second kind of note, not
a mode, and it reopens who owns scrolling. It needs the object storage (3)
and is the most speculative item here. Shape it only after 3 ships, and
let the shaping decide if it is a 1.3 headline or a 2.0 one.

**8. Design retouch.** Not one big pass at the end. A `design-critique` on
the screenshots of each shipped feature, with its fixes as steps in the
next plan, and one two-week pass before 1.2.0 with a canvas as v2 and v3
had, but a brief capped at 150 lines a phase.

**Apple accounts.** Sign in with Apple gives the user nothing without a
server: sync is iCloud and needs no sign-in. It comes with group notes or
comments, if those are ever chosen. One line in `decisions.md` (3 Nov), not
a queue item.
