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

    @Test("Locked text can be selected but not edited, and the keyboard goes away")
    func lockedTextReads() {
        let harness = Harness()
        harness.textView.becomeFirstResponder()

        EditorMode.text.apply(to: harness.textView, saved: nil, textLocked: true)

        #expect(!harness.textView.isEditable)
        #expect(harness.textView.isSelectable)
        #expect(!harness.textView.isFirstResponder)
    }

    @Test("Coming back from ink to locked text doesn't raise the keyboard, even if it was up")
    func lockedTextAfterInk() {
        let harness = Harness()
        harness.textView.becomeFirstResponder()

        let saved = EditorMode.ink.apply(to: harness.textView, saved: nil, textLocked: true)
        EditorMode.text.apply(to: harness.textView, saved: saved, textLocked: true)

        #expect(!harness.textView.isFirstResponder)
        #expect(!harness.textView.isEditable)
        #expect(harness.textView.isSelectable)
    }

    @Test("Ink mode is the same with the text locked", arguments: [false, true])
    func inkIgnoresTheLock(textLocked: Bool) {
        let harness = Harness()
        let canvas = DrawingCanvas(pageSize: CGSize(width: 816, height: 1056))
        harness.textView.addSubview(canvas)

        EditorMode.ink.apply(to: harness.textView, canvas: canvas, saved: nil, textLocked: textLocked)

        #expect(canvas.isUserInteractionEnabled)
        #expect(!harness.textView.isEditable)
        #expect(!harness.textView.isSelectable)
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
        #expect(canvas.controller.directTouchMode == .drawing)
        #expect(!canvas.controller.scrollConfiguration.isScrollEnabled)
    }
}

@Suite("Page scrolling")
@MainActor
struct PageScrollingTests {

    private static func touchTypes(_ pan: UIPanGestureRecognizer) -> Set<Int> {
        Set(pan.allowedTouchTypes.map(\.intValue))
    }

    @Test("Text mode scrolls the way a scroll view does out of the box", arguments: [true, false])
    func textModeIsStandard(fingerDraws: Bool) {
        let pan = UIScrollView().panGestureRecognizer
        let standard = EditorMode.text.scrolling(fingerDraws: fingerDraws)

        #expect(standard == .standard)
        #expect(pan.minimumNumberOfTouches == standard.minimumTouches)
        #expect(Self.touchTypes(pan) == Set(standard.touchTypes.map(\.rawValue)))
    }

    @Test("In ink mode the Pencil never scrolls", arguments: [true, false])
    func pencilNeverScrollsInInk(fingerDraws: Bool) {
        let scrolling = EditorMode.ink.scrolling(fingerDraws: fingerDraws)

        #expect(!scrolling.touchTypes.contains(.pencil))
        #expect(scrolling.touchTypes.contains(.direct))
    }

    @Test("While a finger draws, two fingers scroll; locked to the Pencil, one does")
    func fingersInInk() {
        #expect(EditorMode.ink.scrolling(fingerDraws: true).minimumTouches == 2)
        #expect(EditorMode.ink.scrolling(fingerDraws: false).minimumTouches == 1)
    }

    @Test("Off the canvas, one finger scrolls, with the same kinds of touch", arguments: [EditorMode.text, .ink], [true, false])
    func oneFingerOffTheCanvas(mode: EditorMode, fingerDraws: Bool) {
        let scrolling = mode.scrolling(fingerDraws: fingerDraws)

        #expect(scrolling.offCanvas.minimumTouches == 1)
        #expect(scrolling.offCanvas.touchTypes == scrolling.touchTypes)
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

    @Test("The pixel eraser erases at its size; the object eraser takes whole strokes")
    func eraserTools() throws {
        var settings = EraserSettings()
        settings.size = .large
        let partial = try #require(InkToolState(kind: .eraser, eraser: settings).pencilKitTool as? PKEraserTool)
        #expect(partial.eraserType == .fixedWidthBitmap)
        // PencilKit hands back its own copy, a hair off the width it was given.
        #expect(abs(partial.width - 56) < 0.01)
        #expect(EraserSettings.width(of: .large) == 56)

        settings.size = .custom
        settings.customWidth = 70
        #expect(abs(settings.pencilKitTool.width - 70) < 0.01)

        settings.mode = .wholeStroke
        #expect(settings.pencilKitTool.eraserType == .vector)
    }

    @Test("Every eraser size is one PencilKit's fixed-width eraser takes")
    func eraserWidthsInRange() {
        let pencilKit = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        #expect(abs(EraserSettings.widthRange.lowerBound - pencilKit.lowerBound) < 0.01)
        #expect(abs(EraserSettings.widthRange.upperBound - pencilKit.upperBound) < 0.01)

        let presets = EraserSettings.Size.allCases.compactMap(EraserSettings.width(of:))
        #expect(presets.count == 3)
        #expect(presets == presets.sorted())
        #expect(presets.allSatisfy { EraserSettings.widthRange.contains($0) })
    }

    @Test("Ink colours are fixed, not dynamic", arguments: InkPalette.standard.colors)
    func inkColorsAreFixed(color: InkColor) {
        // A dynamic colour would be stored as whatever appearance was current
        // mid-stroke, and PencilKit would then adapt it a second time.
        let light = color.inkColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.inkColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        #expect(light == dark)
    }

    @Test("A colour picked on a dark page is stored as the light ink that shows as it")
    func pickedOnDarkPage() {
        let picked = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        let stored = InkColor(chosen: picked, on: .dark)

        // Stored as it was picked, near-white would draw near-black on a
        // dark page once PencilKit adapted it.
        #expect(stored.red < 0.5)
        #expect(InkColor(stored.displayColor(for: .dark)).matches(InkColor(picked)))
        #expect(InkColor(chosen: picked, on: .light).matches(InkColor(picked)))
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
