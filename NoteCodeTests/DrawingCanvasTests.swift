//
//  DrawingCanvasTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Drawing canvas")
@MainActor
struct DrawingCanvasTests {

    /// The canvas where the page puts it: inside a text view's content, in a
    /// window, so the responder chain is the real one.
    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 1056))

        init() {
            textView.frame = window.bounds
            textView.text = "binary search invariant"
            window.addSubview(textView)
            textView.addSubview(canvas)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
        }
    }

    @Test("Ink undo is the canvas's own, not the text view's")
    func inkUndoIsSeparate() {
        let harness = Harness()

        // Left to UIKit these would be the same object: `undoManager` walks
        // the responder chain, and the canvas's runs through the text view.
        #expect(harness.canvas.undoManager !== harness.textView.undoManager)
        #expect(harness.canvas.controller.view.undoManager === harness.canvas.undoManager)
    }

    @Test("The canvas doesn't scroll or zoom itself")
    func noScrollingOfItsOwn() {
        let harness = Harness()

        #expect(!harness.canvas.controller.scrollConfiguration.isScrollEnabled)
        #expect(harness.canvas.controller.zoomRange == 1...1)
    }

    @Test("The canvas is transparent")
    func transparent() {
        let harness = Harness()

        #expect(harness.canvas.backgroundColor == .clear)
        #expect(!harness.canvas.isOpaque)
        #expect(harness.canvas.controller.view.backgroundColor == .clear)
        #expect(harness.canvas.controller.contentView?.backgroundColor == .clear)
    }

    @Test("A finger draws too, until the canvas is locked to the Pencil")
    func fingerDrawing() {
        let harness = Harness()

        #expect(harness.canvas.allowsFingerDrawing)
        #expect(harness.canvas.controller.directTouchMode == .drawing)

        harness.canvas.allowsFingerDrawing = false
        #expect(harness.canvas.controller.directTouchMode == .selection)

        // Never left to PaperKit: automatic means a finger draws only while a
        // tool picker is up, and the hotbar replaced the picker.
        #expect(!harness.canvas.controller.directTouchAutomaticallyDraws)
    }

    @Test("A change on the canvas reaches the page")
    func changesReachThePage() {
        let harness = Harness()
        var told = 0
        harness.canvas.onMarkupChanged = { told += 1 }

        harness.canvas.controller.delegate?.paperMarkupViewControllerDidChangeMarkup(harness.canvas.controller)

        #expect(told == 1)
    }

    @Test("Text owns input until the toggle hands it over")
    func inputStartsOff() {
        #expect(!Harness().canvas.isUserInteractionEnabled)
    }

    @Test("The markup's bounds follow the view's")
    func markupBoundsFollowTheView() {
        let harness = Harness()
        let taller = CGRect(x: 0, y: 0, width: 816, height: 4224)

        harness.canvas.frame = taller
        harness.canvas.layoutIfNeeded()

        // PaperKit places content against the markup's bounds, not the view's.
        // Resizing the view alone shifted what was drawn (simulator, 18 Sep),
        // and the page resizes the canvas whenever the note gains a page.
        #expect(harness.canvas.markup.bounds == CGRect(origin: .zero, size: taller.size))
    }

    @Test("The tool the hotbar picks reaches the canvas")
    func toolReachesTheCanvas() {
        let harness = Harness()

        harness.canvas.tool = InkToolState(kind: .highlighter, color: .blue).pencilKitTool

        #expect((harness.canvas.tool as? PKInkingTool)?.inkType == .marker)
    }
}

#endif
