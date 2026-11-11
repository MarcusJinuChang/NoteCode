//
//  PagedGapProbeTests.swift
//  NoteCodeTests
//
//  D9, stage 0 (docs/design/paged-typing-cost.md › "Staged plan"): can a
//  paragraph taller than a page be broken by a per-line gap in the layout
//  copy, in place of exclusion paths, without moving a line? A probe in the
//  real view. Nothing in the app is changed: the gap is laid in by a content
//  storage delegate of the test's own that wraps the view's `BlankLineLayout`.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Paged gap probe (D9 stage 0)")
@MainActor
struct PagedGapProbeTests {

    // MARK: The gap

    /// The view's `BlankLineLayout`, with a gap added to the copy it lays out:
    /// a negative `.baselineOffset` of the break's height on the characters of
    /// the first line after each break (option C). The note's text is not
    /// touched, as with pushes. Gap lines are kept by the offset of their
    /// first character, and shifted with edits, as `PagePushTable` shifts
    /// pushes.
    @MainActor
    final class GapLayout: NSObject, @MainActor NSTextContentStorageDelegate {
        let inner: BlankLineLayout
        /// Line start (UTF-16) to the line's length and its gap.
        private(set) var gaps: [Int: (length: Int, gap: CGFloat)] = [:]

        init(inner: BlankLineLayout, gaps: [Int: (length: Int, gap: CGFloat)], storage: NSTextStorage) {
            self.inner = inner
            self.gaps = gaps
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(storageDidProcessEditing),
                name: NSTextStorage.didProcessEditingNotification, object: storage
            )
        }

        @objc private func storageDidProcessEditing(_ notification: Notification) {
            guard let storage = notification.object as? NSTextStorage else { return }
            let delta = storage.changeInLength
            guard delta != 0 else { return }
            let at = storage.editedRange.location
            var moved: [Int: (length: Int, gap: CGFloat)] = [:]
            for (start, value) in gaps {
                moved[start > at ? start + delta : start] = value
            }
            gaps = moved
        }

        func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
            let laidOut = inner.textContentStorage(textContentStorage, textParagraphWith: range)
            let inside = gaps.filter { NSLocationInRange($0.key, range) }
            guard !inside.isEmpty, let storage = textContentStorage.textStorage else { return laidOut }

