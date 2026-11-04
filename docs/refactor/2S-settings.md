# 2S2. Settings in one place

Part of the refactor plan; the rules every session follows are in
[README.md](README.md) › Rules. The design is
[update-2.md](update-2.md) › 2S2; this file is the briefs. Line numbers were
checked on `main` at `07a5c34` (4 Nov). Four PRs, after 2X (wave 8): 2S2a
first, then 2S2b–2S2d, which touch different files.

**Where the code is today.** 1B5 split SettingsView into one file per
section, so update-2.md's "SettingsView (:278–569)" is now six files:
`GeneralSettings`, `NotesSettings`, `WritingSettings`, `CodeSettings`
(all `NoteCode/Settings/`), `DrawingSettings` (`NoteCode/Ink/`) and
`AboutSettings`. There are **72 `@AppStorage` declarations in 22 files**
(`grep -rn "@AppStorage(" NoteCode`, 77 lines, 5 of them comments). Every
key is a `static let` on the type that owns it, and 2S1 pinned each one and
its default (`SettingsTests.keysAreStable`, `ProKeysTests`).

Keys declared in more than one place (`grep -rhoE "@AppStorage\([^)]*\)" NoteCode | sort | uniq -c`):

| Key | Copies | Where |
|---|---|---|
| `AccentPalette.defaultsKey` | 5 | GeneralSettings:15, NoteList:72, RecentlyDeletedView:69, AppearanceModifier:32, AccentPalette:150 |
| `HotbarDock.defaultsKey` | 3 | PageDetailView:72, GeneralSettings:17, ContentView:95 |
| `NewNotes.defaultsKey` | 3 | NotesSettings:13, NoteList:85, ContentView:74 |
| `IconStyle.defaultsKey` | 3 | GeneralSettings:20, HotbarPrimitives:380, NoteWindowControl:60 |
| `EraserSettings.defaultsKey` | 3 | DrawingSettings:17, :181, HotbarPrimitives:31 |
| 15 more | 2 each | PageDetailView against Writing, Code, General, Notes, Drawing; NoteList against Notes; HotbarPrimitives against Drawing |

PageDetailView's 16 (:72–144) are all copies. 2X4b takes its three AI ones
out (into `AssistantFeature`), so 2S2b starts from **13**.

**Must not (every step).** Change a key's string, a default, a type's raw
values or what a setting reads when nothing is stored. Change what any
screen shows. Read `UserDefaults.standard` in a test (`lint-traps.sh`
rule 7). The pinned tests stay as they are; if one has to change, stop.

## 2S2a. Key tables

**Goal.** One table per feature holds each key and its default; an
`@AppStorage` convenience init takes a table entry, so a declaration can't
repeat a default.

**Files.** New `NoteCode/Settings/SettingKeys.swift` (the general table, or
one table per feature folder beside its owner: say which and why) and
`NoteCode/Pro/ProSettingKeys.swift` (the `ai*` keys, `adHomeVisits`,
`runPanelWidth` (`RunDockWidth.key`), `runDisclosureAccepted`).

**Do.**
1. A `SettingKey<Value>` (name and default) and
   `extension AppStorage { init(_ key: SettingKey<Value>, store:) }` for
   each value kind used (`Bool`, `Int`, `Double`, `String`, `RawRepresentable`).
2. Each owner's `static let …Key` and default become one `SettingKey`; the
   old names stay as forwarding statics until 2S2b–2S2d have moved their
   callers, then go in the last of those PRs.
3. Move no call site yet except the owners' own.

