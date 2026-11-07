# Now

**What this is.** This week, what's next, what's parked. One screen.
**Read it when** you sit down to work. **Last checked:** 7 Nov 2026
(Monday is the check; `/weekly` rewrites this file).

## This week (3–9 Nov)

- **1.1.0 (4) approved 5 Nov**, releasing automatically. Once it is live:
  1. Tag the build: `git tag v1.1.0-4 <its commit>` (`refactor/lessons.md` 1).
  2. One custom offer code in App Store Connect for you and friends
     (`decisions.md`, 3 Nov; an hour).
  3. AdMob: link the app; `app-ads.txt` (ROADMAP › After it's live, 5).
- **Refactor finished 7 Nov** (#178–#229): every wave, 2W (warnings 31 → 2),
  4A's QA and 4B's audit. Follow-ups merged: F5 to F8, dashes, syntax style,
  Compiler Explorer ids, T10 snapshots, T11's `swift test` package, and PDF
  export without trailing blank pages.
- **The device pass:** the tracker's 152 checks, on TestFlight with a
  sandbox tester; nothing since 2 Nov has been seen on an iPad.
- **Then the upload:** bump the build, archive, submit. The release notes
  need a line on F5: existing ink beside paragraphs that crossed a page
  break may sit lower than its text (`decisions.md`, 7 Nov).
- **A decision to record:** 1.1.1 never shipped on its own, and everything
  planned for 1.1.1 and 1.2.0 is now on `main`, so the next upload carries
  both. Pick its version number; one line in `decisions.md`.

## Not this week

No feature from the queue until the upload is submitted.

## Queue (one at a time; each gets `plans/<name>.md`)

| # | Feature | Needs first | Appetite |
|---|---|---|---|
| 1 | The release, then the split (`refactor/` Phase 5) | the device pass | `refactor/` |
| 2 | Pro for you and friends: offer codes | 1.1.0 live | an hour, no plan file |
| 3 | Model version 2 + the object system (one migration; drops `paperStyle`, `runDestination`) | 1.2.0 | 3 weeks |
| 4 | iCloud sync | 3 | 2 weeks + a week on two devices |
| 5 | Paper styles + text alignment, with the ink-anchoring call | 3 | 2 weeks, probe first |
| 6 | Mac editor (Catalyst spike first) and the iPad + Mac pair | 4 | 3 weeks after a 1-day spike |
| 7 | Infinite canvas (a second kind of note) | 3 | shape after 3 ships |
| 8 | Design retouch | a critique per shipped feature; one 2-week pass before 1.2.0 | |

Reasons: `process.md` › The queue, reasoned. Apple accounts: `decisions.md`.

## Parked

- Annual plan and a student price; App Attest on the proxy; wrangler 4
- Spotlight, App Intents, a widget, a Share extension; PDF import
- Side-by-side pages; A4; Face ID lock; note combining; code sort
- Group notes and comments (needs a server and accounts)

## Waiting on others

- Apple: EU trader status (the EU storefronts follow).

## Done this week

- App Review approved 1.1.0 (4), 5 Nov. The whole refactor and its
  follow-ups (#124–#230). The docs map.
