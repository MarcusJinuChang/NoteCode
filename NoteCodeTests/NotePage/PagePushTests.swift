//
//  PagePushTests.swift
//  NoteCodeTests
//
//  F5: page breaks are whole paragraphs pushed to the next page, not exclusion
//  paths. Where they fall, in every mode, and the paragraph too tall to push.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Page break rule")
struct PageBreakRuleTests {

    /// Seamless: body 912, a 1pt break, so a page every 913pt from 36.
    private let layout = PageLayout(mode: .seamless)

    private func placement(top: CGFloat, height: CGFloat) -> PageBreakRule.Placement {
        PageBreakRule.placement(top: layout.firstBodyTop + top, lastLineBottom: layout.firstBodyTop + top + height, layout: layout)
    }

    @Test("A paragraph inside its page's body stays")
    func fits() {
        #expect(placement(top: 0, height: 100) == .fits)
        #expect(placement(top: 812, height: 100) == .fits)   // ends exactly at the body's foot
        #expect(placement(top: 913 + 20, height: 100) == .fits)
    }

    @Test("A paragraph that would end below the body moves to the next page's top, however much of it fitted")
    func pushes() {
        // 5 lines of 22 from 900: the first would fit, the rest not.
        #expect(placement(top: 900, height: 110) == .push(13))
        #expect(placement(top: 913 + 890, height: 30) == .push(23))
    }

    @Test("A paragraph that starts in a break starts the next page")
    func startsInBreak() {
        #expect(placement(top: 912, height: 22) == .push(1))
    }

    @Test("A paragraph taller than a body stays where it is")
    func tall() {
        #expect(placement(top: 0, height: 2000) == .tall)
        #expect(placement(top: 300, height: 913) == .tall)
        // Exactly a body tall, from the top of a page, fits.
        #expect(placement(top: 0, height: 912) == .fits)
    }

    @Test("Pushes agree across modes: the paragraph lands on the same place on the same page")
    func sameInEveryMode() {
        for mode in PageViewMode.allCases {
            let layout = PageLayout(mode: mode)
            let top = layout.bodyTop(ofPage: 2) + 880
            guard case .push(let distance) = PageBreakRule.placement(top: top, lastLineBottom: top + 60, layout: layout) else {
                Issue.record("not pushed in \(mode)")
                continue
            }
            #expect(abs(top + distance - layout.bodyTop(ofPage: 3)) < 0.001)
        }
    }

    @Test("A tall paragraph's lines are pushed one at a time, and none crosses a break")
    func linePlacement() {
        let heights = [CGFloat](repeating: 22, count: 200)   // 4,400pt
        for mode in PageViewMode.allCases {
            let layout = PageLayout(mode: mode)
            let top = layout.bodyTop(ofPage: 0) + 300
            let placed = PageBreakRule.linePlacement(top: top, lineHeights: heights, layout: layout)
            #expect(placed.gaps.count >= 4)
            // Replay it with its gaps: every line ends inside its page's
            // body, and each gap puts its line at the top of the next one.
            var y = top
            for (index, height) in heights.enumerated() {
                if let gap = placed.gaps[index] {
                    y += gap
                    #expect(abs(y - layout.bodyTop(ofPage: layout.pageIndex(atY: y + 1))) < 0.01, "line \(index) is not at a body's top")
                }
                let offset = y - layout.firstBodyTop
                let page = (offset / layout.pitch).rounded(.down)
                let into = offset - page * layout.pitch
                #expect(into + height <= layout.bodyHeight + 0.02, "line \(index) crosses a break")
                y += height
            }
            #expect(abs(y - placed.bottom) < 0.5)
        }
    }
}

@Suite("Page breaks push paragraphs", .tags(.layout))
@MainActor
struct PagePushTests {

    /// Paragraphs of 1 to 9 lines, so some of them straddle a break in any mode.
    private static let paragraphs: String = (0..<120).map { index -> String in
        let sentence = "Paragraph \(index): an invariant holds before and after every iteration of the loop, and a proof by induction shows it."
        return Array(repeating: sentence, count: 1 + (index * 7) % 9).joined(separator: " ")
    }.joined(separator: "\n")

    /// A paragraph, as the lines TextKit laid it out in, in note coordinates.
    private struct Placed {
        let start: Int
        let lines: [CGRect]
    }

