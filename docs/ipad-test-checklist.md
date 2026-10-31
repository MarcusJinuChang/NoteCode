# On-iPad test checklist

Everything the design notes and the roadmap say was never seen on a real iPad,
in the order you would walk through the app, one check to a line with what you
should see. Built 24 Oct, extended 29 Oct with the 1.0 steps' own lines (their PR numbers are given as #n) and 31 Oct with #117, #118 and the QC's release lines, from the "On-iPad checklist", "Not checked" and
"Unverified" sections of `docs/design/` and `docs/ROADMAP.md` (Verification
debt), de-duplicated. Mark a line `[x]` when it works, and write what you saw
beside it when it doesn't.

Each line ends with where it came from: **FB n** is item n of the 21 Oct
feedback list (`docs/archive/feedback-plan.md`, "Item index and retest"); otherwise the
design note's file name (`pages` is `docs/design/pages.md`) **ROADMAP**, or a 1.0 step (**T1**, **L5**… with its PR).
Where a check is for one item, "if it doesn't" says the first thing to look at.

Done on a real iPad already (24 Oct, `ListDragUITests`, run from the Mac):
a note dragged onto a folder files it, and onto the Library header takes it out
of its folder. Both are in section 2 below only for what that test cannot see.

## 1. Launch and Home

