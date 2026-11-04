---
name: plan-feature
description: Shape and plan one NoteCode feature from docs/NOW.md's queue into docs/plans/<name>.md, from the template, with the analysis first. Use for "/plan-feature <feature>".
---

# Shape and plan one feature

Nothing is implemented here. The output is a plan Marcus can read in two
minutes and approve, plus the analysis that justifies it.

1. **Read**: `docs/NOW.md` (the queue row and its "needs first"),
   `docs/process.md` › The stages and › The queue, reasoned (the paragraph
   for this feature, if there is one), `docs/plans/_template.md`, the
   `docs/features.md` rows for the area, and the design note the row names.
   Read code only to confirm what exists; by range, not whole files.
2. **Check the prerequisite.** If the queue's "needs first" isn't shipped,
   stop and say so. If another plan is live (a `docs/plans/*.md` with
   status building or on the iPad), stop and say so.
3. **The analysis**, in chat, a few lines per heading (memory: analytical
   planning):
   - Requirements, each traced to evidence (a feedback item, a design note
     line, a thing Marcus said) or marked assumed.
   - Design decisions with the trade-off that decides each; the pitfalls
     spotted in advance (AGENTS.md › Implementation requirements for the
     area).
   - Risks, and the one spike that answers the biggest.
   - Acceptance: observable on screen.
   - Staging: the cut line, and the appetite (1, 2 or 3 weeks) with the
     reason.
4. **Write `docs/plans/<slug>.md`** from the template, under 150 lines.
   Status: shaped. Every step one PR, one session, under ~400 lines, with
   a "Done when" seen on screen, the files and note it reads, and its
   device lines. "Not in this plan" is written before the steps.
5. **Decisions** this plan makes go in `docs/decisions.md` as "proposed"
   lines, dated today.
6. **Report**: the plan's path, the appetite, the cut line, the spike, and
   what you need from Marcus (the approval, a date, a by-hand step).

Don't start a step. Don't edit the design note; the first building step
does that.
