# On-device assistant: Explain Code and Summarise Note

Roadmap "After the submission" item 5 (24 Oct, branch `claude/hungry-darwin-311566`,
off `claude/integration-oct`). Two features on Apple's on-device model, so the
app still collects nothing. Everything here was decided without Marcus and is
listed under "Provisional (Marcus to review)".

## What it costs and where it runs

Free, and on the device. Apple's `SystemLanguageModel` ships with the OS once
Apple Intelligence is on: no API key, no account, no per-request charge for the
developer or the reader, and no network. The prompt never leaves the iPad. Using
it needs no entitlement, no Info.plist string and no privacy-manifest entry
(it is not a required-reason API), so `AGENTS.md › Shipping` stays true as
written: nothing is collected, the manifest lists UserDefaults only, and the
only network traffic is the system opening a compiler's page.

**Never `PrivateCloudComputeLanguageModel`.** The iOS 27 SDK has a second model
that runs on Apple's servers (it has `NetworkFailure`, `QuotaLimitReached` and a
quota). It is a different promise. `SystemTextModelClient` names
`SystemLanguageModel.default` and nothing else; keep it that way.

## SDK findings (Xcode 27.1, iPhoneSimulator27.1.sdk, read from the swiftinterface)

- `FoundationModels.framework` is a system framework in the SDK. It autolinks
  from `import FoundationModels`, so **no `project.pbxproj` edit** was needed.
  The app's deployment target is 27.0; the model API is iOS 26.0+.
