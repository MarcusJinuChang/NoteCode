# Looking back at 1.0

**What this is.** How the 1.0 build went, read from the git history (498
commits, 123 PRs), the 93 revisions of `ROADMAP.md`, the briefs in
`docs/archive/` and the memory of the sessions. Each finding has its
evidence, then what to do instead. The code-side lessons are in
`refactor/lessons.md` and are not repeated here; this is the planning side.
**Read it when** you are about to plan something and feel the pull to add
one more phase. **Last checked:** 3 Nov 2026.

## The short version

- **The date never moved. What "1.0" meant moved five times.** On 8 Aug the
  MVP was a free app with Sign in with Apple and a handful of users, shipping
  mid-October with November as buffer. What shipped on 1 Nov was a
  subscription, ads, a run service with its own server, LaTeX, iPhone and the
  Duo, and no sign-in, no TestFlight, no device pass.
- **Every plan was written within days of the last one finishing, and each
  was bigger.** None was ever closed with "that is enough".
- **Docs grew 47 times in two months** (272 lines on 5 Sep, 12,873 on 3 Nov)
  because everything went in and nothing came out until the archive folder
  appeared on 2 Nov.
- **The rush was the last ten days.** Week 44 merged 27 PRs; 24 Oct had 48
  commits; the wave 2 integration PR was 83 files and 5,470 added lines.
- You were not winging it for lack of discipline. The system had no place
  for "not now", no closing step, and no weekly checkpoint with yourself. It
  rewarded re-planning, which felt like progress and produced 93 roadmap
  revisions.

## What the history shows

### 1. Scope grew while the date stayed

| Date | What 1.0 meant | Where it is written |
|---|---|---|
| 8 Aug | Free app, Sign in with Apple, TestFlight, a few users. Phase 6 ships 13–31 Oct; November is buffer | Session memory of the 7-phase roadmap |
| 29 Aug | Run cut: "don't re-propose before the MVP ships" | Same |
| 23 Sep | Twelve "before-November candidates", "not completely set in stone" | `ROADMAP.md` at 4fa3c69 |
| 7 Oct | UI design v2: nine phases | `archive/ui-design-v2-implementation.md`, 623 lines |
| 12 Oct | v3, "v2 finished": eight phases, TestFlight Sat 17 Oct | `archive/ui-design-v3-implementation.md`, 699 lines |
| 15 Oct | Sign in with Apple leaves the roadmap. No line says why | `ROADMAP.md`: last mention 3 Oct, none from 15 Oct |
| 18 Oct | Text system overhaul: six phases, "text behaves as in Obsidian" | `archive/text-system-overhaul.md` |
| 21 Oct | 31 feedback items become a plan | `archive/feedback-plan.md` |
| 26 Oct | The 1.0 plan: Run returns as Pro through a proxy and Judge0; subscription; ads; LaTeX; eight streams | `archive/release-1.0/README.md` |
| 1 Nov | Submitted. TestFlight never sent; sandbox pass not done; 237 lines never seen on an iPad | `ROADMAP.md`, `ipad-test-checklist.md` |

The TestFlight target of 17 Oct was the one intermediate date. It was not
met and was never replaced with another; the next fixed point was the
submission itself.

### 2. Decisions were reversed without a recorded reason

- **Run.** Cut 29 Aug with three reasons (cost, a sandbox to host, cold
  start) and a fourth about value ("nobody runs code during a lecture").
  Back on 26 Oct. The 1.0 plan records *how* it would work (decisions 4, 6,
  7) and not why the August reasons stopped applying. Maybe they did; the
  point is that nothing says so, and the privacy label, the proxy and the
  first-Run notice all followed from it.
- **Paper styles.** Built 13 Oct, postponed 14 Oct, removed 15 Oct, rebuilt
  24 Oct, removed 31 Oct. The design note says the cause of the first
  offset was never found and that the choices were "decided without
  Marcus". Four PRs of work, twice.
- **Sign in with Apple.** In every plan from August to 3 Oct, gone on 15 Oct
  with no line. It is now back on your list as "Apple accounts", so the
  question gets argued again from nothing.

A reversal is fine. An unrecorded one means paying for the argument twice.

### 3. The roadmap was a journal, not a plan

