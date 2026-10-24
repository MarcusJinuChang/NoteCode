# Colour
The UI redesign's palette (7 Oct, phase 1 of `docs/archive/ui-design-v2-implementation.md`).

- **Accent** is `AccentColor.colorset`, `#FA8500` in light and dark, with
  `#B85900` and `#FFAA33` in the Increase Contrast slots. The target's
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` was already set, so the
  asset alone reaches SwiftUI's `.tint` and UIKit's `tintColor` (the caret,
  the selection); no root `.tint` was needed. The colorset was empty before,
  which is why everything was system blue. Checked in the built `Assets.car`
  with `xcrun assetutil --info`, all four variants.
- **The accent is editable** (15 Oct, roadmap step 9; Settings › General ›
  Accent Colour, `AccentPalette`). One hex per device under `accentColor`;
  nothing stored, or the orange itself, is the asset above and keeps its
  Increase Contrast slots. `AppearanceModifier` applies it at the root: `.tint`
  for SwiftUI and the window's `tintColor` for UIKit (the caret, selection, Run
  button), and the default sets neither.
  - **`Color.accentColor` ignores `.tint`** (measured; `accentColorIgnoresTint`),
    so nothing uses it. Use the `.tint` shape style, or `Color.accent(stored:)`
    where a `Color` is needed (the selected row, swipe tints; the view holds an
    `@AppStorage` for it).
  - **Text and fills.** Links are the accent as text: the design's pair for the
    orange, otherwise the chosen colour darkened (light) or lightened (dark)
    just far enough for 4.5:1 (`AccentPalette.textHex`, tested for eleven
    colours). `linkColor` is a dynamic colour that reads the stored value as it
    resolves, so no restyle is needed; `DocumentUITextView.tintColorDidChange`
    redraws the fragments. A checked box uses `AccentPalette.drawingColor`, so
    the PDF prints in the reader's accent. Labels on accent fills are white
    unless the accent is too pale to carry it (`accentFill`).
  - The app icon is not recoloured: iOS keeps its own.
  - Checked in the simulator with `-accentColor 066EE5` (the Run button and
    hotbar turned blue). Not looked at: the picker itself, Increase Contrast
    with a custom colour (it uses the one chosen), light mode.
- **Syntax colours are `SyntaxTheme`**, highlight.js CSS handed to
  HighlightSwift through `HighlightColors.custom(css:)`, replacing the stock
  Xcode theme. Pure strings, so tests read them without the JavaScript
  round trip. Measured on C++, Java and Python: the importer honours plain
  class selectors and the compound and descendant forms
  (`.hljs-title.class_`, `.hljs-class .hljs-title`), and `SyntaxThemeTests`
  checks which colour lands on which token. Each role is 4.5:1 or better on
  the code panel; a test computes the ratios.
- **Plain text is `.label`, which CSS can't say.** The HTML importer paints
  anything unstyled `#000000`, and the styler applies every run it's given, so
  without a rule plain code was black on the dark panel. The theme gives
  `.hljs` a sentinel colour (`SyntaxTheme.plainHex`) and the adapter drops runs
  in it. Revert that filter and `plainIsLeftAlone` fails.
- **Weight and italic aren't drawn.** The CSS asks for semibold keywords and
  italic comments, but `ColorRun` carries only colour. Carrying a font trait
  would mean the styler writing fonts after a highlight pass, which is another
  layout below the caret (see "Pages › Cost").
- **Run is the accent**, not green: `CodeBlockActionBar` tints it
  `UIColor.tintColor`. The copy button's green tick stays.

## Colour sets, highlighters and the hotbar swatch (21 to 23 Oct)

From Marcus's 1.0 testing (feedback-plan.md, stream C): dark-mode colours too
dull, light mode a little uncanny, the hotbar swatches need refining, the icons
read as basic, and the original palette should be restorable. **Built 23 Oct** (branch `claude/c-colour-proposal-50a2d1`): highlighters
and the swatch, as below; icons are not built. Revised after Marcus looked at
the sheet: pens keep today's colours, the highlighters get the refined values
except Orange, the swatch's selection ring stays the accent ring, and
dark-mode highlighter swatches are more vivid on the hotbar only. Look at `docs/design/colour-swatches.html` (current against
proposed, light and dark, on the page and the code panel, at hotbar size)
before the numbers. Marcus judges the taste; the numbers are there to explain
each choice.

