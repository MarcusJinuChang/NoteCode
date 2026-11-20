//
//  PageWalkStopTests.swift
//  NoteCodeTests
//
//  D9 F (docs/design/paged-typing-cost.md): after an edit the paginator stops
//  its walk at the first pushed paragraph past the edit that lands where the
//  last walk put it, instead of walking to the end of the note. These check
//  that what it leaves is what a walk to the end would have left.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("The page walk stops below an edit (D9 F)", .tags(.layout), .timeLimit(.minutes(5)))
@MainActor
struct PageWalkStopTests {

    // MARK: Fixtures

    /// About a dozen pages of everything the walk meets: prose of one to
    /// four lines, headings, a list, a code block, a display formula, an
    /// inline formula, a prose paragraph taller than a page (gaps), and one
    /// with a formula in it (exclusion paths, `PagePushTable.tall`).
    static let note: String = {
        func prose(_ index: Int) -> String {
            "Line \(index): " + Array(repeating: "the loop invariant holds", count: 1 + index % 4 * 3).joined(separator: " and ")
        }
        var parts: [String] = []
        for index in 0..<40 {
            parts.append(index % 9 == 4 ? "## Heading \(index)" : prose(index))
        }
        parts.append("- item one with **bold**\n- item two with `code`\n- item three")
        parts.append("```cpp\n" + (0..<30).map { "int value\($0) = \($0) * \($0);" }.joined(separator: "\n") + "\n```")
        parts.append("$$\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$$")
        parts.append("The sum $x^2 + y^2$ is the square of the distance, and it holds for every point.")
        for index in 40..<60 { parts.append(prose(index)) }
        parts.append((0..<130).map { "word\($0) of one very long paragraph with no newline in it at all, running on" }.joined(separator: " "))
        for index in 60..<100 {
            parts.append(index % 11 == 3 ? "## Heading \(index)" : prose(index))
        }
        parts.append((0..<130).map { $0 == 65 ? "the sum $a+b$ of two" : "term\($0) of a long paragraph with a formula in it, running on" }.joined(separator: " "))
        for index in 100..<160 {
            parts.append(index % 11 == 3 ? "## Heading \(index)" : prose(index))
        }
        return parts.joined(separator: "\n")
    }()

    /// The note in an editor wired as the app wires it (styled, code blocks
    /// and formulas rendered), settled.
    static func editor(mode: PageViewMode, stopsEarly: Bool) async throws -> EditorHarness {
        let harness = EditorHarness(note, layout: PageLayout(mode: mode), rendersMarkdown: true)
        try #require(harness.textView.blankLineLayout?.pushes).stopsWalkEarly = stopsEarly
        try await settle(harness)
        return harness
    }

    static func settle(_ harness: EditorHarness) async throws {
        try await harness.settle()
        harness.layOut()
        harness.page.paginate()
        harness.layOut()
    }

    /// Replaces `range` with `text` the way the keyboard does, a paste
    /// included, with the delegate calls that restyle.
    static func edit(_ harness: EditorHarness, _ range: NSRange, _ text: String) async throws {
        let textView = harness.textView
        textView.selectedRange = range
        if text.isEmpty {
            textView.deleteBackward()
        } else {
            textView.insertText(text)
        }
        harness.coordinator.textViewDidChange(textView)
        try await settle(harness)
    }

    /// An edit, found by the text it is next to so it lands in the same
    /// place in every copy of the note.
    struct Edit: CustomStringConvertible {
        var description: String
        /// The range to replace, in the note as it is now.
        var range: (NSString) -> NSRange
        var text: String
    }

    static func after(_ anchor: String, by offset: Int = 0, length: Int = 0) -> (NSString) -> NSRange {
        { text in NSRange(location: text.range(of: anchor).location + anchor.count + offset, length: length) }
    }

    static let tallStart = "word0 of one very long"

