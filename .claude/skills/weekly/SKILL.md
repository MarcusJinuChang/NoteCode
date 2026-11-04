---
name: weekly
description: The Monday check for NoteCode. Rewrites docs/NOW.md from git and the open PRs, archives finished plans, and lists stale or oversized docs. Use for "/weekly".
---

# The weekly check

Twenty minutes of Marcus's time, most of it reading your summary. Read only
what this file names; no subagents; keep tool output short.

1. **What happened.** `git log origin/main --since='7 days ago' --format='%ad %s' --date=short`
   and `gh pr list --state merged --search 'merged:>=<7 days ago>' --json number,title`,
   plus `gh pr list --state open --json number,title,reviewDecision`.
2. **Read** `docs/NOW.md`, `docs/README.md` › Rules, and the live plan's
   status table (`docs/plans/*.md` with a status other than shipped or
   parked; or `docs/refactor/README.md` › Order while the refactor runs).
3. **Rewrite `docs/NOW.md`**, under 60 lines, keeping its sections: This
   week (from the plan's next steps and the open PRs), Not this week,
   Queue (unchanged unless Marcus says), Parked, Waiting on others, Done
   this week (from step 1). Set "Last checked" to today. Absolute dates.
4. **Archive.** A plan whose status is shipped or parked moves to
   `docs/archive/` with `git mv`; add its timeline line to
   `docs/timeline.md` if missing.
5. **Flag, don't fix:**
   - a live plan past its appetite's end date;
   - any `docs/*.md` or `docs/design/*.md` without the three header lines,
     or with "Last checked" over 30 days old;
   - files over their cap (README.md's table): `wc -l`;
   - merged PRs this week that changed `NoteCode/` but not
     `docs/features.md` (`gh pr view <n> --json files`);
   - `decisions.md` lines marked "proposed" older than two weeks.
6. **Report in chat**, ten lines at most: done this week, this week's three
   things, what was flagged, and then **Remaining for you** (the by-hand
   items: device pass, merges, App Store Connect).

Don't commit; show the diff of `NOW.md` and let Marcus commit.
