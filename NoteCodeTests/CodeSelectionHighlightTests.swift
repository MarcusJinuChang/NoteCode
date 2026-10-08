//
//  CodeSelectionHighlightTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import SwiftUI
import Testing
import UIKit
@testable import NoteCode

@Suite("Selection inside code blocks")
@MainActor
struct CodeSelectionHighlightTests {

    // MARK: Which ranges

    private let block = CodeRange(range: NSRange(location: 10, length: 30), isClosed: true)

    @Test("A caret selects nothing")
    func caret() {
        #expect(CodeSelectionHighlight.ranges(selection: NSRange(location: 15, length: 0), in: [block]).isEmpty)
    }

    @Test("A selection in prose paints nothing; UIKit's own highlight shows there")
    func prose() {
        #expect(CodeSelectionHighlight.ranges(selection: NSRange(location: 0, length: 8), in: [block]).isEmpty)
    }

    @Test("A selection inside a block is painted")
    func inside() {
        #expect(CodeSelectionHighlight.ranges(selection: NSRange(location: 15, length: 5), in: [block]) == [NSRange(location: 15, length: 5)])
    }

    @Test("A selection from prose into a block paints only the block's part")
    func straddling() {
        #expect(CodeSelectionHighlight.ranges(selection: NSRange(location: 5, length: 10), in: [block]) == [NSRange(location: 10, length: 5)])
    }

    @Test("A selection across two blocks gives each its part")
    func twoBlocks() {
        let second = CodeRange(range: NSRange(location: 50, length: 20), isClosed: true)
        let ranges = CodeSelectionHighlight.ranges(selection: NSRange(location: 30, length: 30), in: [block, second])
        #expect(ranges == [NSRange(location: 30, length: 10), NSRange(location: 50, length: 10)])
    }

    // MARK: What's drawn

    private final class Box { var value = "" }

    /// A laid-out text view with a block, in a window of the given appearance.
    private func makeEditor(style: UIUserInterfaceStyle) -> (DocumentUITextView, DocumentTextView.Coordinator, UIWindow, PageView, Box) {
        let box = Box()
        let coordinator = DocumentTextView.Coordinator(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400))
        window.overrideUserInterfaceStyle = style
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.delegate = coordinator
        textView.textLayoutManager?.delegate = coordinator
        textView.text = "Prose line\n```cpp\nint value = query(gap);\nint other = 2;\n```\nafter"
        coordinator.restyle(textView)
        let page = PageView(textView: textView)
        page.frame = CGRect(x: 0, y: 0, width: 872, height: 1200)
        window.addSubview(page)
        window.makeKeyAndVisible()
        page.layoutIfNeeded()
        textView.layoutIfNeeded()
        return (textView, coordinator, window, page, box)
    }

    /// Lets the run loop turn, so views invalidated for drawing redraw.
    private func settle(_ textView: UITextView) async throws {
        textView.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        textView.layoutIfNeeded()
    }

    /// The mean colour of the pixels in `rect`, in `textView`'s coordinates.
    private func meanColor(of textView: UITextView, in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: textView.bounds.size, format: format).image { context in
            textView.layer.render(in: context.cgContext)
        }
        let cropped = image.cgImage!.cropping(to: CGRect(
            x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale
        ))!
        var pixels = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
        let context = CGContext(
            data: &pixels, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
            bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        var sums = (r: 0.0, g: 0.0, b: 0.0)
        let count = Double(cropped.width * cropped.height)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sums.r += Double(pixels[i]); sums.g += Double(pixels[i + 1]); sums.b += Double(pixels[i + 2])
        }
        return (sums.r / count, sums.g / count, sums.b / count)
    }

    @Test("Selected text in a block tints the panel behind it", arguments: [UIUserInterfaceStyle.light, .dark])
    func panelShowsSelection(style: UIUserInterfaceStyle) async throws {
        let (textView, coordinator, window, _, _) = makeEditor(style: style)
        _ = window
        let source = textView.text as NSString
        let selected = source.range(of: "value = query")

        // The same pixels with only a caret in the block: the baseline.
        textView.selectedRange = NSRange(location: selected.location, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        try await settle(textView)
        let start = textView.position(from: textView.beginningOfDocument, offset: selected.location)!
        let end = textView.position(from: start, offset: selected.length)!
        let rect = textView.firstRect(for: textView.textRange(from: start, to: end)!)
        let before = meanColor(of: textView, in: rect)

        textView.selectedRange = selected
        coordinator.textViewDidChangeSelection(textView)
        try await settle(textView)
        let after = meanColor(of: textView, in: rect)

        // The tint is orange: red up and blue down against a grey panel, by
        // far more than text antialiasing could move the mean.
        let change = abs(after.r - before.r) + abs(after.g - before.g) + abs(after.b - before.b)
        #expect(change > 30, "panel under the selection changed by only \(change)")
    }

    @Test("Moving the caret out of a block takes the highlight off")
    func clearsWhenSelectionLeaves() {
        let (textView, coordinator, window, _, _) = makeEditor(style: .light)
        _ = window
        let source = textView.text as NSString

        textView.selectedRange = source.range(of: "value")
        coordinator.textViewDidChangeSelection(textView)
        #expect(!coordinator.paintedCodeSelection.isEmpty)

        textView.selectedRange = NSRange(location: 2, length: 0)
        coordinator.textViewDidChangeSelection(textView)
        #expect(coordinator.paintedCodeSelection.isEmpty)
    }

    @Test("Selecting prose paints nothing over a panel")
    func proseLeavesPanelsAlone() {
        let (textView, coordinator, window, _, _) = makeEditor(style: .light)
        _ = window
        textView.selectedRange = NSRange(location: 0, length: 5)
        coordinator.textViewDidChangeSelection(textView)
        #expect(coordinator.paintedCodeSelection.isEmpty)
    }
}

#endif
