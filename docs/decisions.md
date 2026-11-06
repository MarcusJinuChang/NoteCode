# Decisions and reversals

Newest first. One entry each: what was decided, why, and where the detail is.

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
