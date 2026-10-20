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
