# The docs: a map

**What this is.** Where every kind of fact lives, and the rules that keep
the docs readable. **Read it when** you don't know where to look or where
to write. **Last checked:** 7 Nov 2026.

Five minutes a week keep this true: `/weekly`, Mondays.

## Where to look

| You want | Read | Who updates it | Cap |
|---|---|---|---|
| What I'm doing this week, what's next, what's parked | [NOW.md](NOW.md) | you, Mondays, via `/weekly` | 60 lines |
| Whether something exists in the app, and how it works in one line | [features.md](features.md) | the PR that changes the feature | one line per feature |
| Why a feature works the way it does | `design/<area>.md` | the PR | 250 lines; older reasoning goes to `archive/` |
| What was decided, and what was reversed and why | [decisions.md](decisions.md) | the session that decides | one line per decision; an entry under the table when a line isn't enough |
| The rules every session follows (traps, build, shipping) | [../AGENTS.md](../AGENTS.md) | rarely | 300 lines |
| How a feature goes from idea to shipped, and how to use Claude for it | [process.md](process.md) | rarely | 200 lines |
| The plan for the one feature being built | `plans/<feature>.md` from [plans/_template.md](plans/_template.md) | the planning session; you approve | 150 lines |
| The refactor (finished 7 Nov; Phase 5, the split, is still to come) | [refactor/README.md](refactor/README.md) | you, between waves | |
| What was done when | [timeline.md](timeline.md) | at the end of each plan | |
| The long status and the ranked list after 1.0 | [ROADMAP.md](ROADMAP.md) | folds into NOW, decisions and timeline when the next update ships | |
| What to try on a real iPad | [ipad-test-checklist.md](ipad-test-checklist.md) | a PR adds lines; you tick them | |
| How 1.0 went and what to do differently | [retrospective-2026-11.md](retrospective-2026-11.md), [refactor/lessons.md](refactor/lessons.md) | | |
| Finished plans and old reasoning | `archive/` | `/weekly` moves them | |
| The privacy and support pages | `site/` | with the release | |

Private things (marketing, keys, friends' names) never go here:
`/Users/Marcus/Documents/NoteCode-private/`.

## Rules

1. **Every file starts with three lines:** *What this is.* *Read it when.*
   *Last checked: date.* A file whose last check is over 30 days old is
   suspect, and `/weekly` says so.
2. **Live or archived.** A file is in `docs/` because someone will read it
   this month. Otherwise it is in `archive/`, where nothing is updated.
3. **One plan live at a time** in `plans/`. The refactor's release and split
   count as the live plan until the split is done.
4. **Dates are absolute.** Never "next week"; "the week of 10 Nov".
5. **Six status words**, from `features.md`: built, partial, missing,
   planned, idea, stalled. A plan's status: shaped, planned, building, on
   the iPad, shipped, parked.
6. **Caps are real.** Over the cap, split or archive; `/weekly` reports
   files over it until `scripts/check-docs.sh` exists.
7. **A fact lives in one place.** Status in NOW, what exists in features,
   why in design, decisions in decisions. A sentence that would fit two
   files goes in the one from the table and the other links to it.
8. **Agent briefs can be long; your plan can't.** The 150-line plan is what
   you approve. A session may expand a step into a longer brief in chat.

## Reading order for a new session

AGENTS.md is loaded already. Then: `NOW.md`, the live plan's step, the one
design note the step names, `features.md` rows for the area. Nothing else
unless the step says so.
