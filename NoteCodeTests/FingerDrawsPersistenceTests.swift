//
//  FingerDrawsPersistenceTests.swift
//  NoteCodeTests
//
//  Finger Draws is the device's, like the ink tools: each note gets a new
//  editor, and before 10 October that editor started with a finger drawing
//  whatever the reader had chosen in the last note. These host the real note
//  page, so they see the setting reach the canvas rather than a stored value.
//

#if canImport(UIKit)

import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Finger Draws carries over", .serialized)
@MainActor
struct FingerDrawsPersistenceTests {

    /// One open note, with an editor of its own, as opening a note makes.
    @MainActor
    private final class OpenNote {
        let container: ModelContainer
        let editor = NoteEditor()
        let window = HotbarLayoutTests.makeWindow()

        init() throws {
            container = try ModelContainer(
                for: NoteSchema.current,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let page = Page(title: "Graphs", content: "# Graphs\n\nA tree is a graph with no cycles.\n")
            container.mainContext.insert(page)

            let root = NavigationStack { PageDetailView(page: page, editor: editor) }
                .modelContainer(container)
            window.rootViewController = UIHostingController(rootView: root)
            window.makeKeyAndVisible()
            settle()
        }

        /// Lets SwiftUI lay out and run its `onAppear` and `onChange`.
        func settle(_ seconds: TimeInterval = 0.5) {
            let end = Date(timeIntervalSinceNow: seconds)
            repeat {
                window.layoutIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            } while Date() < end
        }

        func close() {
            window.isHidden = true
            window.rootViewController = nil
        }

        var canvas: DrawingCanvas? {
            func find(in view: UIView) -> DrawingCanvas? {
                if let canvas = view as? DrawingCanvas { return canvas }
                for subview in view.subviews {
                    if let found = find(in: subview) { return found }
                }
                return nil
            }
            return find(in: window)
        }
    }

    /// Runs `body` with `value` stored as the device's Finger Draws (`nil`:
    /// nothing stored), and puts back whatever the device had.
    private func withStored(_ value: Bool?, _ body: () throws -> Void) rethrows {
        let key = NoteEditor.fingerDrawsKey
        let saved = UserDefaults.standard.object(forKey: key)
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    private var stored: Bool? {
        UserDefaults.standard.object(forKey: NoteEditor.fingerDrawsKey) as? Bool
    }

    @Test("With nothing stored, a finger draws")
    func onByDefault() throws {
        try withStored(nil) {
            let note = try OpenNote()
            defer { note.close() }

            #expect(note.editor.fingerDraws)
            let canvas = try #require(note.canvas)
            #expect(canvas.allowsFingerDrawing)
        }
    }

    @Test("A note opens with Finger Draws as the device has it", arguments: [false, true])
    func opensAsStored(fingerDraws: Bool) throws {
        try withStored(fingerDraws) {
            let note = try OpenNote()
            defer { note.close() }

            #expect(note.editor.fingerDraws == fingerDraws)
            let canvas = try #require(note.canvas)
            #expect(canvas.allowsFingerDrawing == fingerDraws)
        }
    }

    @Test("Changed in one note, it is what the next note opens with")
    func carriesToTheNextNote() throws {
        try withStored(nil) {
            let first = try OpenNote()
            first.editor.setMode(.ink)
            first.editor.fingerDraws = false
            first.settle()
            #expect(stored == false)
            first.close()

            let second = try OpenNote()
            #expect(!second.editor.fingerDraws)
            let canvas = try #require(second.canvas)
            #expect(!canvas.allowsFingerDrawing)

            second.editor.fingerDraws = true
            second.settle()
            #expect(stored == true)
            second.close()

            let third = try OpenNote()
            defer { third.close() }
            #expect(third.editor.fingerDraws)
        }
    }

    @Test("Changed in Settings over the open note, it reaches that note")
    func settingsChangeReachesTheOpenNote() throws {
        try withStored(true) {
            let note = try OpenNote()
            defer { note.close() }
            #expect(note.editor.fingerDraws)

            UserDefaults.standard.set(false, forKey: NoteEditor.fingerDrawsKey)
            note.settle()
            #expect(!note.editor.fingerDraws)
            let canvas = try #require(note.canvas)
            #expect(!canvas.allowsFingerDrawing)
        }
    }

    @Test("The eraser set in Settings reaches the open note")
    func settingsEraserReachesTheOpenNote() throws {
        let key = EraserSettings.defaultsKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let note = try OpenNote()
        defer { note.close() }

        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .large
        UserDefaults.standard.set(eraser.rawValue, forKey: key)
        note.settle()
        #expect(note.editor.inkTool.eraser == eraser)
    }
}

#endif
