# Shipping

Moved out of AGENTS.md on 26 Oct; AGENTS.md › Shipping keeps the rules.

What an upload checks before a person sees the app (4 Oct).
`AppStoreReadinessTests` checks each of these in the built app.

- **The privacy manifest** (`PrivacyInfo.xcprivacy`) has to list a reason
  for every required-reason API the app calls, or the upload is rejected.
  Today that's only UserDefaults, through `@AppStorage`, for the app's own
  settings (`CA92.1`). Calling one from another category — file
  timestamps, system boot time, disk space, active keyboards — means adding
  its reason. `CACurrentMediaTime` isn't on Apple's list. The manifest
  is no longer empty of collection: since P3 it declares what Google's ad
  SDK collects, all unlinked, tracking, for third-party advertising (see
  "Ads" below and "Privacy, Run and ads" at the end). The SDK carries a
  privacy manifest of its own, merged at build; ours covers the app's
  declarations. Notes still never leave the device.
- **Exempt encryption.** `ITSAppUsesNonExemptEncryption` is `NO` in
  Info.plist: the app's own network traffic is HTTPS through `URLSession` (the
  run service, StoreKit, the ad SDK's requests) and the system opening a
  compiler's page, which is exempt. Encryption of the app's own, beyond
  what the OS provides, would change the answer.
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
  - **The signing is committed** (8 Nov): `CODE_SIGN_IDENTITY = "Apple
    Development"` for every SDK and an empty `PROVISIONING_PROFILE_SPECIFIER`,
    which Xcode set on 8 Oct when the paid account came back, and which lived
    only in Marcus's working tree until 1.2.0 (5) was archived from it.
- **iPad and iPhone** (31 Oct, for 1.0.1). TestFlight 1 was iPad only: the
  NoteCode target had `TARGETED_DEVICE_FAMILY = 2` in Marcus's working tree
  (14 Oct, v3 phase 8), while the iPhone layout was designed and not built.
  It is built now (iphone-and-the-duo.md), so the target is `"1,2"`, as
  committed, and the App Store listing needs iPhone 6.9-inch screenshots
  beside the 13-inch iPad's. The app target lists no macOS platform
  (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, as 1.2.0 shipped).