    static let edits: [Edit] = [
        Edit(description: "a keystroke near the top", range: after("Line 2:", by: 5), text: "z"),
        Edit(description: "typing a line's worth more", range: after("Line 5:", by: 3), text: String(repeating: "more words ", count: 12)),
        Edit(description: "deleting it again", range: after("Line 5:", by: 3, length: 132), text: ""),
        Edit(description: "deleting a newline, joining two paragraphs", range: { text in
            NSRange(location: text.range(of: "\nLine 8:").location, length: 1)
        }, text: ""),
        Edit(description: "Return in the middle of a paragraph", range: after("Line 11:", by: 30), text: "\n"),
        Edit(description: "pasting several paragraphs", range: after("Line 14:", by: 4), text: "Pasted one\nPasted two, a little longer than the first\n\nPasted three\n"),
        Edit(description: "a keystroke in the list", range: after("- item two", by: 2), text: "q"),
        Edit(description: "a new line in the code block", range: after("int value12 = 12 * 12;"), text: "\nint added = 1;"),
        Edit(description: "a keystroke in the code block", range: after("int value20", by: 2), text: "x"),
        Edit(description: "a keystroke in the display formula", range: after("\\frac{n(n+1)}{2}"), text: " + 1"),
        Edit(description: "a keystroke in the inline formula", range: after("$x^2 + y^2"), text: " + z^2"),
        Edit(description: "a keystroke just above the tall paragraph", range: after("Line 59:", by: 2), text: "z"),
        Edit(description: "a keystroke inside the tall paragraph", range: after("word60 of"), text: "z"),
        Edit(description: "a line's worth inside the tall paragraph", range: after("word90 of"), text: String(repeating: " inserted", count: 14)),
        Edit(description: "deleting 400 characters inside the tall paragraph", range: after("word20 of", length: 400), text: ""),
        Edit(description: "a keystroke below the tall paragraph", range: after("Line 70:", by: 3), text: "z"),
        Edit(description: "a line's worth above the paragraph with a formula", range: after("Line 98:", by: 3), text: String(repeating: "more words ", count: 12)),
        Edit(description: "two lines more above it", range: after("Line 96:", by: 3), text: "\nOne more line\nAnd another"),
        Edit(description: "a keystroke inside the paragraph with a formula", range: after("term40 of"), text: "z"),
        Edit(description: "a line's worth inside it, above its formula", range: after("term30 of"), text: String(repeating: " inserted", count: 14)),
        Edit(description: "deleting the line's worth above it", range: after("Line 98:", by: 3, length: 132), text: ""),
        Edit(description: "pasting a page of text near the top", range: after("Line 1:", by: 2), text: (0..<40).map { "Pasted line \($0) of a page of them" }.joined(separator: "\n") + "\n"),
        Edit(description: "deleting it again", range: { text in
            let start = text.range(of: "Pasted line 0").location
            return NSRange(location: start, length: NSMaxRange(text.range(of: "Pasted line 39 of a page of them\n")) - start)
        }, text: ""),
    ]

    // MARK: Comparing

    /// What the pagination left: the table, the paths, the page count, and
    /// where every line is.
    struct Pages {
        var pushes: [Int: CGFloat]
        var gaps: [Int: PageLineGap]
        var tall: [Int: [Int]]
        var paths: [CGRect]
        var pageCount: Int
        var lines: [(start: Int, top: CGFloat)]
        var through: Int
    }

