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
@Suite("Editor leaks")
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
}

#endif
