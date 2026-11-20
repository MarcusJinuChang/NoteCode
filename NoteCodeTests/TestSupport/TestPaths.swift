//
//  TestPaths.swift
//  NoteCodeTests
//
//  Where the source tree is, for the few tests that read it: the app icon's
//  art, the drafted privacy page. Found by looking, never assumed, and a test
//  that can't find it fails, so it can't pass by checking nothing.
//

import Foundation
import Testing

enum TestPaths {

    /// The directory holding `NoteCode.xcodeproj`, found by walking up from this
    /// file. Tests run in the simulator or in the Mac app, both of which can
    /// read the tree they were built from.
    ///
    /// If no directory above has the project, this records an issue and
    /// returns the directory the walk began in, so whatever the test reads
    /// next fails as well. It never returns quietly.
    static var repoRoot: URL {
        findRepoRoot(from: #filePath)
    }

    /// `repoRoot` from a path of your choosing, which is how the walk is
    /// tested (`TestSupportTests`).
    static func findRepoRoot(from file: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
        let start = URL(fileURLWithPath: file).deletingLastPathComponent()
        var directory = start
        while true {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("NoteCode.xcodeproj").path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        Issue.record("No NoteCode.xcodeproj in or above \(start.path), so the source tree can't be found", sourceLocation: sourceLocation)
        return start
    }
}
