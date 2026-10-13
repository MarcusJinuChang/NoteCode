# Phase 7: the app icon

Branch `claude/ui-phase-7-icon`, off `origin/main` at `e13f116` (Phase 6, merged
as PR #42). Not pushed.

## What changed

The app icon set had no images, which fails an App Store upload. It has them
now, drawn by a script, with two alternates and a Settings row to choose
between them.

| Piece | Where |
|---|---|
| The drawing script | `scripts/make-icons.swift` |
| Default icon, Dark and Tinted variants, macOS sizes | `AppIcon.appiconset` |
| Alternates | `AppIcon-Paper.appiconset`, `AppIcon-Orange.appiconset` |
| The build setting that declares the alternates | `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES[sdk=iphone*]` |
| The choice's names and colours | `AppIconChoice` in `AppSettings.swift` |
| The row | Settings › General › App Icon (`AppIconSection`, `SettingsView.swift`) |
| Tests | `AppIconTests` (new), one check added to `AppStoreReadinessTests` |

## How it works

**The art is code, not PNGs.** `swift scripts/make-icons.swift` (from the
repository root) redraws every image with Core Graphics, from the design's
120 × 120 grid: brackets stroked 10 with round caps, the pencil rotated 18°
about (60, 60) and shifted 1 left, filled and stroked 1.2. It deletes and
rewrites the three icon sets, `Contents.json` included, so a file the script
no longer makes can't linger. To change the icon you change the script.

Core Graphics' origin is bottom-left and the design's SVG is top-left, so the
script flips the context first (`translateBy(0, px)`, `scaleBy(s, -s)`). The
rotation matrix is the same in both, which is why the pencil tilts the same
way as in `NoteCodeMark`.

**Three flavours of image**, because the App Store and the system treat them
differently:

- *Opaque* (Default, Paper, Orange, macOS): sRGB with `noneSkipLast`, so the
  PNG has no alpha channel at all. The App Store rejects a marketing icon
  that has one. Checked with `sips -g hasAlpha`: `no`.
- *Transparent* (the Dark variant): brackets and pencil on nothing. Apple's
  dark-icon guidance is that the system supplies the background.
- *Grey* (the Tinted variant): drawn in a greyscale colour space. The system
  maps luminance onto the reader's tint colour, so the pencil is the orange's
  luma (0.6), not white: it stays visibly darker than the brackets once tinted.

Each macOS size (16 to 512, at 1x and 2x) is drawn at its own pixel size
rather than scaled down from the 1024, so strokes land on pixel edges.

**Alternates.** An alternate icon is another icon set in the catalog, named in
a build setting; actool then writes it into Info.plist under
`CFBundleAlternateIcons`, and `UIApplication.setAlternateIconName` can switch
to it. The setting is scoped `[sdk=iphone*]` because the alternates have no
macOS art: unscoped, the Mac build warned "No applicable app icon found" for
both (I saw that warning before scoping it). macOS has no
`setAlternateIconName` anyway, so the Mac gets no row.

**The row stores nothing.** iOS remembers which icon is showing
(`UIApplication.alternateIconName`) and keeps it across launches. A copy in
`UserDefaults` could only ever disagree with the Home Screen, so the row
reads the system as it appears and again after every change. If the system
refuses a switch, the tick goes back to what is really showing.

**Previews are drawn, not loaded.** An icon set can't be loaded as an image
by name (`Image("AppIcon-Paper")` finds nothing), so each choice is drawn
by `NoteCodeMark`, which now takes an `AppIconChoice` and uses its colours.
Colours therefore exist twice, in the script and in `AppIconChoice`; the next
section is how they're kept honest.

## Tests

`AppIconTests` (new, 5 tests):

- names map to choices and back; an unknown name reads as the Default;
- every alternate Settings offers is declared in the built app's Info.plist;
- **the art agrees with the model**: three points in each PNG that are solid
  colour whatever the antialiasing (the corner, the left bracket's vertex, the
  middle of the pencil's body) are compared with `AppIconChoice`'s colours;
- the Default, alternates and Tinted images have no alpha, and the Dark one is
  transparent at the corner;
- the Tinted icon is greyscale at those same points;
- all 13 slots of the Default set have an image at the size the slot says.

`AppStoreReadinessTests` gets one check: the built app declares `AppIcon` as
its primary icon and carries its files. That is the check that fails when the
set is empty, which is what an upload would have said.

**Both failure directions were tried.** I broke `AppIconChoice`'s Paper name
and Orange's pencil colour, and the tests failed: the declared-alternates test
caught the name, and the art test caught the colour
(`image.rgb(atGrid: pencil) == choice.pencil`). Both are restored.

**Switching is deliberately not a unit test.** I wrote one and it hung the run:
iOS puts up a "You have changed the icon" alert and `setAlternateIconName`
doesn't return until someone taps OK. A test that can't finish unattended is
worse than none, so it's removed and a comment in `AppIconTests` says why.

## Checked and not checked

Checked in the iPad Pro 13" simulator, dark appearance:

- Settings › General shows App Icon with the three previews, and the tick is on
  whichever icon the system reports. It started on Paper, left by my
  interrupted test run, which also shows the row reads the system's state and
  not a setting.
- Tapping Default switched the icon (the system alert showed the Default art),
  and after OK the tick moved to Default.
- iPad build, Mac build (no icon warnings after scoping the setting), and the
  full test suite: 694 tests in 86 suites pass.

**Not checked, and I'm not claiming them:** the icons on a real Home Screen;
the Dark and Tinted variants (they need the Home Screen's Dark and Tinted
styles); Orange chosen by hand; the row in light mode; Increase Contrast;
anything on the Mac; the real iPad. Also, the macOS slots are the same
full-bleed art as iOS (the brief says full-bleed squares); I haven't seen how
macOS places them in the Dock.

## Your checklist on the iPad

1. **Install and look at the Home Screen.** The icon should be the near-black
   tile with white brackets and an orange pencil. *A bug:* a blank or default
   white tile, or the pencil leaning left.
2. **Settings › General › App Icon.** Tap Paper. iOS shows "You have changed
   the icon" with the new art; tap OK. The tick should move to Paper and the
   Home Screen icon should change within a second or two. Repeat for Orange
   and Default. *A bug:* a tick that doesn't follow, or an error.
3. **Quit and reopen the app.** The tick should still match the Home Screen.
4. **Home Screen styles.** Long-press the Home Screen › Edit › Customise. Try
   Dark and Tinted. *Dark* should be white brackets and an orange pencil on
   the system's dark ground; *Tinted* should be a tinted, readable glyph with
   the pencil darker than the brackets. *A bug:* a pencil that vanishes into
   the brackets when tinted, or a harsh edge round the glyph in Dark.
5. **Icon on the grid at small size.** On the Home Screen, with the icon next
   to other apps, the brackets and pencil should both read.

## Things to know

- Paper and Orange have no Dark or Tinted variant, so they look the same in
  every Home Screen style.
- iOS's "icon changed" alert can't be turned off without private API.
- Icon Composer's glass look is out of scope per the brief; the script's
  geometry is what you'd rebuild it from.
- `NoteCode.xcodeproj/project.pbxproj` has a signing change of yours in the
  working tree (`CODE_SIGN_IDENTITY = "Apple Development"` and an empty
  provisioning profile specifier). I did **not** commit that: this commit's
  `project.pbxproj` change is only the alternate-icon setting.
