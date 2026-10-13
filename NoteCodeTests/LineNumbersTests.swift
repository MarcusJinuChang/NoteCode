//
//  LineNumbersTests.swift
//  NoteCodeTests
//
//  v3 phase 4: line numbers in the page's left margin, beside each code line.
//

#if canImport(UIKit)

import PDFKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Line numbers", .serialized)
@MainActor
struct LineNumbersTests {

    private typealias Harness = CodeFenceDisplayTests.Harness

    private static let note = """
    Prose before the block
    ```cpp
    int a = 1;
    int b = 2;
    int c = a + b;
    ```
    Prose between
    ```python
    print(1)
    print(2)
    ```
    ```output
    result ok
    ```
    The end
    """

    /// Every code fragment's number as it would be drawn: `nil` for a fence
    /// line, an output line or numbers off.
    private func numbers(in harness: Harness) -> [Int?] {
        var result: [Int?] = []
        harness.textView.textLayoutManager?.enumerateTextLayoutFragments(
            from: harness.textView.textLayoutManager?.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            if let code = fragment as? CodeBlockLayoutFragment {
                result.append(code.isFence || code.isOutput ? nil : code.lineNumber())
            }
            return true
        }
        return result
    }

    // MARK: Numbering

    @Test("Each block counts its own lines from 1, and a fence has none")
    func counting() async throws {
        let harness = Harness(Self.note)
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        // cpp: fence, 3 lines, fence. python: fence, 2, fence. output: not numbered.
        #expect(numbers(in: harness) == [nil, 1, 2, 3, nil, nil, 1, 2, nil, nil, nil, nil])
    }

    @Test("Off, nothing is numbered")
    func off() async throws {
        let harness = Harness(Self.note)
        try await harness.settle()
        #expect(numbers(in: harness).allSatisfy { $0 == nil })

        harness.coordinator.setLineNumbers(true, in: harness.textView)
        harness.coordinator.setLineNumbers(false, in: harness.textView)
        #expect(numbers(in: harness).allSatisfy { $0 == nil })
    }

    @Test("A line that wraps is one line, numbered once; a blank line has a number")
    func wrapped() async throws {
        let long = String(repeating: "veryLongIdentifierForHorizontalClipping + ", count: 12)
        let harness = Harness("```cpp\nint a;\nauto x = \(long);\n\nint b;\n```\n")
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        #expect(numbers(in: harness) == [nil, 1, 2, 3, 4, nil])

        var wrappedLines = 0
        harness.textView.textLayoutManager?.enumerateTextLayoutFragments(
            from: harness.textView.textLayoutManager?.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            if let code = fragment as? CodeBlockLayoutFragment, code.lineNumber() == 2 { wrappedLines = code.textLineFragments.count }
            return true
        }
        #expect(wrappedLines > 1, "the long line did wrap")
    }

    @Test("An unclosed block is numbered to its end")
    func unclosed() async throws {
        let harness = Harness("```cpp\nint a;\nint b;")
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        #expect(numbers(in: harness) == [nil, 1, 2])
    }

    @Test("An edit above a block renumbers nothing: the count is from the block's own start")
    func editAbove() async throws {
        let harness = Harness(Self.note)
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.caret(at: 5)
        harness.textView.replace(harness.textView.textRange(from: harness.textView.position(from: harness.textView.beginningOfDocument, offset: 5)!, to: harness.textView.position(from: harness.textView.beginningOfDocument, offset: 5)!)!, withText: "\nmore\nlines\n")
        try await harness.settle()
        #expect(numbers(in: harness).compactMap { $0 } == [1, 2, 3, 1, 2])
    }

    // MARK: Nothing moves