### How PencilKit remaps a stored ink (measured, and the constraint everything follows)

Only the light value is stored, and a dark page shows the ink with its **HSL
lightness flipped** (`L' = 1 − L`, hue and HSL saturation kept). Every pair in
`InkShadeTests` (all twelve) is reproduced exactly by that rule, so the dark
column can be computed, not measured one swatch at a time. (`convertColor`
isn't on macOS, so this was fitted to the test table, not probed live; a probe
in the iOS simulator would confirm it for colours outside the table.) The rule
keeps the stored-light, shown-dark model as it is, and it fixes what is
possible:

- A colour near HSL L 0.5 looks the same in both appearances. Red, blue and
  purple today sit there (L 0.46 to 0.51), so they are as bright on black as on
  white, and on the code panel (`#1C1C1E`) dark red is 4.0:1, dark purple
  3.5:1 and dark blue 4.5:1.
- A light pastel becomes a dark shade of itself. Highlighters, stored at L 0.7,
  show at L 0.3: olive, brown and maroon.
- Light inks and dark inks trade against each other: to be vivid on black an
  ink has to be stored deeper than the neon it is on white.
- **Increase Contrast can't touch ink.** A stored colour is one value and
  PencilKit resolves the dark one; there is no slot for a third. IC applies to
  the swatch chrome and the accent only.

### What was measured in today's inks

Pens are kept by decision (below); the highlighters change. WCAG 2 contrast;
page `#FFFFFF`/`#000000`, panel `#F2F2F7`/`#1C1C1E`; OKLCH.

- **Light mode, "uncanny":** the seven pens are system-neon against paper.
  Chroma runs 0.16 to 0.23 and lightness 0.51 to 0.79, so purple and red shout
  while yellow and orange are pastel; yellow is 2.0:1 on the page and orange
  2.5:1 (3.2 green): a fine pen stroke in either is hard to see. Ink is pure
  `#000000`.
- **Dark mode:** pure black ink is pure white (21:1), a glare beside everything
  else. Orange, yellow and green flip to lightness 0.75 to 0.85, red, blue and
  purple stay at 0.58 to 0.62, so the set looks unevenly lit. Highlighters are
  the dull part: yellow `#998A00`, orange `#995200`, pink `#880748`, and
  graphite `#474747` is 1.8:1 on the panel (invisible). Their chroma is 0.12 to
  0.16 at lightness 0.4 to 0.63.
- **The pen Orange is the accent** (`#FA8500`), so the swatch's selected state,
  a tint ring, has nothing to show against it.

### Decided from the sheet (21 Oct, Marcus)

- **Pens stay as they are**, on the page and on the hotbar: the current
  colours are the more vibrant. Nothing in `penShades`, the pen palette or its
  tests changes, and Ink stays `#000000`. (The deeper, softer pens in the first
  version of this proposal are dropped.)
- **Highlighters: the proposed values**, as seen behind text in the sheet,
  **except Orange, which keeps today's** (`FFB866`, dark `995200`).
- **The selected swatch's ring stays the original accent ring** (2pt, tint).
  A black ring was too jarring and a grey one was drawn; Marcus kept the
  original. Known cost: on pen Orange, and a little on Yellow, the ring is
  nearly the swatch's own colour. Not changed.
- **Highlighters are marker chips** on the hotbar (26 by 18pt, ring 32 by 24).
- **In dark mode, a highlighter's hotbar face is more vivid than the ink it
  draws**, on the hotbar only (the page, the palette settings list and
  anything else that shows the ink keep the real dark value).

### The highlighters (built)

Stored light value, what a dark page shows, and the dark hotbar face. Black
text on the light value is 7:1 or better, and white text on the dark value is
about 4.5:1 (yellow 4.8, was 3.1:1 failing). Contrast is on page / on panel.