93 revisions. Its headings changed shape six times (Phases; Where things
stand; Before TestFlight and Before submission; Status and What is left).
By 19 Oct it held six jobs in one file: status, what is left, after 1.0,
decisions, deferred work, habits. Nothing in it said what to do this week,
and a 213-line file with six jobs invites re-reading and re-planning over
doing the next boring step. `refactor/lessons.md` 8 says the same about
status living in four files.

### 4. The briefs were too long to hold in your head

The v2 brief was 623 lines, v3 699, the drawing layer 628. Writing them for
an agent was right. The cost was that no version existed that you could
read in two minutes, so you approved on trust and found out on the iPad.
The 31-item feedback list of 21 Oct is what that looked like, and it became
the next plan.

### 5. Verification ran behind building, and the gap compounded

"Built, never seen on the real thing" was a roadmap section from 19 Oct on.
It never emptied; it became the 237-line checklist. Each unverified feature
produced the next plan's fix items (stream B, the 21 Oct list, the QC
passes). Simulator automation stood in for the iPad, and you time-boxed it
yourself on 3 Oct because it was eating sessions.

### 6. A third of the project happened in the last ten days

| Week | PRs merged |
|---|---|
| W41 (5–11 Oct) | 17 |
| W42 (12–18 Oct) | 29 |
| W43 (19–25 Oct) | 6 |
| W44 (26 Oct–1 Nov) | 27 |

When 27 PRs merge in a week and a 5,000-line integration PR lands, nobody
has read all of it. The ~400 isolation warnings, the six files at 7,200
lines, the two tests that silently stopped testing and the whole refactor
plan come from that week and the one before.

### 7. Documentation had no lifecycle

| Date | Lines of docs |
|---|---|
| 5 Sep | 272 |
| 4 Oct | 878 |
| 15 Oct | 2,896 |
| 21 Oct | 6,413 |
| 29 Oct | 10,196 |
| 3 Nov | 12,873 |

Until 2 Nov every finished plan sat beside the live one. AGENTS.md reached
227 KB on 19 Oct, loaded into every session, and had to be split. The
pointer table of 36 design notes is what remains. `features.md` lists 95
built features, 1 partial, 2 planned and 5 ideas: it is a record of what
exists and was never a queue, and the queue had no home of its own.

## Why it happened

- **Fixed date, growing scope.** A fixed date with a variable scope is the
  right shape for a deadline, but only if the scope is cut at the start.
  Here scope was added at the end, every time.
- **Agents made adding cheap.** A nine-phase brief is one evening; the PRs
  then appear. The cost moved to review, device checks and your head, where
  nothing made it visible. Nothing in the process charged anything for
  adding a phase.
- **Nowhere to put "later".** Without a parking lot, an idea went into the
  current plan or was lost, and the plan was safer.
- **Checkpoints were with agents (per PR) and with Apple (submission),
  never with yourself.** No weekly moment to ask "is this still the plan?".
- **ADHD and a journal-shaped roadmap.** Re-planning is novel and feels like
  progress; the next step is boring. A file that mixes status and plans
  feeds that. A one-screen card with "this week", "not this week" and
  "queue" does not.

## What to do instead

The rules, in one place. The system that carries them is `README.md`
(where things live) and `process.md` (how a feature is built).

1. **One live plan at a time.** A new plan starts only when the previous is
   closed: shipped, or cancelled with one line in `decisions.md`.
2. **Scope is cut at the start.** A plan has an appetite (1, 2 or 3 weeks)
   and a "Not in this plan" list written before step 1. When the appetite
   runs out, ship what is verified and park the rest. Never extend.
3. **Every reversal is a dated line** in `decisions.md`: what, why then,
   why now.
4. **Done means seen on the iPad.** A PR reports its device lines; you tick
   them the week it merges; a TestFlight build goes out every week there
   was a merge.
5. **The plan you can read in two minutes is the real one.** Agent briefs
   may be long. The plan file is capped at 150 lines and the week's card
   (`NOW.md`) at 60.
6. **A weekly 20 minutes, same day, run by `/weekly`.** It updates `NOW.md`,
   archives what finished, and lists what is stale. This one habit keeps
   the rest honest.
7. **At most three PRs open; `main` is the integration branch.** No
   integration PRs, no stacking.
8. **Every doc is live or archived**, starts with what it is, when to read
   it and when it was last checked, and has a size cap.
