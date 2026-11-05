//
//  EditorLeakTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

/// A note that is closed has to be freed. The Coordinator owns the code-block
/// overlay and the overlay's hooks point back at the Coordinator, so one
/// strong capture keeps every note ever opened alive (F3).
@Suite("Editor leaks", .tags(.layout))
@MainActor
struct EditorLeakTests {

    @Test("A closed note's coordinator, overlay and text view are freed")
    func closedNoteIsFreed() {
        weak var coordinator: DocumentTextView.Coordinator?
        weak var overlay: CodeBlockOverlay?
        weak var textView: DocumentUITextView?
        weak var editor: NoteEditor?

        autoreleasepool {
            final class Box { var value = "" }
            let box = Box()
            let live = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
            let view = DocumentTextView.makeConfiguredTextView()
            let ed = NoteEditor()
            live.editor = ed
            view.delegate = live
            view.textLayoutManager?.delegate = live
            live.observeEdits(of: view)
            live.attachOverlay(to: view)
            view.text = "# Title\n\n```cpp\nint main() {}\n```\n"

            coordinator = live
            overlay = live.overlay
            textView = view
            editor = ed
        }

        #expect(coordinator == nil, "Coordinator still alive")
        #expect(overlay == nil, "Overlay still alive")
        #expect(textView == nil, "Text view still alive")
        #expect(editor == nil, "NoteEditor still alive")
    }

    /// The page's own wiring: `Coordinator.connect(_:to:)` hands the editor
    /// closures that act on the text view. One the editor keeps that holds
    /// the editor never lets it go (F1, 5 Nov). Run's feature as well:
    /// `EditorLeakTests+Run.swift`.
    @Test("A connected note's editor and coordinator are freed")
    func connectedNoteIsFreed() async throws {
        let refs = Self.openConnectedNote()
        try await Task.sleep(for: .milliseconds(100))

        #expect(refs.editor.value == nil, "NoteEditor still alive")
        #expect(refs.coordinator.value == nil, "Coordinator still alive")
    }

    // MARK: Opening and closing

    final class Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T?) { self.value = value }
    }

    /// A note opened through `EditorHarness`'s full wiring, which calls
    /// `connect`, then closed: its page out of the window and the window
    /// hidden. `inspect` sees the open note first.
    static func openConnectedNote(
        features: [EditorFeatureFactory] = [],
        inspect: (EditorHarness) -> Void = { _ in }
    ) -> (editor: Weak<NoteEditor>, coordinator: Weak<DocumentTextView.Coordinator>) {
        autoreleasepool {
            let harness = EditorHarness(features: features)
            // The connection happened: ⌘R's hook is there.
            #expect(harness.editor.runBlockAtCaret != nil)
            inspect(harness)
            harness.page.removeFromSuperview()
            harness.window.isHidden = true
            return (Weak(harness.editor), Weak(harness.coordinator))
        }
    }
}

#endif
