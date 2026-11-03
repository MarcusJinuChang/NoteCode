---
name: refactor-wp
description: Carry out, review or fix one step of the NoteCode refactor plan in docs/refactor/. Use for "/refactor-wp implement <ID>", "/refactor-wp review <PR number> [--post]" and "/refactor-wp fix \"<bug>\"".
---

# One step of the NoteCode refactor

The plan is `docs/refactor/README.md` (rules, decisions, order) plus one
stream file per area. Usage is limited: read only what this skill and the
brief name, keep tool output short, and don't start subagents.

## implement <ID>

1. **Read** `docs/refactor/README.md` › Rules, then find the brief:
   `grep -n "<ID>" docs/refactor/*.md`. Read that brief, and only the
   design notes and files it names. AGENTS.md is already loaded.
2. **Prerequisites.** README › Order says what the step needs. Check each is
   merged: `git fetch origin && git log origin/main --oneline | grep "<ID of the prerequisite>:"`.
   If one isn't, stop and say which.
3. **Base.** Work on this session's branch, based on `origin/main`
   (`git rebase origin/main` if it isn't). Never on `main`, never stacked
   on another step's branch.
4. **Before changing anything,** run the suites the brief names (or
   `scripts/check.sh --only <Suite> …` once it exists) and note that they
   pass. A brief marked *perf* also runs `scripts/perf.sh` (or the cost
   tests it names) and keeps the numbers.
5. **Implement the brief.**
   - A brief marked *two commits* gets a pure move first: commit it, and
     check it with `scripts/verify-move.sh`.
   - A behaviour change you notice but the brief didn't ask for is a
     finding: write it down, don't fix it.
6. **Verify.**
   - A build, plus the named suites.
   - `scripts/check.sh` and `scripts/lint-traps.sh`, once they exist.
   - `verify-move.sh` for moves.
   - `perf.sh --compare docs/refactor/baseline.md` for *perf* briefs. More
     than 10% worse means stop and report.
7. **Commit.** Stage files by name; never `git add -A`, and never
   `project.pbxproj` or `Info.plist`. The message is `<ID>: <what changed>`.
8. **Open the PR.** Push, and open the PR to `main` with
   `.github/pull_request_template.md` once it exists. The title is
   `<ID>: …`. The description is for anyone viewing the project: what
   changed and why, plus the verify output in short.
9. **Report in chat:**
   - the PR link;
   - the findings;
   - for a move, every member whose access was loosened;
   - the **device lines** for Marcus: what to try on the iPad, and what
     you'd expect to see. Device lines go in chat only, never in the repo
     or the PR.

**Stop and ask** if the acceptance criteria can't be met as written, if the
step needs `project.pbxproj` or `Info.plist`, or if a section needs more
than about five `private` members loosened.

## review <PR number> [--post]

You did not write this PR. Review it read-only: no edits, no commits.

1. Run `gh pr view <n>` and `gh pr diff <n> --name-only`. Take the step's
   ID from the title.
2. Read `docs/refactor/README.md` › Rules and the step's brief.
3. Check out the PR (`gh pr checkout <n>`) and run:
   - the brief's suites, or `scripts/check.sh` once it exists;
   - `lint-traps.sh`;
   - `verify-move.sh` on its move commits;
   - `perf.sh --compare` if the brief is *perf*.
4. **Read the diff** against the brief.
   - **Each "Done when" item:** met, not met, or can't tell, with the
     evidence.
   - **Behaviour:** does a refactor change anything a reader can see? Check
     stored data, settings keys and defaults, the order of menus, rows and
     the edit menu, accessibility identifiers, and launch order.
   - **Moves and extractions:** use swift-lsp find-references on each
     extracted or renamed symbol, to confirm every call site moved with
     it.
   - **Traps** (README › Rules) in the areas the diff touches.
   - **Bugs:** run the `code-review` skill at `high` on the diff.
5. **The verdict.** Give *ready to merge* or *changes needed*, followed by
   the findings, most serious first, each with `file:line`. Also list the
   device lines Marcus still has to do. With `--post`, put the same text on
   the PR as one comment (`gh pr comment <n>`). Without it, give it in chat
   only.

## fix "<bug>"

The F1 loop in `docs/refactor/F-fixes.md`.
1. **Read** README › Rules and F-fixes.md › F1.
2. **Reproduce the bug** with a test that fails, or, if it can't be reached
   from a test, with the debug launch options (AGENTS.md › Debug launch
   options).
3. **Find the cause.** Fix the cause, not the place it shows, then confirm
   the test passes and fails without the fix.
4. **Update** its `features.md` row if what the row says changed.
5. **Open the PR** as `F1: <short bug name>`, and report in chat as in
   implement › 9.
