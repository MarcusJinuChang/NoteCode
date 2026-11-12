//
//  PagedGapProbeTests.swift
//  NoteCodeTests
//
//  D9 (docs/design/paged-typing-cost.md › C): a paragraph taller than a page
//  is broken by a gap above each line after a break, in the layout's copy of
//  the paragraph, not by exclusion paths. Stage 0 was a probe here, with a
//  copy of the rule; stage 1 built it, and these test the app's own gaps
//  against the path layout they replaced, laid out by hand.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Tall paragraph gaps (D9)", .tags(.layout))
@MainActor
struct PagedGapProbeTests {

    // MARK: Reading lines

    struct Line {
        let range: NSRange
        /// The line's typographic bounds, in note coordinates. On a gap line
        /// they start where the line above ended, above the break.
        let bounds: CGRect
        /// The break above its glyphs (`pageLineGap`).
        let gap: CGFloat
        /// The first glyph's baseline, in note coordinates, as the app reads
        /// it: `glyphOrigin`, which leaves the gap out, plus the gap.
        let baseline: CGFloat

        /// Where its glyphs' line starts.
        var glyphTop: CGFloat { bounds.minY + gap }
    }

    /// Every line, with the paragraph it belongs to, laid out to the end.
    static func lines(of page: PageView) -> [(paragraph: Int, line: Line)] {
        let textView = page.textView
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return [] }
        let top = textView.textContainerInset.top
        var result: [(Int, Line)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y + top)
                let gap = line.pageLineGap
                result.append((start, Line(
                    range: NSRange(location: start + line.characterRange.location, length: line.characterRange.length),
                    bounds: bounds,
                    gap: gap,
                    baseline: bounds.minY + line.glyphOrigin.y + gap
                )))
            }
            return true
        }
        return result
    }

    /// The fragment with the most lines: the tall paragraph.
    static func tallFragment(of page: PageView) -> NSTextLayoutFragment? {
        let textView = page.textView
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return nil }
        var tallest: NSTextLayoutFragment?
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            if fragment.textLineFragments.count > (tallest?.textLineFragments.count ?? 0) { tallest = fragment }
            return true
        }
        return tallest
    }

    /// The tall paragraph's range in the note.
    static func tallRange(of page: PageView) throws -> NSRange {
        let content = try #require(page.textView.textLayoutManager?.textContentManager)
        let fragment = try #require(tallFragment(of: page))
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
        return NSRange(location: start, length: end - start)
    }

    /// Pixels a point, when the tall paragraph is drawn to find its glyphs.
    static let drawScale: CGFloat = 2

    /// The tall paragraph drawn the way its view draws it, and for each pixel
    /// row, in note coordinates, whether anything was drawn on it.
    private static func inkedRows(of page: PageView) throws -> (top: CGFloat, rows: [Bool]) {
        let fragment = try #require(tallFragment(of: page))
        let surface = fragment.renderingSurfaceBounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = drawScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: surface.size, format: format).image { context in
            fragment.draw(at: CGPoint(x: -surface.minX, y: -surface.minY), in: context.cgContext)
        }
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        let rows = (0..<height).map { row in
            (0..<width).contains { pixels[(row * width + $0) * 4 + 3] > 64 }
        }
        let top = fragment.layoutFragmentFrame.minY + surface.minY + page.textView.textContainerInset.top
        return (top, rows)
    }

    /// The first row with ink in `range` (note coordinates), in points.
    private static func firstInk(in range: ClosedRange<CGFloat>, of drawing: (top: CGFloat, rows: [Bool])) -> CGFloat? {
        let from = max(Int(((range.lowerBound - drawing.top) * drawScale).rounded(.down)), 0)
        let to = min(Int(((range.upperBound - drawing.top) * drawScale).rounded(.up)), drawing.rows.count - 1)
        guard from <= to, let row = (from...to).first(where: { drawing.rows[$0] }) else { return nil }
        return drawing.top + CGFloat(row) / drawScale
    }

    /// The layout the gaps replaced, by hand: the gaps taken out of the tall
    /// paragraph and an exclusion path on the break after each page it
    /// crosses, as `PagePaginator.applyBands` set them until D9. The push
    /// table is frozen from here on (`isApplying`), so the paginator neither
    /// walks nor puts the gaps back; the harness is not used again after it.
    private static func layOutWithPaths(_ harness: PageHarness) throws -> Int {
        let page = harness.page
        let textView = page.textView
        let layout = page.pageLayout
        let table = try #require(textView.blankLineLayout?.pushes)
        let range = try tallRange(of: page)
        let gapLines = lines(of: page).map(\.line).filter { $0.gap > 0 }
        let pages = Set(gapLines.map { layout.pageIndex(atY: $0.glyphTop + 1) - 1 }).sorted()
        try #require(!pages.isEmpty)

        let content = try #require(textView.textLayoutManager?.textContentManager as? NSTextContentStorage)
        table.isApplying = true
        table.set(gaps: [:], in: range)
        textView.textContainer.exclusionPaths = pages.map {
            UIBezierPath(rect: layout.exclusionBand(afterPage: $0, containerTop: textView.textContainerInset.top))
        }
        let storage = textView.textStorage
        storage.beginEditing()
        storage.edited(.editedAttributes, range: range, changeInLength: 0)
        storage.endEditing()
        harness.layOut()
        textView.textLayoutManager?.ensureLayout(for: content.documentRange)
        return pages.count
    }

    private static func settled(_ text: String, mode: PageViewMode) -> PageHarness {
        let harness = PageHarness(text: text, layout: PageLayout(mode: mode))
        harness.page.paginate()
        harness.layOut()
        harness.page.paginate()
        return harness
    }

    // MARK: Fixtures

    /// One paragraph of 228 lines, five pages and more, between prose (as
    /// `PagePushTests`).
    static let tallParagraph: String = {
        let before = (0..<30).map { "Before \($0): the loop invariant holds before and after every iteration." }.joined(separator: "\n")
        let tall = (0..<260).map { "word\($0) of one very long paragraph with no newline in it at all, running on" }.joined(separator: " ")
        let after = (0..<40).map { "After \($0): the loop invariant holds before and after every iteration." }.joined(separator: "\n")
        return before + "\n" + tall + "\n" + after
    }()

    /// `StylingPerformanceTests.document(lines: 1500)`, about 40 pages, with
    /// one prose paragraph of about 10,000 characters after its line 60.
    static let longNoteWithTallParagraph: String = {
        var lines = StylingPerformanceTests.document(lines: 1500).components(separatedBy: "\n")
        let tall = (0..<130).map { "word\($0) of one very long paragraph with no newline in it at all, running on" }.joined(separator: " ")
        lines.insert(tall, at: 60)
        return lines.joined(separator: "\n")
    }()

    // MARK: Where the lines fall

    /// Ink is kept in page coordinates, so the gaps had to put every line
    /// where the paths did, or ink beside a tall paragraph would drift.
    @Test("The gaps put a tall paragraph's lines where exclusion paths did, with the same wrap, and use no path", arguments: PageViewMode.allCases)
    func gapMatchesPaths(mode: PageViewMode) throws {
        let harness = Self.settled(Self.tallParagraph, mode: mode)
        let textView = harness.page.textView
        let table = try #require(textView.blankLineLayout?.pushes)
        #expect(textView.textContainer.exclusionPaths.isEmpty)
        #expect(table.through == Int.max, "the note had not settled")
        let gapped = Self.lines(of: harness.page)
        let gapDrawing = try Self.inkedRows(of: harness.page)
        let gapCount = gapped.filter { $0.line.gap > 0 }.count
        #expect(gapCount >= 2)
        #expect(gapCount == table.gaps.count, "\(gapCount) lines laid out with a gap, \(table.gaps.count) in the table")
        // The table's keys are line starts in the note as it is.
        let starts = Set(gapped.map(\.line.range.location))
        #expect(table.gaps.keys.allSatisfy { starts.contains($0) })

        let pageCount = try Self.layOutWithPaths(harness)
        let paths = Self.lines(of: harness.page)
        let pathDrawing = try Self.inkedRows(of: harness.page)
        #expect(paths.allSatisfy { $0.line.gap == 0 })

        // The wrap: every line of the note holds the same characters.
        try #require(gapped.count == paths.count, "\(gapped.count) lines with gaps, \(paths.count) with paths")
        #expect(gapped.map(\.line.range) == paths.map(\.line.range))

        let layout = harness.page.pageLayout
        let tallStart = try #require(Dictionary(grouping: paths, by: \.paragraph).max { $0.value.count < $1.value.count }?.key)
        var top: CGFloat = 0, foot: CGFloat = 0, baseline: CGFloat = 0, drawn: CGFloat = 0
        var drawnLines = 0, tallLines = 0, wrongPage = 0
        for (path, gap) in zip(paths, gapped) {
            top = max(top, abs(gap.line.glyphTop - path.line.bounds.minY))
            foot = max(foot, abs(gap.line.bounds.maxY - path.line.bounds.maxY))
            baseline = max(baseline, abs(gap.line.baseline - path.line.baseline))
            if layout.pageIndex(atY: gap.line.glyphTop + 1) != layout.pageIndex(atY: path.line.bounds.minY + 1) { wrongPage += 1 }
            guard path.paragraph == tallStart else { continue }
            tallLines += 1
            // Where the glyphs are drawn: the first inked row of the line,
            // looked for from above the gap.
            let window = (path.line.bounds.minY - 2)...(path.line.bounds.maxY)
            let wide = (gap.line.bounds.minY - 2)...(gap.line.bounds.maxY)
            if let inPath = Self.firstInk(in: window, of: pathDrawing), let inGap = Self.firstInk(in: wide, of: gapDrawing) {
                drawn = max(drawn, abs(inGap - inPath))
                drawnLines += 1
            }
        }
        print(String(format: "GAPS %@: %d gaps, %d paths, %d lines: top %.3f foot %.3f baseline %.3f drawn %.2f",
                     mode.rawValue, gapCount, pageCount, paths.count, top, foot, baseline, drawn))
        #expect(top <= 0.5, "a line's glyphs start \(top)pt from where the paths put them")
        #expect(foot <= 0.5, "a line ends \(foot)pt from where the paths put it")
        #expect(baseline <= 0.5, "a baseline is \(baseline)pt from where the paths put it")
        #expect(wrongPage == 0, "\(wrongPage) lines on another page")
        #expect(drawnLines == tallLines, "\(drawnLines) of the paragraph's \(tallLines) lines found drawn")
        #expect(drawn <= 0.5, "a tall paragraph's glyphs are drawn \(drawn)pt from where the paths drew them")
    }

    // MARK: Editing

    /// Every line's glyphs inside a page's body, and every gap in the table
    /// at a line laid out with it.
    private static func checkBreaks(of harness: PageHarness, _ comment: String) throws {
        let page = harness.page
        let layout = page.pageLayout
        let table = try #require(page.textView.blankLineLayout?.pushes)
        let all = lines(of: page).map(\.line)
        let breaks = layout.exclusionBands(pageCount: page.pageCount, containerTop: layout.firstBodyTop)
            .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
        let intruding = all.filter { line in
            let glyphs = CGRect(x: line.bounds.minX, y: line.glyphTop, width: line.bounds.width, height: line.bounds.maxY - line.glyphTop)
            return breaks.contains { $0.intersects(glyphs.insetBy(dx: 0, dy: 0.5)) }
        }
        #expect(intruding.isEmpty, "\(comment): \(intruding.count) lines in a break")
        let laidOut = Dictionary(all.filter { $0.gap > 0 }.map { ($0.range.location, $0) }, uniquingKeysWith: { a, _ in a })
        for (start, gap) in table.gaps {
            let line = laidOut[start]
            #expect(line != nil, "\(comment): a gap at \(start) on no gap line")
            if let line {
                #expect(line.range.length == gap.length && abs(line.gap - gap.gap) < 0.01, "\(comment): the gap at \(start) is not its line's")
            }
        }
        #expect(laidOut.count == table.gaps.count, "\(comment): \(laidOut.count) gap lines, \(table.gaps.count) in the table")
        #expect(page.textView.textContainer.exclusionPaths.isEmpty)
    }

    @Test("Typing above, inside and below a tall paragraph keeps every gap on its line and every line out of the breaks", arguments: PageViewMode.allCases)
    func editingKeepsGaps(mode: PageViewMode) throws {
        let harness = Self.settled(Self.tallParagraph, mode: mode)
        let textView = harness.page.textView
        try Self.checkBreaks(of: harness, "settled")
        let before = try #require(textView.blankLineLayout?.pushes.gaps.keys.sorted())

        // Above: the gaps' keys move with the text, and their lines with them.
        func type(_ text: String, at offset: Int) {
            let position = textView.position(from: textView.beginningOfDocument, offset: offset)!
            textView.replace(textView.textRange(from: position, to: position)!, withText: text)
            harness.layOut()
        }
        type("zz", at: 10)
        let after = try #require(textView.blankLineLayout?.pushes.gaps.keys.sorted())
        #expect(after == before.map { $0 + 2 })
        try Self.checkBreaks(of: harness, "typed above")

        // Inside: a word typed early in the paragraph rewraps what follows.
        let range = try Self.tallRange(of: harness.page)
        for index in 0..<6 { type("word ", at: range.location + 40 + index * 5) }
        try Self.checkBreaks(of: harness, "typed inside")
        // A line deleted inside it.
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location + 100)!
        let end = textView.position(from: start, offset: 160)!
        textView.replace(textView.textRange(from: start, to: end)!, withText: "")
        harness.layOut()
        try Self.checkBreaks(of: harness, "deleted inside")

        // Below.
        type("z", at: textView.textStorage.length - 20)
        try Self.checkBreaks(of: harness, "typed below")
        #expect(textView.textStorage.string.contains("word word word"))
    }

    @Test("A paragraph that stops being taller than a page loses its gaps")
    func shortenedParagraphLosesGaps() throws {
        let harness = Self.settled(Self.tallParagraph, mode: .print)
        let textView = harness.page.textView
        #expect(try #require(textView.blankLineLayout?.pushes.gaps.isEmpty) == false)
        let range = try Self.tallRange(of: harness.page)
        let start = textView.position(from: textView.beginningOfDocument, offset: range.location + 200)!
        let end = textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(range) - 1)!
        textView.replace(textView.textRange(from: start, to: end)!, withText: "")
        harness.layOut()
        harness.page.paginate()
        #expect(textView.blankLineLayout?.pushes.gaps.isEmpty == true)
        #expect(Self.lines(of: harness.page).allSatisfy { $0.line.gap == 0 })
    }

    @Test("The gaps are only in the layout: the note's text and styles are untouched")
    func gapsAreLayoutOnly() throws {
        let harness = Self.settled(Self.tallParagraph, mode: .print)
        let storage = harness.page.textView.textStorage
        var found = false
        storage.enumerateAttribute(.pageLineGap, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        storage.enumerateAttribute(.baselineOffset, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let value = value as? CGFloat, value < 0 { found = true }
        }
        #expect(!found)
    }

    // MARK: The caret and the selection

    /// A gap line and an ordinary line of the tall paragraph, in note order.
    private static func gapLineAndOrdinary(of page: PageView) throws -> (gap: Line, ordinary: Line, before: Line) {
        let range = try tallRange(of: page)
        let tall = lines(of: page).filter { $0.paragraph == range.location }.map(\.line)
        let index = try #require(tall.indices.dropFirst().first { tall[$0].gap > 0 })
        return (tall[index], tall[index + 1], tall[index - 1])
    }

    @Test("On the first line after a break the caret is an ordinary line's, on the glyphs", arguments: PageViewMode.allCases)
    func caretOnGapLine(mode: PageViewMode) throws {
        let harness = Self.settled(Self.tallParagraph, mode: mode)
        let textView = harness.page.textView
        let (gapLine, ordinary, _) = try Self.gapLineAndOrdinary(of: harness.page)

        func caret(at offset: Int) -> CGRect {
            textView.caretRect(for: textView.position(from: textView.beginningOfDocument, offset: offset)!)
        }
        let onGap = caret(at: gapLine.range.location + 3)
        let onOrdinary = caret(at: ordinary.range.location + 3)
        print(String(format: "GAPS caret %@: gap %.1f, on gap line y %.1f h %.1f (glyphs at %.1f), ordinary h %.1f",
                     mode.rawValue, gapLine.gap, onGap.minY, onGap.height, gapLine.glyphTop, onOrdinary.height))
        #expect(abs(onGap.height - onOrdinary.height) < 0.5, "caret \(onGap.height)pt on a gap line, \(onOrdinary.height)pt on an ordinary one")
        #expect(onGap.minY >= gapLine.glyphTop - CaretHeight.above - 0.5, "the caret's top \(onGap.minY) is above its glyphs' line \(gapLine.glyphTop)")
        #expect(onGap.maxY <= gapLine.bounds.maxY + 1)
        // The same place in its line as on an ordinary one.
        #expect(abs((onGap.minY - gapLine.glyphTop) - (onOrdinary.minY - ordinary.bounds.minY)) < 0.5)
    }

    @Test("A selection across a break inside a tall paragraph is not drawn in the break", arguments: PageViewMode.allCases)
    func selectionAcrossBreak(mode: PageViewMode) throws {
        let harness = Self.settled(Self.tallParagraph, mode: mode)
        let textView = harness.page.textView
        let (gapLine, _, before) = try Self.gapLineAndOrdinary(of: harness.page)
        let band = gapLine.bounds.minY...gapLine.glyphTop

        let from = textView.position(from: textView.beginningOfDocument, offset: before.range.location + 5)!
        let to = textView.position(from: textView.beginningOfDocument, offset: gapLine.range.location + 10)!
        let rects = textView.selectionRects(for: textView.textRange(from: from, to: to)!).map(\.rect).filter { !$0.isEmpty }
        let inBreak = rects.filter { $0.minY < band.upperBound - 0.5 && $0.maxY > band.lowerBound + 0.5 }
        #expect(!rects.isEmpty)
        #expect(inBreak.isEmpty, "selection drawn in the break: \(inBreak)")
        // Both lines are still highlighted.
        #expect(rects.contains { $0.minY < before.bounds.maxY - 1 && $0.maxY > before.bounds.minY + 1 })
        #expect(rects.contains { $0.minY < gapLine.bounds.maxY - 1 && $0.maxY > gapLine.glyphTop + 1 })

        // The whole paragraph: no rect in any of its breaks.
        let range = try Self.tallRange(of: harness.page)
        let all = textView.textRange(
            from: textView.position(from: textView.beginningOfDocument, offset: range.location)!,
            to: textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(range) - 1)!
        )!
        let bands = Self.lines(of: harness.page).map(\.line).filter { $0.gap > 0 }.map { $0.bounds.minY...$0.glyphTop }
        let whole = textView.selectionRects(for: all).map(\.rect).filter { !$0.isEmpty }
        let crossing = whole.filter { rect in bands.contains { rect.minY < $0.upperBound - 0.5 && rect.maxY > $0.lowerBound + 0.5 } }
        #expect(crossing.isEmpty, "\(crossing.count) of \(whole.count) rects in a break")
        // Cut rects still say where the selection starts and ends, once each.
        let selection = textView.selectionRects(for: all)
        #expect(selection.filter(\.containsStart).count == 1)
        #expect(selection.filter(\.containsEnd).count == 1)
    }
}

#endif