| Highlighter | Today (stored → dark) | Proposed (stored → dark) | Dark hotbar face | Light: page / panel | Dark: page / panel |
|---|---|---|---|---|---|
| Graphite | `B8B8B8` → `474747` | `9B9BA1` → `5E5E64` | `9B9BA1` | 2.0 / 1.8 → 2.8 / 2.5 | 2.3 / 1.8 → 3.3 / 2.6 |
| Orange | `FFB866` → `995200` | unchanged | `FF9C29` | 1.7 / 1.5 | 3.6 / 2.9 |
| Yellow | `FFF066` → `998A00` | `FCDD79` → `866703` | `FACA2D` | 1.2 / 1.1 → 1.3 / 1.2 | 6.0 / 4.9 → 4.0 / 3.2 |
| Green | `83E286` → `1D7C20` | `81E4A2` → `1B7E3C` | `40E778` | 1.6 / 1.4 → 1.5 / 1.4 | 4.0 / 3.2 → 4.1 / 3.3 |
| Pink | `F877B8` → `880748` | `EC558D` → `AA134B` | `E93E7E` | 2.5 / 2.3 → 3.4 / 3.0 | 2.2 / 1.8 → 2.9 / 2.4 |

- **The ink on a dark page** is the dark value: pink and graphite are
  lifted from today's (pink from maroon to raspberry, graphite from 1.8:1 to
  2.6:1 on the panel), and yellow becomes a warm gold (hue about 90°, was 102°)
  instead of olive, darker than before so white text reads on it. A yellow that
  is both a pale highlighter on white and a bright one on black can't exist
  under a lightness flip.
- **The hotbar face** (dark only; light uses the stored value) is a pure
  function of the dark value: keep its hue, saturation at least 0.78 and
  lightness at least 0.58 in HSL; a grey stays grey at lightness 0.62. It works
  for a colour the reader adds, and has no storage. Measured against the bar
  (`#3A3A3C`): 2.9 (pink) to 7.3:1.
- If a face reads neon on the iPad, lower the saturation floor.
- **How PaperKit blends a highlighter** (multiply, plain alpha) wasn't
  measured; the sheet draws them opaque with the text on top. The first
  on-device look decides whether the highlighters need another pass.
- **Folder colours and `TextColour` are unchanged** (they share hexes with the
  pens, which don't change either).

### Accent: kept at `#FA8500`

Brand orange, in the icon and the Increase Contrast pair (`#B85900` light,
`#FFAA33` dark). Measured: 8.9:1 on a dark page, 2.5:1 on white (so links use
the text variant, as built), and a white label on it is 2.5:1 (the code's
comment says 2.6), which the design accepts at 17pt semibold. A dark label
(`#1D1D1F`) on the orange fill is 6.7:1; it would cost the white-on-orange
look, so it stays a question. `SyntaxTheme` needs nothing: every role is
4.5:1 or better on its panel (light 4.5 to 5.6, dark 5.2 to 9.6), tested.

### Hotbar swatch presentation (built)

`HotbarSwatch` (InkToolbar.swift) is unchanged for a pen: a 22pt disc, a 1pt
ring at 20% of the label colour, 4pt padding, and a 2pt tint ring when
selected (no tint disc: `hotbarTarget()` is called without a highlight, which
the first version of this note got wrong). A highlighter's swatch is a
marker chip, `isMarker`: 26 by 18pt with 6pt corners, 3pt padding, and a ring
32 by 24pt. The 34 by 40pt cell, the 44pt bar target and the row's 391pt
width don't change, and a selected chip's ring is 2pt clear of its
neighbours'.

**The dark face is vivid** (`InkColor.vividFace`, `swatchFace(for:kind:)`):
only a highlighter, only on a dark appearance, and only on the hotbar (the
Palette settings list, the page and the PDF show the real ink). Pure
function of what a dark page shows: hue kept, HSL saturation at least 0.78,
lightness at least 0.58; a grey stays grey at 0.62. It has no storage and
works for a colour the reader adds. Light mode shows the stored value.

### Icons: decision

**Recommendation: draw a custom set, staged, with SF Symbols kept for the
system chrome.** Marcus has asked for custom (feedback-plan, Answered 3), and
restyling SF Symbols (weight, hierarchical or palette rendering, one optical
size) is a cheap first step that doesn't change what the glyphs are, so it
can't fix "basic". **Still open**: not answered since the first version.

- **What is needed, counted from the source:** the hotbar and options rows are
  about 33 glyphs: undo, redo, text and draw (the toggle, two states), pen,
  highlighter, eraser (pixel and object), lasso, finger draws, insert, add
  colour; and text: style, bold, italic, underline, strikethrough, inline code,
  list, code block, quote, link, highlight, colour, size + and −, indent,
  outdent. The menus use about 25 more that a custom set would cover
  (folder, move, pin, lock, info, duplicate, export, print, trash, search, home,
  settings, …); 63 distinct SF symbols are used in the app in all.
- **Build it the way the app icon is built:** a script, `scripts/make-symbols.swift`
  (Core Graphics, like `scripts/make-icons.swift`), holds each glyph as paths on
  one 24-unit grid with a shared stroke weight and corner rule, and writes the
  `.symbolset` SVGs into `Assets.xcassets` plus a contact sheet PNG to look at.
  Edit the script, never the SVGs. Custom symbols tint like SF Symbols and
  follow the selected-state tint. Not verified before building: how many of
  Xcode's weight and size variants a symbol set must carry (a spike is the
  first step), and whether one path source can also drive a pure-SwiftUI
  `Shape` fallback for macOS.
