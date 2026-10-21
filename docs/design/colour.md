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

## Proposal: a refined palette, swatches, icons, restore (21 Oct, not built)

From Marcus's 1.0 testing (feedback-plan.md, stream C): dark-mode colours too
dull, light mode a little uncanny, the hotbar swatches need refining, the icons
read as basic, and the original palette should be restorable. **Nothing here is
in the app yet.** Revised 21 Oct after Marcus looked at the sheet: pens
keep today's colours, the highlighters get the refined values, the swatch's
selection ring is grey, and dark-mode highlighter swatches are made more vivid
on the hotbar only (below). Look at `docs/design/colour-swatches.html` (current against
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
- **The hotbar's selected swatch ring is grey, not black**: black was too
  jarring in light mode.
- **Highlighters are marker chips** on the hotbar (28 by 18pt).
- **In dark mode, a highlighter's hotbar face is more vivid than the ink it
  draws**, on the hotbar only (the page, the palette settings list and
  anything else that shows the ink keep the real dark value).

### Proposed highlighters

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

### Accent: keep `#FA8500`

Brand orange, in the icon and the Increase Contrast pair (`#B85900` light,
`#FFAA33` dark). Measured: 8.9:1 on a dark page, 2.5:1 on white (so links use
the text variant, as built), and a white label on it is 2.5:1 (the code's
comment says 2.6), which the design accepts at 17pt semibold. A dark label
(`#1D1D1F`) on the orange fill is 6.7:1; it would cost the white-on-orange
look, so it stays a question. `SyntaxTheme` needs nothing: every role is
4.5:1 or better on its panel (light 4.5 to 5.6, dark 5.2 to 9.6), tested.

### Hotbar swatch presentation

Today (`HotbarSwatch`): a 22pt disc, a 1pt ring at 20% of the label colour, 4pt
padding; selected adds a 2pt ring in the tint and an 18% tint disc behind
(36pt). Measured problems: the selected ring is the accent, so on pen Orange it
is 1:1 against the swatch and on yellow 1.3:1; and the tint disc is a second
selection mark that also lands on a pale swatch. The 34 by 40pt cell, the 44pt
bar target and the row's 391pt width don't change.

| | Proposed |
|---|---|
| Pen | 24pt disc, same colours as today, 1pt inner edge: label colour at 28% (light) and 34% (dark), so a pale or near-black face keeps its outline |
| Highlighter | 28 by 18pt marker chip (6pt corners); dark face as above |
| Selected | a 2pt ring with a 2pt gap, 32pt outside (36 by 26 on a chip); no tint disc. Grey: `#8E8E93` in light, `#AEAEB2` in dark (3.3:1 against a light bar, 5:1 against a dark one). It works for every hue and doesn't depend on the accent. The dark grey is a guess: only light was complained about |
| Increase Contrast | ring 3pt, `#636366` light and `#D1D1D6` dark, edge at 50% |
| Disabled | 30% opacity, as now |
| Pointer, drag, hold | unchanged (`.hoverEffect(.highlight)` on the button, context menu to remove) |

Neighbouring swatches are 6pt apart with a selected ring, 10pt otherwise.

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

### Restore the original palette

Today: Settings › Drawing › Reset Colours to Defaults
(`InkPalette.resetStoredPalettes`) rewrites the two ink palettes to
`InkPalette.standard(for:)`, asks first, removes added colours and leaves ink
already on pages. It doesn't cover the accent (its own Default in
Accent Colour), `InkingSettings`' remembered colours or anything else.

With the pens unchanged, the two sets differ only in the highlighters:

- **Both sets ship.** `InkColor.highlighterShades` becomes the Refined values (Orange
  the same in both sets); today's move, unchanged, to `originalHighlighterShades` and stay pinned
  (`InkShadeTests` keeps its five old pairs as the Original set's). The pen
  table is shared. `shadeNames` covers both, so VoiceOver names for the old
  hexes still work. The starting highlighter colour follows the set
  (`highlighterYellow`: `FCDD79` refined, `FFF066` original).
- **One type, one `apply`** (the repo's rule): `InkPaletteSet` (`refined`,
  `original`), key `inkPaletteSet`, holding the two highlighter tables and
  `apply(to:in:)`, which writes both palettes and the remembered highlighter
  colour.
- **Settings › Drawing**: a Colour Set row (Refined, Original; Custom when the
  palettes differ from either), picking one asks first, as Reset does, and
  applies it. Reset Colours then resets to the chosen set. Each palette page
  (Pens, Highlighters) gets a "Restore" for that palette only.
- **Existing devices are not changed.** A device with a saved highlighter
  palette keeps it (that is `@AppStorage`), reading as Original. A device that
  has saved neither palette, and a new install, gets Refined. The set picker is
  how a tester goes either way.
- **Ink already drawn never changes** with either set (stored light values).
- **Not in scope for restore:** the accent (own Default), folder colours, text
  colours.

### Tests that pin today's values, to change in one commit with the palette

- `InkPaletteTests.swift:154-161`: the highlighter names and hexes,
  `standard(for:)` against `standardHighlighter`; lines 236-241 pin the
  starting highlighter colour (`highlighterYellow`), 247-251 the default
  state. The pen lines (147-148, 187-191) don't change.
- `InkShadeTests` (`InkPaletteTests.swift:273-329`): the five highlighter pairs
  and `tablesMatchPalettes` for `.highlighter` become one table per set, and it
  gains a check of the flip rule on the new five (the dark column is computed
  from it). Pens untouched; `toolCarriesSettings` keeps working (`83E286` is
  arbitrary).
- `SettingsTests.swift:91-96`: reset equals `standard(for:)`, per set.
- Not changed: `EditorModeTests.swift:250`, `FolderAppearanceTests.swift:68`,
  `AccentPaletteTests`, `AppIconTests`, `SyntaxThemeTests`.
- No test measures the swatch face (`HotbarSwatch` has no unit test; the UI
  tests that reach a swatch use the cell frames, which don't change), so add
  tests for the vivid-face function (hue kept, lightness and saturation floors,
  grey stays grey), the grey ring colours, and that a selected orange swatch's
  ring isn't 1:1 against it.
