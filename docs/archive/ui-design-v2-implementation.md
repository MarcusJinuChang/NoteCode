# Implementing the UI design (v2): brief for an agent

Written 7 Oct 2026 against `main` at `eeef781`. Hand this whole file to the
agent as its task.

## Run settings

| | |
|---|---|
| Model | Sonnet 5.5 (`claude-sonnet-5-5`) |
| Effort | **high** |
| Agents | one; no subagents, no multi-agent workflows |
| Branches | one branch and one PR per phase, off `main`, in the order below |

**Why high.** The design is settled, so this isn't open-ended research
(max would be wasted). But almost every phase touches code where AGENTS.md
records a bug that is easy to bring back: TextKit 2's lazy layout, ink
that has to stay on its words, buttons inside a `UITextView`, the
typing-cost budget. Low or medium effort skims those notes, and the
regressions they prevent only show on the iPad. If Phase 5's first approach
fails twice, stop and report instead of trying a third.

---

## You are implementing

A UI redesign of NoteCode, an iPad note app for CS students: Markdown text,
code blocks that open in an online compiler, and PaperKit ink on Letter
pages. The design is finished and approved. Your job is to build it,
phase by phase, without breaking what AGENTS.md says must hold.

**The design canvas:** <https://claude.ai/artifact/8R5rgZmdLaW4kH1CjUiX8i>.
If you have an Artifact tool, read its boards (`read` with
`path: "project/<Board>.dc.html"`) to see them. This brief carries every
value you need, and **where the canvas and this brief disagree, this brief
wins**: it reconciles the design with features that merged after the canvas
was drawn.

| Board | Shows |
|---|---|
| `Main` | Colour: accent, page and surround, syntax colours |
| `Ink` | Pen and highlighter palettes, widths |
| `Logo` | The icon's exact geometry and its variants |
| `ScreenNote`, `ScreenInk`, `ScreenPrint`, `ScreenList`, `ScreenSettings`, `ScreenWelcome` | The target screens |
| `ToolSystem` | Where each control moves to |
| `Hotbar` | The two-row ink bar, menus, edit menu, shortcuts |
| `CodeBlock` | Fences away vs editing |
| `NoteList`, `Settings`, `Standard` | List states, every settings row, standard app pieces |

## Before writing code

1. **Read AGENTS.md in full.** It's the project's memory. At minimum,
   internalise: "Who owns scrolling", "Pages" (all of it), "The note page",
   "Implementation requirements", "Shipping", "Build/test" and "Debug
   launch options". Reading `.layoutManager` anywhere downgrades the text
   view to TextKit 1 silently. Anything that edits text storage after a
   keystroke costs a full layout below the caret. Ink lives in page
   coordinates.
2. Read `docs/ROADMAP.md` "Where things stand" for what's merged.
3. Read the files each phase names before changing them. The comments in
   this codebase explain *why*; keep that style.

## Working with Marcus

- He is learning iOS while building this. In each PR description, explain
  the mechanics of what you did and why, not just what changed.
- **He tests on-screen behaviour himself.** Builds and unit tests are fast
  here; simulator UI automation is slow and fights the tools. Keep any
  simulator check under about ten minutes. Past that, stop and put a
  checklist in the PR: what to do on the iPad, what should happen, and what
  would count as a bug.
- Never say something is verified on screen when it wasn't. Say plainly
  what you didn't check.
- For a regression test, revert the fix and confirm the test fails. A test
  that passes both ways isn't a test.
- Check both light and dark mode for anything that draws. Use sample
  content that could actually show the bug, such as descenders, long lines,
  a block at a page break.
- Don't merge. Marcus merges. Don't run an older branch on his iPad.

## Build and test

```bash
xcodebuild test -project NoteCode.xcodeproj -scheme NoteCode -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -parallel-testing-enabled NO
```

