//
//  NoteEditorTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Note editor")
@MainActor
struct NoteEditorTests {

    /// A text view wired the way `DocumentTextView` wires it, in its page,
    /// with the page's stored text behind a binding the test can read.
    @MainActor
    private final class Harness {
        var stored: String
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let editor = NoteEditor()
        let page: PageView
        var canvas: DrawingCanvas { page.canvas }
        var coordinator: DocumentTextView.Coordinator!

        init(_ text: String) {
            stored = text
            page = PageView(textView: textView)
            coordinator = DocumentTextView.Coordinator(
                text: Binding(get: { [unowned self] in stored }, set: { [unowned self] in stored = $0 })
            )
            coordinator.editor = editor

            textView.delegate = coordinator
            textView.text = text
            page.frame = window.bounds
            window.addSubview(page)
            window.makeKeyAndVisible()
            page.layoutIfNeeded()

            editor.attach(textView, canvas: canvas, page: page)
        }

        var pans: [UIPanGestureRecognizer] { [textView.panGestureRecognizer, page.panGestureRecognizer] }
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

    @Test("The arrows follow the mode's own undo stack")
    func undoFollowsTheMode() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)
        harness.editor.toggle(.bold)
        #expect(harness.editor.canUndo)

        harness.editor.setMode(.ink)

        // The text edit is still there to undo, but it isn't ink's to undo.
        // The canvas's stack is empty, so the arrow stands down.
        #expect(!harness.editor.canUndo)

        harness.canvas.undoManager?.registerUndo(withTarget: harness.canvas) { _ in }
        harness.editor.refreshUndoState()
        #expect(harness.editor.canUndo)

        harness.editor.setMode(.text)
        #expect(harness.editor.canUndo)
    }

    @Test("Clearing ink undo stands the arrows down")
    func clearedInkUndoUpdatesTheArrows() {
        let harness = Harness("a word b")
        harness.editor.setMode(.ink)
        harness.canvas.undoManager?.registerUndo(withTarget: harness.canvas) { _ in }
        harness.editor.refreshUndoState()
        #expect(harness.editor.canUndo)

        harness.canvas.forgetUndo()

        #expect(!harness.editor.canUndo)
    }

    @Test("The Pencil-only lock reaches the canvas")
    func pencilLockReachesTheCanvas() {
        let harness = Harness("a word b")
        #expect(harness.canvas.allowsFingerDrawing)

        harness.editor.isPencilOnly = true
        #expect(!harness.canvas.allowsFingerDrawing)

        harness.editor.isPencilOnly = false
        #expect(harness.canvas.allowsFingerDrawing)
    }

    @Test("The page's pans follow the mode and the Pencil lock")
    func scrollingFollowsTheMode() {
        let harness = Harness("a word b")
        func pencilScrolls(_ pan: UIPanGestureRecognizer) -> Bool {
            pan.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.pencil.rawValue))
        }

        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 1 && pencilScrolls($0) })

        harness.editor.setMode(.ink)
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 2 && !pencilScrolls($0) })

        harness.editor.isPencilOnly = true
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 1 && !pencilScrolls($0) })

        harness.editor.setMode(.text)
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 1 && pencilScrolls($0) })
    }

    @Test("A touch off the canvas scrolls with one finger while a finger draws")
    func oneFingerScrollsOffTheCanvas() {
        let harness = Harness("a word b")
        harness.editor.setMode(.ink)

        harness.page.touchWillLand(on: harness.textView)
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 1 })

        harness.page.touchWillLand(on: harness.canvas.controller.view)
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 2 })

        // Back in text mode, one finger scrolls everywhere.
        harness.editor.setMode(.text)
        harness.page.touchWillLand(on: harness.canvas.controller.view)
        #expect(harness.pans.allSatisfy { $0.minimumNumberOfTouches == 1 })
    }

    @Test("The hotbar's tool reaches the canvas")
    func toolReachesTheCanvas() {
        let harness = Harness("a word b")

        harness.editor.inkTool = InkToolState(kind: .highlighter, color: .red)

        #expect((harness.canvas.tool as? PKInkingTool)?.inkType == .marker)
    }
}

#endif
