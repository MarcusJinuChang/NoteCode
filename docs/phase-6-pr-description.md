# Phase 6: Settings

Branch `claude/ui-phase-6-settings`, off `origin/main` at `aef4b49`. Not pushed.

## What changed

Settings opens as a form sheet from a gear at the foot of the note list, or ⌘,.
It is a list of sections, each a page of its own:

| Section | Rows | Stored in |
|---|---|---|
| General | Appearance | `appearance` (new) |
| | Toolbar Position (iPad) | `hotbarDock` |
| | Haptic on Snap (iPad) | `hapticOnSnap` (new) |
| Notes | View | `pageViewMode` |
| | Sort By, Order | `noteSort` |
| Writing | Show Markdown | `showMarkdown` |
| Code | Run Code In, Another Site… | `runDestination.appDefault` |
| Drawing (iPad) | Finger Draws | `fingerDraws` |
| | Pens, Highlighters (swatches) | `inkPalette`, `highlighterPalette` |
| | Eraser | `eraser` |
| | Reset Colours to Defaults (asks first) | both palettes |
| Help and About | mark and wordmark, Acknowledgements, Version | — |

Every row binds the key its owner already used, through the owner's constant.
Only Appearance and Haptic on Snap are new keys.

### Left out, on purpose ("only rows that work")

- **App Icon**: phase 7 builds the icons.
- **New Notes** (Portrait / Landscape): it is the "+" button's tap, which is
  phase 8. A row now would change nothing.
- **Welcome Note**: phase 8.
- **Send Feedback, Privacy Policy**: they need an address and a URL.
  `AppInfo.feedbackAddress` and `AppInfo.privacyPolicy` are `nil`, and each row
  appears when its value does. **I need both from you.** The privacy policy is
  required to submit.
- **Finger Draws needed no new key**: it was already per device before this
  phase, so the row and the hotbar's hand button are the same setting.

## The mechanics (for learning)

**Opening it.** The sheet's state lives in `ContentView`, above the list, so ⌘,
works when the list has slid away over a note. A menu command can't see a
window's state, so the window in front publishes its binding with
`focusedSceneValue` and `SettingsCommands` reads it with `@FocusedValue`. The
gear is a `safeAreaInset` on the list. I started with a `.bottomBar` toolbar
item and the simulator put it at the centre of the screen with the list hidden,
so it moved into the list itself.

**Appearance.** `AppearanceModifier` reads the stored value with `@AppStorage`
and applies `.preferredColorScheme` once, at the root of the scene. SwiftUI turns
that into the window's interface style, which sheets and UIKit controllers
presented from it inherit. That is what makes a change reach every window while
you watch. The PDF already renders light on its own.

**A stale editor would have undone a setting.** The sheet sits over an open
note, whose editor copied the device's eraser and Finger Draws when the note
appeared. Change them in Settings and the editor keeps the old values, and the
next tap of the hand button would write its stale value back over yours.
`InkToolPersistence` now also follows the stored values (only when they differ,
so its own writes aren't echoed back). The palettes needed nothing: every
swatch row reads the same key.

**Haptic on Snap** is `.sensoryFeedback(.alignment, trigger:)`, the haptic meant
for snapping to a grid or edge. `drop` bumps a counter and the setting is the
condition. Moving the bar from Settings, or from its "Dock …" accessibility
actions, doesn't tick, since neither is a snap.

**The palette page** is a `List` with `onDelete` (swipe), `onMove` (Edit) and
Add Colour through the same `InkColorPicker` the hotbar uses. `InkPalette`
already refuses to remove the last colour or hold one twice.

**Acknowledgements** is a bundled text file: HighlightSwift's MIT licence and
highlight.js's BSD licence, since HighlightSwift ships highlight.js inside the
app. Copied from the package checkout; a package update means copying again.

## Tests

- `SettingsTests`: stored key names pinned; appearance raw values; feedback
  link needs an address; version reads `1.0 (1)`; both licences are bundled;
  eraser summary; Reset Colours restores both palettes and leaves other keys.
- `AppearanceSettingTests`: hosts a view in a window and sets the stored value
  light → dark → light → system; the window's style follows each time.
- `FingerDrawsPersistenceTests` +2: a value changed in Settings reaches an open
  note's editor and canvas (Finger Draws, eraser).

Mutation check: with the persistence `onChange`s emptied the two new
persistence tests fail; with `preferredColorScheme` removed the appearance test
fails; both pass restored.

## Checked and not checked

Builds for iPad and Mac. Simulator: the sheet opens from the gear and shows the
six sections, in dark. **Nothing else was looked at on screen**: no page was
opened, no row changed, not tried in light mode, on the Mac, with the keyboard
(⌘,), or with the Pencil.

## Your checklist (iPad)

1. Tap the gear at the foot of the list. A form sheet opens with six rows.
   Also with a note open and the list closed, press ⌘, (keyboard). Bug: nothing
   opens, or it opens twice.
2. **General › Appearance**: pick Dark, then Light, then System, with a note
   open behind the sheet. The sheet, the note, the hotbar and the list all
   change as you pick. Bug: any of them stays behind, or System doesn't return
   to the iPad's own setting. Then open the colour picker (Drawing › Pens › Add
   Colour) in Dark: it should be dark too.
3. **Toolbar Position**: Left, Bottom, Right. The bar moves, and the page
   doesn't resize. **Haptic on Snap**: drag the bar to an edge with it on (a
   tick) and off (none).
4. **Notes › View** changes the open note's layout when you close the sheet.
   **Sort By / Order**: the list reorders; picking Title gives A to Z.
5. **Writing › Show Markdown**: Always shows every fence in the note; While
   Editing hides them away from the caret.
6. **Code › Run Code In**: pick Compiler Explorer; a new note's run button goes
   there. **Another Site…** with `vscode.dev` adds it to the list.
7. **Drawing › Finger Draws**: turn it off with a note open in ink mode; the
   hotbar's hand button follows, and a finger scrolls instead of drawing.
8. **Pens / Highlighters**: swipe a colour away, Edit and drag one to reorder,
   Add Colour. Open a note's pen row: it shows the same swatches in the same
   order. Bug: the last colour can be removed, or a duplicate appears.
9. **Reset Colours to Defaults** asks first; Cancel changes nothing; Reset
   restores seven pen inks and five highlighters.
10. **Eraser**: Whole Strokes greys out Size; Custom shows a slider. The hotbar's
    eraser row shows the same choice.
11. **Help and About**: the mark, "NoteCode", Acknowledgements (both licences,
    scrollable), Version `1.0 (1)`. No Send Feedback or Privacy Policy row yet.
