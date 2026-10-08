# NoteCode roadmap

Source of truth. The published version at
<https://claude.ai/code/artifact/2490317a-7eaf-44ae-9389-f0fb92d7471a>
is a rendering of this file — edit here, ask for the artifact to be regenerated.

Revised 3 October 2026.

| | |
|---|---|
| Drawing layer due | **10 Oct 2026** (hard stop) — done 3 Oct |
| Using it day to day | now — ink is saved as of 23 Sep |
| App Store submission | Nov 2026 |
| Second version | AI + feedback, Mar 2027 |

## Where things stand (3 Oct)

The drawing layer is done, a week inside its deadline: the TextKit 2 editor
with code blocks, run and copy, Letter-sized pages in three view modes with
pinch zoom, the note page and its hotbar, and a PaperKit canvas that a finger
or the Pencil draws on, with ink undo of its own, saved with the note and
drawn at the screen's density. 25 pull requests, all merged.

- **Note search** (4 Oct, PR #27, merged 8 Oct): a search field at the top of the note
  list finds notes by every word typed, in the title or the text, ignoring
  case and accents. Results show the line that matched, with the words in
  bold, title matches first. Opening one scrolls the note to its first match
  and highlights every match until you type. The magnifying glass in an open
  note's header, or ⌘F with a keyboard, finds and replaces within the note.
  Ink isn't searched. Builds for iPad and Mac, and 493 tests pass; not yet
  checked in the simulator or on the iPad.
- **Printing and PDF export** (4 Oct, PR #29, merged 8 Oct): the share button in an
  open note's header makes a PDF of the note, a page for each of its pages
  exactly as print layout shows them, ink, code panels and syntax colours
  included, and opens the share sheet to print it, save it to Files or send
  it. Always light, on white paper, whatever the device's appearance. Text
  stays text, so it can be searched and selected in the PDF; ink goes on as
  a picture at 288 dots per inch, since PaperKit draws only into bitmaps.
  Builds for iPad and Mac, and 486 tests pass; not yet checked in the
  simulator or on the iPad.
- **Text lock** (4 Oct, PR #30, merged 8 Oct): the lock in an open note's header, or
  Lock Text in its long-press menu in the list, makes the note's text and
  title read-only until it's unlocked. Tapping it brings up no keyboard,
  the formatting buttons grey out and undo stands down, but text can still
  be selected and copied, code blocks still run and copy, and ink can still
  be drawn. The note remembers it: a new model version, 6, with migration
  tests from version 5. Locked notes show a small lock in the list. Locking
  isn't an edit, so the date stays. Not the Face ID kind, which is "Note
  locking" in Later. Builds for iPad and Mac, and 486 tests pass; not yet
  checked in the simulator or on the iPad.
- **Autocorrect for prose** (3 Oct, PR #26, merged 8 Oct): prose gets the keyboard's
  autocorrect, capitals, smart quotes and dashes, and inline predictions
  back; code keeps them off, on a block's lines and fences and in inline
  code, an unclosed fence or backtick included, and on the word just after
  inline code until a space ends it. The keyboard switches as the caret
  crosses from one to the other, and is set up as typing begins. Spell
  checking stays off everywhere, since it would mark identifiers typed in
  code. Typed through on the iPad simulator's keyboard and checked in light
  and dark. That found a new note's first letter left lowercase, fixed and
  checked, and autocorrect rewriting inline code's last word and eating its
  backtick, either as the space after it was typed or when the keyboard went
  back over it from the next word. Both inline code fixes are unit-tested
  but not typed through again: the simulator's keyboard checks were stopped
  as too slow.
- **Note info** (3 Oct, merged 3 Oct, PR #25): Get Info, in a note's long-press menu
  in the list, or the info button in an open note's header, shows when the
  note was made and last changed, its folder and orientation, its words,
  and its code blocks by language with their lines. Opened from the note,
  it adds the page count, which only a laid-out note knows. Worked out from
  the text through `DocumentParser` each time it opens, so nothing is
  stored. 476 tests; checked in the iPad simulator in light and dark.
  The sheet is the standard one, holding every row for code in up to
  three languages; a fourth scrolls.
- **Pinning and sorting** (3 Oct, merged 3 Oct, PR #24): a long press pins a note or
  a folder to a Pinned section at the top of the list, and Sort By, in
  the list's ••• menu, orders notes by date modified, date created or
  title, either way round.
  The sort is a per-device setting; folders stay in name order. No model
  change: the pins came with folders. 468 tests; checked in the iPad
  simulator in light and dark, where the first build's Sort button pushed
  the list's title out, so Edit and Sort By now share a ••• menu.
- **Folders** (3 Oct, merged 3 Oct, PR #23): notes file into folders that open and
  close in the list, each with its own run destination between the note's
  and the app's. The model is versioned from here on, and this first
  migration also carries the pins for pinning, so sorting and note info need
  no model change. Its versions include every shape earlier builds wrote:
  with only the latest, stores from before 23 Sep wouldn't open. 459 tests;
  copies of four simulators' stores, from 12 Sep to 25 Sep, open with every
  note intact.
- **The device pass is closed** (3 Oct). Marcus has used the app on the iPad
  and reports it works, so latency, palm rejection and Pencil-versus-finger
  routing are taken as passed rather than measured.
- **Ink is saved** (23 Sep, merged 25 Sep): half a second after
  drawing pauses, and at once when the note closes or the app leaves the
  screen. It survived a force-quit on the simulator. 410 tests.
- **The iPad pass has started.** First findings (25 Sep): ink and the line
  being typed were drawn at a lower density than the screen, and typing
  stuttered now and then. Both density bugs are fixed and measured on the
  simulator, and a keystroke costs about a third less (merged 25 Sep).
  Typing near the top of a long note still costs
  about two frames; the rest of that is pagination by exclusion paths.
  Two smaller bugs found on the way are fixed too: a deleted
  note came back if the app was killed within a few seconds, and the empty
  line after a note's closing fence was shaded as code.
  The simulator's share of the device checklist is done (26 Sep, branch
  `device-pass`): dragging a lasso selection and scrolling with two fingers
  while a finger draws are fixed (merged 26 Sep). Rotation and Split View passed
  on the iPad.
- **Pencil changes** (26 Sep, PR #21, merged 2 Oct): the eraser erases whole
  strokes or only what it passes over, at three sizes or a custom one; "+"
  adds a colour from Apple's colour picker, and a colour can be removed or
  moved; the Pencil's double tap and squeeze do what Settings says; the
  surround around the page scrolls with one finger and zooms; and undo,
  redo and the mode toggle no longer scroll away with the hotbar's tools.
  All but the Pencil checked on the simulator. 448 tests.
- **Ship prep** (4 Oct, PR #28, merged 8 Oct): the app carries the privacy manifest
  App Store Connect requires, saying it tracks and collects nothing and
  reads UserDefaults only for its own settings. It says it uses no
  encryption of its own, so uploads skip the export question, and it no
  longer declares a push background mode or iCloud and push entitlements,
  left over from Xcode's template and never used. Still missing before an
  upload: the app icon, which needs a design, and signing. Builds still
  sign with the free Personal Team, whose profiles last seven days. As of
  11 Sep the paid Developer Program membership wasn't showing on the
  account. That has to be sorted before TestFlight — and before the app can
  stay on the iPad for more than a week at a time.

## Plan

Not set in stone. With the drawing layer done, the before-November list is
being planned (3 Oct): folders came first, then pinning and sorting, then
note info (all merged 3 Oct), since the list was the thing
least likely to last the semester and model changes are safest before
anyone else's notes depend on them. Marcus picked autocorrect for prose
next, then note search, ship prep, printing and text locking, all merged
8 Oct. Next are the UI design and polish, TestFlight and submission. Scrolling direction, infinite canvas and Sign in
with Apple are proposed for Later. Not yet agreed.

### Done — the drawing layer on PaperKit (to 10 Oct)
See [phase-drawing-layer.md](phase-drawing-layer.md) for the build plan.

| Step | Planned | Status |
|---|---|---|
| 1. Spike | 6–7 Sep | Done |
| 2. Geometry | 8–14 Sep | Done, and grew into pages and view modes |
| 3. The toggle | 15–21 Sep | Done; the code-block buttons' overlap with the canvas fixed 25 Sep |
| 4. Saving ink | 22–28 Sep | Done 23 Sep; gate passed on the simulator |
| 5. Device pass | 29 Sep – 10 Oct | Done 3 Oct: rendering density fixed, typing cost cut; the simulator's share of the checks done, and the lasso and two-finger scrolling fixed; Pencil changes merged 2 Oct (PR #21); Marcus reports it works on the iPad |

**Fallback if it runs long:** the phase doc's cut list — stop adding pages for
ink, then PencilKit's canvas instead of PaperKit's. Saving is never cut.

### Before November — candidates
In the order given, which isn't yet a priority order. Notes only where the
code already has something to say.

1. **Scrolling direction, as a setting** — pages below each other, or side by
   side. The text view scrolls itself, and only vertically: `UITextView`
   forces its content width back to its own (measured 12 Sep). Side-by-side
   pages changes who owns scrolling rather than adding a setting.
2. **Text locking.** Merged 8 Oct (PR #30): a per-note read-only lock on
   the text, kept with the note. Ink stays drawable.
3. **Infinite canvas.** Notes are Letter pages, and ink is stored in page
   coordinates. An unbounded canvas is probably a second kind of note rather
   than a mode of this one.
4. **Note search.** Merged 8 Oct (PR #27): across notes from the list,
   and find within a note. Text is plain in `Page.content`. PaperKit's
   `PaperMarkup.indexableContent` may reach text boxes in ink (untested), so
   ink isn't searched yet.
5. **Favouriting / pinning / starring** notes and folders. Folders merged
   3 Oct (PR #23); pinning merged 3 Oct (PR #24).
6. **Note sorting.** Merged 3 Oct (PR #24): date modified, date created or
   title, either way round, saved per device.
7. **Note info / properties.** Merged 3 Oct (PR #25): dates, folder,
   orientation, words, and code blocks by language, plus pages when the note
   is open.
8. **Printing.** Merged 8 Oct (PR #29): the note header's share button
   makes a PDF of the note's pages, to print, save or send.
9. **UI polish**, from the UI design.
10. **Accounts and Sign in with Apple.** No backend: as the only login option
    it also sidesteps Apple's rule requiring it alongside third-party sign-in.
11. **TestFlight.** Needs the paid team (see above) and an app icon. The
    privacy manifest merged 8 Oct (PR #28).
12. **App Store submission.** First submissions bounce on formality, so leave
    review-cycle buffer, not zero margin.

Folders, 5, 6 and 7 were planned as one model change, and are: version 5 of
the model (3 Oct) carries folders and the pins, and sorting and note info turn
out to need nothing stored.

### Later
- Note templates
- Note locking
- Note combination / sealing
- Theme and colour selection
- Code sort
- Code syntax
- Group notes and group comments. Both need a server, which nothing else in
  the app does.
- AI — the second version, Dec 2026 to Mar 2027. One or two features tied to
  the actual use case (explain this code block, summarise this page), built on
  real TestFlight usage.
- The macOS editor
- iCloud sync

Scrolling direction, sorting and note info are on both lists: November
candidates that can slip to here.

## Done so far

**Foundations (Jul–Aug).** Swift and SwiftUI basics before touching NoteCode.

**Walking skeleton (Aug).** The `Page` model, a page list, a page editor, and
`Storage` — which degrades to an in-memory store and says so, rather than
crashing on launch when the disk store fails.

**Custom text engine (Aug – early Sep).** Built before the drawing layer, out
of the original order, because it was the phase most likely to sink the
schedule.

- A real `UITextView` on TextKit 2 (`DocumentTextView`)
- Pure, unit-tested fence parsing (`DocumentParser`)
- Fragment-level code panels (`CodeBlockLayoutFragment`) — `.backgroundColor`
  paints per glyph and leaves a ragged right edge
- Async syntax colouring via HighlightSwift, restyling only the changed block
- Debounce went from a guessed 200ms to a measured 20ms

**Run and copy (11 Sep).** In-app execution was cut: every option needed a
paid API, a VPS sandbox, or a multi-megabyte WASM runtime with a four-second
cold start, for a feature nobody uses during a lecture. It came back as a
redirect. Every code block carries run and copy in its top-right corner, and
run opens a free online compiler.

- `CodeDestination` — where a block goes, and how. Compiler Explorer takes the
  whole program in the URL, so the student lands on a finished run; Programiz
  and OnlineGDB can't be prefilled, so the code goes on the pasteboard.
- Per-note choice, app-wide default behind it. Folders slot in between when
  they exist — `RunDestinationPreference.resolve` walks the levels in order.
- The buttons are TextKit 2 viewport-positioned overlays (`CodeBlockOverlay`),
  not attachments, and the text view has to be stopped from eating their taps.

**The note page and pages (12–23 Sep).** Laid out from the 12 September
mockup: a title header with the note list behind ☰, and one hotbar docked
left, bottom or right carrying undo, redo, the text/draw toggle and the current
mode's tools. It replaced `PKToolPicker`. Notes are Letter-sized pages,
portrait or landscape, chosen when the note is made; a view menu shows them
seamless, compressed or as print layout; pinch zoom is a transform on the
scrolling text view, which measured 40 times cheaper per keystroke than a zoom
container.

**The drawing layer, steps 1–3 (19–23 Sep).** PaperKit's canvas inside the
text view's content, so both layers share one scroll position. Ink is stored in
print coordinates and shown on the same words in every mode. A finger draws
unless the canvas is locked to the Pencil, and ink has an undo stack separate
from the text's.

## Deferred work

Referenced by name from the code.

| Where | What |
|---|---|
| `DocumentStyler.swift` | **Markers that recede.** Markdown markers stay visible in `tertiaryLabel`. Hiding them when the caret is elsewhere is the Obsidian behaviour. |
| `PageLayout.swift` | **A4.** Notes print on US Letter only. A4 is one more paper size here, but a different width re-wraps the text, so it would be a property of the note, chosen when it's made, like orientation. |
| `PageView.swift` | **Typing cost on long paged notes.** Page breaks are exclusion paths, and TextKit 2 then lays out everything below an edit: 34ms a keystroke near the top of a 250-line note on the simulator. If it lags on the iPad, push whole paragraphs with paragraph spacing instead, computed lazily. |
| `PageView.swift` | **Diagonal panning when zoomed in.** The text view scrolls vertically and `PageView` sideways, so a pan picks one. |
| `Page.swift` | **Text-anchored ink.** Wanted for its own sake, not just as a drift fix. Anchor each stroke to an `NSTextLocation` plus an offset, translate the group on relayout. Its own phase. |
| `CodeDestination.swift` | **Pinned Compiler Explorer compilers.** `g142` and `python313`, chosen because the site has 1,197 compilers and no "latest" alias. A retired id still shows the code with the compiler pane complaining, so this is a maintenance item, not a risk. |
| `PageDetailView.swift` | **The macOS editor.** Still a plain `TextEditor` — no fences, no highlighting, no ink. |
| `Storage.swift` | **iCloud sync.** CloudKit via SwiftData, deferred past MVP by design. The model is shaped for CloudKit since 3 Oct (optional relationships, defaults, nothing unique), so turning it on needs no migration of its own. |
| Layout | **iPhone Duo.** Apple's foldable, out 23 Oct 2026, runs standard iOS 27.1, so it's covered by the iPhone target. Apple asks apps to resize with the scene rather than the screen, keep controls out of the fold (`reservedRegions`), and let bars run vertically down the side. Testing needs Xcode 27.1, which carries the Duo simulator. It takes the USB-C Apple Pencil (one report says not until after launch), so ink on any iPhone relies on a finger drawing, which works on PaperKit as of 23 Sep. Checked 2 Oct on the Xcode 27.1 beta (27A9269): main builds with no new warnings, and all 448 tests pass on the Duo simulator once the ink placement test allows a screen pixel, since a 3x screen puts PaperKit's shapes on its own pixels. The beta's iOS 27.1 runtime runs only the Duo, so iPads are still tested on 27.0. |

## Habits that are paying off

- **Measure first.** The highlight debounce was guessed at 200ms and measured
  at 20ms. Ink got the same treatment: 1,000 strokes read back in 29ms, so
  reading as a note opens is fine.
- **Isolate risk.** Spike the hard part standalone. A failed spike costs an
  afternoon; a failed integration costs a week.
- **Settings travel together.** `TextRewritingPolicy` groups six traits into
  one type with one `apply(to:)` so they cannot drift. `EditorMode` does the
  same for the drawing toggle.
- **Degrade, don't crash.** `Storage` falls back to an in-memory store and says
  so. Unreadable ink gives an empty canvas and a warning, and is never written
  over.
- **Check what's on screen, not what the code computed.** The view-switch bug
  of 13 Sep passed a test comparing the scroll offset to page geometry while
  the screen showed the wrong page. The debug launch options report where
  TextKit actually put the lines.
