//
//  DisplayFormulaTests.swift
//  NoteCodeTests
//
//  LaTeX step 4 (docs/design/latex.md › Build steps): a `$$` block drawn as
//  one centred formula, its source lines taking no room.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Display formulas")
@MainActor
struct DisplayFormulaTests {

    static let tex = "\\sum_{i=1}^{n} \\frac{i}{2}"

    static let note = [
        "Before the block.",
        "$$",
        Self.tex,
        "",
        "$$",
        "Between.",
        "$$ \\int_0^1 x\\,dx $$",
        "After.",
        "",
    ].joined(separator: "\n")

    @Test("Runs: the first line is the formula, every other non-empty line collapses")
    func runs() {
        let source = Self.note
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let displays = runs.filter { if case .displayFormula = $0.kind { true } else { false } }
        #expect(displays.count == 2)
        let text = source as NSString
        #expect(text.substring(with: displays[0].range) == "$$")
        #expect(text.substring(with: displays[1].range) == "$$ \\int_0^1 x\\,dx $$")
        // Three source lines of the first block, one of which is blank, and
        // every run is as long as its source.
        let joiners = runs.filter { $0.kind == .joiners }
        #expect(joiners.count == 2)
        for run in runs { #expect(run.replacement.utf16.count == run.range.length) }
    }

    @Test("An unclosed or undrawable block stays as typed")
    func undrawable() {
        for source in ["$$\nx^2\nno close\n", "$$\n\\frac{1}{\n$$\n", "$$\n\n$$\n"] {
            let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
            #expect(runs.isEmpty, "\(source.debugDescription)")
        }
        let harness = CodeFenceDisplayTests.Harness("$$\n\\frac{1}{\n$$\n")
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        let colour = harness.textView.textStorage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? UIColor
        #expect(colour == .secondaryLabel)
    }

    @Test("The opening line takes the formula's height plus its gaps; source lines take one point")
    func lineHeights() throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let lines = CodeBlockRoomTests.lines(of: harness.textView)
        let size = NoteTypography.standard.prose.pointSize
        let expected = try #require(DisplayFormula.lineHeight(tex: TeXAliases.resolve(Self.tex), pointSize: size))
        let heights = lines.map { $0.frame.height }
        // Before | $$ (formula) | tex | blank | $$ | Between | $$ … $$ | After
        #expect(heights.count >= 8, "\(heights)")
        guard heights.count >= 8 else { return }
        let font = NoteTypography.standard.prose
        let m = FormulaAttachment.metrics(tex: TeXAliases.resolve(Self.tex), pointSize: size, display: true)
        #expect(abs(heights[1] - expected) < 1.0, "\(heights) expected \(expected) metrics \(String(describing: m)) descent \(CodeBlockRoom.descent(of: font)) lift \(DisplayFormula.baselineLift(tex: TeXAliases.resolve(Self.tex), font: font))")
        for index in 2...4 { #expect(heights[index] < 3.5, "line \(index): \(heights)") }
        #expect(heights[0] > 5 && abs(heights[5] - heights[0]) < 0.5)
        // The one-line block takes its own formula's height.
        let one = try #require(DisplayFormula.lineHeight(tex: TeXAliases.resolve("\\int_0^1 x\\,dx"), pointSize: size))
        #expect(abs(heights[6] - one) < 1.0, "\(heights) expected \(one)")
    }

    /// The ink of the first formula, found in a render of the text view:
    /// the white space left above and below it inside its line.
    @Test("The ink sits between the line's top and bottom, with room on both sides", arguments: ["\\sum_{i=1}^{n} \\frac{i}{2}", "\\int_0^1 x\\,dx", "\\frac{a}{b}"])
    func inkInLine(tex: String) throws {
        let harness = CodeFenceDisplayTests.Harness("Before\n$$\n\(tex)\n$$\nNext\n")
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let line = CodeBlockRoomTests.lines(of: harness.textView)[1].frame
        let view = harness.textView
        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = try #require(UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.backgroundColor = .white
            view.layer.render(in: context.cgContext)
        }.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let top = Int(line.minY * scale), bottom = Int(line.maxY * scale)
        var first = -1, last = -1
        for y in top..<bottom {
            if (0..<image.width).contains(where: { pixels[(y * image.width + $0) * 4] < 128 }) {
                if first < 0 { first = y }
                last = y
            }
        }
        #expect(first >= 0, "no ink in the line")
        let above = Double(first - top) / Double(scale), below = Double(bottom - last) / Double(scale)
        #expect(above > 3 && below > 3, "\(tex): above \(above) below \(below) in \(line)")
        #expect(abs(above - below) < 8, "\(tex): above \(above) below \(below) in \(line)")
    }

    @Test("A formula is centred in the column")
    func centred() throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let line = try #require(CodeBlockRoomTests.lines(of: harness.textView).dropFirst().first)
        let container = harness.textView.textContainer
        let columnMid = harness.textView.textContainerInset.left + container.size.width / 2
        // The attachment's own width is not in the frame, so ask the glyph:
        // the line's text starts where the (centred) attachment starts.
        let width = FormulaAttachment.metrics(tex: TeXAliases.resolve(Self.tex), pointSize: NoteTypography.standard.prose.pointSize, display: true)?.width ?? 0
        #expect(abs(line.frame.midX - columnMid) < 2 || abs(line.frame.minX + width / 2 - columnMid) < 2,
                "line \(line.frame), column mid \(columnMid), formula \(width)")
    }

    @Test("A formula wider than the column is scaled to fit")
    func wide() {
        let wide = (1...40).map { "x_{\($0)}" }.joined(separator: "+")
        let attachment = FormulaAttachment.make(tex: wide, pointSize: 17, display: true, fitting: true)
        let fitted = attachment?.attachmentBounds(
            for: [:], location: NSTextLocationStub(), textContainer: nil,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 200, height: 40), position: .zero
        )
        #expect((attachment?.bounds.width ?? 0) > 200)
        #expect(abs((fitted?.width ?? 0) - 200) < 0.01)
        #expect((fitted?.height ?? 0) < (attachment?.bounds.height ?? 0))
    }

    @Test("A block at every place around a page break paginates the same in every mode")
    func paginatesAlike() {
        let body = PageLayout().bodyHeight
        let line = NoteTypography.standard.prose.lineHeight
        let near = Int(body / line)
        var mismatches: [String] = []
        for prose in (near - 8)...(near + 1) {
            let text = (0..<prose).map { _ in "Line of prose" }.joined(separator: "\n")
                + "\n$$\n\\frac{\\sum_{i} i}{\\sqrt{n}}\n$$\nTail line\nEnd\n"
            let harness = CodeFenceDisplayTests.Harness(text)
            harness.coordinator.setRendersMarkdown(true, in: harness.textView)
            var placements: [[String]] = []
            for mode in PageViewMode.allCases {
                let layout = PageLayout(mode: mode)
                harness.page.pageLayout = layout
                harness.layOut()
                placements.append(CodeBlockRoomTests.lines(of: harness.textView).map { line in
                    let y = line.frame.minY
                    let index = layout.pageIndex(atY: y)
                    return "\(line.text.prefix(12)) p\(index) \(String(format: "%.1f", y - layout.bodyTop(ofPage: index)))"
                })
            }
            if placements[0] != placements[1] || placements[0] != placements[2] {
                mismatches.append("\(prose) lines")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }
}

private final class NSTextLocationStub: NSObject, NSTextLocation {
    func compare(_ location: any NSTextLocation) -> ComparisonResult { .orderedSame }
}

#endif
