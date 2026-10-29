# Shipping

Moved out of AGENTS.md on 26 Oct; AGENTS.md › Shipping keeps the rules.

What an upload checks before a person sees the app (4 Oct).
`AppStoreReadinessTests` checks each of these in the built app.

- **The privacy manifest** (`PrivacyInfo.xcprivacy`) has to list a reason
  for every required-reason API the app calls, or the upload is rejected.
  Today that's only UserDefaults, through `@AppStorage`, for the app's own
  settings (`CA92.1`). Calling one from another category — file
  timestamps, system boot time, disk space, active keyboards — means adding
  its reason. `CACurrentMediaTime` isn't on Apple's list. Notes never leave
  the device, so nothing is collected or tracked; a server would change
  that.
- **Exempt encryption.** `ITSAppUsesNonExemptEncryption` is `NO` in
  Info.plist: the only network traffic is the system opening a compiler's
  page over HTTPS. Encryption of the app's own would change the answer.
- **No background modes or entitlements it doesn't use.** Xcode's template
  declared push as a background mode and had an unused entitlements file
  for iCloud and push; both went on 4 Oct, since a mode the app never uses
  is a question in review. iCloud sync brings them back, through Signing &
  Capabilities.
- **Signing is the paid team** (9 Oct). Automatic signing, team
  `N454V8HV9J`. That ID was the free Personal Team, whose device profiles
  last seven days, and it can't sign push or CloudKit; Marcus re-obtained
  the paid Developer Program membership, and the same ID is now a paid
  Individual team, so the project's team setting didn't need to change.
  Read from Xcode's team list (`defaults read com.apple.dt.Xcode
  IDEProvisioningTeamByIdentifier`: `isFreeProvisioningTeam = 0`, team name
  "Marcus Chang" with no "(Personal Team)"), a new "Apple Development:
  Marcus Chang" certificate issued 8 Oct to 8 Oct 2027, and the app's
  team provisioning profile, made 8 Oct and valid a year. When an on-device
  build misbehaves, check which team signed it before reading any Swift.
  - **Marcus's working tree carries an uncommitted `project.pbxproj` edit**,
    and has since 8 Oct: Xcode set `CODE_SIGN_IDENTITY = "Apple Development"`
    for every SDK, in place of ad-hoc `-` for macOS (`"CODE_SIGN_IDENTITY
    [sdk=macosx*]" = "-"`), and added an empty `PROVISIONING_PROFILE_SPECIFIER`,
    when the paid account came back. It is his local state: **leave it
    unstaged, never commit or revert it, and don't mention it in summaries or
    PRs** (he knows). Stage files by name, never `git add -A` or `-a`. If a
    change needs `project.pbxproj` itself, stop and ask first.
- **iPad only, build 2** (14 Oct, v3 phase 8). The NoteCode target (both
  configurations) has `TARGETED_DEVICE_FAMILY = 2` and
  `CURRENT_PROJECT_VERSION = 2`; the test targets are untouched. The iPhone
  layout is designed, not built, so TestFlight 1 is iPad only; macOS is a
  separate platform in `SUPPORTED_PLATFORMS` and still builds. Bump the build
  number for every upload. The edit sits in Marcus's working tree beside his
  signing change and is not committed (see above).
- **Privacy and support pages** are drafted in `docs/site/privacy.md` and
  `support.md` for Marcus to host: nothing collected, notes stay on the device,
  Run sends a block's code to the compiler site the reader picked. They carry
  `DATE` and `EMAIL ADDRESS` placeholders. When they're hosted, set
  `AppInfo.privacyPolicy` and `.feedbackAddress` and the two About rows appear.
- **The app icon** (10 Oct, phase 7 of `docs/archive/ui-design-v2-implementation.md`):
  the set had no images, which fails an upload; it has them now. They are
  **drawn by `scripts/make-icons.swift`** (Core Graphics, the Logo board's
  120-unit geometry), which rewrites the three icon sets and their
  `Contents.json` outright: `swift scripts/make-icons.swift` from the
  repository root. Edit the script, never the PNGs.
  - **`AppIcon`**: Default (opaque), Dark (brackets and pencil on a
    transparent ground: the system supplies the background) and Tinted
    (greyscale, with the pencil at the orange's luma so it stays darker than
    the brackets once tinted), plus the ten macOS slots. Each macOS size is
    drawn at its own pixel size, not scaled from the 1024.
  - **Opaque except Dark.** The App Store rejects a marketing icon with an
    alpha channel, so the Default, both alternates and the Tinted image are
    written with none (`sips -g hasAlpha`); `AppIconTests.alpha` checks it.
  - **Alternates** `AppIcon-Paper` and `AppIcon-Orange`, named in
    `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, **scoped to the iPhone
    and iPad SDKs** (`[sdk=iphone*]`): they have no macOS art, so unscoped
    the Mac build warned "No applicable app icon found" for both. macOS has
    no `setAlternateIconName` either. One image each, with no Dark or Tinted
    variant, so they look the same in every Home Screen style.
  - **Full-bleed squares**, as the design says. The macOS slots are the same
    art, unmasked: not seen on a Mac, so check the Dock before shipping there.
  - **The colours live twice**, in the script and in `AppIconChoice`
    (AppSettings.swift), which Settings draws its previews from, since an
    icon set can't be loaded as an image by name. `AppIconTests` samples the
    background, a bracket and the pencil in each PNG against the model, so a
    change to one side fails until the other follows.
  - **Settings › General › App Icon** (iOS only) reads
    `UIApplication.alternateIconName` as it appears and after each change,
    and stores nothing: iOS keeps the choice, so a copy in `UserDefaults`
    could only disagree with the Home Screen. iOS puts up its own "You have
    changed the icon" alert on a change; it can't be turned off without
    private API. The Mac has no row.
  - **Not done:** Icon Composer's glass look (out of scope; Marcus can rebuild
    from the script's geometry), and the icon on a real Home Screen with
    Increase Contrast or a tint colour (the system composes both).


## Ads (P3)

Banners only, for readers without Pro (`AdBanner.swift`, `AdConfig.swift`,
`AdConsent.swift`). Release uses the real app and unit ids, every other build
Google's test ids (`AdConfig.units(forRelease:)`, pinned in `AdTests`).
`Info.plist` carries `GADApplicationIdentifier`, the ATT reason and Google's
`SKAdNetworkItems` (50 ids as of 28 Oct 2026; refresh when the SDK is updated).

- **Order**: Home's first visit runs the UMP consent flow, then starts the SDK;
  no ad is requested before. The ATT prompt is asked from the second Home visit
  on, never at launch. Without ATT consent the request carries `npa=1`.
- **Privacy manifest**: `NSPrivacyTracking` is true, with Google's tracking
  domains and data types, all for third-party advertising and unlinked from
  the reader. `AppStoreReadinessTests` pins this.
- **Age rating**: if asked, the app contains ads; general-audience AdMob
  banners, not aimed at children.
