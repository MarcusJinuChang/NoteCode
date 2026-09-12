//
//  NoteEditorTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Note editor")
@MainActor
struct NoteEditorTests {

    /// A text view wired the way `DocumentTextView` wires it, with the page's
    /// stored text behind a binding the test can read.
    @MainActor
    private final class Harness {
        var stored: String
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        var coordinator: DocumentTextView.Coordinator!

        init(_ text: String) {
            stored = text
            coordinator = DocumentTextView.Coordinator(
                text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
            )
            coordinator.editor = editor

            textView.frame = window.bounds
            textView.delegate = coordinator
            textView.text = text
            window.addSubview(textView)
            window.makeKeyAndVisible()

            editor.attach(textView)
        }
    }

    @Test("A formatting button edits the text view and the page both")
    func formattingReachesThePage() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)

        harness.editor.toggle(.bold)

        #expect(harness.textView.text == "a **word** b")
        // If this fails, replace(_:withText:) didn't reach the delegate and
        // the edit would vanish on the next render.
        #expect(harness.stored == "a **word** b")
        #expect(harness.textView.selectedRange == NSRange(location: 4, length: 4))
    }

    @Test("A formatting edit can be undone, and undoing reaches the page")
    func formattingUndoes() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)

        harness.editor.toggle(.bold)
        #expect(harness.editor.canUndo)

        harness.editor.undo()

        #expect(harness.textView.text == "a word b")
        #expect(harness.stored == "a word b")
        #expect(harness.editor.canRedo)
    }

    @Test("Formatting does nothing in ink mode")
    func noFormattingInInk() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)

        harness.editor.setMode(.ink)
        harness.editor.toggle(.bold)

        #expect(harness.textView.text == "a word b")
    }

    @Test("Switching to ink and back restores the caret")
    func modeRoundTripKeepsCaret() {
        let harness = Harness("binary search invariant")
        harness.textView.selectedRange = NSRange(location: 7, length: 6)

        harness.editor.setMode(.ink)
        harness.editor.setMode(.text)

        #expect(harness.textView.selectedRange == NSRange(location: 7, length: 6))
        #expect(harness.textView.isEditable)
    }

    @Test("Undo stands down in ink mode until the canvas has a stack of its own")
    func undoDisabledInInk() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)
        harness.editor.toggle(.bold)

        harness.editor.setMode(.ink)

        #expect(!harness.editor.canUndo)
    }
}

#endif