    @Test("Every line sits where it did with numbers on", arguments: [
        PageLayout(), PageLayout(orientation: .landscape), PageLayout(orientation: .portrait, mode: .print),
        PageLayout(orientation: .portrait, mode: .compressed),
    ])
    func linesDontMove(layout: PageLayout) async throws {
        let harness = Harness(Self.note, layout: layout)
        try await harness.settle()
        let off = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        let height = harness.textView.contentSize.height

        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        let on = CodeFenceDisplayTests.lineFrames(of: harness.textView)

        #expect(off.count > 10)
        #expect(on == off, "a line moved when numbers came on")
        #expect(harness.textView.contentSize.height == height)
    }

    @Test("Lines wrap the same with numbers on, so ink stays on its words")
    func wrapsTheSame() async throws {
        let long = String(repeating: "wordsThatMakeALineWrapAroundTheContainer ", count: 10)
        let harness = Harness("```cpp\nint x = \(long);\n```\n")
        try await harness.settle()
        let before = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        #expect(CodeFenceDisplayTests.lineFrames(of: harness.textView) == before)
        #expect(before.count >= 4, "the line wrapped")
    }

    @Test("Turning numbers on makes no fragment and edits no text")
    func costsNothing() async throws {
        let harness = Harness(Self.note)
        try await harness.settle()
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: harness.textView.textStorage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        harness.coordinator.setLineNumbers(true, in: harness.textView)
        harness.coordinator.setLineNumbers(false, in: harness.textView)
        #expect(edits == 0)
    }

    // MARK: What's drawn

