# T11. Should `Text/Core` be a Swift package?

Status: proposed, 6 Nov. Marcus decides. Docs only; nothing in the project
changed.

## Question

`NoteCode/Text/Core` (18 files, 4,977 lines, imports only Foundation) is the
parser and formatter. Would a Swift package make its tests run with
`swift test` on the Mac, without a simulator, and is that worth the `public`
the app would then need?

## What was measured (6 Nov, M-series Mac, Xcode 27, debug builds)

The prototype is outside the repo: Core's files, the Core tests and
`Tags.swift`/`TopLevelSpans.swift` copied into a scratch package
(tools 6.2, Swift 5 language mode, default actor isolation MainActor and
MemberImportVisibility, as the app target has them). The project was not
touched.

| | Today (Xcode, `check.sh --only` the 38 Core suites) | Package (`swift test`) |
|---|---|---|
| Tests | 321 (the whole of `NoteCodeTests/Text/Core`, including the UIKit editor and layout suites) | 235 in 27 suites |
| Test run | 20.1 s in the simulator | 6.7 to 16 s warm (five runs; the spread is machine load), 12.1 s once after a clean build |
| Wall clock | 199 s (build, simulator boot and install, test run) | 22 s clean build, then 7 to 16 s |
| Needs | a booted iPad simulator, the app's SwiftPM packages (Google Mobile Ads, SwiftMath, HighlightSwift) | Swift toolchain only |

The Fast plan as a whole was not timed again: it is 1,954 tests in 164
files, and 235 is 12% of them. The saving is the 199 s of building and
booting, which the iterating loop pays on every `--only` run, not the test
time, which is similar.

**How many pure tests would move.** `NoteCodeTests/Text/Core` has 14 files and
about 325 test functions (321 cases once parameterised ones count). 235 cases compile and pass against Core alone. The rest
stay in the app's bundle, because:

- 2 snapshot files need `DebugFixture` (app code). They stay.
- 9 test functions inside `TextColourTests`, `NestingInlineTests` and
  `InlineMarksTests` also touch `TextRewritingPolicy`, `NoteSearch`,
  `NoteInfo`, `NoteOutline`, `AccentPalette` or `HighlightColour`'s palette.
  They are "elsewhere" checks that happen to live in a Core suite. They
  would move to the folder of what they test.
- The `...LayoutTests` and `...EditorTests` suites are UIKit and stay.

No other pure tests would move: `MathParserTests`, `CodeBlockIdentityTests`
and the like test code outside Core.

## What Core still reaches out for

Core is not clean, though it imports only Foundation. The prototype needed
two things from the app:

1. `CodeRange` and `CodeLanguage`, in `Code/CodeBlockAction.swift` (146
   lines, Foundation only). Core uses `CodeRange` 28 times.
2. `SettingKeys` (`FenceVisibility.swift:18`, one line, the key
   `showMarkdown`).

The first is a move (the file would join Core); the second needs the key's
name passed in or stored as a literal that a test pins. Both are small, but
they are changes to the app's source, so they would be their own PRs.

## What `public` would cost

Core declares 29 top-level types and about 436 member names. The app
references 25 of the types, from 50 of its 178 files:

`BlockNode CodeBlock CodeBlockID CodeBlockKind CodeLanguage DocumentCache
DocumentParser FenceTag FenceVisibility HighlightColour InlineAttributes
InlineNode InlineSpan LinkTarget ListMarker MarkdownFormatting MathBlock
ShowMarkdown SpanSize SpanStyle StyledLine TeXAliases TextColour TextEdit
TypingStyle`

Each of those needs `public`, and so does every member and initialiser the
app touches: up to 224 member names by a rough count (upper bound; it
matches on `.name`). Memberwise initialisers are never public, so each
struct the app builds also needs a written `public init`. Enums need
`@frozen` or `@unknown default` handling at the app's switches. That is the
real cost: hundreds of edits to files the text stream (2T) is still
changing, plus a rule to keep it right (the compiler enforces it, so it
would not drift). Tests need none of it: `@testable import` sees internals
in debug builds.

Also: the target would build Swift 5 mode with default isolation, which the
package must repeat (`defaultIsolation(MainActor.self)`), or it would
silently differ from the app. The module is also a second place the
`nativeUTF8` and `.layoutManager` rules have to hold, though Core cannot
reach `.layoutManager` (no UIKit).

## Options

**A. A real package, the app depends on it.** Full `public` API, a pbxproj
edit (add a local package reference and product to the NoteCode target),
and a guarantee Core cannot import UIKit. Cost as above; no benefit that B
lacks for speed.

**B. A test-only package at the repo root that compiles the same files in
place.** A `Package.swift` whose target is named `NoteCode` (so every test's
`@testable import NoteCode` works unchanged) with `path:`/`sources:` listing
`NoteCode/Text/Core/*.swift` and `Code/CodeBlockAction.swift`, and a test
target listing the pure test files. The app does not depend on it; the
Xcode project does not know it exists; nothing becomes `public`. The
prototype above is exactly this, with copied files; it ran the 235 tests
and passed with the module named `NoteCode`. It adds a `Package.swift`, a
`scripts/core-test.sh`, a CI line, and a lint that fails when a file in Core
imports a framework other than Foundation (that part is already true).
It needs the two Core clean-ups above, and moving the 9 mixed tests to the
suites for what they test. It does not need a pbxproj edit. Xcode may offer
the root `Package.swift` as a workspace package when the folder is opened;
that is harmless but worth knowing.

**C. Do nothing.** The Xcode loop already runs these tests (20 s once the
simulator is warm).

## Recommendation

Do **B**, after the 2T text stream settles, and not A.

- It gives what the brief wanted: the pure tests in seconds on the Mac,
  without a simulator and without the app's three heavy dependencies, which
  is what lets a session iterate on the parser quickly (the 199 s a run is
  mostly build and boot).
- It costs no `public`, no pbxproj edit and no behaviour change, and the
  tests stay one set: the same files run in both places, so they cannot
  drift.
- A buys a compiler-enforced boundary (Core cannot import UIKit or reach
  the app), which `scripts/check-seam.sh` and a lint rule can enforce for the
  price of a script. It is not worth hundreds of `public`s while 2T is
  moving the files.
- Revisit A only if Core is to be shared with a second target (the macOS
  app, the open-source build) as a binary dependency. The `OpenSource`
  folder's own build already compiles the sources it needs.

If Marcus agrees, the steps are, in order: (1) move `CodeRange` and
`CodeLanguage` into `Text/Core` and pass `FenceVisibility` its key (PR, text
stream); (2) move the 9 mixed tests; (3) add `Package.swift`,
`scripts/core-test.sh` and the CI line. None of these touch
`project.pbxproj` for B; if the tests files move between folders on disk,
check whether the test target uses folder references or per-file entries
(it is Marcus's call, since a per-file entry is a pbxproj edit).
**Adding a package to the Xcode project (option A) is a pbxproj edit and is
Marcus's step; nothing here does it.**

## Findings on the way

- `scripts/lint-traps.sh` rule 9 reports 49 sleeps or run-loop spins against a
  limit of 48 on current `origin/main`, so `check.sh` fails its lint step. It
  is not from this PR.
- `docs/decisions.md`, which AGENTS.md links to, did not exist; this PR
  creates it with this entry.