    static func pages(of harness: EditorHarness) throws -> Pages {
        let textView = harness.textView
        let table = try #require(textView.blankLineLayout?.pushes)
        let manager = try #require(textView.textLayoutManager)
        let content = try #require(manager.textContentManager)
        var lines: [(Int, CGFloat)] = []
        manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
            let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                lines.append((start + line.characterRange.location, fragment.layoutFragmentFrame.minY + line.typographicBounds.minY))
            }
            return true
        }
        return Pages(
            pushes: table.pushes, gaps: table.gaps, tall: table.tall,
            paths: textView.textContainer.exclusionPaths.map(\.bounds),
            pageCount: harness.page.pageCount, lines: lines, through: table.through
        )
    }

    /// The differences between two paginations of the same text, none when
    /// they are the same.
    static func differences(_ early: Pages, _ full: Pages) -> [String] {
        var found: [String] = []
        let tolerance = PageBreakRule.tolerance
        if early.pageCount != full.pageCount { found.append("pages \(early.pageCount) against \(full.pageCount)") }
        if early.through != full.through { found.append("through \(early.through) against \(full.through)") }
        for offset in Set(early.pushes.keys).union(full.pushes.keys).sorted()
        where abs((early.pushes[offset] ?? 0) - (full.pushes[offset] ?? 0)) > tolerance {
            found.append("push at \(offset): \(early.pushes[offset] ?? 0) against \(full.pushes[offset] ?? 0)")
        }
        for offset in Set(early.gaps.keys).union(full.gaps.keys).sorted() {
            switch (early.gaps[offset], full.gaps[offset]) {
            case let (a?, b?) where a.matches(b): break
            case let (a, b): found.append("gap at \(offset): \(String(describing: a)) against \(String(describing: b))")
            }
        }
        if early.tall != full.tall { found.append("tall \(early.tall) against \(full.tall)") }
        if early.paths != full.paths { found.append("paths \(early.paths) against \(full.paths)") }
        if early.lines.count != full.lines.count {
            found.append("\(early.lines.count) lines against \(full.lines.count)")
        } else {
            for (a, b) in zip(early.lines, full.lines) where a.start != b.start || abs(a.top - b.top) > tolerance {
                found.append("line at \(a.start) top \(a.top) against line at \(b.start) top \(b.top)")
                break
            }
        }
        return found
    }

    // MARK: Tests

    /// The same note in two editors, one stopping the walk early and one
    /// walking to the end every time, given the same edits: after each,
    /// every push, gap, path, line and the page count agree. And a walk to
    /// the end over the early one's note, from the top, finds nothing to
    /// change.
    @Test("Stopping the walk early leaves the pages a walk to the end would, after every kind of edit", arguments: PageViewMode.allCases)
    func sameAsFullWalk(mode: PageViewMode) async throws {
        let early = try await Self.editor(mode: mode, stopsEarly: true)
        let full = try await Self.editor(mode: mode, stopsEarly: false)
        let earlyTable = try #require(early.textView.blankLineLayout?.pushes)
        let fullTable = try #require(full.textView.blankLineLayout?.pushes)
        #expect(early.page.pageCount >= 8, "\(early.page.pageCount) pages")
        #expect(!earlyTable.gaps.isEmpty, "the tall paragraph has gaps")
        #expect(earlyTable.tall.values.contains { !$0.isEmpty }, "the paragraph with a formula runs through pages")
        #expect(!early.textView.textContainer.exclusionPaths.isEmpty, "and has exclusion paths")
        var paths = early.textView.textContainer.exclusionPaths.map(\.bounds)
        var pathChanges = 0
        #expect(Self.differences(try Self.pages(of: early), try Self.pages(of: full)).isEmpty, "opened")

        var totals = (early: 0, full: 0)
        for edit in Self.edits {
            #expect(early.source == full.source)
            let range = edit.range(early.source)
            try #require(range.location != NSNotFound && NSMaxRange(range) <= early.source.length, "\(edit)")
            let walkedBefore = (earlyTable.paragraphsWalked, fullTable.paragraphsWalked)
            try await Self.edit(early, range, edit.text)
            try await Self.edit(full, range, edit.text)
            let walked = (earlyTable.paragraphsWalked - walkedBefore.0, fullTable.paragraphsWalked - walkedBefore.1)
            if edit.description.contains("keystroke") {
                totals.early += walked.0
                totals.full += walked.1
            }
            print("D9 F, \(mode.rawValue), \(edit): walked \(walked.0) early, \(walked.1) to the end")

            let differences = Self.differences(try Self.pages(of: early), try Self.pages(of: full))
            #expect(differences.isEmpty, "\(mode.rawValue), after \(edit): \(differences.prefix(5))")
            #expect(walked.0 <= walked.1, "\(edit): walked \(walked.0) paragraphs early, \(walked.1) to the end")
            let now = early.textView.textContainer.exclusionPaths.map(\.bounds)
            if now != paths { pathChanges += 1 }
            paths = now

            // From the top, to the end: nothing to change.
            earlyTable.stopsWalkEarly = false
            earlyTable.through = 0
            let paginator = PagePaginator(textView: early.textView)
            #expect(!paginator.paginate(layout: early.page.pageLayout), "\(mode.rawValue), after \(edit): a walk to the end changed something")
            earlyTable.stopsWalkEarly = true
        }
        // A keystroke far above the end of the note walks a small part of
        // what the full walk does. (An edit that moves every break below it,
        // a line's worth or a paste, walks to the end either way, and so
        // does the check after a pass that moved the formula paragraph's
        // paths.)
        print("D9 F, \(mode.rawValue): the keystrokes of \(Self.edits.count) edits walked \(totals.early) paragraphs stopping early, \(totals.full) to the end")
        #expect(totals.early * 2 < totals.full, "walked \(totals.early) paragraphs early, \(totals.full) to the end")
        // Edits above the paragraph with a formula move its breaks, and the
        // paths with them.
        #expect(pathChanges >= 2, "the exclusion paths changed \(pathChanges) times")
    }

    /// The pushed paragraphs' starts, in order, that have text above them.
    static func pushedStarts(_ harness: EditorHarness) throws -> [Int] {
        try #require(harness.textView.blankLineLayout?.pushes).pushes.keys.filter { $0 > 1 }.sorted()
    }

    /// Runs `round` on both editors at up to `count` pushed paragraphs,
    /// comparing them after each; `round` returns the edits it makes at one
    /// paragraph's start, or none to skip it.
    static func compareRounds(
        mode: PageViewMode, count: Int,
        _ round: (_ early: EditorHarness, _ start: Int) throws -> [(NSRange, String)]?
    ) async throws {
        let early = try await Self.editor(mode: mode, stopsEarly: true)
        let full = try await Self.editor(mode: mode, stopsEarly: false)
        var tried = 0
        var index = 0
        while tried < count {
            let starts = try Self.pushedStarts(early)
            guard index < starts.count else { break }
            let start = starts[index]
            index += 1
            guard let edits = try round(early, start) else { continue }
            tried += 1
            for (range, text) in edits {
                try await Self.edit(early, range, text)
                try await Self.edit(full, range, text)
            }
            let differences = Self.differences(try Self.pages(of: early), try Self.pages(of: full))
            #expect(differences.isEmpty, "\(mode.rawValue), after \(edits.map { "\($0.0) → \($0.1.debugDescription)" }): \(differences.prefix(5))")
            if !differences.isEmpty { return }
        }
        #expect(tried > 0)
    }

    /// Deleting the head of a pushed paragraph: the deletion ends where the
    /// paragraph starts, so `mustWalkThrough` is that start, and the landing
    /// there was the whole paragraph's. What is left, still pushed onto the
    /// same page, landed where the whole one did, and the walk stopped on
    /// pages set for the taller paragraph.
    @Test("Deleting the first line of a pushed paragraph", arguments: PageViewMode.allCases)
    func deletingHeadOfPushedParagraph(mode: PageViewMode) async throws {
        try await Self.compareRounds(mode: mode, count: 6) { early, start in
            // The paragraph's first line, if it has more than one.
            let manager = try #require(early.textView.textLayoutManager)
            let content = try #require(manager.textContentManager)
            let location = try #require(content.location(content.documentRange.location, offsetBy: start))
            var firstLine: Int?
            manager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
                let lines = fragment.textLineFragments
                if lines.count >= 2 { firstLine = lines[0].characterRange.length }
                return false
            }
            return firstLine.map { [(NSRange(location: start, length: $0), "")] }
        }
    }

    /// Joining a pushed paragraph to the one above by replacing the newline
    /// between them, then splitting them again at the same place: the joined
    /// paragraph's walk set the pages below and passed the old landing
    /// without landing there, and the split one found that landing and
    /// stopped.
    @Test("Joining a pushed paragraph to the one above and splitting them again", arguments: PageViewMode.allCases)
    func joinAndSplitAgain(mode: PageViewMode) async throws {
        try await Self.compareRounds(mode: mode, count: 6) { early, start in
            guard early.source.character(at: start - 1) == 10 else { return nil }
            let newline = NSRange(location: start - 1, length: 1)
            return [(newline, "x"), (newline, "\n")]
        }
    }

    /// Joining a pushed paragraph to the one above with Backspace, then
    /// deleting the one above's text: the old landing moves into the joined
    /// paragraph, and then back onto a paragraph start.
    @Test("Joining a pushed paragraph to the one above, then deleting the one above", arguments: PageViewMode.allCases)
    func joinThenDeleteAbove(mode: PageViewMode) async throws {
        try await Self.compareRounds(mode: mode, count: 6) { early, start in
            let text = early.source
            guard text.character(at: start - 1) == 10 else { return nil }
            let above = text.paragraphRange(for: NSRange(location: start - 1, length: 0))
            guard above.length > 1 else { return nil }
            return [(NSRange(location: start - 1, length: 1), ""), (NSRange(location: above.location, length: above.length - 1), "")]
        }
    }

    /// The walk after a keystroke at the top of a 40-page note covers the
    /// paragraph typed in and the page or so below it, not the note.
    @Test("A keystroke at the top of a 40-page note walks a page or two, not the note")
    func keystrokeWalksLittle() throws {
        let harness = PageHarness(text: StylingPerformanceTests.document(lines: 1500))
        harness.page.paginate()
        harness.layOut()
        let textView = harness.page.textView
        let table = try #require(textView.blankLineLayout?.pushes)
        #expect(harness.page.pageCount >= 40)
        let pageCount = harness.page.pageCount
        let pushes = table.pushes

        let before = table.paragraphsWalked
        let position = try #require(textView.position(from: textView.beginningOfDocument, offset: 120))
        textView.replace(try #require(textView.textRange(from: position, to: position)), withText: "z")
        harness.layOut()
        let walked = table.paragraphsWalked - before
        // About 37 lines to a page, one paragraph each.
        #expect(walked > 0 && walked < 120, "walked \(walked) paragraphs of about 1,500")
        #expect(harness.page.pageCount == pageCount)
        #expect(table.pushes.count == pushes.count)
        #expect(table.through == Int.max)
    }

    /// The table's own bookkeeping: what must be walked moves with the text,
    /// and a landing moves with its paragraph.
    @Test("The end of what must be walked, and the landings, move with edits")
    func bookkeepingMovesWithEdits() {
        let table = PagePushTable()
        table.through = Int.max
        table.mustWalkThrough = 0
        table.set(landing: 500, at: 100)
        table.set(landing: 900, at: 200)

        // Typing 3 characters at 50.
        table.edited(NSRange(location: 50, length: 3), changeInLength: 3)
        #expect(table.mustWalkThrough == 53)
        #expect(table.landing(at: 103) == 500 && table.landing(at: 203) == 900)
        #expect(table.landing(at: 100) == nil)
        #expect(table.through == 50)

        // Deleting 10 characters at 20: the end moves back with the text.
        table.edited(NSRange(location: 20, length: 0), changeInLength: -10)
        #expect(table.mustWalkThrough == 43)
        #expect(table.landing(at: 93) == 500)

        // Deleting across a landing's paragraph start drops it.
        table.edited(NSRange(location: 90, length: 0), changeInLength: -5)
        #expect(table.landing(at: 90) == nil && table.landing(at: 93) == nil)
        #expect(table.landing(at: 188) == 900)
        #expect(table.mustWalkThrough == 90)

        // Deleting a paragraph's head: what starts there now is not what
        // landed there. Deleting a whole paragraph: the one below moves up,
        // landing and all.
        table.set(landing: 400, at: 120)
        table.set(landing: 700, at: 150)
        table.edited(NSRange(location: 120, length: 0), changeInLength: -10)
        #expect(table.landing(at: 120) == nil && table.landing(at: 140) == 700)
        table.edited(NSRange(location: 100, length: 0), changeInLength: -40)
        #expect(table.landing(at: 100) == 700)

        // An edit below it pushes it on; a new layout forgets everything.
        table.edited(NSRange(location: 300, length: 4), changeInLength: 4)
        #expect(table.mustWalkThrough == 304)
        table.restart()
        #expect(table.mustWalkThrough == 0 && table.landing(at: 188) == nil)
    }
}

#endif
