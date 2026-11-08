//
//  TestSupportTests.swift
//  NoteCodeTests
//
//  The tests that read the source tree (the icon art, the privacy page) are
//  only worth running if a tree that can't be found fails them. These pin
//  that, and that the helpers for settings leave nothing behind.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Test support", .tags(.pure))
struct TestSupportTests {

    @Test("The repo root is the directory holding the Xcode project")
    func repoRootHoldsTheProject() {
        let root = TestPaths.repoRoot
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("NoteCode.xcodeproj").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/site/privacy.md").path))
    }

    @Test("A path with no project above it records an issue instead of passing quietly")
    func missingRootIsAnIssue() {
        withKnownIssue {
            _ = TestPaths.findRepoRoot(from: "/nonexistent/NoteCodeTests/Anything.swift")
        }
    }

    @Test("TestDefaults starts empty, is not the standard defaults, and is removed with its owner")
    func scratchDefaults() throws {
        var name: String?
        do {
            let store = TestDefaults("Support")
            name = store.suiteName
            store.defaults.set("kept", forKey: "TestDefaults.key")
            #expect(store.defaults.string(forKey: "TestDefaults.key") == "kept")
            // The app's own settings, read through a fresh instance on the
            // same search list as the shared one, which tests leave alone.
            #expect(UserDefaults().object(forKey: "TestDefaults.key") == nil)
        }
        let suite = try #require(name)
        let reopened = try #require(UserDefaults(suiteName: suite))
        defer { reopened.removePersistentDomain(forName: suite) }
        #expect(reopened.object(forKey: "TestDefaults.key") == nil)
    }

    @Test("Two TestDefaults never share a domain")
    func scratchDefaultsAreUnique() {
        let first = TestDefaults()
        let second = TestDefaults()
        first.defaults.set(1, forKey: "TestDefaults.key")
        #expect(first.suiteName != second.suiteName)
        #expect(second.defaults.object(forKey: "TestDefaults.key") == nil)
    }
}
