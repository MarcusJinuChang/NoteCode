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
in the app yet.** Look at `docs/design/colour-swatches.html` (current against
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

### What is wrong with today's inks (WCAG 2 contrast; page `#FFFFFF`/`#000000`, panel `#F2F2F7`/`#1C1C1E`; OKLCH)

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

### Proposed inks

Stored light value, and what a dark page shows. Each pen is chosen so the light
value is at least 4.5:1 on the page (3:1 for orange and yellow, which can't be
darker without going brown) and the dark value is 4.5:1 or better on the panel;
each highlighter so black text on the light value is 7:1 or better and white
text on the dark value is about 4.5:1. Contrast is on page / on panel.

| Ink | Today (stored → dark) | Proposed (stored → dark) | Light: page / panel | Dark: page / panel | Dark OKLCH L/C, was → now |
|---|---|---|---|---|---|
| Ink | `000000` → `FFFFFF` | `1B1B1D` → `E2E2E4` | 21.0 / 18.8 → 17.2 / 15.4 | 21.0 / 17.0 → 16.2 / 13.2 | 1.00/0.00 → 0.91/0.00 |
| Red | `DA101E` → `EF2533` | `A91E29` → `E15661` | 5.2 / 4.6 → 7.2 / 6.5 | 5.0 / 4.0 → 5.7 / 4.6 | 0.61/0.23 → 0.64/0.17 |
| Orange | `FA8500` → `FF8A05` | `E75D13` → `EC6218` | 2.5 / 2.2 → 3.5 / 3.2 | 8.9 / 7.2 → 6.3 / 5.1 | 0.75/0.18 → 0.66/0.19 |
| Yellow | `EBB000` → `FFC414` | `BC8D15` → `EABB43` | 2.0 / 1.8 → 3.0 / 2.7 | 13.2 / 10.7 → 11.7 / 9.5 | 0.85/0.17 → 0.81/0.14 |
| Green | `27A551` → `5AD884` | `1D8752` → `78E2AD` | 3.2 / 2.9 → 4.5 / 4.1 | 11.6 / 9.4 → 13.3 / 10.8 | 0.79/0.16 → 0.83/0.13 |
| Blue | `066EE5` → `1A82F9` | `1A59B7` → `4887E5` | 4.8 / 4.3 → 6.7 / 6.0 | 5.6 / 4.5 → 5.9 / 4.8 | 0.62/0.20 → 0.63/0.16 |
| Purple | `8E22C3` → `A83CDD` | `672B94` → `A76BD4` | 6.6 / 5.9 → 8.9 / 8.0 | 4.4 / 3.5 → 5.7 / 4.6 | 0.58/0.24 → 0.63/0.16 |

| Highlighter | Today (stored → dark) | Proposed (stored → dark) | Light: page / panel | Dark: page / panel | Dark OKLCH L/C, was → now |
|---|---|---|---|---|---|
| Graphite | `B8B8B8` → `474747` | `9B9BA1` → `5E5E64` | 2.0 / 1.8 → 2.8 / 2.5 | 2.3 / 1.8 → 3.3 / 2.6 | 0.40/0.00 → 0.48/0.01 |
| Orange | `FFB866` → `995200` | `FA9242` → `BD5505` | 1.7 / 1.5 → 2.3 / 2.0 | 3.6 / 2.9 → 4.5 / 3.6 | 0.51/0.12 → 0.57/0.15 |
| Yellow | `FFF066` → `998A00` | `FCDD79` → `866703` | 1.2 / 1.1 → 1.3 / 1.2 | 6.0 / 4.9 → 4.0 / 3.2 | 0.63/0.13 → 0.53/0.11 |
| Green | `83E286` → `1D7C20` | `81E4A2` → `1B7E3C` | 1.6 / 1.4 → 1.5 / 1.4 | 4.0 / 3.2 → 4.1 / 3.3 | 0.51/0.15 → 0.52/0.13 |
| Pink | `F877B8` → `880748` | `EC558D` → `AA134B` | 2.5 / 2.3 → 3.4 / 3.0 | 2.2 / 1.8 → 2.9 / 2.4 | 0.41/0.16 → 0.48/0.18 |

Why each change:

- **Pens are stored deeper** (HSL L 0.32 to 0.49, saturation 0.55 to 0.85) so
  they read as pigment in light mode, not system neon, and flip to luminous,
  evenly lit colours on a dark page: dark lightness 0.63 to 0.66 for red, blue,
  purple, orange, and 0.81 to 0.83 for yellow and green (their
  chroma is now 0.13 to 0.19 across the set, was 0.16 to 0.24). Every dark pen
  is 4.6:1 or better on the panel, every light pen 4.5:1 on the page except
  orange and yellow at 3.0 and 3.5.
- **Ink is `#1B1B1D`**, not black: 17:1 on white, and a soft `#E2E2E4` on a dark
  page instead of 21:1 glare. Notes drawn in the old black keep it; the two
  look the same at a glance.
- **Orange moves off the accent** (hue 21°, vermilion; the accent is 32°), which
  frees the swatch ring.
- **Highlighters**: orange, pink and graphite are lifted in dark mode (pink from
  maroon to a raspberry, graphite from 1.8:1 to 2.6:1 on the panel), the three
  hues keep their colour, and **yellow gets honest, not brighter**: it is
  physically impossible for a yellow to be both a pale highlighter on white and
  a bright one on black under a lightness flip. The new yellow is a warm gold
  (hue about 90°, was 102°) rather than olive, and white text on it is 4.8:1 (was 3.1:1,
  failing), at the price of being darker. If a bright dark-mode highlight
  matters more than a pale light one, store them near L 0.55 and accept a
  heavier light highlighter: the one dial there is.
- **How PaperKit blends a highlighter** (multiply, plain alpha) wasn't
  measured; the sheet draws them opaque with the text on top. The first
  on-device look decides whether the highlighters need another pass.
- **Folder colours and `TextColour` are not changed.** They share hexes with
  today's pens (`FolderColor` says so, and `FolderAppearanceTests` pins it);
  whether they follow is a question for Marcus (below).

### Accent: keep `#FA8500`

Brand orange, in the icon and the Increase Contrast pair (`#B85900` light,
`#FFAA33` dark). Measured: 8.9:1 on a dark page, 2.5:1 on white (so links use
the text variant, as built), and a white label on it is 2.5:1 (the code's comment says 2.6), which the
design accepts at 17pt semibold. A dark label (`#1D1D1F`) on the orange fill is
6.7:1 and is the only change that would help; it would cost the white-on-orange
look, so it is a question. `SyntaxTheme` needs nothing: every role is 4.5:1 or
better on its panel (light 4.5 to 5.6, dark 5.2 to 9.6), tested.

### Hotbar swatch presentation

Today (`HotbarSwatch`): a 22pt disc, a 1pt ring at 20% of the label colour, 4pt
padding; selected adds a 2pt ring in the tint and an 18% tint disc behind
(36pt). Measured problems: the selected ring is the accent, so on pen Orange it
is 1:1 against the swatch and on yellow 1.3:1; and the tint disc is a second
selection mark that also lands on a pale swatch. The 34 by 40pt cell, the 44pt
bar target and the row's 391pt width don't change.

| | Proposed |
|---|---|
| Pen | 24pt disc, 1pt inner edge: label colour at 28% (light) and 34% (dark), so a pale or near-black face keeps its outline |
| Highlighter | 28 by 18pt marker chip (6pt corners), so the two palettes read as different tools at a glance |
| Selected | a 2pt ring in the label colour (black on light, white on dark) with a 2pt gap, 32pt outside; no tint disc. It works for every hue and doesn't depend on the accent |
| Increase Contrast | ring 3pt, edge at 50% |
| Disabled | 30% opacity, as now |
| Pointer, drag, hold | unchanged (`.hoverEffect(.highlight)` on the button, context menu to remove) |

Neighbouring swatches are 6pt apart with a selected ring, 10pt otherwise.

### Icons: decision

**Recommendation: draw a custom set, staged, with SF Symbols kept for the
system chrome.** Marcus has asked for custom (feedback-plan, Answered 3), and
restyling SF Symbols (weight, hierarchical or palette rendering, one optical
size) is a cheap first step that doesn't change what the glyphs are, so it
can't fix "basic".

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

Once the redesign exists:

- **Both sets ship.** `InkColor.penShades` / `.highlighterShades` become the
  Refined set; today's tables move, unchanged, to `originalPenShades` and
  `originalHighlighterShades` and are pinned forever (`InkShadeTests` keeps its
  twelve pairs as the Original set's). `shadeNames` covers both, so VoiceOver
  names for the old hexes still work.
- **One type, one `apply`** (the repo's rule): `InkPaletteSet` (`refined`,
  `original`), key `inkPaletteSet`, holding the two tables, the starting pen
  and highlighter colours (`InkingSettings.standard(for:)`) and
  `apply(to:in:)` which writes both palettes and the two remembered colours.
- **Settings › Drawing**: a Colour Set row (Refined, Original; shows Custom
  when the palettes differ from either), picking one asks first, as Reset does,
  and applies it. Reset Colours then resets to the chosen set. Each palette
  page (Pens, Highlighters) gets a "Restore" for that palette only.
- **Existing devices are not changed.** A device with a saved palette keeps it
  (that is `@AppStorage`), reading as Original. Only a new install defaults to
  Refined. The set picker is how the 1.0 testers get the new colours, and how
  anyone goes back.
- **Ink already drawn never changes** with either set (stored light values).
- **Not in scope for restore:** the accent (own Default), folder colours, text
  colours.

### Tests that pin today's values, to change in one commit with the palette

- `InkPaletteTests.swift:147-161`: the pen and highlighter hex lists, the shade
  names, `standard(for:)` against `standard`/`standardHighlighter`. Lines
  187-191 (`shadeNames`: "Ink" for `000000`, "Orange" for `FA8500` and
  `FFB866`) keep passing and become the Original names; add the new hexes.
  Lines 236-241 pin the starting colours (pen `.black`, highlighter
  `highlighterYellow`), 247-251 compare the default state.
- `InkShadeTests` (`InkPaletteTests.swift:273-329`): the twelve light → dark
  pairs, `tablesMatchPalettes`, and the colours in `toolCarriesSettings`
  (`066EE5`, `83E286` are arbitrary and keep working). It becomes one table per
  set, and gains a check of the flip rule on the new twelve (the proposal's dark
  column is computed from it).
- `SettingsTests.swift:91-96`: reset equals `standard(for:)`.
- `EditorModeTests.swift:250`: reads `InkPalette.standard.colors` (fixed, not
  dynamic); follows the new set.
- `FolderAppearanceTests.swift:68`: "with the base colours of the ink palette"
  pins the same hexes for folders; only changes if folders follow the pens.
- Not changed unless the accent is: `AccentPaletteTests` (`FA8500`, its text
  pair, the white label), `AppIconTests` and `AppIconChoice`
  (`AppSettings.swift:89-104`), the colorset.
- Not changed: `SyntaxThemeTests` (contrast 4.5:1 on the panel).
- No test measures the swatch face (`HotbarSwatch` has no unit test; the UI
  tests that reach a swatch use the cell frames, which don't change), so add
  one for the ring and the chip, and a render check that a selected orange
  swatch's ring isn't 1:1 against it.