- **Availability**: `SystemLanguageModel.default.availability` is
  `.available` or `.unavailable(reason)` with reasons `deviceNotEligible`,
  `appleIntelligenceNotEnabled` and `modelNotReady`. `isAvailable` and
  `supportsLocale(_:)` (the device's language) are separate checks;
  `supportedLanguages` lists them. The model is `Observable`.
- **Context window**: `contextSize` (back-deployed; 4,096 tokens before iOS
  27, a runtime value on 27). Input, instructions and output share it.
  `tokenCount(for:)` (iOS 26.4+) counts a prompt exactly but is async and
  per-call, so the budget below uses a conservative character rule instead
  and lets `LanguageModelError.contextSizeExceeded` catch the rest.
- **Sessions**: `LanguageModelSession(model:instructions:)`, then
  `respond(to:options:)` or `streamResponse(to:options:)`. A stream yields
  *snapshots*, each the whole answer so far (not a delta). `GenerationOptions`
  has `temperature` and `maximumResponseTokens`. A session keeps a transcript
  and refuses a second concurrent request (`concurrentRequests`), so the client
  makes **one session per request**: no note's text carries into the next, and
  the transcript never fills the window.
- **Guided generation** (`@Generable`) exists. Not used: the answers are
  free-form prose, and a schema would spend context on structure.
- **Errors** (iOS 27): `LanguageModelError` has `contextSizeExceeded`,
  `guardrailViolation`, `refusal`, `unsupportedLanguageOrLocale`, `timeout`,
  `rateLimited`; `SystemLanguageModel.Error.assetsUnavailable`. The older
  `LanguageModelSession.GenerationError` is deprecated in 27.
- **The simulator** (measured 24 Oct, Xcode 27.1, iOS 27.0 simulator on an Apple
  Intelligence Mac): `availability` reads `.available` and `supportedLanguages`
  has 24 entries, because the simulator inherits the Mac's state, but
  **`contextSize` is 0 and generating fails** (`LanguageModelError` -1 with a
  "Model Catalog … no underlying assets" log): the model's assets aren't in the
  simulator. So the real model **cannot be run in the simulator**; only a real
  iPad with Apple Intelligence on can. Two consequences built in: the client
  treats a context size under 1,000 as 4,096, and any error from the model is a
  state the sheet words ("The model couldn't finish. Try again."), never a
  crash. `AISystemModelTests` records what it finds and demands only what holds
  everywhere.

## UX

- **Explain Code** is **Explain Block** in the edit menu of a code block
  (beside Run Block, Copy Block and Share Block, which the coordinator's
  `codeBlockMenu` builds) and an **Explain** word in the text options row when
  the caret is in a code block (beside + Output), both acting on that block.
  It is **not a third button in the block's
  header**: `CodeBlockActionBar` sits inside the text view and
  `AGENTS.md › Implementation requirements` says a button there is not simply a
  button (the text view's recognisers cancel its touches; the gesture refusal
  in `DocumentUITextView` is tuned to two buttons' frames, and every size,
  `copyOnlySize` and `containsInteractiveElement` would change). The edit menu
  is chrome-free and already the place Run and Copy are for the keyboard; the
  menu path involves no overlay, no hit-testing and no new recogniser.
  Not shown for an output block or an empty one.
- **Summarise Note** is in the note's ••• menu, after Find in Note. It acts on
  the whole note's text (ink is not read).
- **The result is a sheet** (`AIResultSheet`, a standard medium sheet): a title,
  the answer streaming in as it is written, a small "Apple Intelligence · on
  this iPad" line, and buttons: **Stop** while generating, then **Copy** and
  **Insert Below**. Insert Below writes the answer under the block (Explain) or
  under the line the caret is on (Summarise) as a **quote** or an **output
  block** (Settings picks; the sheet's menu on Insert Below offers the other for
  once). One undo step: the edit goes through `replace(_:withText:)` like
  every formatting button, so it is undoable, restyled, and written to the page.
  Insert Below is disabled for a locked note and in ink mode (Copy still
  works), and Summarise Note is disabled in ink mode.
- If the text was cut to fit, the sheet says so in one line ("Only the first
  part of this note fit.") and that line is *not* inserted.
- **Progress and cancelling.** A progress ring until the first text arrives,
  then the text itself. A long note shows "Part 2 of 5" while it works through
  its pieces. Stop cancels the stream; closing the sheet cancels it too;
  starting another run cancels the first.

## Availability

States, in `AIUnavailableReason`: switchedOff (Settings), deviceNotEligible,
appleIntelligenceOff, modelNotReady, languageNotSupported.

- **Hidden** (menu items left out) when the reader switched it off or the device
  can never run it: nothing to tap, nothing to explain.
- **Shown, and the sheet explains why** for the reasons that change (Apple
  Intelligence off, model still downloading, language): a disabled menu item
  can't say anything in a UIKit edit menu, and a sheet can ("Turn on Apple
  Intelligence in the system's Settings"). So there is no dead item and no
  silent failure.
- Nothing calls the model without checking `availability` first, and every
  model error becomes a state (`AIFailure`) with a sentence; there is no `try!`
  and no force unwrap on the path.

## Prompts

All in `AIPrompts`. Two rules: **the reader's text is in the prompt and never in
the instructions** (and the instructions say it is content, not orders, so a
note that says "ignore the above" is summarised, not obeyed), and **nothing but
the text is sent**: not the reader's name, device, folder, other notes, dates
or ink. A summary carries the note's title; an explanation carries only the
language and the code.

- *Explain*: instructions as a tutor for a CS student reading their own notes:
  what the code does and why in the order it runs, the main idea or algorithm
  and cost if clear, no rewriting the code, plain sentences with no headings,
  lists or fences (so the quote and output block hold it cleanly), a stated
  length, and "answer in the language the notes are written in". Prompt:
  `Language: C++` and the code.
- *Summarise*: main ideas, definitions and results in order, only what the
  notes say, plain sentences, a stated length. Prompt: the title and the text,
  with a note's `<span>` tags and layout characters removed
  (`SpanStyle.maskingTags`), which say nothing and take the budget.
- **Length** (Settings): Brief (2–3 sentences, 160 tokens), Standard (a
  paragraph, 350), Detailed (up to three, 700). The words ask; the token cap
  bounds.
- Temperature 0.3: explanations should agree with the code, not be creative.

### Fitting the context

`AIBudget`: a request's text may be
`(contextTokens − 300 for instructions − response cap) × 3` characters, at least
1,000. Three characters a token is the cautious end for code and mixed
languages; a prompt that errs short is cheap, one that overflows is an error.
At 4,096 tokens and Standard that is about 10,000 characters, roughly 250
lines of code.

- **A code block** over the budget is cut to its first two thirds and its last
  third **on whole lines**, with `… (part of the code left out here) …` between
  and a line in the prompt saying so (the signature and the ending say most
  about code). One enormous line is cut by characters.
- **A note** over the budget is split into pieces on blank lines (then lines,
  then characters), packed greedily up to the budget, in order. One piece is
  one request. Several: each piece gets a short working-notes request (200
  tokens), then one request joins the notes into the summary. **At most 4
  pieces** (about 40,000 characters at 4,096 tokens); the rest is not read
  and the sheet says so. That bounds the time (five model calls) and keeps
  the stated rule simple. Counting characters is linear, so only the first
  five pieces' worth of text is even measured.

## Privacy

- On device: no network call, key or account. The prompt is built, used and
  dropped; nothing is stored, logged or cached, and no transcript is kept
  (a session per request).
- The App Store label stays "Data Not Collected"; `PrivacyInfo.xcprivacy` is
  unchanged. `AppStoreReadinessTests` still passes.
- Apple's own safety layer may refuse some text (`guardrailViolation`,
  `refusal`); the sheet says "The model wouldn't answer this one."
- The Settings switch turns the features off entirely.

## Settings

Settings › Writing › **On-Device Assistant** (one `AIFeatureSettings`, one
`apply(to:)`, per the repo's rule): **Assistant** switch (default on, where the
model is available), **Answer Length** (Brief, Standard, Detailed), **Insert
As** (Quote, Output Block). Keys `aiEnabled`, `aiAnswerLength`, `aiInsertStyle`
are pinned by a test. When the model is unavailable the section's footer says
why, in the same words as the sheet.

## Accessibility

The sheet is a standard sheet and navigable by VoiceOver: buttons are labelled
(Stop, Copy, Insert Below), the streaming text is one element that updates, and
VoiceOver is told when the answer is ready and when it fails (an
announcement, as the toasts do). Dynamic Type is respected in the sheet (it is
not the note, which doesn't follow it). Reduce Motion: the progress is a
`ProgressView`, no animation of ours.

## Architecture

- `AIFeatures.swift`: the vocabulary (`AIAction`, lengths, `AIAvailability`),
  `AIFeatureSettings` and the `TextModelClient` protocol.
- `AIPrompts.swift`: jobs, budgets, cutting, wording. `AIInsertion.swift`:
  where and what to write. `AIAssistant.swift`: the state machine (idle,
  generating, done, failed, unavailable), an `@Observable` over a client.
- `SystemTextModelClient.swift`: the only file that imports FoundationModels.
- `AIResultSheet.swift` and the menu items: SwiftUI and UIKit glue.
- Tests use `FakeTextModel` (scripted snapshots, failures, a hang to cancel).
  Everything but the real model is unit-tested: prompts, truncation and
  chunking, the state machine, insertion (including that the inserted text
  parses as a quote and as an output block, and that it undoes), settings.

## Tests and what is checked

`AIFeaturesTests` (prompts, budget, cutting and chunking, the state machine
against `FakeTextModel`, insertion, settings), `AIEditorTests` (the edit menu's
item shown and hidden by availability and the switch, jobs built from a real
text view, Insert Below as a quote and as an output block, one undo, locked and
ink mode) and `AISystemModelTests` (the real client's availability, context
size and error mapping, recorded). 68 tests with the readiness, settings and
model-freeze suites, all passing on the iPad Pro 13-inch simulator; the macOS
app builds. **Mutation-checked** (24 Oct, each fails the tests named): tail of a
long block dropped (`headAndTail`); availability ignored (`unavailable`,
`switchedOff`, `shownWithReason`); no blank line before an insertion (`quote`,
`atTheEnd`, `output`, `insertAndUndo`); Stop not cancelling the run (`cancel`,
whose script sends a snapshot after Stop); the edit menu ignoring availability
(`hidden`).

**Not verified: the real model.** It cannot run in the simulator (see the SDK
findings), so no answer from Apple's model has been seen: its quality on
real code and notes, its streaming speed and time to first text, the 3
characters-a-token rule against the real `contextSize` on an iPad, the
guardrails on ordinary course text, the sheet on screen (layout, dark mode,
Dynamic Type, VoiceOver), the edit menu item and the Explain chip by a tap,
Settings › Writing on screen, and Insert Below on a note with ink.

### On-iPad checklist (Apple Intelligence on)

1. Settings › Writing › On-Device Assistant: switch, Answer Length and Insert
   As are there; the footer is plain when available.
2. In a C++ block, tap in the code, open the edit menu: **Explain Block** is
   there. Tap it: the sheet opens, text streams in, **Stop** works, the answer
   is plain sentences about this code.
3. The text row shows **Explain** with the caret in a block (not in an output
   block); it does the same.
4. **Insert Below** puts a quote under the block with a blank line each side;
   the menu on it offers the Output Block; ⌘Z takes it back in one step.
5. ••• › **Summarise Note** on a short note, then on a 30-page one: the sheet
   says "Reading part n of 5" and the "Only the first part fit" line.
6. Airplane mode: it still works (no network).
7. Switch the assistant off: the items go. Turn Apple Intelligence off in the
   system's Settings: the items stay and the sheet says to turn it on.
8. Lock the note: Insert Below is disabled, Copy is not. VoiceOver reads the
   answer and announces "Answer ready".
9. Tune the 3-characters-a-token rule (`AIBudget.charactersPerToken`) and the
   4-piece limit if answers are cut too early or fail with "too long".

## Provisional (Marcus to review)

1. **No third button in the code block header.** The edit menu and ••• carry
   it. A header button would be better to find; it costs a change to the
   action bar's geometry and gesture refusal, which needs a real-finger check.
2. **Insert Below, not Replace**, as a quote by default. The note's text is
   never changed without a tap, and nothing is inserted automatically.
3. **Hidden vs shown**: hidden when switched off or device ineligible; otherwise
   shown with a reason in the sheet.
4. **Length of notes**: at most 4 pieces, then cut with a notice.
5. **Plain-sentence answers.** No Markdown from the model, so nothing renders
   half-formatted in a quote.
6. ~~No Pro/ads gating.~~ **Replaced by P2 (28 Oct 2026): the AI features are Pro**; see "Pro gate" below.
7. **Ink is not summarised.** Only the note's text.

## Pro gate (P2, 28 Oct 2026)

Decision 7 of the 1.0 plan: Explain Code and Summarise Note are part of Pro.

- **One check, in `AIAssistant.begin`.** Every entry point (the edit menu's
  Explain Block, the text row's Explain chip, ••• › Summarise Note) ends there,
  so the gate cannot be missed by adding a menu. A free reader sets
  `needsPro`, no job is made and the model client is never called;
  `PageDetailView` shows `PaywallView` for it in place of the result sheet.
  The app's assistant (`AIAssistant.system()`) reads `ProStatus.shared.isPro`;
  the `isPro` closure defaults open so the state-machine tests need no store.
- **The items stay visible to free readers**, so the paywall is how they learn
  what Pro does. Hiding for an ineligible device or the Settings switch is
  unchanged (`offersFeatures`).
- **The paywall says whether this iPad can run the AI** (the same
  `AIUnavailableReason` words), and that Run and no ads work regardless.
- Tests: `PaywallTests` (free is gated and the model sees no request; Pro runs;
  buying lifts the gate; the paywall's strings). Mutation-checked: with the
  guard defeated, `PaywallTests` fails.