- **Order:** tool glyphs last, since the object system (stream O) is changing
  the lasso and rectangle tools; text-row glyphs and the hotbar's fixed ones
  first, menus last.
- **Cost:** a script and its contact sheet (about a session), the 33 hotbar and
  row glyphs over about four review rounds with Marcus judging each sheet, the
  25 menu glyphs after that (optional: menus conventionally keep SF Symbols,
  and the mix is still consistent if the hotbar and rows are custom), a spike
  for the asset format, and the accessibility labels, which stay as they are.
- **Risks:** hand-drawn glyphs at 17pt medium look uneven against SF Symbols in
  the same menu (mitigated by drawing menus too, or by leaving them alone);
  Dynamic Type and weight don't follow unless the symbol carries variants;
  the macOS build needs the same assets; any glyph left as an SF Symbol must be
  listed so the set doesn't end up half and half by accident.
- **If Marcus wants the cheap version instead:** restyle SF Symbols with
  `.symbolRenderingMode(.palette)` for the tool icons (tool in the label
  colour, the selected tool's accent as the second layer), one fixed point size
  and weight, and a filled variant for the selected state. Half a session, no
  assets, and still "SF Symbols" to a keen eye.

### Restore the original palette (built)

`InkPaletteSet` (InkTool.swift; `refined`, `original`; key `inkPaletteSet`):
one type for what moves together. `apply(to:)` writes the choice, both
palettes and the highlighter's remembered colour (keeping its width);
`resetPalette(for:)` puts one palette back; `matching(pen:highlighter:)`
says which set the palettes are exactly, or `nil` (Custom) once a colour is
added, removed or moved. The pens are one table for both sets, so the sets
differ only in the highlighters: `InkColor.highlighterShades` is Refined,
`originalHighlighterShades` is today's, pinned (`InkShadeTests` keeps its
five old pairs). Orange is the same in both. The names for both sets' hexes
are in `shadeNames`, so VoiceOver still reads a saved Original palette.

- **Settings › Drawing**: a Colour Set menu (checkmark on the matching set,
  "Custom" when none), which asks first, as Reset does, and applies; Reset
  Colours resets to the device's set; each palette page has a Restore for that
  palette. An open note's editor follows the highlighter's new remembered
  colour (`InkToolPersistence`).
- **Which set a device is on** (`InkPaletteSet.stored`): its choice; failing
  that, Original if it saved either palette before sets existed (those
  highlighters are the old ones), Refined if it saved none. A new install is
  Refined. Nothing changes under a device that has saved palettes.
