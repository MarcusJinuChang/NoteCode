# P. Pro and ads

Part of the 1.0 plan; the rules every session follows are in
[README.md](README.md) › Rules.

Builds on ROADMAP step 21 (branch `claude/roadmap-pro-plan`).

**Free is the whole notes app.** Pages, text, ink, code blocks with Copy,
LaTeX, folders, search, export: every note feature is free, with no limit on
notes or pages. Free users see a small ad, and have no in-app Run and no AI.

**Pro is no ads, in-app Run, and the AI features.**
- **$4.99 a month**, one auto-renewable subscription, no yearly plan and no
  free trial (decided 26 Oct). The paywall is how a free user learns what
  Pro does.
- AI is what is built now (Explain Code, Summarise Note;
  `design/ai-features.md`), moved behind Pro. More AI features and a higher
  price come after 1.0.
- **AI depends on the iPad**: Apple Intelligence, on an eligible device,
  switched on. The paywall says whether this iPad can use it
  (`SystemLanguageModel.default.availability`), so nobody pays for AI they
  can't run. Run and no ads work everywhere.
- Tips stay as they are: consumables that unlock nothing.
- TestFlight testers lose the free redirect from the build with R4, and buy
  Pro with sandbox accounts.

**Where ads go.** Never inside a note: a note is where people write in
lectures, and an ad there is the fastest way to a one-star review.
- One adaptive banner at the foot of Home, and one at the foot of the
  sidebar list (`ListFoot`), below the tip jar row.
- No interstitials, no rewarded video, nothing on opening or closing a note,
  nothing in Settings, the paywall or a sheet.
- Labelled "Ad", with a "Remove ads" link that opens the paywall.

### P1. `ProStatus` and the subscription

- `ProStatus` (`@Observable`, main actor): whether the reader has Pro, the
  product, the expiry, and the signed transaction (JWS)
  R4 sends to the proxy. Fed by StoreKit 2's `Transaction.currentEntitlements`
  at launch and `Transaction.updates` while running; finishes transactions;
  a revoked or refunded transaction ends Pro. **The one thing Run, AI and ads
  read.** Injected through the environment, with a stand-in for tests and a
  `-debug-pro on|off` launch option (`DebugLaunch`).
- Products from `Product.products(for:)`; purchase, Restore
  (`AppStore.sync()`), and Manage (`showManageSubscriptions`). Share store
  plumbing with `TipJar` where it is the same code; keep the two models apart.
- A StoreKit configuration file for the simulator with the product,
  following the tip jar's pattern (`DebugTipStore`).

**Done when.** `ProStatusTests`: entitlement on and off from the stand-in,
expiry, revocation, the JWS exposed, `-debug-pro` both ways; in the simulator
the StoreKit configuration buys and restores. Mutation check on revocation.
**Read:** `design/the-list-s-foot-and-the-tip-jar.md`.

### P2. The paywall and the AI gate

- `PaywallView`: what Pro gives (no ads; Run with output and input; Explain
  Code and Summarise Note, with this iPad's AI availability), the price,
  Restore, and links to the Terms of Use (Apple's standard EULA
  unless Marcus has his own) and the privacy policy. App Review requires all
  of these on a subscription screen (guideline 3.1.2). Opened from a free
  user's Run (R3, R4), any AI action, Settings › Pro and "Remove ads".
- **The AI gate**: every AI entry point (`AIFeatures`, `AIAssistant`, the
  menus and shortcuts that offer it) checks `ProStatus` and opens the paywall
  for a free user. `design/ai-features.md` decision 6 ("No Pro/ads gating")
  is replaced in the same PR, and `features.md`'s AI rows say Pro.
- Settings › Pro: status, the renewal date, Manage Subscription, Restore.
- No glass (W4), colours from `design/colour.md`.

**Done when.** Tests: a free user's AI action opens the paywall and starts no
model session; a Pro user's runs as today; the paywall shows price, period,
Restore, Terms and Privacy (a view test over its strings). Screenshots
light and dark, 13-inch and 11-inch.

### P3. Ads

After W3 (both touch `HomeView`), and after Marcus has added the Google
Mobile Ads package and the `Info.plist` keys (wave 0).

- `AdBanner`: a `UIViewRepresentable` around `BannerView` at the adaptive
  anchored size, shown only while `ProStatus` says free, at Home's foot and
  in `ListFoot`. Google's test ad unit ids in Debug; the real ids are
  constants Marcus fills, never guessed.
- **Consent before any ad request**: Google's User Messaging Platform (it
  comes with the SDK) for the EEA and UK consent form, then App Tracking
  Transparency's prompt, asked on a later Home visit, never at launch.
  Refused or not yet asked: non-personalised ads. The SDK starts only after
  consent is gathered.
- "Remove ads" under the banner opens the paywall. Buying Pro removes the
  banners at once, without a relaunch.
- If App Store Connect's age rating questions ask about ads, the PR says
  what to answer.

**Done when.** Tests with `ProStatus` stand-ins: Pro shows no banner; free
shows one in each of the two places and none in a note, Settings, the paywall
or a sheet; the tracking prompt is never requested at launch. Screenshots
with a test ad, light and dark. iPad checklist: the consent flow once, a test
ad loads on the device, buying Pro in the sandbox removes it.

### After 1.0

More on-device AI features, then a price rise for new subscribers (Apple asks
existing subscribers to agree to a rise above its thresholds; keeping them on
their price avoids that). App Attest on the proxy, which needs an entitlement
and so is Marcus's to add.
