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

        /// - Parameter lockedFirst: locks the text before the editor has a
        ///   text view, the way a locked note's page opens.
        init(_ text: String, lockedFirst: Bool = false) {
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

            if lockedFirst {
                editor.setTextLocked(true)
            }
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

    @Test("Formatting can take inline code's backticks away, though the keyboard can't")
    func formattingRemovesInlineCode() {
        let harness = Harness("a `word` b")
        harness.textView.selectedRange = NSRange(location: 3, length: 4)

        harness.editor.toggle(.code)

        // The edit replaces more than the selection and drops two
        // backticks, which is what the delegate turns away from the keyboard.
        #expect(harness.textView.text == "a word b")
        #expect(harness.stored == "a word b")
    }

    @Test("Formatting does nothing in ink mode")
    func noFormattingInInk() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)

        harness.editor.setMode(.ink)
        harness.editor.toggle(.bold)

        #expect(harness.textView.text == "a word b")
    }

    @Test("Formatting does nothing while the text is locked")
    func noFormattingWhileLocked() {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)

        harness.editor.setTextLocked(true)
        harness.editor.toggle(.bold)
        harness.editor.insertCodeBlock(language: .cpp)

        #expect(harness.textView.text == "a word b")
        #expect(harness.stored == "a word b")
    }

    @Test("Locking puts the keyboard away, and unlocking doesn't bring it back")
    func lockingPutsTheKeyboardAway() {
        let harness = Harness("a word b")
        harness.textView.becomeFirstResponder()

        harness.editor.setTextLocked(true)
        #expect(!harness.textView.isFirstResponder)
        #expect(!harness.textView.isEditable)
        #expect(harness.textView.isSelectable)

        harness.editor.setTextLocked(false)
        #expect(harness.textView.isEditable)
        #expect(!harness.textView.isFirstResponder)
    }

    @Test("A note locked before its page exists opens locked")
    func lockedBeforeAttach() {
        let harness = Harness("a word b", lockedFirst: true)

        #expect(harness.editor.isTextLocked)
        #expect(!harness.textView.isEditable)
    }

    @Test("Switching modes keeps the text locked")
    func lockSurvivesModeSwitch() {
        let harness = Harness("a word b")
        harness.editor.setTextLocked(true)

        harness.editor.setMode(.ink)
        harness.editor.setMode(.text)

        #expect(!harness.textView.isEditable)
        #expect(harness.textView.isSelectable)
    }

    @Test("Locked text has nothing to undo until it's unlocked, and ink keeps its undo")
    func undoWhileLocked() throws {
        let harness = Harness("a word b")
        harness.textView.selectedRange = NSRange(location: 2, length: 4)
        harness.editor.toggle(.bold)

        harness.editor.setTextLocked(true)
        // Something on the text view's stack for certain, whatever UIKit
        // does with it as the keyboard goes: the arrows still leave it be.
        let textUndo = try #require(harness.textView.undoManager)
        textUndo.registerUndo(withTarget: harness.textView) { _ in }
        harness.editor.refreshUndoState()
        #expect(!harness.editor.canUndo)
        harness.editor.undo()
        #expect(harness.textView.text == "a **word** b")

        // The lock is on text only: ink's own stack still works.
        harness.editor.setMode(.ink)
        harness.canvas.undoManager?.registerUndo(withTarget: harness.canvas) { _ in }
        harness.editor.refreshUndoState()
        #expect(harness.editor.canUndo)

        harness.editor.setMode(.text)
        #expect(!harness.editor.canUndo)

        harness.editor.setTextLocked(false)
        #expect(harness.editor.canUndo)
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

    @Test("The eraser toggle goes to the eraser and back to the tool before it")
    func eraserToggle() {
        let harness = Harness("a word b")
        harness.editor.inkTool.kind = .highlighter

        harness.editor.toggleEraser()
        #expect(harness.editor.inkTool.kind == .eraser)
        #expect(harness.canvas.tool is PKEraserTool)

        harness.editor.toggleEraser()
        #expect(harness.editor.inkTool.kind == .highlighter)

        // Chosen from the bar, then toggled: back to the pen, not nowhere.
        let fresh = Harness("a word b")
        fresh.editor.inkTool.kind = .eraser
        fresh.editor.inkTool.kind = .eraser
        fresh.editor.toggleEraser()
        #expect(fresh.editor.inkTool.kind == .pen)
    }

    @Test("Switching to the previous tool swaps between the last two")
    func previousTool() {
        let harness = Harness("a word b")
        harness.editor.inkTool.kind = .lasso
        harness.editor.inkTool.kind = .highlighter

        harness.editor.switchToPreviousTool()
        #expect(harness.editor.inkTool.kind == .lasso)
        harness.editor.switchToPreviousTool()
        #expect(harness.editor.inkTool.kind == .highlighter)

        // A colour change isn't a tool change.
        harness.editor.inkTool.color = .red
        harness.editor.switchToPreviousTool()
        #expect(harness.editor.inkTool.kind == .lasso)
    }

    @Test("Each Pencil setting maps to what the app does")
    func pencilSettings() {
        #expect(PencilResponse(.switchEraser) == .toggleEraser)
        #expect(PencilResponse(.switchPrevious) == .switchToPreviousTool)
        #expect(PencilResponse(.showColorPalette) == .showInkTools)
        #expect(PencilResponse(.showInkAttributes) == .showInkTools)
        #expect(PencilResponse(.showContextualPalette) == .showInkTools)
        #expect(PencilResponse(.runSystemShortcut) == .nothing)
        #expect(PencilResponse(.ignore) == .nothing)
    }

    @Test("The hotbar's tool reaches the canvas")
    func toolReachesTheCanvas() {
        let harness = Harness("a word b")

        harness.editor.inkTool = InkToolState(kind: .highlighter, color: .red)

        #expect((harness.canvas.tool as? PKInkingTool)?.inkType == .marker)
    }
}

#endif
