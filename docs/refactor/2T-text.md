# 2T. The text system

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. The design is [update-2.md](update-2.md) ›
2T; this file is the briefs. Line numbers were checked on `main` at
`07a5c34` (4 Nov), before 2X; 2X4a and 2X5b move the Run and assistant code
out of DocumentTextView and CodeFenceDisplay, so find the code by name.

**When.** Wave 9, after 2X and 2S2, alongside 2P (different files). One 2T
step open at a time: every one of them edits DocumentTextView. Each step
marked *perf* runs `scripts/perf.sh` before and after and puts both sets of
`PERF` lines in the PR (baseline.md:135–150); more than 10% worse is a stop.

**Traps that apply to every step** (AGENTS.md › Implementation
requirements): never read `.layoutManager`; parse and index
`(textView.text ?? "").nativeUTF8`, never `textView.text`; fences detected
while typing (fast typing, paste, mid-fence edits need Marcus's hands);
action bars placed from the viewport, never by forcing layout further down;
`DocumentUITextView`'s stored properties stay Optional.

**What the facades protect.** 14 test files name `DocumentTextView.Coordinator`
since T4 moved the harnesses (update-2.md says 34). In tests,
`restyle(` appears 24 times in 15 files, `setRendersMarkdown(` 28 in 10,
`textViewDidChangeSelection(` 21 in 7. Every extraction keeps those entry
points on the Coordinator as forwarding methods.

## T5 tests for this track (each lands before its step, in its own PR)

| Before | Pin today's behaviour of | Through |
|---|---|---|
| 2T1 | highlighting landing after its 20ms debounce, and a newer edit cancelling an older pass (`scheduleHighlighting` :621, `highlightGeneration` :322); no test names either today | `EditorHarness`, awaiting `highlightingFinished()` (:698), never a sleep |
| 2T5 | `CodeBlockOverlay`'s bars: one per block in the viewport, none for a block scrolled away, placed after an edit with no layout pass of the text view (`addViewportLayoutObserver`, :519); only `EditorLeakTests` names the overlay today | `PageHarness` |
| 2T5 | the formula editor: open on a formula, Done writes it, Cancel leaves the text (`FormulaEditor`, untested by name) | `EditorHarness` |

## 2T1. One `DocumentSnapshot` per edit (four PRs; perf at each)

**Why.** A keystroke copies the whole document many times. `nativeUTF8`
is read 11 times in DocumentTextView (:459, 470, 479, 533, 590, 709, 885,
920, 1100, 1144, 1183), 3 in CodeFenceDisplay, and once each in
CodeSelectionHighlight:63, DocumentStyler and NoteEditor. Not all run on
one keystroke; find out which do first (a counter in a scratch commit, its
numbers in the PR) and count those. `DocumentCache` (Text/Core/DocumentCache.swift:36)
compares by string; `layoutCodeRanges` (DocumentTextView.swift:233),
`layoutNewlines` (:239) and `layoutMarkerRuns` (:274) are three more caches
keyed on `editCount` (:285, bumped at :417).

**First: 1B9 hasn't been done.** `BlockLayout`, `InlineLayout`,
`BlockSignature`, `layouts` (:538) and `changedIndices` (:468) are still in
DocumentStyler.swift. Do 1B9 as written (1-structure.md) as **PR 0** of
this step, a pure move to `Text/Core/DocumentLayout.swift`.

**The PRs.**
1. `Text/Core/DocumentSnapshot.swift`: an immutable value holding the source
   (`nativeUTF8` once), `editCount`, the parse, the layouts, the block
   targets and the code ranges, each worked out once and lazily.
   Foundation only (`lint-traps.sh` rule 4). Tests in `Text/Core`.
2. `DocumentStyler.applyStyling` and the fragment cache take a snapshot.
3. The Coordinator makes one snapshot per edit (in `observeEdits`, :396)
   and its callers read it.
4. The old caches go: `layoutCodeRanges`, `layoutNewlines`,
   `layoutMarkerRuns`, `DocumentCache.cachedCodeRanges`, and the extra block
   lists `CodeBlockAction.targets(in:blocks:)` builds at each call.

**Must not.** Change what is styled or when; make a snapshot hold the text
storage's `NSString` (the reason `nativeUTF8` exists); compute anything
eagerly that only one path needs.

**Acceptance.** Each PR: the perf suites within 10%, and PR 3 or 4 shows
`StylingPerformanceTests/keystrokeCost` and `CodeFenceCostTests/caretMoveCost.keystroke`
lower. `StylingPerformanceTests`, `CodeFenceDisplayTests`, `LineNumbersTests`,
`MarkdownLayoutTests` pass.

**Device line** (PR 3 and 4). Type fast in a long note's code block and its
prose, paste a block, edit inside an open fence: highlighting and the bars
keep up.

## 2T2–2T6. Types out of the Coordinator

Each is **two commits** (the section to `DocumentTextView+Area.swift`,
then the type), keeps forwarding methods on the Coordinator for the test
entry points above, and lists the members it loosened. Today's sections:

| Step | Type | Takes (DocumentTextView.swift unless named) |
|---|---|---|
| 2T2 | `TextStyleSession` | `documentCache` :216, `styleSignatures` :315, `restyle` :586–619, `setTypography` :452, `markerRuns` :468, `invalidateStyling` :716, the marker dimming and `showMarkdown` state :242–246 |
| 2T3 | `SyntaxColouring` | `highlighter` :317, `highlightTask` :318, `highlightGeneration` :322, `highlightedBlocks` :327, `HighlightKey` :332–346, `highlightedAppearance` :347, `pinnedAppearance` :357, `scheduleHighlighting` :621–697, `highlightingFinished` :698, `observeAppearance` :706 |
| 2T4 | `EditRouter` + `CaretTracker` | `textViewDidChange` :722, `shouldChangeTextIn` :1112, `apply(_:to:)` :971, `markerEdit` :993, `textViewDidChangeSelection` :872, `caretStop` :900, `normalizeCaret` :932, `lastCaret` :289, `editCountAtLastSelection` :286 |
| 2T5 | `KeyboardPolicyController` + `FenceDisplayController` | `applyRewritingPolicy` :1155, `setRewritesProse` :1180, the code-keys row :1187–1255, `hardwareKeyboardObservers` :258; CodeFenceDisplay.swift's fence visibility (`refreshFenceVisibility`, `fenceVisibility` :277, `headingVisibility` :281) |
| 2T6 | `CodeBlockCommands` | `copy` :525, `target(atCaret:)` :532, `run`/`openAtSite` (what 2X5b left), `codeBlockMenu` :790, `indentEdit` :1060, CodeFenceDisplay's `connect` closures |

**2T2.** `NotePDF` (InOut/NotePDF.swift:262, :272) builds a whole
Coordinator to style text for printing; it uses `TextStyleSession` instead.
*Perf* (`NotePDFTests/printingCost`). Acceptance: `NotePDFTests`,
`StylingPerformanceTests`, `MarkdownLayoutTests`, `TypingStyleTests` pass.

**2T3, with feature-audit.md › A11.** Syntax colours are told apart from
other foregrounds by their colour value ("not `.label`, not the output text
colour, not `markerColor`, not `.clear`", DocumentStyler.swift:601 and
:616–617, :851), and the output colours are a hair off `.label`
(CodeOutputPanel.swift:17–18) so the comparison works. A custom attribute
(`.noteCodeSyntax`) marks highlighted runs; `codeColors` and
`inheritedCodeColor` (DocumentStyler.swift:601–622, :844–856) read it
instead of comparing colours. The output colours stay exactly as they are
(changing them is a visible change; say in the PR whether they could now be
`.label`, as a finding). *Perf*. Acceptance: the T5 highlighting tests,
`SyntaxHighlightingTests`, `HighlightAlignmentTests`, `OutputBlockTests`,
`TokenEdgeTests`, `SyntaxThemeTests` pass; a new test that a token coloured
exactly `.label` by the theme still counts as highlighted. Device line: dark
and light, every language in `-debug-note code`, an output block: colours
as before, and switching appearance recolours.

**2T4. The re-entrancy flags in one place.** Today 39 uses over four files:
`isFormatting` (NoteEditor, DocumentTextView; 12), `isApplyingMarkerEdit`
(8), `isRetagging` (CodeFenceDisplay, DocumentTextView; 6),
`isNormalizingCaret` (7), `isWritingTypedText` (NoteEditor; 6). One
`EditGuard` (or the router) owns them, with a scoped `perform(as:)` so a
flag can't be left set. Acceptance: `CaretAnywhereTests`, `MarkerEditingTests`,
`EditingBehaviorTests`, `ReturnAndBackspaceTests`, `TypingStyleTests`,
`RichPasteTests`, `NoteEditorTests` pass. Device line: type
fast across a hidden marker, select across a bold run and type, autocorrect
a word next to the caret.

**2T5.** After the T5 overlay and formula tests. The bars stay placed from
the viewport (`addViewportLayoutObserver`) and below the ink canvas
(`CodeBlockOverlay.ceiling`). Acceptance: the T5 tests, `CodeKeysTests`,
`TextRewritingPolicyTests`, `CodeFenceDisplayTests`, `CodeBlockActionBarTests`
pass. Device line: the bars' Run and Copy take a real tap after typing a
new block, after scrolling, and in draw mode they don't.

**2T6. `TextCommandTarget`.** NoteEditor has 12 closure slots
(`@ObservationIgnored var …: ((…) -> …)?`: `modeDidChange` :31,
`runBlockAtCaret` :212, `presentNewFormula` :246, `copyBlockAtCaret` :247,
`onBlockCopied` :260, `codeRanges` :749, `indentAtCaret` :753,
`retagBlockAtCaret` :757, `commitTextSize` :1194, `commitLineSpacing`
:1252, and the two 2X removes). The ones the Coordinator sets
(`runBlockAtCaret`, `copyBlockAtCaret`, `codeRanges`, `indentAtCaret`,
`retagBlockAtCaret`, `presentNewFormula`) become one weak
`textTarget: TextCommandTarget?`, which removes most of the 26
`[weak self, weak textView]` preambles (CodeFenceDisplay 10, MarkerTaps 7,
FormulaEditor 5, DocumentTextView 4). Callbacks the page sets
(`commitTextSize`, `commitLineSpacing`, `onBlockCopied`) stay closures.
Acceptance: `KeyboardAndMenuTests`, `NoteEditorTests`, `CodeIndentTests`,
`EditorLeakTests` pass (the leak test proves the target is weak).

## 2T7. `NoteEditor` splits (two commits per type)

NoteEditor.swift is 1,386 lines; its sections (MARK lines): Insert :280,
Find :468, Formatting :480, the typing style :624, the text options row
:745, the assistant :773 (gone after 2X4a), the size at the caret :878,
the note's text size :1179, line spacing :1242, Outline :1281, Undo :1302.

- `EditorModeState` (mode, ink tool hand-off, :23–130 or so: find the end
  by the first non-mode member).
- `TypingStyleController` (:624–744).
- `SelectionSizeController` (:878–1178, without the pure helpers).
- `NoteTypographyController` (:1179–1280).
- `UndoRouter` (:1302–), which owns the 13 calls to `refreshUndoState()`
  (11 in NoteEditor, DocumentTextView.swift:736 and :983).
- The pure size helpers (`stepped` :1028, `clampedPoints` :1033,
  `points(typed:)` :1039, … `offset(_:through:replacing:)` :1120) move to
  `Text/Core` with their tests.
- `UIResponder.currentFirstResponder` (:1367–1384) is general; it moves to
  `Shared/` (feature-audit.md › A12).

NoteEditor stays the `@Observable` facade the hotbar and tests use; an
observed property that moves keeps a forwarding computed property, so
observation still fires. Acceptance per PR: `NoteEditorTests`,
`EditorModeTests`, `TextSizeTests`, `TypingStyleTests`, `TextRowTests`,
`HotbarLayoutTests` pass. Device line (the last PR): undo and redo after
typing, formatting, a size change and a paste each take one step.

## 2T8. Long functions (three PRs; perf)

| Function | Today | Becomes |
|---|---|---|
| `DocumentStyler.applyStyling` | DocumentStyler.swift:204–344 (141 lines) | one function per block kind, called from a switch |
| `InlineParser.collect` | Text/Core/InlineParser.swift:152–288 (137) | one tokenizer per case and a delimiter resolver |
| `DocumentParser.parse` | Text/Core/DocumentParser.swift:25–109 (85) | a fence scanner and a math scanner |

Behaviour identical: before each, add a test that parses or styles the
`-debug-note pages` and `code` fixtures (`TestFixtures`) and compares
against a snapshot of today's output taken in the same PR's first commit.
*Perf* (`parseCost`, `fullPassCost`, `keystrokeCost`).

## 2T9. One helper per repeated piece of logic (tests first)

Counted 4 Nov:
- `infoString.split(separator: " ").first`: 7 copies → `CodeBlock.tag`.
- `0x0A` written out 11 times (and some bare `10`s next to UTF-16 reads;
  count them) → one constant.
- A code-range `contains`: about twenty hand-written checks; grep
  `codeRanges.contains(where:` and `NSLocationInRange(` near `codeRanges`.
- Position-to-`textRange` conversions (`position(from:offset:)` then
  `textRange(from:to:)`): one `TextEditExecutor`.
- "Block at offset": unify only the versions whose end-of-document rule is
  the same; list the others and why.

Each helper's test lands in the same PR, before the call sites move.
Acceptance: the suites of every file touched pass; the PR lists each copy
replaced.
