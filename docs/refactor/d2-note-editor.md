# D2. NoteEditor: is the feature plumbing a type of its own?

Decision note for [debt.md](debt.md) › D2, written 8 Nov 2026 against
`main` 40937bf. Docs only; nothing here has been built.

## Answer

**No.** The feature plumbing is too small to be a type of its own, and
pulling it out would not reach what makes `NoteEditor` the place where
everything meets. The file gets smaller by **two pure moves into extension
files** instead. They loosen one private method that adds nothing new, and
they can wait until after the split.

## What the 728 lines are

| Lines | Section | Kind |
|---|---|---|
| 23-97 | Mode and ink tool | One-line forwarders to `EditorModeState`, plus two setting names |
| 99-144 | Lock, undo, edit guard, typing style, text target | Stored state and forwarders |
| **146-202** | **Feature plumbing** | `features`, `featuresInstalled`, `services`; `install`, `connectFeatures`, `blocksDidChange`, `feature(_:)`, `actions(for:in:)` |
| 204-333 | The page: count, add, insert into ink, commit, PDF, print | Asks `PageView` (about 130 lines; the move below takes about 90) |
| 335-381 | `attach`, `setTextLocked` | Wiring |
| 383-605 | Find, formatting, the text options row | Text commands through `perform` |
| 607-667 | Selection size, link, settle clock | Forwarders and the link alert's state |
| 669-703 | Typography | Forwarders |
| 705-725 | Outline, scroll | Asks `PageView` |

The feature plumbing is about 55 lines, with the doc comments. The text
commands are about 220 and the page's requests about 130, of which
about 90 can move (step 2 below). The forwarders
to the four controllers are about 150 more. Those exist so that callers
write `editor.setMode`, not `editor.modeState.setMode`.

## Why the plumbing stays on NoteEditor

- **A feature is made from the whole editor.**
  `EditorFeatureFactory` is `(NoteEditor) -> any EditorFeature`. Both
  features keep a weak `NoteEditor` and read its `mode`, `isTextLocked`,
  `textView`, `codeRanges`, `codeBlockAtCaret`, `perform` and
  `scroll(toLineAt:)`. An `EditorFeatureHost` would still need the editor
  to call the factories, so the coupling D2 asks about would stay where it
  is. Only the bookkeeping would move.
- **`features` is observed.** `PageDetailView` builds its accessories and
  side panels with a `ForEach` over `editor.features`, and installs them in
  `onAppear`, after the editor exists. `RunFeature` relies on that ("whether
  Run exists is known as soon as the editor has the feature"). A separate
  type would also have to be `@Observable` and read through the editor. If
  that went wrong, a note would open with no Run panel, and no unit test
  would notice. `EditorLeakTests+Run` comes closest.
- **Callers.** Ten general call sites use it: `PageDetailView` (3),
  `NoteHeader`, `TextOptionsRow`, `NoteMoreMenu`, `CodeFenceDisplay`,
  `DocumentTextView+Styling` and `CodeBlockCommands` (2). So do three Pro
  test files (`RunFeatureTests`, `EditorLeakTests+Run`, `AIEditorTests`),
  and a general test, `KeyboardAndMenuTests`, calls `editor.actions(for:in:)`.
  The host would need forwarders on `NoteEditor` for all of them, or Pro
  tests would change for a general refactor.
- **A move into `NoteEditor+Features.swift` loosens access.**
  `featuresInstalled` and `services` are `private` stored properties.
  Stored properties cannot go in an extension, so the methods in another
  file would need them `internal`. That trade isn't worth 55 lines.

## The split I recommend instead (pure moves)

1. **`NotePage/NoteEditor+Formatting.swift`** gets lines 395-605:
   - `toggle(_:)`, `setHeading`, `toggleBullet`, `toggleQuote`,
     `insertFormula`, `insertRule` and `toggleList`;
   - `formattingShown`, both `insertCodeBlock`s and
     `insertCodeBlockInLastLanguage`;
   - both `perform`s;
   - `codeRanges`, `indent`, `setCodeBlockKind`, `addOutputBlock`,
     `setColour`, `recolourText` and `setHighlight`.

   About 200 lines leave. **No access change:** `finishLink` stays
   behind and calls `perform` with a closure that returns a plain
   `TextEdit` (`MarkdownFormatting.link`). Once the private
   `perform(_: (String, NSRange) -> TextEdit)` is in another file, Swift
   matches that closure to the internal `perform` for an optional edit by
   wrapping the result, and the private overload only does that wrapping
   (`Optional(makeEdit(...))`). The other way, moving the link section
   too, would loosen `linkTarget`'s setter, which is state the alert
   depends on.
   The stored properties `caretFormatting`,
   `rendersMarkdown` and `showsLineNumbers` stay, and so does
   `setCaretFormatting`, which assigns a `private(set)` property.
2. **`NotePage/NoteEditor+Page.swift`** gets what asks `PageView`:
   - `pageCount`, `addPage`, `insertionPageWidth`, `insertionMaxHeight`;
   - `commitInk`, `pdf(title:)`, `currentText`, `printNote`, `showFind`;
   - `outline()` and both `scroll`s.

   About 90 lines leave.
3. **These stay**, because they write private state:
   - `insertIntoInk` and `reselectInserted` (`lastInserted`);
   - the link section (`linkTarget` is `private(set)`);
   - `attach` and `setTextLocked`;
   - the feature plumbing.

That leaves about 440 lines: the stored state, the wiring and the
forwarders. Each move is one commit checked with
`scripts/verify-move.sh origin/main`, and `check.sh` must stay green. No
`perf.sh` run is needed, since nothing on a typing path changes its code.

## Risk

The moves themselves are low risk. An extension in another file sees the
same members, apart from `private` ones. None of the moved members reads a private member, and none stays behind
that needs a moved private one. The compiler and `verify-move.sh` would catch a mistake.
`NoteEditor` is `@Observable`, and the macro only rewrites stored
properties, all of which stay in the class body.

The one thing to watch is a computed property moved out of the class body,
such as `codeRanges` or `formattingShown`. It is observed through the
stored properties it reads, so it behaves the same in an extension.

## Before the repo split?

**No.** Both moves are general code. They land in the public repo the same
way before or after S3, and after S5 they cost one public PR. They don't
block S2 or S3, and the release work comes first.

One thing would be cheaper before the split: **narrowing the feature
contract.** That means features getting a protocol, or more of
`EditorServices`, instead of the whole `NoteEditor` (D13's closure
coupling). After S5 it becomes a public PR and a private commit, merged by
`sync-upstream.sh`. It still isn't worth doing now:

- only two features use the contract, and both are in this repo;
- the members they read are already a short, stable list (above);
- a third feature, if one ever comes, is the time to ask again.
