# T. Tests

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules.

**What the last full run showed** (29 Oct, 1,858 test cases, all passing):

- **Most of the run is not tests.** The tests themselves add up to 222s of
  a 566s run.
- **Two-thirds of the tests are tiny.** 1,219 take under 10ms each, about
  1s in all; they are the pure ones.
- **A few are heavy.** 56 tests over 1s take 122s between them; the
  slowest is `PageViewTests.canvasStaysScreenSized` at 9.2s.
- **Other findings:**
  - 54 sleeps or run-loop spins across about 20 files.
  - 4 files write `UserDefaults.standard`, which reaches the simulator
    app's own settings and the next test.
  - 16 files each define their own harness, and about 34 drive the text
    view's Coordinator directly.
  - The perf tests assert absolute times.
  - There are no tags, test plans or coverage numbers.
  - The UI tests have never run.
  - One test can't fail: `AppStoreReadinessTests` returns early when it
    can't find the repo.

T2 (measuring) is part of 0D. T1, T3, T4 and T9 ship in 1.1.1; the rest wait
for Update 2.

## T1. Results you can trust

**Do.**

1. **`repoRoot`.**
   - Add `NoteCodeTests/TestSupport/TestPaths.swift`. Its `repoRoot` walks
     up from `#filePath` until it finds the directory holding
     `NoteCode.xcodeproj`. If it never finds one, it records an issue,
     never returns quietly.
   - Use it in `AppIconTests.swift:55` and `AppStoreReadinessTests.swift:60`,
     and anywhere else `#filePath` is walked up
     (`grep -rn "#filePath" NoteCodeTests`).
   - `AppStoreReadinessTests`' early `return` when the file is missing
     becomes a failure.
2. **`TestDefaults`.**
   - A helper that gives a test its own `UserDefaults(suiteName:)` with a
     unique name, and removes that domain afterwards.
   - Move onto it the four files that write `UserDefaults.standard`:
     `FingerDrawsPersistenceTests`, `HotbarLayoutTests`,
     `AccentPaletteTests` and `SettingsTests`.
   - Some app code reads `.standard` itself, such as
     `AccentPalette.drawingColor()` and `ExportAll.swift:225`. There, add a
     `defaults: UserDefaults = .standard` parameter, which changes nothing
     in the app, or host the view with `.defaultAppStorage(_:)`.
   - Where neither works, the test saves and restores every key it touches.
     List those tests in the PR.
3. **The lint.** `lint-traps.sh` rule 7 (no `UserDefaults.standard` in
   tests) reaches zero, or an allow-list entry with a reason.

**Done when.**
- The four files and the readiness tests pass, and so does `check.sh`.
- The readiness test is **seen to fail** when it is pointed at a wrong
  path, and when `PrivacyInfo.xcprivacy` is renamed in a scratch commit.
  Both outputs go in the PR.

## T3. Tags and test plans (after 1A3)

**Do.**

1. **Tags.** Add them in `NoteCodeTests/TestSupport/Tags.swift`: `.pure`,
   `.editor`, `.layout`, `.ink`, `.library`, `.perf`, `.pro`.
   - Tag each `@Suite` by the folder its file is in after 1A3: `Text/Core`
     is `.pure`, `Pro/` is `.pro`, and so on.
   - The perf suites (the ones `perf.sh` runs) are `.perf` as well.
   - A suite's tag covers its tests.
2. **Test plans.** Four, in the shared scheme:
   - **Fast** is everything except `.perf`, and is the default.
   - **Full** is all of `NoteCodeTests`.
   - **Perf** is `.perf` only.
   - **Pro** is `.pro` only.

   Create them in Xcode's test plan editor, or by hand if
   `xcodebuild -testPlan Fast` then runs the expected count. **Marcus
   approves the scheme change** before it merges, since it is project
   configuration.
3. **The scripts.** `check.sh` runs Fast, `check.sh --full` runs Full and
   the UI tests, and `perf.sh` runs Perf.
4. **Bounds.** The perf tests' absolute bounds stay: they are the budgets
   that caught real regressions. They just stop running in the inner loop.

**Done when.**
- Fast plus Perf equal Full's count, and every suite has a tag.
- The PR gives Fast's wall time; the target is under 90s.
- If Fast is still slow, name what dominates, from 0D's numbers.