Also build the macOS destination; the target must keep compiling there
even where a feature is iPad-only (`#if canImport(UIKit)` as elsewhere).
Tests use Swift Testing. `scripts/debug-launch.sh` with `-debug-note`,
`-debug-mode`, `-debug-page` and `-debug-report` puts the app in a known
state for a quick screenshot.

---

## Reconciliations: design vs today's code

These merged after the design was drawn; build around them as stated.

| In the design | Today | Do this |
|---|---|---|
| Search field in the list | **Built** (`NoteSearch`, PR #27) | Keep it. Add the empty state only if it's missing |
| Find in Note in ••• | Magnifying glass in the header (`editor.showFind()`) | Move it into ••• › Find in Note; ⌘F stays |
| "Lock Text (later)" | **Built**: lock button in the header, `Page.isTextLocked` | Lock/Unlock Text goes in the **title menu**; a small `lock.fill` beside the title shows a locked note |
| Writing › Autocorrect, Smart Punctuation toggles | **Built** as automatic per region, no setting | No toggles: the system keyboard settings govern these. Writing has only Show Markdown |
| Account in the list footer | Disabled placeholder in the header | Remove it. Show no account UI until Sign in with Apple exists (App Review rejects placeholders) |
| Logo on the Welcome note's first line | Notes are text and ink only | No image in the note. The mark appears only in Settings' About header |
| "Double Tap and Squeeze" row opening Pencil settings | No public URL opens Settings › Apple Pencil | Footer text only; no link that pretends to go there |
| Settings › Storage row | Would need disk-size APIs | Leave it out: those are required-reason APIs and would need a new privacy-manifest entry |

**Model:** the store is at version 6. **Nothing in this brief needs a model
change.** If you find you need one, stop and ask.

---

## Design tokens

### Colour

| Token | Light | Dark | Notes |
|---|---|---|---|
| Accent (`AccentColor`) | `#FA8500` | `#FA8500` | One value in both appearances |
| Accent, High Contrast slot | `#B85900` | `#FFAA33` | iOS swaps these in with Increase Contrast |
| Page | `systemBackground` | `systemBackground` | white / black |
| Beside the page (surround) | `secondarySystemBackground` | `secondarySystemBackground` | #F2F2F7 / #1C1C1E |
| Code panel | `secondarySystemBackground` | same | keep what `CodeBlockLayoutFragment` uses |
| Selected list row | accent at 18% (#FFE9CF) with label text | accent at 22% | a tint, never white-on-orange |

**Where orange goes:** the mode toggle, the selected tool, the selected
colour, switches, the caret and selection (`.tint` on the text view does
this), Run, and standard tinted controls in the list and sheets (+, •••,
Done). **Where it doesn't:** the note page's header buttons (☰, title,
Share, •••) use the label colour, black on light and white on dark.

### Syntax colours

HighlightSwift takes custom CSS:
`HighlightColors.custom(css:background:)`. Replace `.light(.xcode)` and
`.dark(.xcode)` in `HighlightSwiftHighlighter` with highlight.js CSS using
these values. Each is 4.5:1 or better on its panel. The PDF uses the light
set (it already draws light).

| Role | hljs classes (check the output, map what's there) | Light | Dark |
|---|---|---|---|
| keyword | `hljs-keyword`, `hljs-literal` | `#AD5300`, semibold | `#FFAA33`, semibold |
| type | `hljs-type`, `hljs-built_in`, `hljs-class .hljs-title` | `#1F63B0` | `#6CB6FF` |
| function | `hljs-title.function_`, `hljs-title` | `#00727A` | `#5ED0D6` |
| string | `hljs-string` | `#2E7D32` | `#7ED68A` |
| number | `hljs-number` | `#7B3FC4` | `#C39BFF` |
| comment | `hljs-comment` (italic) | `#6E6E73` | `#8E8E93` |
| plain | | `label` | `label` |

`HighlightAlignmentTests` and `SyntaxHighlightingTests` must still pass.
Check that the colour runs still map (weight and italic may not come
through `ColorRun`; colour is what matters).

### Ink

PencilKit stores ink in its light colour and shows it on a dark page with
HSL lightness flipped (l → 1 − l). **Store only the light value**, as
`InkColor` already does. The dark column is PencilKit's own output,
measured on macOS 27, so use it as a test expectation for
`displayColor(for: .dark)` within 1/255.

**Pens**, in this order:

| Name | Light (stored) | Dark (shown) |
|---|---|---|
| Ink | `#000000` | `#FFFFFF` |
| Red | `#DA101E` | `#EF2533` |
| Orange | `#FA8500` | `#FF8A05` |
| Yellow | `#EBB000` | `#FFC414` |
| Green | `#27A551` | `#5AD884` |
| Blue | `#066EE5` | `#1A82F9` |
| Purple | `#8E22C3` | `#A83CDD` |

**Highlighters**, in this order:

| Name | Light (stored) | Dark (shown) |
|---|---|---|
| Graphite | `#B8B8B8` | `#474747` |
| Orange | `#FFB866` | `#995200` |
| Yellow | `#FFF066` | `#998A00` |
| Green | `#83E286` | `#1D7C20` |
| Pink | `#F877B8` | `#880748` |

**Widths**: three per inking tool, as multiples of the ink type's
`defaultWidth`, clamped to its `validWidthRange`. Pen: Fine 0.5×,
Medium 1×, Bold 2×. Highlighter: 0.6×, 1×, 1.6×. Medium is the starting
choice.

### Logo geometry

Everything on a 120 × 120 grid; the system masks the corners, so icon
images are full-bleed squares.

- **Brackets:** stroke 10, round caps and joins.
  `M38 38 L18 60 L38 82` and `M82 38 L102 60 L82 82`.
- **Pencil:** one group, `transform="translate(-1 0) rotate(18 60 60)"`,
  filled and stroked 1.2 in the same colour, round joins:
  body `rect x=55 y=38 w=10 h=36 rx=2`; tip `M55 77 H65 L60 89 Z` (the 3pt
  gap between body and tip is the notch). The −1 shift balances its
  clearance to both brackets at about 6 units each.

| Icon | Background | Brackets | Pencil |
|---|---|---|---|
| Default | `#141416` | `#FFFFFF` | `#FA8500` |
| Paper (alternate) | `#FFFFFF` | `#141416` | `#FA8500` |
| Orange (alternate) | `#FA8500` | `#FFFFFF` | `#141416` |

**Wordmark:** "NoteCode", SF Pro Bold, tracking −0.03em, one colour: the
label colour. No two-tone.

---

## Phases

Each phase lists what to build, then **Done when**. Write the tests named;
add others where the logic is pure.

### Phase 1: Colour foundation

- Fill `Assets.xcassets/AccentColor.colorset`: Any, Any + High Contrast,
  Dark, Dark + High Contrast, with the values above. Today it's empty, which
  is why everything is system blue.
- Apply `.tint(Color.accentColor)` at the root if the asset alone doesn't
  reach UIKit views. The text view's caret and selection follow
  `tintColor`.
- Syntax colours via `HighlightColors.custom(css:)` as above.
- **Done when:** builds; all tests pass; Marcus's checklist covers caret,
  selection, toggles and a C++, Java and Python block in light, dark, and
  with Increase Contrast on.

### Phase 2: The page against its surround

In seamless and compressed views the page becomes its own column: page
colour on the page, surround colour beside it. Print layout already works
this way; don't change it.

- `PageView` sets `backgroundColor` per mode (`.secondarySystemBackground`
  for print, `.clear` otherwise, near the `applyBands()` call). Make the
  surround show in every mode, and give the page column `systemBackground`
  beneath both text and ink. The existing `outline` and the text view's
  rounded corners (`placeOutline()`) already sit on the page's edges; build
  on them. The text view's own background is `.clear` on purpose (the
  canvas is inside it); choose where the page fill lives by reading why.
- **Compressed is seamless plus a dashed line at each page end, and nothing
  else** (changed 9 Oct). Don't paint its 24pt band: filling it with the
  surround colour, as this brief first asked, made the break read as a gap
  between pages, and Marcus had it taken out (PR #36).
  `PageDecorationView` draws the line. **Seamless:** the 1pt band stays as
  it is.
- The hotbar's reserved strips and anything outside the page show the
  surround, **with the keyboard up too**. The page layer ignores the
  keyboard's safe area but its stack keeps it, for the hotbar, so the
  surround has to be a background view that ignores every safe area
  (`.background { Color(…).ignoresSafeArea() }`). `.background(Color)`
  ignores only the container's, and the grey rode up with the keyboard.
- **Ink across page breaks: seamless is the reference** (decided 9 Oct,
  superseding a print-only mask that blanked text). A stroke across a break
  is bent: each point moves with its own page (`InkBending`,
  `PageLayout.inkY`), so it stays on its words and stays one stroke.
  Compressed's strip and print layout's top and bottom margins and gaps take
  no ink, and `PageCoverView` hides the stretch across them. Never put a
  mask on the canvas: masked, PaperKit's tiles painted over the text beneath.
- **Done when:** a portrait note on a landscape iPad shows surround on both
  sides in seamless and compressed, light and dark; a landscape note on a
  portrait iPad still fits; ink drawn near the page edge stays on the page;
  compressed's page ends show only the dashed line on the page colour; a
  stroke drawn from one sheet across to the next shows nothing over the
  surround; the surround stays put, all round the keyboard, when it comes
  up; `NotePDFTests` and `PageSettlingTests` pass unchanged; `typingCost`
  is no worse.
- **Status:** built in PR #34 (8 Oct); the band removed and the keyboard
  fixed in PR #36 (9 Oct); ink across page breaks, and the text the #36
  mask blanked, on `claude/ink-split-pages` (9 Oct).

### Phase 3: Note header

Today: ☰, then Find, View, Run destination, Share, Note Info, Lock and a
disabled Account. Below that, a large-title `TextField`. Target:

`☰ │ Title ⌄ │ … │ Share │ •••`

- **Title menu** (the title is the menu's label, with a chevron): Rename,
  Pin / Unpin, Move to Folder ›, Lock Text / Unlock Text, Get Info,
  divider, Delete. The order matches the list's note menu. Rename edits the
  title in place; disabled while the text is locked. Delete asks once
  (the note is open), deletes with `Page.delete(_:from:)`, and leaves the
  detail with no note selected. A locked note shows a small `lock.fill`
  after the title.
- **•••:** a View section (Seamless, Compressed, Print Layout with a
  checkmark; reuse `PageViewMenu`'s model), Run Code In › (what
  `RunDestinationMenu` offers today, including folder and new-note
  defaults), Find in Note (⌘F).
- **Share** stays (`NoteShareButton`).
- Share and ••• and ☰ use the label colour, not the accent.
- The large-title field goes. A new note opens with Rename active, so its
  title can be typed straight away.
- Try SwiftUI's editable navigation title (`navigationTitle(_:)` with a
  binding plus `toolbarTitleMenu`) first, since it gives iPad's standard
  rename. The custom header exists for reasons in its comments; if they
  rule that out, build the same behaviour in the custom header and say why
  in the PR.
- **Done when:** every action reachable today is still reachable (list it in
  the PR, old place to new); ⌘F, the view and run menus and lock all work;
  the macOS build compiles.

### Phase 4: Hotbar

**Text tools** (after the divider): Style ▾ (Heading 1, 2, 3, Body, then
Strikethrough), Bold, Italic, Inline Code, List ▾ (Bulleted only, for now),
Code Block ▾ (C++, Java, Python, Plain Text). The separate strikethrough
button goes.

**Ink mode is two rows.** The main bar holds: grip, undo, redo, Text │
Draw, divider, Pen, Highlighter, Eraser, Lasso, divider, Finger Draws. The
selected tool's options move to a thinner **options row**:

| Tool | Options row |
|---|---|
| Pen | its palette, Add Colour, divider, three widths |
| Highlighter | its palette, Add Colour, divider, three widths |
| Eraser | Pixel / Object, divider, small, medium, large, custom (today's `EraserOptions`) |
| Lasso | no row |

- The row is 40pt thick to the eye, but each control takes touches across a
  full 44pt, reaching toward the page. It sits 8pt from the main bar **on
  its page side**: above it when docked at the bottom, left of it when
  docked right, right of it when docked left. It's centred along the bar.
- It **floats over the page and reserves nothing.** The rule that moving
  the bar never resizes the page must still hold. Write a test that the
  page's frame and scale are identical in text and ink mode.
- It slides in on entering ink mode or picking a tool that has options,
  and out otherwise; a cross-fade under Reduce Motion. The main bar never
  moves.
- **Two palettes.** The pen keeps `InkPalette.defaultsKey` ("inkPalette"),
  so a device's saved palette survives. The highlighter gets its own key.
  New defaults are the tables above; a device with a saved palette keeps
  it. Each tool remembers its own selected colour and width (stored per
  device, like the dock).
- The squeeze palette (`InkToolPopover`) shows the tools, then the selected
  tool's options row.
- Keep `HotbarTrack`'s single-pass layout; its comment explains a freeze
  that `ViewThatFits` caused.
- **Done when:** `InkPaletteTests` cover two palettes, defaults, keeping an
  existing "inkPalette", widths round-tripping, and dark shades against the
  table; the page-frame test passes; Marcus's checklist covers each dock
  edge in both modes on an 11-inch landscape iPad, where the ink bar
  should now fit down the side without scrolling.

### Phase 5: Code-block fences, away and editing

A block's fence lines show their backticks only while the caret or a
selection is inside the block (opening fence to closing fence). Tap out
and the backticks disappear.

**Hard constraints:**

1. **Hide glyphs, never lines.** The fence lines keep their height.
   Collapsing them moves every line below, re-breaks pages, and leaves ink
   over the wrong words.
2. **No text-storage edits** to hide or show them. A storage attribute
   change lays out everything below (66ms a keystroke on a 500-line note,
   see "Pages › Cost"), and this happens on every caret move.

**Approach, in order:**

- **(a)** TextKit 2 *rendering attributes*
  (`NSTextLayoutManager.setRenderingAttributes` and
  `removeRenderingAttribute`) affect drawing, not layout. Set
  `.foregroundColor: .clear` on the fence characters of inactive blocks.
- **(b)** If (a) relays out, or doesn't draw, have
  `CodeBlockLayoutFragment` draw its lines itself (it already can, for the
  PDF) and skip the fence lines while inactive, then invalidate rendering
  only.

**Prove whichever you use doesn't lay out:** measure a caret move into and
out of a block on a 500-line note, against `PageViewTests.typingCost`'s
method.

**What the opening fence line shows:**

- **Away:** the language name on the left (C++, Java, Python, or the tag as
  typed), and Copy and Run on the right. `CodeBlockActionBar.frame` already
  centres the bar on the block's first line, which is that fence line.
- **Editing:** "```cpp" in the marker colour on the left, Copy and Run still
  on the right, and a thin accent ring around the panel, drawn in
  `drawPanel`.
- The **language name is a button**: a menu of C++, Java, Python, Plain
  Text that rewrites the fence's tag through `replace(_:withText:)`, so it's
  undoable and restyles. Run follows the new language. It's an action-bar
  control, so the tap rules in "Implementation requirements" apply.

**When a block counts as away:**

- In ink mode, every block is away.
- In print layout's PDF (`NotePDF` draws lines itself), the fence lines are
  never drawn.
- An unclosed block counts as active while the caret is in it, and stays
  highlighted as today.

**Setting:** Settings › Writing › Show Markdown: While Editing (default) or
Always.

**Done when:**

- A pure-function test covers which blocks are active for a given
  selection.
- A layout test shows the text after a block sits at identical line frames
  when the block is active and away. Prove it fails if you collapse the
  fences.
- A `NotePDFTests` case checks the PDF's text contains no "```".
- The cost measurement is in the PR.
- Marcus's checklist covers: fast typing into a new block, pasting a block,
  undo across a fence, a block split by a page break, dark mode.

**Optional, only if time remains:** inline-code backticks drawn clear when
the caret is outside them, by the same mechanism, widths unchanged.

### Phase 6: Settings

Entry points:

- a gear at the foot of the note list (a bottom bar holding only that, for
  now)
- ⌘,

It opens as a form sheet with a `NavigationStack`: a list of sections,
each opening its own page.

Build **only rows that work.** No "coming soon" rows.

**General**
- Appearance: System / Light / Dark. Store it per device and apply it at
  the root; the PDF stays light regardless.
- App Icon: Default / Paper / Orange (Phase 7).
- Toolbar Position: Left / Bottom / Right, bound to `HotbarDock`.
- Haptic on Snap.

**Notes**
- New Notes: Portrait / Landscape. This is the + button's tap (Phase 8).
- View: the `PageViewMode` key; the device default.
- Sort By: the `NoteSort` key.

**Writing**
- Show Markdown: While Editing / Always.

**Code**
- Run Code In: `RunDestinationPreference.appDefaultKey`, the same choices
  as the run menu.

**Drawing**
- Finger Draws: a new key; the hotbar's hand button starts each note from
  it.
- Pens: swatches.
- Highlighters: swatches.
- Reset Colours to Defaults: confirms first.
- Eraser: the current default.
- Footer: "Double tap and squeeze follow the Settings app › Apple Pencil."

**Help and About** (header: the Default mark and the wordmark)
- Welcome Note (Phase 8).
- Send Feedback: `mailto:` [FEEDBACK ADDRESS], ask Marcus.
- Privacy Policy: [PRIVACY POLICY URL], ask Marcus; hide the row until he
  gives one.
- Acknowledgements: HighlightSwift's licence text, from its package.
- Version: short version (build).

**Not built:** Account, iCloud, Templates, Recently Deleted, Export All,
code keys, indent, syntax-colour choice, line numbers, shapes, Storage,
Rate (no App Store ID yet), What's New (until there's an update).

**Never settings, on purpose** (see AGENTS.md "Page geometry"): note text
size or font, an existing note's orientation, page size or margins,
overriding the Pencil's double tap.

**Done when:** every row reads and writes the same key the rest of the app
uses (test the keys); Appearance changes every window live; Marcus's
checklist covers each row.

### Phase 7: App icon

AGENTS.md "Shipping" says the empty icon set fails an upload; this fixes
that.

- **Generate the PNGs with a script** you commit, for example
  `scripts/make-icons.swift`: Core Graphics drawing the geometry above at
  1024 × 1024, full-bleed and opaque. That way the icon can be rebuilt
  exactly. Later, Marcus can rebuild it in Icon Composer for the glass
  look.
- **AppIcon:**
  - Default.
  - Dark appearance variant: brackets and pencil on a transparent
    background, per Apple's dark-icon guidance.
  - Tinted variant: a greyscale glyph.
  - Fill the macOS slots too if the target uses this set.
- **Alternates:**
  - `AppIcon-Paper` and `AppIcon-Orange`, set as Alternate App Icon Sets in
    build settings.
  - `setAlternateIconName` from Settings › General › App Icon, showing
    each icon as a choice.
- **Done when:** `AppStoreReadinessTests` passes with the icon present (add
  a check if it doesn't test this); switching icons works on the simulator;
  the "Still missing" line in AGENTS.md "Shipping" is updated.

### Phase 8: Note list and first run

- **+** (`Menu` with a primary action):
  - Tap makes a note in Settings' New Notes orientation, inside the open
    folder.
  - Hold shows Portrait Pages, Landscape Pages, New Folder.
- **Selected row:** the accent tint with label-coloured text (see tokens).
- **Note menu:** the same rows and order as the title menu. The folder menu
  is unchanged.
- **Empty states:**
  - No notes: New Note, Open Welcome Note.
  - An empty folder.
  - No search results: `ContentUnavailableView.search` if search doesn't
    have one already.
- **Welcome note:** made once on first launch (a UserDefaults flag), and
  again from Settings › Help if asked, as a new note.
  - Title "Welcome to NoteCode".
  - Content below.
  - No seeded ink: that would mean shipping PaperMarkup data.
- **Launch screen:** the system background and nothing else (no logo
  splash).

~~~markdown
Type here like any note. Headings, **bold**, lists and `inline code` come from the bar below, or from Markdown as you type.

## Code

Three backticks and a language start a code block. Run opens it in a free online compiler; nothing runs on the iPad. Copy puts it on the clipboard.

```python
def greet(name):
    return f"Hello, {name}!"

print(greet("CS133"))
```

## Ink

Tap the pencil in the bar to draw on the page. The Pencil always draws; a finger draws too, or scrolls, as the hand button says. Ink stays on the words it was drawn over.

## Pages

Notes are Letter pages. ••• › View shows them seamless, compressed or as printed sheets, and Share makes a PDF.
~~~

**Done when:** `NoteListTests` cover the + default and the welcome flag
(made once, not again after deletion unless asked); creating the Welcome
note doesn't change another note's `modifiedAt`.

### Phase 9: Finishing

- **Edit menu** (`textView(_:editMenuForTextIn:suggestedActions:)`):
  - On prose: Bold, Italic, Code, then Format › (Strikethrough, headings).
  - Inside a code block: Run Block, Copy Block.
- **Keyboard shortcuts**, each with a discoverability title so holding ⌘
  lists them:

  | Action | Keys |
  |---|---|
  | Undo, Redo | ⌘Z, ⇧⌘Z |
  | Bold, Italic, Inline Code | ⌘B, ⌘I, ⌘E |
  | Heading 1–3, Body | ⌥⌘1–3, ⌥⌘0 |
  | Strikethrough | ⇧⌘X |
  | Bulleted List | ⇧⌘L |
  | Code Block, last language | ⇧⌘K |
  | Run Block, Copy Block | ⌘R, ⇧⌘C |
  | Text ↔ Draw | ⇧⌘D |
  | Pen, Highlighter, Eraser, Lasso | P, H, E, L |
  | Thinner, Thicker | [ and ] |
  | Seamless, Compressed, Print | ⌘1, ⌘2, ⌘3 |
  | Find | ⌘F |
  | Print | ⌘P |
  | New Note, New Folder | ⌘N, ⇧⌘N |
  | Search Notes | ⇧⌘F |
  | Note List | ⌃⌘S |
  | Settings | ⌘, |

  Single letters and brackets work only in ink mode with no text being
  edited.
- **Haptics:** a light tap on dock snap (behind the setting) and on Copy
  Block.
- **Pointer:** hover effects on hotbar and options-row buttons and on
  Run/Copy.
- **Dynamic Type** for the list, settings and menus. **Not the note body**:
  its size is part of its pagination.
- **Done when:** every shortcut is tested where testable; a checklist
  covers the rest.

---

## After each phase

- Update AGENTS.md where behaviour or structure changed, in its existing
  style: dated, specific, with the reason and anything measured. Header,
  hotbar, code blocks, settings and shipping will all need it.
- Update `docs/ROADMAP.md` "Where things stand" with what merged.
- The PR: what changed, the mechanics explained, tests added, what was and
  wasn't checked on screen, and Marcus's checklist.

## Out of scope

- Sign in with Apple
- iCloud sync
- Recently Deleted (needs model version 7)
- Templates
- AI features
- Pages side by side
- Infinite canvas
- Shapes and text boxes
- A code-keys row above the keyboard
- Syntax theme choice
- Line numbers
- A Java-fallback or custom-sites settings page (the run menu covers
  both)
- Seeded ink
- Icon Composer glass

Ask before starting any of them.