            let copy = NSMutableAttributedString(attributedString: laidOut?.attributedString ?? storage.attributedSubstring(from: range))
            for (start, line) in inside {
                let local = NSRange(location: start - range.location, length: min(line.length, range.location + range.length - start))
                // Added to what is there, never in place of it.
                var runs: [(NSRange, CGFloat)] = []
                copy.enumerateAttribute(.baselineOffset, in: local) { value, run, _ in
                    runs.append((run, CGFloat((value as? NSNumber)?.doubleValue ?? 0)))
                }
                for (run, existing) in runs {
                    copy.addAttribute(.baselineOffset, value: Double(existing - line.gap), range: run)
                }
            }
            return NSTextParagraph(attributedString: copy)
        }
    }

    // MARK: Reading lines

    struct Line {
        let range: NSRange
        /// The line's typographic bounds, in note coordinates.
        let bounds: CGRect
        /// The first glyph's baseline, in note coordinates.
        let baseline: CGFloat
    }

    /// Every line, with the paragraph it belongs to, laid out to the end.
    private static func lines(of page: PageView) -> [(paragraph: Int, line: Line)] {
        let textView = page.textView
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return [] }
        let top = textView.textContainerInset.top
        var result: [(Int, Line)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y + top)
                result.append((start, Line(
                    range: NSRange(location: start + line.characterRange.location, length: line.characterRange.length),
                    bounds: bounds,
                    baseline: bounds.minY + line.glyphOrigin.y
                )))
            }
            return true
        }
        return result
    }

    /// The fragment with the most lines: the tall paragraph.
    private static func tallFragment(of page: PageView) -> NSTextLayoutFragment? {
        let textView = page.textView
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return nil }
        var tallest: NSTextLayoutFragment?
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            if fragment.textLineFragments.count > (tallest?.textLineFragments.count ?? 0) { tallest = fragment }
            return true
        }
        return tallest
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

    /// The gap before each line of a tall paragraph, by the rule the
    /// paginator places its lines with (`PageBreakRule.linePlacement`), from
    /// the paragraph's top and its lines' natural heights.
    static func gaps(top: CGFloat, lineHeights: [CGFloat], layout: PageLayout) -> [Int: CGFloat] {
        var y = top
        var gaps: [Int: CGFloat] = [:]
        for (index, height) in lineHeights.enumerated() {
            let offset = y - layout.firstBodyTop
            let page = (offset / layout.pitch).rounded(.down)
            let into = offset - page * layout.pitch
            if into >= layout.bodyHeight - PageBreakRule.tolerance
                || (into + height > layout.bodyHeight + PageBreakRule.tolerance && height <= layout.bodyHeight) {
                gaps[index] = layout.pitch - into
                y += layout.pitch - into
            }
            y += height
        }
        return gaps
    }

    /// Settles the harness, then swaps the tall paragraph's exclusion paths
    /// for gaps in the layout copy and lays it out again.
    ///
    /// The push table is frozen from here on (`isApplying`), so the paginator
    /// neither walks nor puts the paths back. Stage 1 teaches the walk the
    /// gaps; this probe only asks whether TextKit lays the lines out where the
    /// paths did, and what a keystroke costs without them.
    private static func replacePathsWithGaps(in harness: PageHarness) throws -> (layout: GapLayout, count: Int) {
        let page = harness.page
        let textView = page.textView
        page.paginate()
        let table = try #require(textView.blankLineLayout?.pushes)
        try #require(table.through == Int.max, "the note had not settled")
        try #require(!textView.textContainer.exclusionPaths.isEmpty, "the tall paragraph has no paths")

        let content = try #require(textView.textLayoutManager?.textContentManager as? NSTextContentStorage)
        let fragment = try #require(tallFragment(of: page))
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let end = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.endLocation)
        let lines = fragment.textLineFragments
        let top = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top
        let byIndex = gaps(top: top, lineHeights: lines.map(\.typographicBounds.height), layout: page.pageLayout)

        var gaps: [Int: (length: Int, gap: CGFloat)] = [:]
        for (index, gap) in byIndex {
            gaps[start + lines[index].characterRange.location] = (lines[index].characterRange.length, gap)
        }
        let storage = textView.textStorage
        let gapLayout = GapLayout(inner: try #require(textView.blankLineLayout), gaps: gaps, storage: storage)

        table.isApplying = true
        content.delegate = gapLayout
        textView.textContainer.exclusionPaths = []
        storage.beginEditing()
        storage.edited(.editedAttributes, range: NSRange(location: start, length: end - start), changeInLength: 0)
        storage.endEditing()
        harness.layOut()
        textView.textLayoutManager?.ensureLayout(for: content.documentRange)
        return (gapLayout, byIndex.count)
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

    // MARK: 1 and 2: where the lines fall, and the wrap

    @Test("A per-line gap puts a tall paragraph's lines where the exclusion paths did, with the same wrap", .tags(.layout), arguments: PageViewMode.allCases)
    func gapMatchesPaths(mode: PageViewMode) throws {
        let harness = PageHarness(text: Self.tallParagraph, layout: PageLayout(mode: mode))
        harness.page.paginate()
        harness.layOut()
        harness.page.paginate()
        let paths = Self.lines(of: harness.page)
        let pathCount = harness.page.textView.textContainer.exclusionPaths.count
        let pathDrawing = try Self.inkedRows(of: harness.page)

        let (gapLayout, gapCount) = try Self.replacePathsWithGaps(in: harness)
        defer { withExtendedLifetime(gapLayout) {} }
        #expect(harness.page.textView.textContainer.exclusionPaths.isEmpty)
        let gapped = Self.lines(of: harness.page)
        let gapDrawing = try Self.inkedRows(of: harness.page)

        // 2. The wrap: every line of the note holds the same characters.
        try #require(gapped.count == paths.count, "\(gapped.count) lines with gaps, \(paths.count) with paths")
        #expect(gapped.map(\.line.range) == paths.map(\.line.range))

        // 1. Where the lines fall. A gap line's bounds include the gap above
        // its glyphs, so it is compared by its foot and its baseline, and its
        // glyphs' top is the foot less the line's natural height.
        let tallStart = try #require(Dictionary(grouping: paths, by: \.paragraph).max { $0.value.count < $1.value.count }?.key)
        var tallFoot: CGFloat = 0, tallBaseline: CGFloat = 0, tallTop: CGFloat = 0, noteFoot: CGFloat = 0
        var gapHeights: [CGFloat] = []
        var drawnShift: CGFloat = 0, drawnLines = 0
        for (path, gap) in zip(paths, gapped) {
            if path.paragraph == tallStart {
                // Where the glyphs are drawn: the first inked row of the line,
                // looked for from above the gap.
                let window = (path.line.bounds.minY - 2)...(path.line.bounds.maxY)
                let wide = (gap.line.bounds.minY - 2)...(gap.line.bounds.maxY)
                if let inPath = Self.firstInk(in: window, of: pathDrawing), let inGap = Self.firstInk(in: wide, of: gapDrawing) {
                    drawnShift = max(drawnShift, abs(inGap - inPath))
                    drawnLines += 1
                }
            }
            let foot = abs(gap.line.bounds.maxY - path.line.bounds.maxY)
            let baseline = abs(gap.line.baseline - path.line.baseline)
            let top = abs((gap.line.bounds.maxY - path.line.bounds.height) - path.line.bounds.minY)
            noteFoot = max(noteFoot, foot)
            if path.paragraph == tallStart {
                tallFoot = max(tallFoot, foot)
                tallBaseline = max(tallBaseline, baseline)
                tallTop = max(tallTop, top)
                let grown = gap.line.bounds.height - path.line.bounds.height
                if grown > 0.5 { gapHeights.append(grown) }
            }
        }
        print(String(format: "PROBE gapMatchesPaths %@ paths %d gaps %d lines %d: tall paragraph foot %.3f glyph top %.3f drawn %.2f (%d lines), glyphOrigin baseline %.3f, whole note foot %.3f; gap lines grew %@",
                     mode.rawValue, pathCount, gapCount, paths.count, tallFoot, tallTop, drawnShift, drawnLines, tallBaseline, noteFoot,
                     gapHeights.map { String(format: "%.1f", $0) }.joined(separator: " ")))
        #expect(gapCount >= 2)
        #expect(tallFoot <= 0.5, "a tall paragraph's line moved \(tallFoot)pt at its foot")
        #expect(tallTop <= 0.5, "a tall paragraph's glyphs moved \(tallTop)pt at their top")
        // Drawn, which is what the reader and the ink see.
        #expect(drawnLines > 100)
        #expect(drawnShift <= 0.5, "a tall paragraph's glyphs are drawn \(drawnShift)pt from where the paths put them")
        // `glyphOrigin` leaves `.baselineOffset` out: on a gap line it reads
        // the gap high, while the glyphs are drawn where the paths drew them
        // (above). Recorded, not checked; anything placed from it needs the
        // gap taken off (stage 1, risk "The PDF").
        #expect(noteFoot <= 0.5, "a line of the note moved \(noteFoot)pt")
    }

    // MARK: 3: what a keystroke costs

    /// The median of nine one-character edits near the top, as
    /// `PageViewTests.Cost` takes it.
    private static func keystrokeMedian(in textView: UITextView) -> TimeInterval {
        var times: [TimeInterval] = []
        for index in 0..<9 {
            let position = textView.position(from: textView.beginningOfDocument, offset: 120 + index)!
            let start = Date()
            textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
            textView.layoutIfNeeded()
            times.append(Date().timeIntervalSince(start))
        }
        return times.sorted()[4]
    }

    /// The gap's cost, in the same run as the notes it is set against. The
    /// gap variant runs with the push table frozen (no paginator walk), so it
    /// is set against the note without a tall paragraph frozen the same way;
    /// the walk is the same for both, and stage 1 keeps it. Loose on purpose:
    /// the numbers are recorded in the design note.
    @Test("A keystroke in a 40-page note with a tall paragraph costs, with gaps, what one without a tall paragraph does", .tags(.perf))
    func gapCost() throws {
        let plain = PageHarness(text: StylingPerformanceTests.document(lines: 1500))
        #expect(plain.page.pageCount >= 40)
        #expect(plain.page.textView.textContainer.exclusionPaths.isEmpty)
        let noTall = Self.keystrokeMedian(in: plain.page.textView)
        plain.layOut()
        plain.page.paginate()
        let plainTable = try #require(plain.page.textView.blankLineLayout?.pushes)
        plainTable.isApplying = true
        let noTallFrozen = Self.keystrokeMedian(in: plain.page.textView)
        plainTable.isApplying = false
        plain.page.removeFromSuperview()

        let tall = PageHarness(text: Self.longNoteWithTallParagraph)
        tall.page.paginate()
        tall.layOut()
        #expect(!tall.page.textView.textContainer.exclusionPaths.isEmpty)
        let withPaths = Self.keystrokeMedian(in: tall.page.textView)
        tall.layOut()
        tall.page.paginate()
        let tallTable = try #require(tall.page.textView.blankLineLayout?.pushes)
        tallTable.isApplying = true
        let withPathsFrozen = Self.keystrokeMedian(in: tall.page.textView)
        tallTable.isApplying = false
        tall.layOut()

        let (gapLayout, gapCount) = try Self.replacePathsWithGaps(in: tall)
        defer { withExtendedLifetime(gapLayout) {} }
        #expect(tall.page.textView.textContainer.exclusionPaths.isEmpty)
        let withGaps = Self.keystrokeMedian(in: tall.page.textView)

        let ms = { (seconds: TimeInterval) in String(format: "%.1f", seconds * 1000) }
        print("PROBE gapCost ms: no tall \(ms(noTall)), no tall frozen \(ms(noTallFrozen)), paths \(ms(withPaths)), paths frozen \(ms(withPathsFrozen)), gaps frozen \(ms(withGaps)) (\(gapCount) gaps)")
        #expect(gapCount >= 2)
        #expect(withGaps < withPathsFrozen / 3, "gaps \(withGaps)s, paths \(withPathsFrozen)s")
        #expect(withGaps < noTallFrozen * 2 + 0.002, "gaps \(withGaps)s, no tall paragraph \(noTallFrozen)s")
    }
}

#endif