- [ ] First launch (`-debug-first-launch`, or a fresh install): the title screen shows once, then the Welcome note is in the list. Never again after. — home-the-title-screen
- [ ] Home on the iPad Pro 11-inch in landscape *and* portrait: Continue card, Recent, Folders, nothing cramped or cut off; the list's strip beside it. — home-the-title-screen (11-inch, portrait), the-page-fills-the-window
- [ ] Home's Settings, Search and + buttons, a folder tile, Show All and ⇧⌘H each do what they say. — home-the-title-screen
- [ ] The house button from a note goes to Home; reopening the app puts you where you were (note, page). — home-the-title-screen
- [ ] The title screen in dark mode, and with Reduce Motion on (it fades, doesn't slide). — home-the-title-screen
- [ ] A note's thumbnail updates after an edit; a note with ink has ink in its thumbnail. — home-the-title-screen
- [ ] The side bar always shows beside Home (sidebar beside Home, not over it). — **FB 3**
- [ ] Going Home from a note: the note shrinks into the card it was opened from (a note opened from the list shrinks toward the middle); with Reduce Motion on it cross-fades. The joined list/Home pill at the top left reads in light and dark, and the system's own sidebar button is gone. — **W3** #101
- [ ] Home's excerpt for a note shows its text, not its Markdown (no `#`, `**`, `-`); a line like `#include` stays as typed. — **B1** #85
- [ ] Home and the list's foot show a banner while you are free, with "Remove ads"; buying Pro removes them at once. First Home visit asks for consent (EEA/UK) and no ATT prompt at launch; the ATT prompt comes on a later Home visit. — **P3** #112
- [ ] The banner stays inside Home's column in landscape and portrait (Home scrolls, nothing cut off at the sides). Beside the list on a portrait 11-inch, Home takes the phone layout: the Continue card's title whole, folder tiles named, the buttons stacked; as Pro (no banner) too. — #117
- [ ] On the TestFlight build: the banners are the real units (no "Test Ad" label), or show no fill while the app isn't linked in AdMob. Add the iPad as an AdMob test device first: taps on your own live ads count as invalid traffic. — QC A-items
- [ ] The page fills the window: header (Home, ☰, title; lock, Share, •••), floating bottom bar, the side-bar strip all look right, with Reduce Motion on too. — the-page-fills-the-window, ROADMAP
- [ ] Page edge doesn't touch the screen edge: a buffer on the sides the hotbar doesn't take, top included. — **FB 1**
- [ ] Scrolling by dragging anywhere, the grey surround included: one pan; a zoomed page pans diagonally and a sideways fling carries on. No space can be pulled open above the page; the bottom still bounces. The scroll indicator sits at the window's edge and fades; the page has a hairline edge and soft shadow in both appearances, and the top bar's hairline does not double. In ink mode: two-finger scrolling, PaperKit's lasso and a pinch still behave (if not, fall back to the split pans). — **W2** #99
- [ ] No Liquid Glass anywhere: the hotbar, the pen and text rows, the code keys row, the top bars and the Home/list pill share one opaque bar tone with a hairline; is it right against the surround in light mode? — **W4** #104
- [ ] Settings from inside a note: ☰ › ••• › Settings opens the sheet. — **FB 11**, settings

## 2. The list and drag and drop

- [ ] The list shows folders and notes as one list; each row's icon draws: the folder badges (symbol on a tint), the open/close chevrons, a pinned or locked note's pin and lock, the Recently Deleted trash, the foot's mark. **Report which, if any, are blank.** — **FB 13**, recently-deleted-and-folder-faces (sidebar icons reported missing 24 Oct; not reproduced in testing, see the commit message)
- [ ] Drag a note and drop it on a folder row: it files in that folder and the folder's count goes up. (Tested from the Mac; check by hand with a finger and with the Pencil.) — organising-notes, ROADMAP
- [ ] While dragging over a folder's middle, the row gets an outline; over the top or bottom edge of a folder, a line above or below it. — organising-notes (hover indicator, never seen)
- [ ] Drag a folder onto another folder's edge: it lands before or after it (arranged by hand), among its siblings; into the middle: nested inside. With the sort set to Name the order shows as sorted. — organising-notes
- [ ] Drop a folder on itself or its own subfolder: nothing happens, no outline. A pinned folder only takes things into it. — organising-notes
- [ ] Drag a note or folder onto the Library header: it leaves its folder / goes to the top. — organising-notes
- [ ] Drag near the top or bottom edge of a long list: the list scrolls under the finger. — organising-notes (unchecked)
- [ ] Press and hold a row without moving: the context menu, not a drag; press, hold half a second and move at once: it lifts. — organising-notes
- [ ] Drag a note or folder onto Recently Deleted: it goes there (a folder with its notes) and the row can be restored; the lift now starts quicker. If the drag still feels slow, `-debug-probe` shows where. — **S1** #87
- [ ] Long-press menu is shorter: Lock Text and Duplicate are under Manage; Delete is still a visible item. — **S2** #94
- [ ] Move to Folder in a note's menu, and Move To in a folder's menu, still work with no dragging. — organising-notes
- [ ] A moved note keeps its date; the list's order doesn't change because of a move. — organising-notes
- [ ] "+" makes a note without opening it; holding it offers the other orientation, From Template and a folder. — **FB 12**, navigation
- [ ] Delete a folder: asked whether its notes go too; Recently Deleted shows the folder as one row with a badge and "Deleted n days ago". — recently-deleted-and-folder-faces
- [ ] The list's sort menu (date modified/created, title) reorders; a folder's colour and symbol picker (8 colours, 16 symbols) change its badge. — organising-notes, recently-deleted-and-folder-faces
- [ ] The list taking ⇧⌘N and ⇧⌘F with a hardware keyboard, even right after it slides in. — keyboard-edit-menu-pointer-dynamic-type
- [ ] Search finds a note by a word in it; a result row's tap opens the note. — iphone-and-the-duo (result row), organising-notes

## 3. Writing

- [ ] Tap empty space below the text: the caret goes there. — **FB 7**
- [ ] Return in prose, after a heading and in a list: the next line is not taller than the others. Hold Return, then Backspace, in a 5-line note and in a 500-line one: no dropped presses (if only the long one drops, it is cost). — **FB 14, 20, 31**, pages (cost), typing-style
- [ ] Type quickly into a rendered note and paste a block of text: nothing jumps, markers stay hidden, no lag. — writing-hidden-markdown, typing-style
- [ ] Hidden Markdown markers: headings, lists, quotes show no `#`, `-`, `>` when the caret is elsewhere, and show on the caret's line. The margin hash in light mode. — writing-hidden-markdown
- [ ] Settings to not dim bullets and other markers: Off, Dim and Full for headings, bullets, checkboxes and fences each change the page on screen, with a note open too. — **FB 9**, settings
- [ ] Lists: Tab and ⇧Tab indent and outdent; Return on an empty item ends the list; a checklist box ticks on a tap. — writing-hidden-markdown
- [ ] A link: tap opens it (http, https, mailto); hold shows Open Link and Copy Link; a link at the end of a line works; a selection handle over a link stays draggable. — writing-hidden-markdown (fixed 15 Oct on device; handle over a link not tried)
- [ ] Bold, italic, underline, strike on a selection: the bar's lit state follows the selection; ⌘B and ⌘I with a keyboard. — formatting-per-character
- [ ] Nested marks (bold inside italic inside a highlight): typed by hand, they look right; the PDF of one too. — inline-nesting
- [ ] Obsidian marks: `==highlight==`, `<u>`, a quote of two lines with a nested level (bars continuous), a rule, H4 to H6; the Quote chip and Highlight menu by a tap; Style ▾'s new items. — obsidian-s-other-marks-and-blocks
- [ ] Text colour and size: pick a colour from the menu, recolour one word beside another; the size control is dim with no caret on a word, live on one; + steps 17 to 22; Custom…, Default, ••• › Text Size, ⌘+ and ⌘−; a selection in several sizes shows a dash. — coloured-and-sized-text
- [ ] Coloured and sized text in the PDF (share sheet) and with a selection across several lines. — coloured-and-sized-text
- [ ] Text size: the stepper, Custom… and a selection's size apply at once with no alert (also on a note with ink); one ⌘Z undoes a size change, redo works; headings follow the body size. Same for line spacing. — **T1** #82
- [ ] The text options row: Bold, Italic, Underline, Strikethrough, then colour swatches (Default ring clears), highlight, size, More (Body/H1–H3, Quote, Link, lists, indent, Line Spacing). It fits an 11-inch portrait iPad or scrolls; opaque capsule, light and dark. — **T2** #95
- [ ] Line spacing presets in points (••• or the text row): a pick applies at once; no change to the date or undo stack; off in ink mode and for a locked note. — **FB 2**, navigation
- [ ] The text options row: the order, the outline popover jumping to a heading, the page badge, a dock other than the bottom, Link's alert. — navigation-and-the-text-options-row
- [ ] Autocorrect outside code turned off (Settings): prose doesn't autocorrect, code never does. — **FB 19**
- [ ] A new note opens with its title ready to rename. — the-note-page
- [ ] Lock Text: the lock shows in the header; typing is refused, Copy works, a link still opens. — the-note-page
- [ ] Paste from Safari, Notes, Pages and Mail keeps bold and links and brings no stray styles; copying out and pasting back keeps formatting; Allow Paste's prompt from another app. — paste-and-copy-with-formatting
- [ ] Scribble: handwrite with the Pencil into the page in text mode and into the note's title field; the words land as typed text. The app has no handwriting-to-text of its own, so this is the only one. — **QC** §4.5

## 4. Code blocks

- [ ] Type ``` and a language: the block appears as you type, with its closing fence missing too; type the fence closed and open again. — code-block-fences, code-blocks-room
- [ ] Tap the language name: the menu opens and retags the block; C++, Java and Python highlight. "Plain Text" is called Code. — code-block-fences, **FB 15**
- [ ] A real finger on Run, Copy and the language name: each fires (not swallowed by the text view); a tap below the last block adds lines and raises the keyboard. — code-blocks-room, the-note-page, AGENTS (action bars)
- [ ] Copy puts the code on the pasteboard with a Copied toast. A free reader's Run opens the paywall and nothing else. No menu anywhere offers a choice of where code runs (the note's •••, a folder's menu, Settings › Code). — code-blocks-room (taps on Run and Copy), **R4** #103, #118
- [ ] The panel's room: 14pt into each margin, the text on the column, a caret on a fence line, light mode, landscape and other text sizes. — code-blocks-room
- [ ] Return inside a block: lines keep the same height (no thin extra space under the border). — **FB 14**
- [ ] The keys row (⇥, brackets, …) appears in a block and hides with a hardware keyboard; Tab and ⇧Tab indent; indentation width follows Settings; line numbers up to 4 digits. — code-languages-and-keys
- [ ] The Output block: selection highlight is visible; "Insert Output Block" from the edit menu. — code-languages-and-keys
- [ ] An awkward border where ink crosses a code block (highlighter over code). — **FB 22**
- [ ] A block scrolled out of view and back after changing state draws the new state; find highlights on a hidden fence. — code-block-fences

### Run in the app (Pro)

- [ ] Notes | Run control in the top bar (PRO mark while free). The panel opens at the page's right at 360pt, drags from 280pt to half the window and is remembered, collapses to an edge tab; in a compact width or Split View it is a bottom sheet (medium keeps the page usable). The page's zoom and place don't move across open, resize and shut in all three layouts. — **R3** #100
- [ ] The first Run in the app (`-debug-first-launch` clears it): the panel opens on "Before your first run" with the Privacy Policy link, and nothing runs; Not Now leaves it and the next ▷ asks again; Run runs the block and the notice never shows again. Readable in light and dark. — **QC** R3
- [ ] Sandbox Pro, on the TestFlight build (an Xcode build signs purchases in the "Xcode" environment, which the proxy answers with 402): ▷, ⌘R and the edit menu's Run run a C++, a Java and a Python block; stdout in the code font, compile errors and stderr in the error colour, Stop works, input from the Input tab reaches the program. — **R4** #103, **R2** #90
- [ ] Edit the block after a run: the result dims with "Code changed since this run"; delete or edit the running block mid-run: Run isn't ignored and a late answer doesn't land on another block. — **R3**, **QC bugs** #113
- [ ] Keep in Note writes or replaces the ` ```output ` block under the code, one ⌘Z removes it, and it does nothing in a locked note. A `file:line` in a compile error puts the caret on that line. — **R4** #103
- [ ] Airplane mode, the daily cap and a proxy outage each show their own message; the cap and the outage offer "Open on a Site Instead", airplane mode doesn't. That button takes a C++ block to Compiler Explorer with the code already there, and a Java block to Programiz with the code on the pasteboard. — **R4** #103, #118
- [ ] Chips and the PRO badge follow a custom accent (a pale accent gets a black label); the badge scales with Dynamic Type; VoiceOver says "Run, part of Pro". Run panel in dark mode. — **QC cohesion** #111
- [ ] One run in each of the seven languages (C++, C, Java, Python, JavaScript, Rust, Go) confirms the Judge0 ids in `languages.json`, and RapidAPI's dashboard shows one bill per run. (The proxy is deployed, 28 Oct; a non-Pro request answers 402.) — **R2** #90

## 5. Select tool and ink

Run these with the selection probe if anything is odd: build and install with
`xcodebuild build -project NoteCode.xcodeproj -scheme NoteCode -configuration Debug -destination 'generic/platform=iOS' -allowProvisioningUpdates`
then `xcrun devicectl device install app --device 00008142-000C28EA2109401C <path to NoteCode.app>` and
`xcrun devicectl device process launch --terminate-existing --device 00008142-000C28EA2109401C com.marcus.NoteCode -- -debug-selection-probe`;
do the steps, pull `tmp/selectionprobe.log` with
`xcrun devicectl device copy from --device 00008142-000C28EA2109401C --domain-type appDataContainer --domain-identifier com.marcus.NoteCode --source tmp/selectionprobe.log --destination <file>`.
(A `selection changed` line with `pkSelection > 0` after a pen tap says the pen selects.) — object-system

- [ ] Pen tap on a few strokes close together: no cluster highlight (PaperKit's tap-to-highlight). — **FB 29**, object-system
- [ ] Lasso a group, move it, tap empty space: it lets go; the hotbar stays where it was after the move. — **FB 24**, object-system
- [ ] Select with the lasso, switch to the pen: the selection lets go. — **FB 30**, object-system
- [ ] Rectangular selection: drag a box, strokes and objects inside are selected. — **FB 6**
- [ ] Back to the previous tool after a selection (Settings option). — **FB 16**
- [ ] Recolour text from ink mode with the lasso (unlocked notes; locked and code lines select no text); undo it from text mode. — **FB 26**, object-system
- [ ] Insert a photo and a shape: popover opens, the button un-lights, the element can be dragged and scaled with a finger and with the Pencil; the Pencil-only lock; two fingers. — insert-and-templates, object-system, ROADMAP
- [ ] After Insert, the new object stays selected and the options row shows (shape, photo, line, text box); choosing another tool lets go. — **O1** #88
- [ ] Moving and scaling a selection is smooth on a note with thousands of strokes, with finger and Pencil; one ⌘Z after release; zoomed in, the drag may look soft until release. — **O2** #97
- [ ] Pencil: latency, palm rejection, squeeze and double-tap, the lasso on cut strokes, the eraser on a stopped stroke. — ROADMAP, pages
- [ ] Pixel eraser, Pencil lifted after each: across one stroke, across several, on a note with thousands of strokes; then text mode and back, and leave and reopen the note: no crash, the gaps stay. Lasso an erased stroke and recolour it: the gap doesn't fill in. — pixel eraser crash, 28 Oct
- [ ] Pencil double tap in text mode swaps to the pencil; if nothing happens, the fallback is a `UIPencilInteraction` on the text view. — **FB 23**, the-note-page
- [ ] Tool change shows at once on the hover mark. — **FB 17** (PaperKit's own; note if it lags)
- [ ] Draw through a code block's panel and along a quote: the stroke is clean, no awkward border. — **FB 22**
- [ ] The live drag of a selection at thousands of strokes and at zoom stays smooth; the overlay above the canvas in print layout. — object-system
- [ ] Ink in light mode and Increase Contrast. — colour

## 5b. LaTeX

- [ ] Inline `$x^2$` draws inside the line in the text's colour and size, baseline-aligned, sharp at high zoom; `\$5` stays a price; a formula that can't be drawn keeps its dollars, dimmed. — **L1–L3** #83, #96, #102
- [ ] A `$$` block draws centred on a line of its own (its gap of 8pt above and below looks right), scales down when wider than the column, and its source lines are nearly flat. Block heights hold at other text sizes (the 1.71pt allowance was measured at 17pt). — **L4** #105
- [ ] Tap a formula: the editor popover (a page sheet when narrow) with live preview and SwiftMath's message for bad TeX; Done writes back, Remove deletes, Done is off while empty; locked notes open read-only. — **L5** #106
- [ ] Arrow keys and taps never leave the caret inside a formula; Backspace deletes a whole formula in one undo step; selections never half-cover one; the end of a note that finishes with a block can still be typed after. — **L5** #106
- [ ] Style ▾ › Inline Formula and Display Formula, ⇧⌘M and ⌥⌘M, edit menu Format; seeded from the selection; not inside code. — **L5** #106
- [ ] Share ▸ PDF and a thumbnail show formulas as crisp vectors in black, once each, with no TeX source. — **L6** #107
- [ ] Get Info doesn't count words in a formula; the outline shows a heading's TeX without dollars; copy gives the source in Menlo; a rich paste with `$` is escaped as `\$` (a pasted lone `$` can still pair with one on the line). — **L7** #108

## 6. Pages and paper

- [ ] Draw down past the page foot: a page is added (end point decides); Add Page from the menu; the buffer while drawing. — **FB 8**, pages
- [ ] A stroke across a page break stays on the same words in seamless, compressed and print layouts; undo and redo take a stroke and its overflow together. — pages
- [ ] Move between pages by scrolling fast and by the outline: ink isn't blank for a moment. Note how long. — **FB 27**, pages
- [ ] Long note (20 pages with dots) scrolls at speed without hitching. — paper-styles, pages
- [ ] ••• › Paper: pick each style, spacing and strength; the tick follows; Blank hides Spacing and Strength; the note's date and the list order don't change. — paper-styles
- [ ] Settings › Notes › Paper, then "+": the new note has that paper, an old note doesn't change. — paper-styles
- [ ] Pinch-zoom to 4x on grid and dots and draw along a rule with the Pencil: paper stays on the same words and ink as you zoom, and is sharp, no shimmer. — paper-styles, ROADMAP
- [ ] Switch seamless, compressed and print layout and rotate the iPad: paper stays with its page body. — paper-styles
- [ ] Share ▸ PDF, open it in Files: paper is faint and vector (zoom in), margins plain; the PDF of a quote across a page break. — paper-styles, obsidian-s-other-marks
- [ ] Duplicate a ruled note; Export All with a ruled note that has ink. — paper-styles
- [ ] A note with thousands of strokes opens in a few seconds and writing stays smooth. — pages, AGENTS

## 7. Colours and icons

- [ ] The ink palettes: pen and highlighter swatches read well; the Colour Set row; dark-mode highlighters are vivid and blend (light multiplies, dark opaque). — **FB 5, 28**, colour
- [ ] Settings › restore the original palette: Reset Colours brings back the first palette; Add Colour from a sheet. — **FB 4**, settings, colour
- [ ] The hotbar's drawn icons, in ink mode (Select, pen, eraser rows) and the text bar: each reads; Delete, Duplicate, Adjust, Done, Lasso and Rectangle are the ones intended. — **FB 5**, colour (icons: "not seen in ink mode")
- [ ] Settings › Toolbar Icons: Drawn and System, and the weight (light/regular/bold): the bar changes at once. Menu items inside menus stay SF Symbols. — colour, settings
- [ ] Light mode and Increase Contrast (a step heavier) with the hotbar and rows; the Pencil on a drawn icon. — colour
- [ ] Folder badges and sidebar icons in light and dark. — recently-deleted-and-folder-faces

## 8. Settings

- [ ] Open every page of Settings once (only the section list was ever seen): each row does what it says and persists. — settings
- [ ] Settings › General › Appearance with a note open changes the look at once. — settings
- [ ] App Icon (General): three previews; choosing one shows iOS's "changed the icon" alert and the Home Screen icon follows; Dark and Tinted Home Screen styles. — settings, AGENTS (app icon)
- [ ] The icon's pencil sits centred between the chevrons at every size; the upper margin is tight, so check it on the Home Screen. — **B2** #86
- [ ] Open Note After Creating (Notes) on and off; New Notes orientation; Plain Text is called Code. — settings, **FB 12, 15**
- [ ] Marker dimming rows: Off, Dim, Full each on screen, in dark mode. — **FB 9**, settings
- [ ] Haptics where they are offered. — settings
- [ ] Tip jar (list's foot): rows appear in TestFlight with real products; a sandbox purchase thanks you; Feature Request and Send Feedback each open a mail to notecodesupport@gmail.com with its own subject; Privacy Policy opens the page. — the-list-s-foot-and-the-tip-jar, ROADMAP

## 8b. Pro, paywall and privacy

- [ ] Sandbox: the paywall shows $4.99 per month, Subscribe, Restore Purchases, Terms of Use and Privacy Policy, and the AI line matches this iPad's Apple Intelligence state; Subscribe works and the paywall says you have Pro. Try it at the largest Dynamic Type size. — **P1, P2** #91, #98, #111
- [ ] Settings › Pro shows Pro and the renewal date; Manage Subscription opens the system sheet; Restore works on a second install; as a free reader See NoteCode Pro opens the paywall. A refund or expiry turns Pro off. `-debug-pro on` and `off` both launch. — **P1, P2** #91, #98
- [ ] Free (`-debug-pro off`): Explain Block and ••• › Summarise Note open the paywall, nothing generates; Pro: Explain runs. — **P2** #98
- [ ] The paywall with no network (airplane mode, fresh launch): "Couldn't reach the App Store." with Try Again instead of a price; Try Again with the network back shows $4.99. The renewal text ends with the cancel-24-hours sentence. — **QC** S4, S5
- [ ] Ad Privacy Options (free, an EEA or UK region or VPN): after Home's consent form, Help and About has the row and it opens Google's form; change the answer and the banner follows. Outside those regions, and for Pro, no row. Also after a launch straight into a note. — **QC** A4
- [ ] Settings › Help and About: Privacy Policy row opens the page; Send Feedback opens a mail to notecodesupport@gmail.com. — **R5** #114, **QC** #111
- [ ] After the pages are published to `gh-pages`: the Privacy Policy row and the paywall's link open the *new* page (dated 10/31/26, with Run and ads), and `/NoteCode/support` loads. — **R5** #114
- [ ] The upload: App Store Connect didn't ask the export-compliance questions, so `ITSAppUsesNonExemptEncryption` survived in `Info.plist`. — **QC** A1

## 9. On-device assistant (Apple Intelligence on)

- [ ] Settings › Writing › On-Device Assistant: switch, Answer Length and Insert As are there; the footer is plain when available. — ai-features
- [ ] In a C++ block, edit menu › Explain Block: the sheet opens, text streams, Stop works, the answer is plain sentences about this code. — ai-features
- [ ] The text row shows Explain with the caret in a block (not in an output block) and does the same. — ai-features
- [ ] Insert Below puts a quote under the block with a blank line each side; the menu on it offers the Output Block; ⌘Z takes it back in one step. — ai-features
- [ ] ••• › Summarise Note on a short note, then on a 30-page one: "Reading part n of 5" and the "Only the first part fit" line. — ai-features
- [ ] Airplane mode: both still work. — ai-features
- [ ] Switch the assistant off: the items go. Turn Apple Intelligence off in system Settings: the items stay and the sheet says to turn it on. — ai-features
- [ ] Lock the note: Insert Below is disabled, Copy is not; VoiceOver reads the answer and announces "Answer ready". — ai-features
- [ ] If answers are cut early or fail with "too long", tune `AIBudget.charactersPerToken` (3) and the 4-piece limit. — ai-features
- [ ] Does a header button for Explain belong in the code block (instead of the menu only)? A real-finger decision. — ai-features (provisional 1)

## 10. Import, export and sharing

- [ ] Share menu: hold, its items, and the share sheet for `.md`; Copy as Markdown's toast; opening the `.md` in Obsidian. — notes-in-and-out, ROADMAP
- [ ] Import: Home's button and the list's menu item; the Files picker, a real `.md` coming in, and the alert for a skipped one. — notes-in-and-out
- [ ] Export All: the sheet, its progress and Cancel; `fileExporter` writes a folder in Files of the right shape (CS133/Labs as nested folders) and its PDFs open; the toast after Settings › Notes › Export All Notes…. — notes-in-and-out, ROADMAP
- [ ] A mixed-size note's PDF in the share sheet and in Files; printing goes through a PDF. — ROADMAP, the-note-page
- [ ] Open in Another Window (Stage Manager or Split View): the second window shows "Open in Another Window", and lets go when the first closes. — notes-in-and-out, ROADMAP
- [ ] Settings › Notes › Export All Notes… and Import… from Settings. — notes-in-and-out

## 11. Hardware keyboard and pointer

- [ ] The whole shortcut table (⌘B, ⌘I, ⌘U, ⌘Z, ⌘P and its dialog, ⌘, ⌘+ ⌘− ⌃⌘O, ⇧⌘H, ⇧⌘N, ⇧⌘F), and the ⌘ overlay on holding ⌘. — keyboard-edit-menu-pointer-dynamic-type, ROADMAP
- [ ] Bare-letter shortcuts are off while a field is typing; ⌘Z in ink mode undoes ink. — keyboard-edit-menu-pointer-dynamic-type
- [ ] Tab and ⇧Tab in lists and code; arrows move past hidden markers; Return and Backspace in a quote. — writing-hidden-markdown, obsidian-s-other-marks
- [ ] The code keys row hides with a hardware keyboard attached, and with a floating keyboard. — code-languages-and-keys, ROADMAP
- [ ] Pointer effects and the trackpad: hover on buttons, tapping a link with the trackpad, the edit menu on the iPad. — keyboard-edit-menu-pointer-dynamic-type
- [ ] Dynamic Type: the list and Home grow with it; the page does not. — keyboard-edit-menu-pointer-dynamic-type

## 12. Sizes, appearances and other devices

- [ ] iPad 11-inch and portrait for every newer feature above (Home, the list, options rows, paper, the hotbar docks). — ROADMAP, navigation, home-the-title-screen
- [ ] A hotbar docked left and right: rows sit beside it; the options row's width with the newer buttons. — navigation-and-the-text-options-row, object-system
- [ ] Light and dark, and Increase Contrast, through Home, the list, a note, Settings and the hotbar. — ROADMAP, colour
- [ ] Reduce Motion: the title screen fades, the side bar and floating bar don't slide. — home-the-title-screen, the-page-fills-the-window
- [ ] Stage Manager and a narrow Split View: the layout holds (the page fits its column). — home-the-title-screen, iphone-and-the-duo
- [ ] iPhone layouts (the app is iPad only for TestFlight 1; when it ships): landscape, the list's search, a folder tile, Delete's Undo in the stack, a search result's tap. — iphone-and-the-duo
- [ ] A physical Duo, after 23 Oct: unfolded flat, half-folded and upright; fold avoidance was simulator-only. — iphone-and-the-duo, ROADMAP
- [ ] macOS (it builds): Home, the list (drops don't work there; menus do), Settings and ⌘, — home-the-title-screen, settings

## Reading a probe

The debug launch options (`AGENTS.md`, "Debug launch options") work on the iPad
too: pass them after `--` to `xcrun devicectl device process launch --device
00008142-000C28EA2109401C --terminate-existing com.marcus.NoteCode --`.
`-debug-home -debug-keep-defaults` shows sample notes in memory without touching
yours; `-debug-probe` writes `tmp/notecode-probe.log` (what the list's drag and
drop receive), pulled as above with `--source tmp/notecode-probe.log`.