- Ink already drawn never changes with either set.
- Not in the set: the accent (own Default), folder colours, text colours.

### Highlighter ink across a code panel (23 Oct, from T's report)

T found the "awkward border where ink crosses a code block" is the
highlighter's blend (docs/design/pages.md): PencilKit's marker blends with
what is under it, so its colour steps where the page becomes the panel
(`#F2F2F7` / `#1C1C1E`), and on a dark page it hides the code beneath. The
swatch sheet's section 5 models it (light as multiply, dark as opaque: modelled,
not measured). Under multiply the light step is the panel's 5% (F2/FF), the
same on every highlighter.

The three options, and what I recommend:

1. **Panel colour closer to the page**: it only shrinks the step (a panel at
   `#F7F7FA` is 3%) and costs the panel's separation from the page, which is
   what marks a block as code. The contrast tests would pass (syntax roles are
   4.5:1 or better on the panel and a lighter light panel only raises them;
   Output has its own), but it doesn't remove the step, and in dark it does
   nothing for the hiding. **Not changed.**
2. **A normal blend for the highlighter, if PaperKit allows it**: removes the
   step and, with a translucent colour, the hiding. Unknown whether
   `PKInkingTool` or PaperKit exposes the blend for a marker; **recommended
   as the first thing to try**, a spike of an hour: set the tool's ink type or
   a PaperKit render option and look at a stroke across a panel's edge. If the
   marker's look depends on the multiply (text visible through it in light),
   a normal blend would need the colour to carry alpha.
3. **Draw the highlighter under the code text**: the real fix for the dark
   hiding, but ink is one canvas above the text view, so it means a second
   layer or per-block masking: not small. Only if option 2 fails.

### Tests that pinned today's values (changed in one commit with the code)

