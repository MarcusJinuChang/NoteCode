# The list's foot and the tip jar
Roadmap steps 2 and 12 (17 Oct, branch `claude/list-foot`). Decided by
Marcus: a StoreKit tip jar now; ads and a Pro subscription (no ads, the AI
features) after the release.

- **The foot** (`ListFoot`) is the note list's last section, under Recently
  Deleted: Tip Jar, Feature Request, Send Feedback, Privacy Policy, then the
  mark at 28pt and "NoteCode 1.0 (2)" as its footer. **Each row appears only
  once it works**, as in Settings: the tip jar once the store has answered
  with its products (`TipJar.isAvailable`), the two mail rows once
  `AppInfo.feedbackAddress` is set (Feature Request is the same address under
  its own subject, `AppInfo.featureRequestURL`), the policy once
  `AppInfo.privacyPolicy` is. Not while searching, and not under the empty
  list's overlay.
- **Tips are consumables that unlock nothing** (`TipJar`, `TipJarView`):
  `com.marcus.NoteCode.tip.small`, `.medium` and `.large`, named and priced
  in App Store Connect (`NoteCodeTests/NoteCode.storekit` has $0.99, $2.99
  and $4.99 for the tests). Nothing is recorded or restored. A purchase is
  finished as soon as it's verified, and `TipJar.start()`, from the app's
  `init`, listens to `Transaction.updates` from launch, so a tip approved
  later through Ask to Buy is finished too; StoreKit redelivers an
  unfinished one at every launch.
- **`TipStore`** is what the jar needs from a store: `StoreKitTipStore` in
  the app, a fake in the state tests, and `DebugTipStore` under
  `-debug-tip-jar`, so the row and sheet can be looked at without App Store
  Connect.
- **The StoreKit configuration is in the test bundle**, not at the
  repository root: `SKTestSession(contentsOf:)` with a file outside the
  bundle loaded no products (simulator, 17 Oct). `TipJarTests` buys a tip
  through StoreKit against it and checks no transaction is left unfinished
  (fails with `finish()` removed, checked). To try tips from Xcode, set the
  scheme's Run › Options › StoreKit Configuration to that file.
- **StoreKit can answer the first request with nothing.** In a full test
  run, with other suites going at once, the test session served no products
  to the first request (iPad mini simulator), though alone it never did; the
  tests wait up to 5s for them (`productsServed`). In the app, the foot asks
  again each time it appears (`TipJar.load` does nothing once loaded), so a
  store slow at launch doesn't hide the jar until the next one.
- **Before tips work for anyone**, in App Store Connect: the Paid
  Applications agreement with banking and tax, the three products
  submitted with the build, and the Small Business Program (15% instead of
  30%). Until then the products don't load and the row doesn't show, in
  TestFlight too.
- **Checked in the simulator** (iPad, light, `-debug-home -debug-tip-jar`):
  the foot with the Tip Jar row and the mark, the sheet, a tip thanked. **Not
  checked:** dark mode, a real sandbox purchase in TestFlight, Ask to Buy on
  screen, VoiceOver's announcement, the haptic, the mail and policy rows
  (their values are still `nil`).

## Pro status (P1, 27 Oct)
`ProStatus` (`ProStatus.swift`) is the one place Run, AI and ads read whether
the reader has Pro, kept apart from `TipJar`: tips record nothing, Pro is state.
- **One product**, `com.marcus.NoteCode.pro.monthly`, $4.99, no yearly plan, no
  trial. It is in `NoteCodeTests/NoteCode.storekit` beside the tips (one file to
  select in the scheme, none added to the project).
- **`ProStore`** is what it needs from a store: `StoreKitProStore` in the app,
  a fake in the tests, `DebugProStore` under `-debug-pro on|off`.
- **Fed by** `Transaction.currentEntitlements` at launch (`start()`), and
  `Transaction.updates` while running. Both are finished. A revoked transaction
  ends Pro; an expired one does too, through `isPro` comparing the expiry with
  now. `signedTransaction` is the JWS (`jwsRepresentation`) for R4's proxy, nil
  for a free reader.
- **`TipJar`'s listener now finishes only tip transactions**, so it can't
  consume the subscription's.
- **Checked:** `ProStatusTests`; the mutation (a revoked transaction kept as
  Pro) fails two of them. **Not checked:** that `finish()` took on the
  subscription (the test session listed it unfinished anyway), a refund
  arriving through `Transaction.updates` (the test session sent none; the
  launch path is tested), Manage Subscriptions, a sandbox purchase.
