//
//  LineSpacingTests.swift
//  NoteCodeTests
//
//  Line spacing in points (feedback item 2): line height only, per note.
//

#if canImport(UIKit)

import SwiftData
import Testing
import UIKit

@testable import NoteCode

@Suite("Line spacing")
@MainActor
struct LineSpacingTests {

    static let note = """
    # Heading
    Prose line one
    - a list item
    > a quote

    Prose after a blank line
    ```cpp
    int a = 1;
    ```
    After the block
    """

    // MARK: The value

    @Test("Presets snap to the nearest, and none is nil in the model")
    func presets() {
        #expect(NoteTypography().lineSpacing == 0)
        #expect(NoteTypography(lineSpacing: 6).lineSpacing == 6)
        #expect(NoteTypography(lineSpacing: 5).lineSpacing == 4, "ties go to the smaller: 5 is as near 4 as 6")
        #expect(NoteTypography(lineSpacing: 99).lineSpacing == 12)
        #expect(NoteTypography(lineSpacing: -3).lineSpacing == 0)
        #expect(NoteTypography(lineSpacing: 0).storedLineSpacing == nil)
        #expect(NoteTypography(lineSpacing: 8).storedLineSpacing == 8)
        #expect(NoteTypography(lineSpacing: 2) != NoteTypography(), "a change of spacing is a change of typography")
        #expect(NoteTypography().isStandard && !NoteTypography(lineSpacing: 2).isStandard)
        #expect(NoteTypography(bodySize: 19).storedSize == 19 && NoteTypography(lineSpacing: 4).storedSize == nil)
    }

    @Test("The note's size and spacing come from the page, and a copy keeps them")
    func pageHoldsIt() throws {
        let page = Page(title: "T", content: "x")
        #expect(page.typography == .standard)
        page.textSize = 19
        page.lineSpacing = 6
        #expect(page.typography == NoteTypography(bodySize: 19, lineSpacing: 6))
        let container = try ModelContainer(for: NoteSchema.current, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(page)
        #expect(page.duplicated(in: context).lineSpacing == 6)
    }

    // MARK: Laid out

    /// Every line's text and height at a spacing.
    static func heights(at spacing: Int) async throws -> [String: CGFloat] {
        let harness = CodeFenceDisplayTests.Harness(note)
        harness.coordinator.setTypography(NoteTypography(lineSpacing: spacing), in: harness.textView)
        harness.layOut()
        try await harness.settle()
        var heights: [String: CGFloat] = [:]
        for line in CodeBlockRoomTests.lines(of: harness.textView) { heights[line.text] = line.frame.height }
        return heights
    }

    @Test("Each prose line is its spacing taller, and code and its fences are as they were",
          arguments: [2, 6, 12])
    func linesGrowByTheSpacing(spacing: Int) async throws {
        let base = try await Self.heights(at: 0)
        let spaced = try await Self.heights(at: spacing)
        let grows = ["Heading", "Prose line one", "a list item", "a quote", "Prose after a blank line", "After the block"]
        for text in grows {
            let line = try #require(spaced.keys.first { $0.contains(text) })
            let before = try #require(base.keys.first { $0.contains(text) })
            #expect(abs(spaced[line]! - base[before]! - CGFloat(spacing)) < 0.01,
                    "\(text): \(base[before]!) → \(spaced[line]!) at \(spacing)")
        }
        for text in ["```cpp", "int a = 1;", "```"] {
            #expect(spaced[text] == base[text], "\(text) is a code line or a fence, which keep their heights")
        }
        // The blank line is a prose line.
        let blank = try #require(spaced[""])
        #expect(abs(blank - base[""]! - CGFloat(spacing)) < 0.01, "the blank line: \(base[""]!) → \(blank)")
    }

    /// The reason spacing is line height: a line is pushed across a page
    /// break whole, so a line's page and place on it can't depend on the mode.
    /// The block is moved across the first break a few points at a time, as in
    /// `CodeBlockRoomTests.paginatesAlike`.
    @Test("At every place around a page break, every mode paginates alike with spacing on",
          arguments: [6, 12])
    func paginatesAlike(spacing: Int) async throws {
        let body = PageLayout().bodyHeight
        let line = NoteTypography.standard.codeLineHeight + CGFloat(spacing)
        var mismatches: [String] = []
        for headings in [0, 3, 7, 10] {
            let near = Int((body - CGFloat(headings) * (26 + CGFloat(spacing))) / line)
            for prose in (near - 3)...(near + 1) {
                let harness = CodeFenceDisplayTests.Harness(CodeBlockRoomTests.sweepNote(headings: headings, prose: prose))
                harness.coordinator.setTypography(NoteTypography(lineSpacing: spacing), in: harness.textView)
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
                    mismatches.append("\(headings) headings, \(prose) lines")
                }
            }
        }
        #expect(mismatches.isEmpty, "at \(spacing)pt: \(mismatches)")
    }

    @Test("A restyle at a spacing is no edit, and a line made by Return is as tall as the lines around it")
    func restyleAndReturn() async throws {
        let harness = CodeFenceDisplayTests.Harness("Intro\nPara one\nPara two\n")
        harness.coordinator.setTypography(NoteTypography(lineSpacing: 6), in: harness.textView)
        try await harness.settle()
        let before = harness.textView.textStorage.copy() as! NSAttributedString
        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)
        #expect(harness.textView.textStorage.isEqual(to: before), "restyling changed the storage")

        try await harness.caret(at: harness.offset(of: "Para one") + 8)
        ReturnAndBackspaceTests.press(harness, backspace: false)
        harness.layOut()
        try await harness.settle()
        let heights = CodeBlockRoomTests.lines(of: harness.textView).map(\.frame.height)
        let expected = NoteTypography.standard.codeLineHeight + 6
        for height in heights.dropLast() { #expect(abs(height - expected) < 0.01, "\(heights)") }
    }

    // MARK: The note

    typealias Harness = TextSizeEditorTests.Harness

    @Test("A note without ink takes a spacing at once; none is nil in the model")
    func noInkAtOnce() {
        let harness = Harness(withInk: false)
        var committed: [Int?] = []
        harness.editor.commitLineSpacing = { committed.append($0) }
        harness.editor.setLineSpacing(6)
        #expect(committed == [6] && harness.editor.lineSpacing == 6 && harness.editor.typography.lineSpacing == 6)
        harness.editor.setLineSpacing(0)
        #expect(committed.count == 2 && committed.last == .some(nil))
    }

    @Test("A note with ink asks first, once, and a locked note or ink mode refuses")
    func inkAsksOnce() {
        let harness = Harness(withInk: true)
        var committed: [Int?] = []
        harness.editor.commitLineSpacing = { committed.append($0) }
        harness.editor.setLineSpacing(6)
        #expect(committed.isEmpty && harness.editor.spacingAwaitingConfirmation == 6)
        harness.editor.cancelLineSpacing()
        #expect(harness.editor.lineSpacing == 0 && harness.editor.spacingAwaitingConfirmation == nil)

        harness.editor.setLineSpacing(6)
        harness.editor.confirmLineSpacing()
        #expect(committed == [6])
        harness.editor.setLineSpacing(8)
        #expect(committed == [6, 8], "answered once for this opening")

        harness.editor.setTextLocked(true)
        harness.editor.setLineSpacing(2)
        #expect(committed == [6, 8], "a locked note is read, not changed")
    }
}

#endif