    private func paragraphs(of page: PageView) -> [Placed] {
        let textView = page.textView
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return [] }
        let top = textView.textContainerInset.top
        var result: [Placed] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let origin = fragment.layoutFragmentFrame.origin
            // Each line's glyphs: a line after a break in a tall paragraph
            // holds the break above them.
            result.append(Placed(start: start, lines: fragment.textLineFragments.map {
                let bounds = $0.typographicBounds.offsetBy(dx: origin.x, dy: origin.y + top)
                let gap = $0.pageLineGap
                return CGRect(x: bounds.minX, y: bounds.minY + gap, width: bounds.width, height: bounds.height - gap)
            }))
            return true
        }
        return result
    }

    private func whole(_ text: String, mode: PageViewMode) -> PageHarness {
        let harness = PageHarness(text: text, layout: PageLayout(mode: mode))
        harness.page.paginate()
        harness.layOut()
        return harness
    }

    @Test("No paragraph is split by a break, and no line sits in one", arguments: PageViewMode.allCases)
    func paragraphsStayOnOnePage(mode: PageViewMode) {
        let harness = whole(Self.paragraphs, mode: mode)
        let layout = harness.page.pageLayout
        let placed = paragraphs(of: harness.page)

        #expect(harness.page.pageCount > 3)
        for paragraph in placed {
            let first = layout.pageIndex(atY: paragraph.lines.first!.midY)
            let last = layout.pageIndex(atY: paragraph.lines.last!.midY)
            #expect(first == last, "paragraph at \(paragraph.start) spans pages \(first)-\(last)")
        }
        let breaks = layout.exclusionBands(pageCount: harness.page.pageCount, containerTop: layout.firstBodyTop)
            .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
        let intruding = placed.flatMap(\.lines).filter { line in breaks.contains { $0.intersects(line.insetBy(dx: 0, dy: 0.5)) } }
        #expect(intruding.isEmpty)
    }

    @Test("A paragraph that would straddle a break starts the next page", arguments: PageViewMode.allCases)
    func pushedParagraphStartsThePage(mode: PageViewMode) {
        let harness = whole(Self.paragraphs, mode: mode)
        let layout = harness.page.pageLayout
        let table = harness.page.textView.blankLineLayout!.pushes

        #expect(table.pushes.count >= 3)
        let placed = Dictionary(uniqueKeysWithValues: paragraphs(of: harness.page).map { ($0.start, $0) })
        for (start, _) in table.pushes {
            guard let paragraph = placed[start] else { Issue.record("no paragraph at \(start)"); continue }
            let index = layout.pageIndex(atY: paragraph.lines[0].midY)
            #expect(abs(paragraph.lines[0].minY - layout.bodyTop(ofPage: index)) < 0.5, "paragraph at \(start) starts \(paragraph.lines[0].minY - layout.bodyTop(ofPage: index)) into page \(index)")
        }
    }

    @Test("Every mode puts every paragraph on the same page, the same distance down")
    func sameBreaksInEveryMode() {
        var placements: [[String]] = []
        for mode in PageViewMode.allCases {
            let harness = whole(Self.paragraphs, mode: mode)
            let layout = harness.page.pageLayout
            placements.append(paragraphs(of: harness.page).map { paragraph in
                let index = layout.pageIndex(atY: paragraph.lines[0].midY)
                return "\(paragraph.start) p\(index) \(String(format: "%.1f", paragraph.lines[0].minY - layout.bodyTop(ofPage: index)))"
            })
        }
        #expect(placements[0] == placements[1])
        #expect(placements[0] == placements[2])
    }

    @Test("There are no exclusion paths while no paragraph is taller than a page", arguments: PageViewMode.allCases)
    func noPaths(mode: PageViewMode) {
        let harness = whole(Self.paragraphs, mode: mode)
        #expect(harness.page.textView.textContainer.exclusionPaths.isEmpty)
    }

    // MARK: A paragraph taller than a page

    /// One paragraph of about 2.5 pages, between prose.
    private static let tallParagraph: String = {
        let before = (0..<30).map { "Before \($0): the loop invariant holds before and after every iteration." }.joined(separator: "\n")
        let tall = (0..<260).map { "word\($0) of one very long paragraph with no newline in it at all, running on" }.joined(separator: " ")
        let after = (0..<40).map { "After \($0): the loop invariant holds before and after every iteration." }.joined(separator: "\n")
        return before + "\n" + tall + "\n" + after
    }()

    @Test("A paragraph taller than a page is broken by line, and no line sits in a break", arguments: PageViewMode.allCases)
    func tallParagraphBreaksByLine(mode: PageViewMode) {
        let harness = PageHarness(text: Self.tallParagraph, layout: PageLayout(mode: mode))
        harness.page.paginate()
        harness.layOut()
        harness.page.paginate()
        let layout = harness.page.pageLayout
        let placed = paragraphs(of: harness.page)

        let tall = placed.first { $0.lines.count > 40 }
        #expect(tall != nil)
        guard let tall else { return }
        let height = tall.lines.last!.maxY - tall.lines.first!.minY
        #expect(height > layout.bodyHeight * 2, "the paragraph should be taller than two bodies, was \(height)")

        // By a gap above each line after a break (D9), not by exclusion paths.
        #expect(harness.page.textView.textContainer.exclusionPaths.isEmpty)
        #expect(harness.page.textView.blankLineLayout!.pushes.gaps.count >= 2)
        let breaks = layout.exclusionBands(pageCount: harness.page.pageCount, containerTop: layout.firstBodyTop)
            .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
        let intruding = placed.flatMap(\.lines).filter { line in breaks.contains { $0.intersects(line.insetBy(dx: 0, dy: 0.5)) } }
        #expect(intruding.isEmpty)

        // It starts where the prose above ended, not on a page of its own...
        let before = placed[placed.firstIndex { $0.start == tall.start }! - 1]
        #expect(abs(tall.lines[0].minY - before.lines.last!.maxY) < 1)
        // ...and the paragraph below it is whole on one page.
        let after = placed[placed.firstIndex { $0.start == tall.start }! + 1]
        #expect(layout.pageIndex(atY: after.lines.first!.midY) == layout.pageIndex(atY: after.lines.last!.midY))
        #expect(after.lines.first!.minY >= tall.lines.last!.maxY - 0.5)
    }

    @Test("Page count follows a tall paragraph's pushed lines", arguments: PageViewMode.allCases)
    func tallParagraphPageCount(mode: PageViewMode) {
        let harness = PageHarness(text: Self.tallParagraph, layout: PageLayout(mode: mode))
        harness.page.paginate()
        harness.layOut()
        harness.page.paginate()
        let layout = harness.page.pageLayout
        let bottom = paragraphs(of: harness.page).last!.lines.last!.maxY
        #expect(harness.page.pageCount == layout.pageCount(textBottom: bottom, inkBottom: nil))
        #expect(harness.page.pageCount >= 4)
    }

    // MARK: Editing

    @Test("A line added near the top moves the breaks below it, and every paragraph is still whole")
    func editMovesBreaks() {
        let harness = whole(Self.paragraphs, mode: .print)
        let textView = harness.page.textView
        let before = textView.blankLineLayout!.pushes.pushes.keys.sorted()

        let start = textView.beginningOfDocument
        let position = textView.position(from: start, offset: 40)!
        textView.replace(textView.textRange(from: position, to: position)!, withText: "\nA new paragraph near the top of the note, one line long.\n")
        harness.layOut()
        harness.page.paginate()

        let layout = harness.page.pageLayout
        for paragraph in paragraphs(of: harness.page) {
            #expect(layout.pageIndex(atY: paragraph.lines.first!.midY) == layout.pageIndex(atY: paragraph.lines.last!.midY))
        }
        let after = textView.blankLineLayout!.pushes.pushes.keys.sorted()
        #expect(before != after)
        // Pushes are keyed by where a paragraph starts, in the text as it is now.
        let text = textView.textStorage.string as NSString
        for offset in after {
            #expect(offset == 0 || text.character(at: offset - 1) == 10, "push at \(offset) is not at a paragraph start")
        }
    }

    @Test("Typing leaves the text of the note alone: a push is only in the layout")
    func pushIsLayoutOnly() {
        let harness = whole(Self.paragraphs, mode: .print)
        let storage = harness.page.textView.textStorage
        var pushed = false
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, style.paragraphSpacingBefore > 0 { pushed = true }
        }
        #expect(!pushed)
        storage.enumerateAttribute(.pagePush, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { pushed = true }
        }
        #expect(!pushed)
        #expect(!harness.page.textView.blankLineLayout!.pushes.pushes.isEmpty)
    }
}

#endif
