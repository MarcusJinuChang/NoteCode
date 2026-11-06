# Decisions and reversals

Newest first. One entry each: what was decided, why, and where the detail is.

## 7 Nov 2026: in print layout, ink stays clipped to each sheet's body

Question (found by T10's `inkAcrossPageBreak` snapshot): a stroke that
crosses a sheet's margins or the gap between sheets is drawn only inside
each sheet's body. Draw it over the margins instead?

Decided (Marcus): keep it clipped. Print layout is a preview of paper, and
the PDF matches what's on screen; paper has no gap, so ink there could only
be dropped or split anyway. The stroke itself is stored whole, so seamless
and compressed modes still show all of it. The snapshot pins this.

## 6 Nov 2026: 2P4 gets an app seam, not a UI test

Question (refactor 2P4): how are navigation, create and delete-with-Undo
tested, when they live in ContentView's and NoteList's private state?

Decided: route A. `NoteNavigation` (`@Observable`, App/NoteNavigation.swift)
owns the selection, the compact path, the columns, the opened search and the
new page, and the create, delete and folder-delete actions; the views hold
one and pass the `ToastCenter` and `ModelContext` in. Landed first as its own
PR with no behaviour change, so the T5 tests drive it as unit tests in the
Fast plan; a UI test would run only under `check.sh --full`. The 2P4 proper
(`NavigationModel`, `NoteActions`) builds on it. Both Undos stay as they are:
the note's reopens, the list's only restores.

Detail: [refactor/2P-page.md](refactor/2P-page.md) › T5 tests for this track.

## 6 Nov 2026: Text/Core gets a test-only package, not a real one (proposed)

Question (refactor T11): make `NoteCode/Text/Core` a Swift package so its
pure tests run with `swift test` on the Mac?

Measured: 235 of the folder's ~325 tests compile against Core alone and
pass in a scratch package in 7 to 16 s (22 s clean build), against 20 s of
test time and 199 s of wall clock (build, simulator boot) in Xcode.
Making the app depend on a package would need `public` on 25 types and up
to ~224 members, and a project edit.

Recommended: a root `Package.swift` that compiles the same files in place
under the module name `NoteCode` and runs the same test files, with no
`public` and no project edit; after the 2T text stream settles, and after
`CodeRange`/`CodeLanguage` move into Core and `FenceVisibility` stops reading
`SettingKeys`. Adding the package to the Xcode project stays Marcus's step
(`project.pbxproj`). Not yet accepted: Marcus decides.

Detail and numbers: [refactor/T11-core-package.md](refactor/T11-core-package.md).
