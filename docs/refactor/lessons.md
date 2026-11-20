# What to do differently

Written 2 Nov 2026, while planning the refactor. Each point is something
the codebase or its history shows, and what to do instead from now on.

1. **Make every build reproducible.** The version, build number, platforms
   and signing of the build in App Review exist only in local edits, so
   `main` can't rebuild it. Keep them in committed configuration (an
   xcconfig), and tag every upload (`v1.1.0-4`).

2. **A rule that matters is a check, not a paragraph.** Each line in
   AGENTS.md › Implementation requirements is a bug that shipped once.
   Written down, it only guards the code until an agent skims past it. Turn
   it into one of three things:
   - a test that fails;
   - a lint (`lint-traps.sh`);
   - a type that can't express the mistake, like a snapshot that holds its
     own source string.

3. **Design where a feature plugs in before building it.** Run and the AI
   features went into `NoteEditor` because it was the quickest place. That
   made the open-source split a project of its own. When a feature
   registers with an extension point instead (dependency inversion), it can
   be added, removed or kept private cheaply.

4. **Give files a size budget.** Six files grew to 7,200 lines by accretion,
   each change sensible on its own. Ask "is this a new type?" at 400 lines,
   and justify anything past 600.

5. **A device check is part of done.** "Built, unverified on device" piled
   up into a 237-line checklist at the end. Check touch, ink, scroll and
   Pencil work on the iPad before the PR merges, and send a TestFlight
   build every week rather than once before release.

6. **Fast, trustworthy feedback.** An eight-minute suite run by hand gets
   skipped. A test that returns early when it can't find its file passes
   forever, and tests that share `UserDefaults.standard` pass or fail by
   order. Aim for a minute-long inner loop, CI on every PR, and tests that
   are seen to fail.

7. **Branch hygiene.** By 2 Nov there were 55 worktrees, 96 branches, and
   two stacked PRs that merged into dead branches instead of `main`. Delete
   a branch when it merges, never stack PRs, and prune the worktrees each
   week.

8. **One source of truth per kind of document.** There are 11,000 lines of
   docs for 40,000 of code. The same status sat in four files, and
   ROADMAP's known problems went stale. Keep status in ROADMAP, the
   inventory in `features.md` and the reasons in short design notes, and
   archive the rest. Every agent pays for every line it reads.

9. **Separate writing from reviewing.** Most 1.0 PRs were written from a
   brief and merged on the author's word. A second session with fresh
   context catches what the author can't see; this plan's own review found
   two tests that would have silently stopped testing.

10. **Ratchet what you can count.** Warnings, file sizes and Pro references
    in general code: counts that may only fall stop the slow growth no
    single PR would notice.

11. **Test a lock by running two at once.** The 0C1 simulator lock passed
    review on single runs. Its `EXIT` trap fired as `take_lock` returned,
    so it never held, and parallel sessions killed each other's test hosts
    until 0C3. Anything meant to keep two runs apart is proven with two
    runs.

12. **Worktrees come from the local `main` ref.** A new session's worktree
    branches from `main` on this machine, not `origin/main`. Keep it
    fast-forwarded (`git fetch origin main:main`) after each merge, or new
    sessions start stale.
