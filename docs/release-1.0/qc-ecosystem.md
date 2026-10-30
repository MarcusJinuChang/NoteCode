# QC: ecosystem and readiness analysis

Written 29 Oct 2026 against `release-1.0-integration` (11c8273). Focused
research, not exhaustive: where a claim rests on a secondary source, or I
could not verify it, the text says so. No app code was changed.

**What was on the branch.** The paywall (`PaywallView.swift`), `ProStatus`,
the Run client (`RunServiceClient.swift`) and the proxy
(`server/run-proxy/`) are there. **The ads are not**: P3 has no PR yet. Only
the Google Mobile Ads package reference is in `project.pbxproj`, and
`Info.plist` has no `GADApplicationIdentifier`,
`NSUserTrackingUsageDescription` or `SKAdNetworkItems`. The ad findings below
are therefore requirements for P3 and R5, not bugs in code.

Sources are linked inline; they are listed again at the end.

---

## 1. Competitors

Prices are what the vendors' own pages said on 29 Oct 2026 unless marked
"secondary" (a review site or search summary, to be re-checked before they
are quoted anywhere public).

| | Price | Code | Math | Ink | Sync |
|---|---|---|---|---|---|
| **NoteCode** | Free (ads); Pro $4.99/mo | Inline fenced blocks, highlighting for C++/Java/Python and more, Copy, Run (redirect free; in-app Pro) | Inline and display LaTeX typed in text, drawn in the line | PaperKit over the same page | None in 1.0 |
| **[Notability](https://notability.com/pricing)** | Free: 5 notes. Lite $11.99/yr, Plus $15.99/yr, Pro $79.99/yr (page labels are ambiguous between yearly and monthly figures) | None (not on the pricing page) | Handwriting math in other tiers is not listed; not a LaTeX tool | Best-in-class | iCloud, cross-platform |
| **[GoodNotes](https://www.goodnotes.com/pricing)** | Free: 3 files. Essential $11.99/yr, Pro $35.99/yr, AI Pass +$9.99/mo | None | On-device Math Assist free; AI for Math in Essential | Best-in-class | Goodnotes Cloud on Pro |
| **[Obsidian](https://obsidian.md/pricing)** | App free; Sync $4/mo billed yearly ($5 monthly) | Fenced blocks with highlighting, plugins for more | LaTeX (`$…$`) built in | Plugins only; weak on iPad | Sync (paid) or iCloud folder |
| **Notion** (secondary: [affine.pro](https://affine.pro/vs), [Capterra](https://www.capterra.com/p/186596/Notion/): roughly $10 to $12 per user per month) | Free tier; paid per user | Code blocks with highlighting, no run | Block equations (KaTeX) | None | Cloud |
| **Nebo** (MyScript; nebo.app now redirects to myscript.com/notes; price is secondary, [scribecount](https://scribecount.com/author-resource/writing-tools-for-authors/note-taking-apps): $11.99 one-time) | Not verified | None | Its core strength: handwritten equations converted to typeset | Handwriting to text | iCloud |
| **Code-notes apps** ([Code Notes](https://apps.apple.com/us/app/code-notes/id6449167420), [CodingNote](https://apps.apple.com/us/app/codingnote/id6737834478)) | Code Notes: free with a Plus subscription; CodingNote: free | Code Notes: snippets, highlighting, run; CodingNote: code boxes with highlighting | None listed | CodingNote: Pencil handwriting | Not stated |

Notion's, Nebo's and the code apps' details come from search summaries and
store listings that I did not open in full. Treat those rows as a first
pass.

**What NoteCode does that none of them do together.** One continuous
Markdown page where typed prose, fenced code, typeset LaTeX and Pencil ink
sit on the same sheet, with Run in the margin. Notability and GoodNotes are
ink-first with no code concept. Obsidian and Notion have code and math but
no real Pencil layer. The two code-notes apps have snippets, not coursework
pages. The closest rival for the CS student is "Obsidian plus GoodNotes
side by side", and NoteCode's pitch is that you stop switching. Free being
the entire notes app (no note cap) is also unusual: Notability caps at 5
notes and GoodNotes at 3 files.

**Table stakes NoteCode lacks** (from `docs/features.md`, which lists none
of these as built):

1. **Sync across devices.** Every rival has it. Planned, not in 1.0
   (`features.md` line 40).
2. **PDF import and annotation.** CS students mark up slides and papers; both
   big rivals lead with it. `features.md` has PDF export only.
3. **Handwriting to text / Scribble, and handwritten math recognition.** Nebo
   is built on it; GoodNotes and Notability offer conversion. NoteCode has
   neither.
4. **Audio recording tied to notes.** Notability's signature, in GoodNotes
   too. Not present.
5. **iPhone and Mac.** iPad only in 1.0. Notion, Obsidian and the big two
   are everywhere.
6. **Templates / sharing and collaboration.** Beyond the paper styles there
   are none; collaboration needs a server (AGENTS.md open questions).

None of these blocks a 1.0 aimed at "typed notes with code and math on an
iPad", but 1, 2 and 3 are what a reviewer or a student comparing
screenshots will ask about first. Say in the App Store description what the
app is, so nobody buys it expecting Notability.

---

## 2. App Store review risk

Guideline text from Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
and [subscriptions page](https://developer.apple.com/app-store/subscriptions/).
I could not read the last 14k characters of the guidelines page; nothing
below depends on them.

### 2.1 Subscription screen and metadata (3.1.2)

What Apple requires: the subscription's name, length and content; the full
renewal price shown prominently; a way to restore; and links to the Terms of
Use and Privacy Policy in both the app and App Store Connect metadata
(subscriptions page; guideline 3.1.2(c); restore also 3.1.1). Rejection
notices on the developer forums
([example](https://developer.apple.com/forums/thread/807082)) add that the
Privacy Policy link goes in the Privacy Policy field and the Terms of Use
(for Apple's standard EULA) in the App Description.

What `PaywallView.swift` has: title "NoteCode Pro", features, price line
("$4.99 per month") bold in the Subscribe row, renewal sentence, Restore
Purchases, Terms link to Apple's standard EULA, and Manage in Settings. That
covers most of it. The risks:

| # | Risk | File | Fix |
|---|---|---|---|
| S1 | **No Privacy Policy link anywhere.** `AppInfo.privacyPolicy` is `nil`, and the paywall wraps the link in `if let`, so the link silently disappears. This is a certain rejection under 3.1.2 and 5.1.1(i) ("a link to their privacy policy in the App Store Connect metadata field and within the app"). | `AppSettings.swift:126`, `PaywallView.swift:122` | Host `docs/site/privacy.md`, set the constant. Make the paywall unconditional (a non-optional URL, or a test that fails while it is nil) so it cannot ship without. |
| S2 | **The privacy page is false once Run and ads ship.** `docs/site/privacy.md` says "collects nothing", "no advertising, tracking or analytics code", and describes Run as opening a browser site. | `docs/site/privacy.md` | R5's job. Do not host the current text. See 2.4 for the new content. |
| S3 | **Terms link must also be in the metadata.** For the standard EULA, the App Description needs the Terms of Use URL. | App Store Connect | Add the line "Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" to the description. |
| S4 | **Renewal text lacks the cancel deadline.** It says renews monthly until cancelled, but not that cancelling must be at least 24 hours before the period ends, which is Apple's standard wording and what reviewers look for. | `PaywallView.swift` (`PaywallContent.renewal`) | Append "Cancel at least 24 hours before the end of the current period." Keep the test over the strings. |
| S5 | **Price never loads = a dead paywall.** While `product == nil` the button reads "Loading the price…" and is disabled. Reviewers use sandbox accounts; if the product is not attached to the submission, or the first request fails, they see a paywall with no price and no way to subscribe, which is a common rejection. | `PaywallView.swift` | When loading fails, show "Couldn't reach the App Store" with a Retry button. In App Store Connect, attach `com.marcus.NoteCode.pro.monthly` to the version and add the subscription's review screenshot. |
| S6 | **AI promised on iPads that cannot run it.** The paywall does say whether Apple Intelligence is available, which is good. A reviewer's iPad may not have it. | `PaywallView.swift` | Say in the review notes that Explain and Summarise need Apple Intelligence, and that Run and no ads work everywhere, so a missing AI is not read as a broken purchase. |

Restore: present and disabled while buying or restoring. Fine.
No-trial: nothing in the guidelines requires one.

### 2.2 Ads, ATT and AdMob consent

**Order of Google's flow**, from [Google's AdMob iOS privacy page](https://developers.google.com/admob/ios/privacy):
`GADApplicationIdentifier` in Info.plist; on **every launch** call
`requestConsentInfoUpdate`, then `loadAndPresentIfRequired`; offer a Privacy
Options entry point when `privacyOptionsRequirementStatus` says so; request
ads only when `canRequestAds` is true. That page does not cover ATT; I did
not read Google's separate IDFA page, so the ATT-versus-UMP order below is
unverified.

Apple's side: tracking requires the ATT prompt (5.1.2), and the data
collected needs consent (5.1.1(ii)) and a way to withdraw it.

| # | Risk | File | Fix |
|---|---|---|---|
| A1 | **Info.plist is missing the keys.** Without `NSUserTrackingUsageDescription` the ATT call crashes or does nothing; without `GADApplicationIdentifier` the SDK crashes at start; `SKAdNetworkItems` missing costs attribution. Marcus must add them (his local `Info.plist` edit). | `NoteCode/Info.plist` | Marcus adds them. Also confirm `ITSAppUsesNonExemptEncryption` = `false` survives his local edit; the README says that edit drops it. |
| A2 | **The privacy manifest contradicts ads.** It says `NSPrivacyTracking` false and `NSPrivacyCollectedDataTypes` empty. Once the SDK collects device ID, advertising data, product interaction, coarse location and diagnostics, the app's own manifest and the nutrition label must say so. (The SDK ships its own manifest too; the app's must still be right.) | `NoteCode/PrivacyInfo.xcprivacy`, `AppStoreReadinessTests` | P3/R5 updates it, with tracking true and Google's tracking domains if ATT is asked, and updates the readiness test that currently pins the old values. |
| A3 | **UMP must run every launch, not just "later".** P3's plan gathers consent "before any ad request", which fits, but the consent info update itself must run at launch even though the ATT prompt does not. If someone defers the whole sequence to a later Home visit, an EEA reader gets ads before the form. | P3 (`AdBanner`, consent manager) | Run `requestConsentInfoUpdate` at launch; keep banners hidden until `canRequestAds`. Ask ATT only after UMP, only when the app is active (the system silently drops the request otherwise), and never in a note. |
| A4 | **"Remove ads" and Privacy Options must be reachable.** The withdrawal route (5.1.1(ii)) is Google's Privacy Options entry; with the banner-only layout it needs a row in Settings. | P3, `SettingsView.swift` | Add "Privacy options" in Settings when UMP requires it. |
| A5 | **ATT prompt without tracking, or tracking without a prompt, are both rejection grounds.** Decide: personalised ads on request of ATT means "Data Used to Track You" in the label. | App Store Connect label | Choose one and make manifest, label and policy agree (see 2.4). |
| A6 | **Age rating.** Ads change the rating questionnaire; a student app with ads is not "made for kids", so do not tick that. | App Store Connect | Answer the ads question yes; keep the rating at 4+ only if the AdMob content ceiling is set to match (AdMob > Blocking controls). |
| A7 | **Ad unit ids.** Real ones are constants Marcus fills. A release build with Google's test ids is not a rejection but earns nothing. | P3 | A Release-only test that fails on the test id. |

### 2.3 Running code on a remote server (2.5.2, 4.7)

[2.5.2](https://developer.apple.com/app-store/review/guidelines/): apps may not "download, install, or execute code which introduces or changes features or functionality of the app". NoteCode sends the student's own text to a server and displays stdout; nothing is downloaded or executed on the device. That is the same shape as a web compiler app, and is not what 2.5.2 prohibits. **4.7** is for mini apps, plug-ins, emulators and chatbots (software offered inside the app by third parties). The user's own code run remotely is not that. I read 4.7 as not applicable, but a reviewer might ask, so say so in the notes. Risks that do apply:

| # | Risk | File | Fix |
|---|---|---|---|
| R1 | **Review notes must explain Run.** Without them a reviewer sees "execute code" and a paid feature. | App Store Connect, App Review Information | Notes: "Run sends the code in the block to our server (Cloudflare Worker → Judge0), runs it in a sandbox and returns the output. No code is downloaded or run on the device. Sandbox subscription is needed; here is how to test." Include a sandbox tester. |
| R2 | **Sandbox transactions must verify in the proxy.** The Worker checks the app's signed transaction against Apple's chain, product and expiry. The reviewer is in sandbox, and TestFlight does too, so a Worker that accepts only the Production environment would show the reviewer a Pro purchase with Run returning 402. I did not test it. | `server/run-proxy/src/transaction.ts` | Confirm it accepts `Sandbox` and `Production`; test with a sandbox JWS before submitting. |
| R3 | **No in-app disclosure before code leaves the device.** Sending user content to a third party is a privacy-guideline topic (5.1.1/5.1.2). The first Run should say once: "Your code and input are sent to NoteCode's run service and Judge0 to run." | `RunPanel.swift`, `RunSession.swift` | One-time notice, remembered; the privacy page says the same. |
| R4 | **Judge0 retention not checked.** R5 calls for finding out whether hosted Judge0 retains submissions. If it does, the label needs "Other User Content". | R5 | Decide before the label is filled in. |
| R5 | **Output of arbitrary programs.** Output goes only to the author; nothing is shared. Fine, but the proxy must not log bodies. | `server/run-proxy` | Already a requirement; keep it tested. |
| R6 | **Fallback when down.** Pro falls back to the redirect, which is a good outcome for a reviewer on a dead network. | `RunRouting.swift` | Keep. |

### 2.4 Privacy nutrition label (what Marcus should choose)

Choose based on the final design; this is the list for R5 to give him.

- **Run:** Other User Content (the code and input), collected, **not linked to identity, not used for tracking**; purpose App Functionality. Add it even if Judge0 retains nothing, since the proxy does receive it, unless the proxy provably never stores it (it keeps only a day's count per subscription). Check Apple's definition of "collect" (data transmitted off the device and stored longer than needed to serve the request); if the answer is "not stored", the label may stay empty, but then the policy must say so explicitly.
- **Ads (Google SDK):** Device ID, Advertising Data, Product Interaction, Coarse Location, Crash/Performance data, usage data: collected for Third-Party Advertising and Analytics. If ATT is asked: "Data Used to Track You" for Device ID and Advertising Data. Pro readers see no ads, but the label covers the app as shipped.
- **Purchases:** Purchase history, via StoreKit; Apple handles it, and it is typically not declared unless the app sends it to a server. The app does send the signed transaction to the proxy, which verifies and caches by transaction id: declare "Purchases" (not linked, App Functionality) or state why not.
- **Contact info:** the support address is not collected.

### 2.5 Other review items the code shows

- **Privacy policy and support URLs are both `nil`** (`AppSettings.swift:122,126`). The support URL is required (guideline 1.5); `ListFoot.swift` and `SettingsView.swift` hide the rows while they are nil, so nothing in the app complains.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` is `false` on the branch; Marcus's local edit may drop it (A1).
- **iPad only** plus screenshots in the 13-inch size (below).

---

## 3. Pricing sanity

$4.99/month is **$59.88 a year**, with no yearly option.

| App | Entry paid | Mid | Source |
|---|---|---|---|
| GoodNotes | Essential $11.99/yr | Pro $35.99/yr | [goodnotes.com/pricing](https://www.goodnotes.com/pricing) |
| Notability | Lite $11.99/yr | Plus $15.99/yr | [notability.com/pricing](https://notability.com/pricing) |
| Obsidian | App free | Sync $48/yr billed yearly | [obsidian.md/pricing](https://obsidian.md/pricing) |
| Notion | n/a | about $10 to $12/user/month (secondary) | Capterra |

Read honestly:

- **It is 2 to 5 times the price of the market's entry tier** (GoodNotes and
  Notability from $11.99 a year), and above the top of GoodNotes' own
  non-AI tier ($35.99/yr). The comparison that matters is that those apps
  charge for removing limits on a notes app, while NoteCode gives the whole
  notes app away and charges for Run, AI and ad removal. So the fair
  benchmark is the *add-on* tier: GoodNotes' AI Pass is $9.99/month, and
  Obsidian Sync $4 to $5/month. At $4.99 NoteCode sits at Obsidian Sync's
  price and half of AI Pass. That is defensible if Run and AI deliver,
  weaker for a student who only wants no ads.
- **No annual plan is the real gap.** Every rival bills annually, and
  students think in semesters. The 12-month cost is the headline number and
  it is high. Apple also treats the monthly-only structure as fine, but the
  conversion cost is likely greater than the revenue per annual subscriber
  lost. The proxy economics (archive/release-1.0/R-run.md: Judge0 costs at most $1.53/month at
  the cap) leave room for a ~$39.99/yr plan with margin. I would add it
  after 1.0 rather than delay the release, or add it now if it is a few lines
  in `ProStatus` and one more product in App Store Connect; it is a decision
  for Marcus, not an app-review matter.
- **No trial** is workable because free is the whole notes app and Run has
  a free redirect: the free tier is the trial. It does mean the only way to
  try Run is the paywall, so the paywall should *show* a run (a screenshot
  of the Run panel) rather than describe it.
- **A semester or student price** (e.g. $14.99 for 4 months, or an
  education offer code) is the usual answer in this market; also post-1.0.
- Apple's 15% Small Business Program rate is already assumed
  (archive/release-1.0/R-run.md); confirm enrolment before launch.

Verdict: the *monthly* price is in line with add-on subscriptions in this
market and the proxy costs support it; the *absence of an annual plan*
and the headline $59.88/yr are the weak points. Not a blocker.

---

## 4. Launch ecosystem: what is missing outside the app

| Item | State | Do |
|---|---|---|
| **Privacy policy URL** | Draft in `docs/site/privacy.md`, dated 10/17/26, not hosted, now inaccurate (S2) | Rewrite in R5, host (GitHub Pages is enough), set `AppInfo.privacyPolicy`, fill ASC's Privacy Policy field |
| **Support URL** | Draft `docs/site/support.md`, not hosted; `feedbackAddress` nil | Host; required field in ASC (1.5). Set `AppInfo.feedbackAddress` |
| **Marketing URL** | none | Optional, but AdMob wants a developer site for **app-ads.txt**; without it ad fill is limited. Put `app-ads.txt` at the developer-website root named in the listing |
| **Terms of Use** | Apple's standard EULA | Link it in the description (S3) |
| **Screenshots** | none made | iPad only: the 13-inch set (Apple's current required size; confirm the pixel size in App Store Connect). Guideline 2.3.3: show the app in use. Show: a page with code + LaTeX + ink together, Run panel with output, Home, dark mode, the paywall. No title-only art |
| **Keywords (100 chars)** | none | Candidates: `notes,code,markdown,latex,pencil,c++,java,python,computer science,study,programming,syntax`; don't repeat words from the name or subtitle. Name idea: "NoteCode: Code & Math Notes". Do not use competitor names (2.3.7) |
| **Subscription metadata** | product named in README only | Display name, description, review screenshot of the paywall, localisation; attach to the version |
| **App Privacy label, age rating** | not filled | See 2.4, A6 |
| **Review notes + demo** | none | R1, S6, a sandbox tester, and how to see ads (they appear only on the free tier) |
| **Export compliance** | `false` | Keep (A1) |
| **TestFlight external beta** | iPad checklist exists | Run it with a sandbox subscription and an unlinked AdMob app before submission |

**Apple platform hooks.** I found no widgets, App Intents/Shortcuts, Spotlight
indexing or Quick Note support in `features.md` or the project. What is
worth doing, in my order:

1. **Spotlight (Core Spotlight) indexing of note titles and text.** Cheap, and
   students search from the home screen. After 1.0 unless it is a few lines;
   note that titles in Spotlight are on-device data and need a privacy
   sentence.
2. **App Intents: "New Note", "Open Last Note".** Gives Shortcuts, the Action
   Button and Siri for free. After 1.0.
3. **Widget: "Continue last note" and a new-note button.** After 1.0.
4. **Quick Note (iPadOS 15+ system feature):** Apple's own Notes, not
   something an app can integrate with directly; a third-party app can only
   take a share or a drop. A "New note from selection/Share extension" is
   the equivalent, later.
5. **Pencil:** double-tap and squeeze are built (`features.md:101`) but
   unchecked on a Pencil; hover is PaperKit's. **Scribble** (handwrite into
   text fields) should work in a UITextView by default; check it does in
   the editor and the title field and put it in the checklist, since the
   app has no handwriting-to-text of its own.
6. **iCloud sync.** The model is shaped for CloudKit but nothing syncs
   (`features.md:40`), and nothing in the UI says so. Readers coming from
   GoodNotes will assume it. Until then: (a) say "notes stay on this iPad"
   in the first-launch note and the description; (b) iCloud *device backup*
   does cover the app's data, so a lost iPad is recoverable, and the privacy
   page already says so; (c) Export All is the other safety net; make sure
   it is findable. A free-tier user losing an iPad and finding no sync is the
   most likely one-star review in the first month.

---

## Fix before release (ranked)

1. **Host the privacy page and set `AppInfo.privacyPolicy`**, after
   rewriting it for Run and ads. Make the paywall link unconditional. (S1, S2)
2. **Fill App Store Connect metadata the review checks:** Privacy Policy and
   Support URL fields, Terms link in the description, the subscription
   product attached with its review screenshot, review notes explaining
   Run. (S3, S5, R1, 1.5)
3. **Make the privacy manifest, label, policy and ATT behaviour agree.**
   Update `PrivacyInfo.xcprivacy` and its readiness test when ads land;
   decide whether to ask ATT; fill the label as in 2.4. (A2, A5)
4. **Info.plist keys** (`GADApplicationIdentifier`,
   `NSUserTrackingUsageDescription`, `SKAdNetworkItems`) and confirm
   `ITSAppUsesNonExemptEncryption` survives. (A1)
5. **UMP at every launch, ATT only after it and only when active;
   banners wait for `canRequestAds`;** a Privacy Options row in Settings.
   (A3, A4)
6. **Verify the proxy accepts sandbox transactions** with a real sandbox JWS,
   and the reviewer can run code on a sandbox subscription. (R2)
7. **First-Run disclosure** that code goes to the run service. (R3) And find
   out Judge0's retention. (R4)
8. **Paywall polish:** cancel-24-hours wording; a failure state with Retry
   when the price does not load. (S4, S5)
9. **Screenshots (13-inch), keywords, age rating** (ads question), AdMob
   `app-ads.txt` on a hosted developer site. (section 4, A6)
10. **Say "no sync yet" in the description and first-launch note.**
    (section 4)

## After 1.0

1. iCloud sync (the biggest gap against every rival).
2. An annual plan, ~$39.99, and a student/semester offer.
3. PDF import and annotation.
4. Spotlight indexing, App Intents/Shortcuts, a widget, a Share extension.
5. Handwriting to text and handwritten math (check Scribble first).
6. iPhone and Mac editors.
7. App Attest on the proxy (already planned).
8. More AI features, then a price rise that leaves existing subscribers on
   their price (the subscriptions page says Apple lets you do this).

## Sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 1.5, 2.3, 2.5.2, 3.1.1, 3.1.2(c), 4.7, 5.1.1, 5.1.2
- [Apple, Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
- [Google, AdMob iOS privacy and messaging](https://developers.google.com/admob/ios/privacy)
- [Apple Developer Forums, 3.1.2 rejection notice](https://developer.apple.com/forums/thread/807082) (secondary, for the metadata placement)
- [Notability pricing](https://notability.com/pricing), [Goodnotes pricing](https://www.goodnotes.com/pricing), [Obsidian pricing](https://obsidian.md/pricing)
- Secondary: [affine.pro comparison](https://affine.pro/vs), [Capterra on Notion](https://www.capterra.com/p/186596/Notion/), [scribecount](https://scribecount.com/author-resource/writing-tools-for-authors/note-taking-apps), [Code Notes](https://apps.apple.com/us/app/code-notes/id6449167420), [CodingNote](https://apps.apple.com/us/app/codingnote/id6737834478)