## T4. One TestSupport folder (after T3; two PRs)

**Do.**

1. **Find the harnesses.** Read the 16 harness definitions
   (`grep -rln "class Harness\|func makeTextView\|func makeEditor" NoteCodeTests`).
   They include `PageViewTests:141`, `CodeFenceDisplayTests:25`,
   `NoteEditorTests:22`, `TextSizeTests:329`, `TextRowTests:149`,
   `EditorModeTests:21`, `PageOverlayTests:20`, `InkInsertTests:215` and
   `DrawingCanvasTests:21`. Find the shape they share.
2. **Write the harnesses** in `NoteCodeTests/TestSupport/`:
   - `EditorHarness`: a text view, its Coordinator and a `NoteEditor` in
     `makeTestWindow`.
   - `PageHarness`: adds the `PageView`, page layout, view mode and zoom.
   - `InkHarness`: the canvas and ink capture, with an `async` commit.

   They speak in what a reader does and sees: type, paste, select, set a
   setting, the text, the attributes at a point, the blocks and their bars.
   Only what the copies already do, under clearer names.
3. **Fixtures.** `TestFixtures` provides:
   - the DebugLaunch seed notes (`pages`, `code`, `empty`), exposed to
     tests behind `#if DEBUG`;
   - a long note and an ink-heavy note, built from the generators the
     cost tests already use.
4. **Migrate.** PR 1 adds the harnesses and moves four files. PR 2 moves
   the other twelve. The assertions don't change, and the test count
   doesn't change.

**Done when.**
- No test file defines its own harness.
- `check.sh` passes, with the same count.
- A new test can be written in five lines; show one in the PR.

## T9. UI tests that run

**Do.**

1. **Run the four existing files once** on the simulator and report each
   result.
   - `ListDragUITests` needs a real iPad, since the simulator delivers no
     drop. It skips itself on the simulator, with that reason.
   - Fix or skip the others, giving a reason for each.
2. **Write a smoke test** in `NoteCodeUITests/SmokeUITests.swift`:
   - Launch with `-debug-note code`.
   - Type a line.
   - Check a code block's Run and Copy buttons exist.
   - Toggle draw mode and back.
   - Switch view mode from the menu.
   - Open Settings and close it.

   Find elements by accessibility identifier, adding identifiers where
   they are missing; identifiers change nothing a reader sees. Keep the
   smoke test under 60s.
3. **Wire it in.** `check.sh --full` runs `NoteCodeUITests`.

**Done when.** `check.sh --full` runs the UI tests green. The skips have
their reasons. The PR gives the smoke test's time.

## Update 2 (expanded into briefs when it starts)

- **T5. Characterisation tests first.** Before each extraction in
  update-2.md, pin the area's behaviour today through the harness, starting
  with the untested areas:
  - navigation and create/delete with Undo (before 2P4);
  - the ink tool's settings round trip (before 2P5);
  - the formula editor;
  - `CodeBlockOverlay`'s placement in the viewport;
  - highlighting landing after its debounce.
- **T6. No sleeps.** Inject a clock, or an awaitable "settled" hook, into
  the debounces: the 20ms highlight, `DrawingSaveScheduler`, toasts, the
  badge fade, the launch delay. Then replace the 54 sleeps and spins.
- **T8. Prove the trap tests.** For each AGENTS.md trap that has a test,
  reintroduce the mistake once and see the test fail. Write one where a
  trap has none: the `.layoutManager` downgrade, `inkType` on eraser ink,
  `drawingData` after a purge, and the `MarkupOrderedSet` costs.
- **T10. Snapshots (optional).** A handful of rendering checks with a
  tolerance, as `HotbarIconPixelTests` does, on one simulator model:
  - a code block's panel
  - hidden markers
  - print layout
  - a display formula
  - ink across a page break
- **T11. A Core package?** Once `Text/Core` is clean, decide whether to make
  it a Swift package. The pure tests would then run with `swift test` on
  the Mac in seconds, but every type it shares needs `public`, and it is a
  project edit. Write the decision either way.

(T7, the leak tests, is part of F3.)

## Rules from now on

These go into AGENTS.md when Update 1 ends.
- A fix starts with a test that fails without it.
- A refactor of an untested area starts with characterisation tests.
- Tests use the harnesses and `TestDefaults`, and never sleep.
- Perf numbers are compared with the baseline.
