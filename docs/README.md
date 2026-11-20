# The docs: a map

Where every kind of fact about NoteCode lives. Read it when you don't know
where to look, or where to write.

## Where to look

| You want | Read |
|---|---|
| The rules for changing the code (traps, build, the seam) | [../AGENTS.md](../AGENTS.md) |
| Whether something exists in the app, and how it works in one line | [features.md](features.md) |
| Why a feature works the way it does | `design/<area>.md`, indexed in [../AGENTS.md](../AGENTS.md) › Design notes |
| What was decided, and what was reversed and why | [decisions.md](decisions.md) |
| Where the app stands and the ranked list of what is next | [ROADMAP.md](ROADMAP.md) |
| What was done when, phase by phase | [timeline.md](timeline.md) |
| What to try on a real iPad | [ipad-test-checklist.md](ipad-test-checklist.md) |
| The shape of a plan for a new feature | [plans/_template.md](plans/_template.md) |
| Finished plans and older reasoning | [archive/](archive/) |
| The cost tests' and the warning ratchet's numbers | [refactor/baseline.md](refactor/baseline.md) |
| What the November 2026 refactor taught | [refactor/lessons.md](refactor/lessons.md) |

Some rows of `features.md` and `decisions.md` describe the App Store
edition's own parts, which are not in this repository.

## Rules

1. **A fact lives in one place.** What exists in `features.md`, why in
   `design/`, decisions in `decisions.md`. A sentence that would fit two
   files goes in the one from the table, and the other links to it.
2. **Update the docs in the PR that changes the code**: a feature's row in
   `features.md`, and its design note when the reasoning changes.
3. **Dates are absolute.** Never "next week"; "the week of 10 Nov".
4. **Status words**, from `features.md`: built, partial, missing, planned,
   idea, stalled.
5. **Live or archived.** A file is in `docs/` while it is kept up to date;
   otherwise it is in `archive/`, where nothing is updated.
