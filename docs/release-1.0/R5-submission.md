# R5: submission text for Run and ads

**Used for the 1 Nov submission** (1.1.0 (4), in App Review). Keep it in
step with App Store Connect if an answer to App Review changes anything.

What goes into App Store Connect and onto `gh-pages`. The privacy page itself
is `docs/site/privacy.md` (paste-ready: it is the `gh-pages` `privacy.md`
as it should be) and `docs/site/support.md`.

## App Review notes (paste into App Review Information › Notes)

> NoteCode is a notes app with syntax-highlighted code blocks. Run on a code
> block is part of NoteCode Pro; for free users it opens the paywall. For
> subscribers, Run sends the block's source code (and any input they typed)
> over HTTPS to our server, which compiles and runs it on a hosted service
> (Judge0) and returns the text output. Code is never downloaded or executed
> on the device, and the app downloads no code or executable content
> (Guideline 2.5.2). If a run can't happen (the daily limit, or the service
> down), the panel offers to open the code on a free online compiler website
> in Safari (Compiler Explorer or Programiz) instead.
>
> To test Run: subscribe in the sandbox (Settings › Pro, or tap ▷ on a code
> block), open any note with a ```python block and tap ▷. The first run shows
> a one-time notice saying where the code goes; tap Run. Output appears in
> the panel beside the page.
>
> Free users see Google AdMob banner ads (at the foot of Home and of the note
> list). Pro removes them. We show Google's consent form where required, then
> the App Tracking Transparency prompt: outside the EEA and UK right after
> Google's explainer on the first visit to Home, in the EEA and UK on a later
> visit. Declining still shows non-personalised ads.
>
> Subscription: NoteCode Pro, $4.99/month, auto-renewing. Terms of Use (Apple
> standard EULA) and the Privacy Policy are linked on the paywall.
>
> Explain Code and Summarise Note run on the device and need Apple
> Intelligence; on a device without it the paywall says so. Run and the
> removal of ads work on every iPad and iPhone.

## App Privacy label (App Store Connect › App Privacy)

"Do you or your third-party partners collect data from this app?" **Yes.**

| Data type | Linked to user | Used to track | Purposes |
|---|---|---|---|
| Other User Content (code and input sent by Run) | No | No | App Functionality |
| Device ID | No | **Yes** | Third-Party Advertising |
| Advertising Data | No | **Yes** | Third-Party Advertising |
| Product Interaction | No | **Yes** | Third-Party Advertising |
| Coarse Location | No | **Yes** | Third-Party Advertising |
| Crash Data | No | **Yes** | Third-Party Advertising |
| Performance Data | No | **Yes** | Third-Party Advertising |
| Other Diagnostic Data | No | **Yes** | Third-Party Advertising |

The last seven match `PrivacyInfo.xcprivacy` exactly (`AppStoreReadinessTests`).
Check Google's current AdMob list in "Google's Mobile Ads SDK data disclosure"
before submitting; add whatever it adds to both the label and the manifest.
Judge0 keeps submissions and its hosted service can't delete them (checked
3 Nov), so "Other User Content" stays declared. Purchases/Usage: the subscription id never leaves Apple's system
except as the opaque signed transaction the proxy checks, and nothing is stored
against it but a count, so no entry for it.

Also: age rating questionnaire › "Contains ads" yes, not aimed at children.
Tracking: yes (the app uses ATT).

## Marcus, by hand in App Store Connect

1. App Privacy: enter the label above.
2. App Information › Privacy Policy URL: `https://marcusjinuchang.github.io/NoteCode/privacy`
   (after the gh-pages push below). Support URL: `https://marcusjinuchang.github.io/NoteCode/support`.
3. Description: add the Terms of Use link (Apple standard EULA,
   https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) and the
   Privacy Policy link; say there is no sync yet (QC item 10).
4. App Review Information: paste the notes above; give a sandbox-capable path
   (no demo login is needed).
5. Subscription: attach the product to the version, add its review screenshot
   (the paywall).
6. Age rating: answer the ads question.
7. Judge0's retention: settled 3 Nov. It keeps submissions and deletion is
   off on the hosted service, so the privacy page says so and "Other User
   Content" stays (docs/design/shipping.md).

## Marcus, on `gh-pages`

1. Replace `privacy.md` with `docs/site/privacy.md` from this PR (after merge).
2. Add `support.md` (from `docs/site/support.md`) and link it in `index.md`
   beside the Privacy Policy link.
3. Check `https://marcusjinuchang.github.io/NoteCode/privacy` and `/support`
   load. The privacy URL already returns 200 today, with the old text.
4. For AdMob, `app-ads.txt` needs a hosted developer-site root (QC item 9);
   Pages on this project path won't serve one at a domain root.
