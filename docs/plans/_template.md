# <Feature> (plan)

**What this is.** The plan for <feature>: goal, cut line, steps.
**Read it when** starting any step of it. **Last checked:** <date>.

| | |
|---|---|
| Status | shaped · planned · building · on the iPad · shipped · parked |
| Appetite | <1, 2 or 3> weeks: <start date> to <end date>. Not extended; see process.md › When the appetite runs out |
| Design note | `design/<area>.md` |
| Decisions | the dated lines in `decisions.md` this plan adds |

## Goal

One sentence, in your words, that a tester could check.

## Not in this plan

What this feature could include and deliberately doesn't. Write this before
the steps. Anything here goes to NOW.md › Parked, not into a step.

## What exists

The `features.md` rows, the design note sections and the files the work
starts from. From the code, not from memory.

## The risk, and the spike that answers it

The one assumption the build rests on. If it is a guess, step 1 is a
one-session spike that answers it, standalone, before anything else.

## Steps

One PR and one session per step; under about 400 changed lines; off `main`;
never stacked. "Done when" is something seen on screen, not a value the
code computes.

| ID | Step | Done when | Reads | Device lines | PR |
|---|---|---|---|---|---|
| X1 | | | | | |

## Docs this changes

Which `features.md` rows, which design note, the checklist lines, and the
timeline line at the end.

## Left out

Filled when the plan closes: what the appetite didn't cover and where it
went (NOW.md › Parked, or `decisions.md` if it was cut for good).