**Before you start, check each copy's default.** Where two copies disagree
(the `@AppStorage` default differs from the owner's constant), write it in
the PR and keep the one the screen uses today; that is a finding, not a fix.

**Acceptance.** `SettingsTests`, `ProKeysTests` and the build pass. A new
test: every `SettingKey` in the tables has the name and default 2S1 pinned.
Count of `@AppStorage(` declarations unchanged.

## 2S2b. `NoteViewSettings` (two commits)

**Goal.** PageDetailView's 13 remaining `@AppStorage`s become one
`NoteViewSettings: DynamicProperty`.

**Files.** PageDetailView.swift:72–144 (dock, view mode, Show Markdown, the
four marker levels, indent width, code keys, line numbers, Autocorrect,
haptic on snap, add pages while drawing); their uses in the
`DocumentTextView(` call (:562–600) and the dock's get/set (:89–94).

**Do.** *Commit 1:* the declarations to `PageDetailView+Settings.swift`
(pure move). *Commit 2:* the struct in `NotePage/NoteViewSettings.swift`,
built from the 2S2a tables; PageDetailView holds one `let settings`.
`storedDock`'s compact rule (:89–94) stays in PageDetailView: it depends on
`isCompact` and folds, not on the setting.

**Must not.** Change when a setting change reaches an open note (F2 made
Autocorrect apply at once; `TextRewritingPolicyTests` covers it).

**Acceptance.** `NotePageChromeTests`, `TextRewritingPolicyTests`,
`MarkerDimmingTests`, `HotbarDockTests`, `LineNumbersTests`,
`CodeKeysTests` pass. PageDetailView has 0 `@AppStorage`.

**Device line.** Change each of Show Markdown, a marker level, line numbers,
code keys and Autocorrect in ••• › Settings with a note open; each applies
without reopening.

## 2S2c. The Settings pages read the tables

**Goal.** The six Settings pages, NoteList and ContentView declare their
`@AppStorage`s from the tables; no default is written twice.

**Files.** GeneralSettings:14–20, NotesSettings:13–16, WritingSettings:11–17,
CodeSettings:11–13, DrawingSettings:15–21 and :181, NoteList:72–90,
ContentView:74 and :95, HotbarPrimitives:25–40 and :380. Leave the ink
tool's five copies (HotbarPrimitives' `InkToolPersistence`, DrawingSettings)
on the table but in place: 2P5 merges them.

**Acceptance.** `SettingsTests` and the build pass; `grep -c` of literal
defaults beside `@AppStorage(` falls to the `@AppStorage private var
palette` cases, which take their key at `init` (DrawingSettings:120,
HotbarPrimitives:87). The old forwarding statics from 2S2a are gone.

**Device line.** Open Settings and walk every page: every row shows what it
did before on a device with settings already changed.

## 2S2d. `EditorSettings` with `apply(to:)`

**Goal.** The editor settings `DocumentTextView` takes one by one become one
value with one `apply(to:in:)`, as `TextRewritingPolicy` does (AGENTS.md ›
Conventions).

**Files.** DocumentTextView.swift: `showMarkdown` :59, `markerDimming` :62,
`rendersMarkdown` :67, `codeSettings` :70, `rewritesProse` :74; applied at
`makeUIView` :103–107 and `updateUIView` :174–177. `CodeEditorSettings`
(Code/CodeEditorSettings.swift) and `MarkerDimming` already have
`apply(to:in:)`; `EditorSettings` holds them and calls them in today's order.
`typography` (:78) is per note and applied inside `page.reflow` (:165): it
stays separate.

**Alongside (feature-audit.md › A10, optional in the same wave).** The page
half of `DocumentTextView` (:17–55, :82–90: layout, clearances, area, ink
saver, reveal, resume, page count, page growth, callbacks) as one
`PageConfiguration` with `apply(to: PageView)`. Its own PR, beside this one;
the Coordinator's name doesn't change.

**Must not.** Change the order `makeUIView` and `updateUIView` apply
settings in (rendering, typography, code, rewriting, markers); stop
`setRewritesProse`'s early return.

**Acceptance.** `TextRewritingPolicyTests`, `CodeFenceDisplayTests`,
`LineNumbersTests`, `NotePDFTests` and the build pass. `DocumentTextView`
takes one `editorSettings` instead of five properties.