- **The build number** (8 Nov). `Config/Version.xcconfig` holds
  `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, and is the base of the
  NoteCode target's Debug and Release configurations, so a release edits that
  file and not the project. Edit the file, not the target's General tab:
  Xcode writes a Version or Build typed there back into the project, where it
  overrides the file. Bump the build for every upload, archive from a clean
  commit on `main`, and tag it `v<version>-<build>`. `xcodebuild
  -showBuildSettings` gave the same settings before and after the move.
- **Privacy and support pages** are drafted in `docs/site/privacy.md` and
  `support.md`; Marcus copies them to the `gh-pages` branch (`privacy.md` is
  the page at `AppInfo.privacyPolicy`, which is now always set, so the
  paywall, Settings and the list's foot always link it). R5 rewrote them for
  Run and ads. `.feedbackAddress` is the support address,
  `notecodesupport@gmail.com` (31 Oct).
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
  on, never at launch. A "visit" is Home in front of the reader
  (`ConsentGate`): not its first appearance on a first launch, which comes
  before the launch has decided about the title screen and then sits under it
  (31 Oct; Google's form and the system's tracking prompt showed over the title
  screen). `HomeView.consentMayStart` is false until the launch task has
  claimed the title screen and while it is up. Without ATT consent the
  request carries `npa=1`.
  That order is the app's own. While the AdMob console publishes an IDFA
  explainer message for this app, Google's flow puts ATT on the first visit
  outside the EEA and UK (next bullet).
- **UMP's IDFA explainer asks for tracking on the first visit** (found 8 Nov,
  device pass home-4). The sequence was a fresh install in the US (en_US,
  simulator, the real `GADApplicationIdentifier`), Get Started, and then
  Google's "Our app wants to stay free for you" on the first Home visit.
  One Continue and the system ATT alert appeared half a second later, with
  Google's card still behind it.
  `adHomeVisits` was 0 going in, so `AdConsent`'s `visits >= 1` gate did not
  fire and the app never called `requestTracking()`. The defaults showed
  `IABTCF_gdprApplies` = 0, so no GDPR form was due, and
  `IABTCF_idfaFlowControl` = 5. What the reader saw was not a consent form.
  It was the **IDFA explainer message** published under AdMob › Privacy &
  messaging › IDFA. Google shows that message "immediately before the iOS
  ATT alert", and Continue on it raises ATT itself
  ([AdMob help 10115027](https://support.google.com/admob/answer/10115027),
  [10115331](https://support.google.com/admob/answer/10115331),
  [UMP iOS IDFA guide](https://developers.google.com/admob/ios/privacy/idfa)).
  `ConsentForm.loadAndPresentIfRequired` in `SystemAdPlatform.gatherConsent`
  presents whichever message UMP says is due, and the SDK has no parameter
  to leave out one type. Which message is due (Google's help says EEA readers
  may see the GDPR message instead; the split below is a Google forum answer,
  not yet checked in an EEA region):
  - Outside the EEA and UK: the IDFA explainer, so ATT comes on the first visit.
  - In the EEA or UK with no answer yet: the GDPR form, and no ATT. The
    app's own ATT prompt comes on the second Home visit ever (`adHomeVisits`
    is saved, so that may be a later launch's first), without the explainer.
  - In the EEA or UK after an answer: UMP would show the explainer on a
    later launch's first visit, but by then ATT has usually been answered,
    and UMP loads that form only while the status is not determined.

  The code could keep its own order only by not presenting the form on the
  first visit when `IABTCF_gdprApplies` is not 1, and presenting it on the
  second visit instead. GDPR would not wait, but the change leans on an
  IAB key UMP writes rather than on UMP's API. It would also still show
  the explainer, one visit later. Which way to go is Marcus's choice; no
  code changed:
  - **Accept it** (no change in the build). The first visit outside the EEA
    is Google's explainer and then ATT. The app's second-visit prompt stays
    as the fallback for the EEA and UK, and for when the explainer isn't
    published. The rating prompt already waits for tracking to be answered
    (`mayAskForReview` in `Pro/AppStoreEdition.swift`, checked by
    `ContentView`), so it is unaffected. Change the Order bullet above,
    features.md › Ads, the App Review notes
    (`release-1.0/R5-submission.md`, "on a later visit to Home") and the
    P3 line of `ipad-test-checklist.md` to say so.
  - **Turn it off** in the console: admob.google.com › Privacy & messaging
    › IDFA (Manage on its card) › the NoteCode message's row › Unpublish,
    then confirm. Google says the message can keep showing for up to 10
    minutes. After that the first visit outside the EEA shows nothing and
    ATT comes, bare, on the second visit, as designed. Readers who already
    answered are unaffected. To check, run a fresh install with
    `simctl privacy reset all` and look for no alert on the first Home
    visit (home-4).
- **Size**: the standard anchored adaptive size (`AdSizing`, 31 Oct), for the
  width the slot is given, measured on a placeholder the banner lies over.
  It was the large anchored size, up to 150pt tall: a seventh of an iPad
  mini's landscape screen for an ad on a page about notes, with the link
  and a see-through slot over Home's content. The standard one is at most
  90pt (the 728 by 90 shape iPads fill), so the strip with its link is about
  120pt. It fills as readily; the large size's draw is a higher bid, which a
  free tier of a student app can give up. One line (`AdSizing.size`) to go
  back.
- **Home's slot is a strip below the page** (31 Oct): `HomeView` is the page
  above and `AdSlot(opaque: true)` under it in a `VStack`, on the card
  colour with a hairline above, so nothing scrolls under it. "Remove ads" is
  in the strip under the banner, over nothing. (A safe-area inset of a
  see-through view let Home scroll beneath the ad and the link.) Measured on the
  banner itself, the width fed back on itself (a `BannerView` won't be
  narrower than its ad) and Home grew to 1720pt in an 1180pt window, cut off
  on both sides and, in landscape, not scrolling (30 Oct; `AdTests`).
- **Privacy manifest**: `NSPrivacyTracking` is true, with Google's tracking
  domains and data types, all for third-party advertising and unlinked from
  the reader. `AppStoreReadinessTests` pins this.
- **Age rating**: if asked, the app contains ads; general-audience AdMob
  banners, not aimed at children.

## Privacy, Run and ads (R5)

What the policy, the manifest and the App Store label have to agree on:

| Data | Where | Linked | Tracking | Label entry |
|---|---|---|---|---|
| Code and input, on an explicit Run (Pro) | our proxy, then Judge0 | no | no | **Other User Content**, App Functionality |
| Device ID, advertising data, product interaction, coarse location, crash and performance data, other diagnostics | Google AdMob (free readers) | no | yes, only if ATT is allowed | each as in `PrivacyInfo.xcprivacy` |
| Subscription id (opaque), IP | proxy, a day's/minute's count only | no | no | not collected (not stored beyond the counters; not linked to identity) |

- **Judge0 keeps submissions** (checked 3 Nov). Judge0 stores a submission
  to hand back by token and publishes no retention period, and its hosted
  service has deletion switched off (`"enable_submission_delete": false` at
  `ce.judge0.com/config_info`), so neither we nor a reader can remove one.
  The policy says Judge0 keeps them and we can't delete them, and tells
  readers not to run secrets; the label keeps **Other User Content**. The
  first-Run notice (`RunDisclosure.message`) still says "for a while"
  (ROADMAP › Known problems).
- **The first-Run notice and Ad Privacy Options** (QC items 7 and 5, built
  30 Oct). The panel holds the first run in the app and says where the code
  goes before anything is sent (`RunDisclosure`, the policy's own words in
  short); Help and About has an Ad Privacy Options row where UMP requires
  one (`AdConsent.privacyOptionsRequired`). The policy names both.
- Review notes, label choices and the hand-done steps: `docs/release-1.0/R5-submission.md`.