- `InkPaletteTests.swift`: `highlighterDefaults` (Refined hexes) and a new
  `originalHighlighters`; `names` (both sets' names); `startsInItsPalette`;
  `InkShadeTests` (the five Refined pairs, the five Original pairs kept,
  `tablesMatchPalettes`, `originalTableMatches`); new suites `Colour sets`
  and `The hotbar's swatch faces`.
- `SettingsTests.resetPalettes`: per set, and `resetFollowsTheDevice`.
- Not changed: `EditorModeTests`, `FolderAppearanceTests`, `AccentPaletteTests`,
  `AppIconTests`, `SyntaxThemeTests` (the pens, folders, accent and syntax
  colours are all unchanged).

### Highlighter blend over a code panel: the spike (23 Oct)

Measured with `InkBlendTests` (prints; PaperKit's own draw path, as the PDF
draws, light-page values only), a `FCDD79` stroke over four backdrops:

| Ink | white | panel `F2F2F7` | black | dark panel `1C1C1E` |
|---|---|---|---|---|
| `.marker` | `FCDD7A` | `EFD276` | `000000` | `1C180E` |
| `.pen` | `FCDD79` | `FCDD79` | `FCDD79` | `FCDD79` |
| `.pen`, colour at 50% | `FEEEBE` | `F7E7BA` | `7B6B3B` | `89794A` |

- **The marker multiplies**: it takes the backdrop's colour into its own, so
  the panel's 5% step is the multiply, and on black it vanishes (this path is
  not how a dark page is shown on screen; the on-screen dark behaviour was
  **not measured**, since driving ink mode in the simulator didn't work).
- **A normal blend exists only as another ink type** (`.pen` or `.monoline`
  with a translucent colour), which changes the highlighter's look and leaves
  old `.marker` strokes as they are. **It doesn't remove the step**: any
  translucent stroke over two backdrops differs by (1 − alpha) times the
  difference between them (the table's 50% row still steps by 7). An opaque
  stroke has no step and hides the text under it.
- **Drawing it under the code text is not feasible without a redesign**: the
  panel is an opaque fill painted by the text view's fragments (and "can't go
  translucent", Pages › selection note), and ink is one canvas above the text
  view, so ink below the text would be hidden by the panel, and a second
  canvas below it means a second owner of touches. Not built, on purpose.
- **Conclusion: nothing small fixes it.** Leave the panel and the marker as
  they are. If the step matters, the realistic options are a panel colour
  nearer the page (shrinks, never removes it) or accepting it.

### Icons: built (24 Oct)

`NoteCode/NoteIconGeometry.swift`: 32 icons as paths on a 24-unit grid (pure
CoreGraphics; layers of stroke, solid and a 24% soft second tone;
`IconWeight` light / regular / bold at 1.5 / 1.8 / 2.2). `NoteIcon.replacing(systemName:)`
maps each SF symbol name the bar hands to `HotbarIcon` to its drawn icon, so
no call site changed and accessibility labels are untouched (the drawn view
is hidden from VoiceOver; the button's label speaks). `HotbarIcon` draws it in
a 22pt box inside the same 44pt target (`HotbarLayoutTests` passes), with the
selected tint and the disabled 30% as before.

The set: undo, redo, text, draw, pen, highlighter, eraser, pixel eraser,
object eraser, finger draws, insert, add colour, style, bold, italic, underline,
strikethrough, inline code, list, code block, quote, link, plus, minus, indent,
outdent, and the Select tool's: lasso, rectangle, done, adjust (Edit), delete,
duplicate.

**Setting** (Settings › General): Toolbar Icons (NoteCode or System) and, for
NoteCode's, Icon Weight (light, regular, bold). One stored string under
`iconStyle` (`IconStyle`), read by `HotbarIcon`; no `apply(to:)`, since nothing
else moves with it. **Increase Contrast** draws one weight heavier
(`IconStyle.increased`). System shows the SF Symbols as before, which is the
way back.

**Sheet**: `swiftc NoteCode/NoteIconGeometry.swift scripts/icon-sheet/main.swift -o /tmp/icon-sheet && /tmp/icon-sheet out.png`
draws every icon at 22pt in light and dark and at 44pt in three weights.

**Still SF Symbols**: every `Label(…, systemImage:)` inside a menu (Style's,
List's and Code Block's items, the note and folder menus, swipe actions), the
text row's Highlight menu face (`Image(systemName: "highlighter")`), the ink
colour menu's rings, and the eraser's size dots. A menu item takes an image,
not a view, so drawn icons there mean the custom-symbol asset route (an
`.symbolset` per icon, the template's weights still to be checked by a spike):
not done, and not needed for the bar.

**Tests** (`NoteIconTests`, 6, all pass; mutation-checked: dropping a name's
mapping, an icon with no stroke, light weight equal to regular, and Increase
Contrast not heavier each fail them). They check that every symbol the bar
names has an icon, each icon is used once, every icon has a stroke and sits
inside its grid, inks between 3% and 50% of a 22pt box (readable, not a slab),
heavier weights ink more, and the style round-trips.

**Not seen**: the bar in ink mode (the Select, pen and eraser rows) on the
simulator (driving ink mode failed twice); the text bar and its row were seen
on the 13-inch in dark. Not checked on an iPad: light mode, Increase Contrast
on screen, the Pencil.

### Provisional (Marcus to review)

- Icons (24 Oct, built): the Text toggle is an I-beam beside lines of text
  (an A with a caret read as "AI"); Delete is a trash can, Duplicate two
  overlapping squares, Adjust (Edit) three sliders, Done a check, Select
  Lasso a dashed loop with a tail, Select Rectangle a dashed box.
- Icons: drawn on a 24 grid, strokes 1.5 / 1.8 / 2.2 for light / regular /
  bold, round caps and joins, a 24% soft second tone on the tool bodies.
- Bold's B is drawn at 1.35 times the weight; the quote's bar the same, to
  match the bar the page draws beside a quote.
- Insert is drawn as a square overlapping a circle (shapes), not a plus.
- Finger Draws is a pointing hand.
- Menu items inside menus stay SF Symbols (see above).
- The setting is a Toolbar Icons choice plus a weight, not a set of styles:
  cheap, and System is the way back.

### Still to do from the colour work

- On-screen look at the highlighter swatches and the Colour Set row on an iPad
  (the checklist in the report); the dark-mode blend on screen.
