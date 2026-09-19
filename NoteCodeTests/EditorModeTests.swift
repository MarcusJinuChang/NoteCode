//
//  EditorModeTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Editor mode")
@MainActor
struct EditorModeTests {

    /// A text view in a window, so it can take the keyboard the way it does on
    /// the page. Off-window, first-responder changes don't happen at all.
    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let textView = DocumentTextView.makeConfiguredTextView()

        init(_ text: String = "binary search invariant") {
            textView.frame = window.bounds
            textView.text = text
            window.addSubview(textView)
            window.makeKeyAndVisible()
        }
    }

    @Test("Ink mode turns off editing and selection, and puts the keyboard away")
    func inkStopsEditing() {
        let harness = Harness()
        harness.textView.becomeFirstResponder()

        EditorMode.ink.apply(to: harness.textView, saved: nil)

        #expect(!harness.textView.isEditable)
        #expect(!harness.textView.isSelectable)
        #expect(!harness.textView.isFirstResponder)
    }

    @Test("A round trip through ink, mid-edit, leaves everything where it started")
    func roundTrip() {
        let harness = Harness()
        harness.textView.becomeFirstResponder()
        harness.textView.selectedRange = NSRange(location: 7, length: 6)

        let saved = EditorMode.ink.apply(to: harness.textView, saved: nil)
        EditorMode.text.apply(to: harness.textView, saved: saved)

        #expect(harness.textView.isEditable)
        #expect(harness.textView.isSelectable)
        #expect(harness.textView.isFirstResponder)
        // Nothing restores this — UIKit keeps it. If the canvas ever makes
        // this fail, the restore belongs in EditorMode.apply.
        #expect(harness.textView.selectedRange == NSRange(location: 7, length: 6))
    }

    @Test("Coming back from ink doesn't raise a keyboard that wasn't up")
    func readingStaysReading() {
        let harness = Harness()

        let saved = EditorMode.ink.apply(to: harness.textView, saved: nil)
        EditorMode.text.apply(to: harness.textView, saved: saved)

        #expect(!harness.textView.isFirstResponder)
    }

    @Test("Applying ink twice keeps the first session, not the keyboard-down one")
    func inkTwiceKeepsFirstSession() {
        let harness = Harness()
        harness.textView.becomeFirstResponder()

        let first = EditorMode.ink.apply(to: harness.textView, saved: nil)
        let second = EditorMode.ink.apply(to: harness.textView, saved: first)
        EditorMode.text.apply(to: harness.textView, saved: second)

        #expect(harness.textView.isFirstResponder)
    }

    @Test("Returning to text spends the session")
    func textConsumesSession() {
        let harness = Harness()
        let saved = EditorMode.ink.apply(to: harness.textView, saved: nil)

        #expect(EditorMode.text.apply(to: harness.textView, saved: saved) == nil)
    }

    @Test("Ink mode hands input to the canvas, and text mode takes it back")
    func canvasTakesInput() {
        let harness = Harness()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 1056))
        harness.textView.addSubview(canvas)

        let saved = EditorMode.ink.apply(to: harness.textView, canvas: canvas, saved: nil)
        #expect(canvas.isUserInteractionEnabled)

        EditorMode.text.apply(to: harness.textView, canvas: canvas, saved: saved)
        #expect(!canvas.isUserInteractionEnabled)
    }

    @Test("A round trip leaves the canvas's own settings alone")
    func canvasSettingsSurviveARoundTrip() {
        let harness = Harness()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 1056))
        harness.textView.addSubview(canvas)

        // Who may draw belongs to the canvas, not to the mode. If a mode ever
        // starts moving these, they belong in `apply` with the rest.
        let saved = EditorMode.ink.apply(to: harness.textView, canvas: canvas, saved: nil)
        EditorMode.text.apply(to: harness.textView, canvas: canvas, saved: saved)

        #expect(!canvas.controller.directTouchAutomaticallyDraws)
        #expect(canvas.controller.directTouchMode == .selection)
        #expect(!canvas.controller.scrollConfiguration.isScrollEnabled)
    }
}

@Suite("Ink tools")
@MainActor
struct InkToolTests {

    @Test("Pen and highlighter are inking tools of the right type")
    func inkingTools() {
        let pen = InkToolState(kind: .pen, color: .blue).pencilKitTool as? PKInkingTool
        let highlighter = InkToolState(kind: .highlighter, color: .blue).pencilKitTool as? PKInkingTool

        #expect(pen?.inkType == .pen)
        #expect(highlighter?.inkType == .marker)
    }

    @Test("Eraser and lasso are their own tools")
    func otherTools() {
        #expect(InkToolState(kind: .eraser).pencilKitTool is PKEraserTool)
        #expect(InkToolState(kind: .lasso).pencilKitTool is PKLassoTool)
    }

    @Test("Ink colours are fixed, not dynamic", arguments: InkColor.allCases)
    func inkColorsAreFixed(color: InkColor) {
        // A dynamic colour would be stored as whatever appearance was current
        // mid-stroke, and PencilKit would then adapt it a second time.
        let light = color.inkColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.inkColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        #expect(light == dark)
    }

    @Test("Only drawing tools use a colour")
    func colourUse() {
        #expect(InkToolKind.pen.usesColor)
        #expect(InkToolKind.highlighter.usesColor)
        #expect(!InkToolKind.eraser.usesColor)
        #expect(!InkToolKind.lasso.usesColor)
    }
}

#endif