    /// The ink in a column of the text view, left of the page's text, beside
    /// one line: the digits are secondaryLabel on the page, and nothing else
    /// is out there.
    private func marginInk(_ harness: Harness, besides text: String) -> Int {
        let line = harness.rect(of: text)
        let margin = CGRect(x: 4, y: line.minY, width: PageLayout.margin - 4, height: line.height)
        return CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin)
    }

    @Test("Each code line has digits in the margin, in both appearances; nothing else does",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func marginPixels(style: UIUserInterfaceStyle) async throws {
        let harness = Harness(Self.note, style: style)
        try await harness.settle()
        for text in ["int a = 1;", "int c = a + b;", "print(2)", "Prose before", "Prose between", "The end"] {
            #expect(marginInk(harness, besides: text) == 0, "ink beside \(text) before")
        }

        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()
        for text in ["int a = 1;", "int b = 2;", "int c = a + b;", "print(1)", "print(2)"] {
            #expect(marginInk(harness, besides: text) > 20, "no digits beside \(text), \(style)")
        }
        for text in ["Prose before", "Prose between", "The end"] {
            #expect(marginInk(harness, besides: text) == 0, "digits beside prose: \(text)")
        }
        // The output block is a console, not code.
        #expect(marginInk(harness, besides: "result ok") == 0, "digits beside output")
    }

    @Test("A fence line has no number, away or being edited")
    func fenceLines() async throws {
        let harness = Harness(Self.note)
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.caret(at: harness.offset(of: "int b"))
        // The editing block shows its fences; the number still isn't drawn.
        #expect(marginInk(harness, besides: "```cpp") == 0)
        #expect(marginInk(harness, besides: "```\nProse between") == 0)
    }

    @Test("The digits are right-aligned against the panel, whatever their width")
    func rightAligned() async throws {
        let body = (1...12).map { "x\($0);" }.joined(separator: "\n")
        let harness = Harness("```cpp\n\(body)\n```\n")
        harness.coordinator.setLineNumbers(true, in: harness.textView)
        try await harness.settle()

        // The rightmost ink column beside "x2;" (one digit) and "x12;" (two). Both end in a 2: a 1 has more space to its right, in its own cell.
        let panelLeft = harness.rect(of: "x2;").minX
        func rightEdge(_ text: String) throws -> CGFloat {
            let line = harness.rect(of: text, backwards: false)
            // Up to just short of the panel, so the code isn't in it.
            let rect = CGRect(x: 0, y: line.minY + 2, width: panelLeft - 4, height: line.height - 4)
            let scale: CGFloat = 2
            let image = CodeFenceDisplayTests.render(harness.textView, scale: scale)
            let cropped = try #require(image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)))
            var pixels = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
            let context = CGContext(data: &pixels, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: cropped.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
            let base = (pixels[0], pixels[1], pixels[2])
            var right = -1
            for y in 0..<cropped.height {
                for x in 0..<cropped.width where (pixels[(y * cropped.width + x) * 4], pixels[(y * cropped.width + x) * 4 + 1], pixels[(y * cropped.width + x) * 4 + 2]) != base {
                    right = max(right, x)
                }
            }
            return CGFloat(right + 1) / scale + rect.minX
        }
        let one = try rightEdge("x2;")
        let two = try rightEdge("x12;")
        let expected = panelLeft - CodeBlockLayoutFragment.lineNumberGap
        #expect(abs(one - expected) <= 2, "one digit ends at \(one), expected near \(expected)")
        #expect(abs(two - expected) <= 2, "two digits end at \(two), expected near \(expected)")
    }

    @Test("The fragment's drawing area reaches the widest number it can have")
    func surfaceReach() async throws {
        let harness = Harness(Self.note)
        try await harness.settle()
        var checked = 0
        harness.textView.textLayoutManager?.enumerateTextLayoutFragments(
            from: harness.textView.textLayoutManager?.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            if let code = fragment as? CodeBlockLayoutFragment {
                // TextKit clips a fragment to this; a layer render doesn't
                // apply the clip, so the pixel tests can't see it.
                let widest = ("99999" as NSString).size(withAttributes: [.font: CodeBlockLayoutFragment.lineNumberFont]).width
                #expect(code.renderingSurfaceBounds.minX <= -(CodeBlockLayoutFragment.lineNumberGap + widest))
                #expect(code.renderingSurfaceBounds.minX >= -(PageLayout.margin + 5), "no further than the page's margin")
                checked += 1
            }
            return true
        }
        #expect(checked > 5)
    }

    // MARK: Printing

    private func pdfText(_ text: String, lineNumbers: Bool) async throws -> String {
        let data = await NotePDF.render(NotePDF.Note(
            title: "Numbers", text: text, ink: nil, orientation: .portrait, lineNumbers: lineNumbers
        ))
        let pdf = try #require(PDFDocument(data: data))
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test("Numbers print when they're on, and not when they're off")
    func printed() async throws {
        let text = "Intro\n```cpp\nint a;\nint b;\nint c;\n```\nOutro\n"
        // PDFKit reads a number and the code beside it as one line of text.
        func numbered(_ pdf: String) -> [String] {
            pdf.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.range(of: #"^\d+ int "#, options: .regularExpression) != nil }
        }
        let on = try await pdfText(text, lineNumbers: true)
        #expect(numbered(on) == ["1 int a;", "2 int b;", "3 int c;"], "numbers in the PDF: \(on.debugDescription)")
        let off = try await pdfText(text, lineNumbers: false)
        #expect(numbered(off).isEmpty, "no numbers: \(off.debugDescription)")
        #expect(off.contains("int a;") && off.contains("int c;"), "the code itself is there")
    }

    // MARK: The setting

    @Test("Settings › Code reaches the editor and the PDF's editor mirror")
    func settings() async throws {
        let harness = Harness(Self.note)
        CodeEditorSettings(indentWidth: 2, codeKeys: false, lineNumbers: true).apply(to: harness.coordinator, in: harness.textView)
        #expect(harness.coordinator.showsLineNumbers)
        #expect(harness.editor.showsLineNumbers)
        #expect(harness.coordinator.indentWidth == 2)
        #expect(!harness.coordinator.codeKeysEnabled)

        // A width the picker can't have made reads as 4.
        CodeEditorSettings(indentWidth: 3, codeKeys: true, lineNumbers: false).apply(to: harness.coordinator, in: harness.textView)
        #expect(harness.coordinator.indentWidth == 4)
        #expect(!harness.coordinator.showsLineNumbers)
        #expect(harness.coordinator.codeKeysEnabled)
        #expect(LineNumbers.enabledByDefault == false)
    }
}

#endif
