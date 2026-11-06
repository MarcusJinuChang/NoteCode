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

@Suite("Finger Draws carries over", .serialized, .tags(.ink))
@MainActor
struct FingerDrawsPersistenceTests {

    /// The device's settings for this test. The page reads them through
    /// `.defaultAppStorage`, so nothing here touches `UserDefaults.standard`.
    private let device = TestDefaults("FingerDraws")

    /// One open note, with an editor of its own, as opening a note makes.
    @MainActor
    private final class OpenNote {
        let container: ModelContainer
        let editor: NoteEditor
        let window = HotbarLayoutTests.makeWindow()

        init(defaults: UserDefaults) throws {
            container = try ModelContainer(
                for: NoteSchema.current,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            editor = NoteEditor(inkTools: InkToolStore(defaults: defaults))
            editor.defaults = defaults
            let page = Page(title: "Graphs", content: "# Graphs\n\nA tree is a graph with no cycles.\n")
            container.mainContext.insert(page)

            let root = NavigationStack { PageDetailView(page: page, editor: editor) }
                .modelContainer(container)
                .defaultAppStorage(defaults)
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

    /// Stores `value` as the device's Finger Draws (`nil`: nothing stored).
    private func store(_ value: Bool?) {
        if let value {
            device.defaults.set(value, forKey: NoteEditor.fingerDrawsKey)
        } else {
            device.defaults.removeObject(forKey: NoteEditor.fingerDrawsKey)
        }
    }

    private var stored: Bool? {
        device.defaults.object(forKey: NoteEditor.fingerDrawsKey) as? Bool
    }

    @Test("With nothing stored, a finger draws")
    func onByDefault() throws {
        store(nil)
        let note = try OpenNote(defaults: device.defaults)
        defer { note.close() }

        #expect(note.editor.fingerDraws)
        let canvas = try #require(note.canvas)
        #expect(canvas.allowsFingerDrawing)
    }

    @Test("A note opens with Finger Draws as the device has it", arguments: [false, true])
    func opensAsStored(fingerDraws: Bool) throws {
        store(fingerDraws)
        let note = try OpenNote(defaults: device.defaults)
        defer { note.close() }

        #expect(note.editor.fingerDraws == fingerDraws)
        let canvas = try #require(note.canvas)
        #expect(canvas.allowsFingerDrawing == fingerDraws)
    }

    @Test("Changed in one note, it is what the next note opens with")
    func carriesToTheNextNote() throws {
        store(nil)
        let first = try OpenNote(defaults: device.defaults)
        first.editor.setMode(.ink)
        first.editor.fingerDraws = false
        first.settle()
        #expect(stored == false)
        first.close()

        let second = try OpenNote(defaults: device.defaults)
        #expect(!second.editor.fingerDraws)
        let canvas = try #require(second.canvas)
        #expect(!canvas.allowsFingerDrawing)

        second.editor.fingerDraws = true
        second.settle()
        #expect(stored == true)
        second.close()

        let third = try OpenNote(defaults: device.defaults)
        defer { third.close() }
        #expect(third.editor.fingerDraws)
    }

    @Test("Changed in Settings over the open note, it reaches that note")
    func settingsChangeReachesTheOpenNote() throws {
        store(true)
        let note = try OpenNote(defaults: device.defaults)
        defer { note.close() }
        #expect(note.editor.fingerDraws)

        store(false)
        note.settle()
        #expect(!note.editor.fingerDraws)
        let canvas = try #require(note.canvas)
        #expect(!canvas.allowsFingerDrawing)
    }

    @Test("The eraser set in Settings reaches the open note")
    func settingsEraserReachesTheOpenNote() throws {
        let note = try OpenNote(defaults: device.defaults)
        defer { note.close() }

        var eraser = EraserSettings()
        eraser.mode = .wholeStroke
        eraser.size = .large
        device.defaults.set(eraser.rawValue, forKey: EraserSettings.defaultsKey)
        note.settle()
        #expect(note.editor.inkTool.eraser == eraser)
    }
}

#endif
