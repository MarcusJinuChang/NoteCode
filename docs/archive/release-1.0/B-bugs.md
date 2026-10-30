# B. Bugs and the app icon

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

## B1. Home shows the note's text, not its Markdown

**Bug.** Home's card quotes the first prose line raw: `**bold**`,
`<span color=…>`, list markers, `> `, `- [ ]`, `[text](url)` all show.
`HomeExcerpt.of` (HomeSections.swift:117) takes the line as typed.

**Do.** Strip markup with the parser rather than with new regexes: parse the
line with the inline parser (`InlineParser`) and keep only the text nodes,
dropping hidden markers, tags and link targets (look for an existing
plain-text projection first: `NoteSearch`, `RichCopy`'s plain text and
`NoteOutline` each make one; reuse it if it fits). Skip block markers (list
bullets, numbers, checkboxes, quotes, rules). Keep it `nonisolated` and pure.

**Done when.** A `HomeExcerptTests` case per marker kind (bold, italic,
strike, underline, highlight, span colour and size, link, list, checklist,
quote, inline code) gives the visible text; a note whose first line is all
markup with no text falls through to the next line. Mutation check: the test
fails against today's `HomeExcerpt`.
**Read:** `design/home-the-title-screen-thumbnails-reopening.md` (Home's card only).

## B2. App icon: pencil centred between the chevrons

**Do.** In `scripts/make-icons.swift`, raise the pencil so the gap above its
top equals the gap below its bottom, measured against the chevrons' top and
bottom tips in the 120-unit geometry (say the before/after offsets in the
PR). Regenerate with `swift scripts/make-icons.swift`. If `AppIconTests`
samples the pencil at a fixed point, move its sample point with it.

**Done when.** `AppIconTests` pass; the PR shows the 1024 Default before and
after (attach both PNGs). Edit the script, never the PNGs.
