//
//  HeadingMarkerTests.swift
//  NoteCodeTests
//
//  A heading's hashes are drawn in the margin while the caret is on it, and
//  nothing about the page moves when they come and go.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Heading markers")
@MainActor
struct HeadingMarkerTests {

    static let note = "# Hash tables\nA hash table keeps each key in a bucket.\n```cpp\n# not a heading\n```\n## Second\nend"

    // MARK: Which headings show

    @Test("The caret or a selection on a heading line shows its hashes; code lines and body lines don't")
    func visibilityTable() {
        let text = Self.note as NSString
        let code = DocumentCache().codeRanges(for: Self.note)
        func at(_ selection: NSRange, mode: ShowMarkdown = .whileEditing, ink: Bool = false) -> HeadingMarkerVisibility {
            .at(selection: selection, in: text, codeRanges: code, mode: mode, isInk: ink)
        }
        let first = 0
        let second = text.range(of: "## Second").location

        #expect(at(NSRange(location: 0, length: 0)).editing == [first])
        #expect(at(NSRange(location: 5, length: 0)).editing == [first])
        #expect(at(NSRange(location: text.range(of: "A hash").location, length: 0)).editing.isEmpty)
        #expect(at(NSRange(location: text.range(of: "# not").location + 2, length: 0)).editing.isEmpty, "a line in a code block is not a heading")
        #expect(at(NSRange(location: 0, length: text.length)).editing == [first, second], "a selection across both")
        #expect(at(NSRange(location: 5, length: 0), ink: true) == .hidden, "ink mode leaves the margin bare")
        #expect(at(NSRange(location: 5, length: 0), mode: .always, ink: true) == .hidden)

        let always = at(NSRange(location: text.range(of: "A hash").location, length: 0), mode: .always)
        #expect(always.shows(headingAt: first) && always.shows(headingAt: second))
        #expect(!at(NSRange(location: 5, length: 0)).shows(headingAt: second))
    }

    @Test("What a heading line is comes from the parser: a space after the hashes, one to six of them")
    func headingLines() {
        func hashes(_ line: String) -> Int? {
            ProseLine.headingHashes(in: line as NSString, line: NSRange(location: 0, length: (line as NSString).length))
        }
        #expect(hashes("# a") == 1)
        #expect(hashes("### a\n") == 3)
        #expect(hashes("###### a") == 6)
        #expect(hashes("#include <x>") == nil)
        #expect(hashes("####### seven") == nil)
        #expect(hashes("not # one") == nil)
    }

    // MARK: Drawn

    private func harness(_ layout: PageLayout = PageLayout(), mode: ShowMarkdown = .whileEditing) -> CodeFenceDisplayTests.Harness {
        let harness = CodeFenceDisplayTests.Harness(Self.note, layout: layout, showMarkdown: mode)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        return harness
    }

    /// The part of the heading's line left of its text, where the hashes go.
    private func margin(of harness: CodeFenceDisplayTests.Harness, line text: String) -> CGRect {
        let rect = harness.rect(of: text)
        return CGRect(x: 8, y: rect.minY, width: rect.minX - 8 - 3, height: rect.height)
    }

    /// TextKit crops a fragment's drawing to its `renderingSurfaceBounds`, and
    /// the default reaches only 11pt left of the text (measured). A unit test
    /// can't see the crop, since `layer.render` doesn't apply it, so this holds
    /// the other end: the area the fragment claims reaches past the hashes of
    /// every level, in the font they are drawn in. Checked on screen too.
    @Test("A heading's drawing area reaches past its hashes, at every level")
    func surfaceReachesTheHashes() throws {
        let note = "# One\n## Two\n### Three\n#### Four\nbody"
        let harness = CodeFenceDisplayTests.Harness(note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let manager = try #require(harness.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)

        var checked = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
            guard let heading = fragment as? HeadingLayoutFragment else { return true }
            let font = DocumentStyler.headingFont(level: heading.hashes)
            let width = (String(repeating: "#", count: heading.hashes) as NSString).size(withAttributes: [.font: font]).width
            #expect(heading.renderingSurfaceBounds.minX <= -(HeadingLayoutFragment.gap + width),
                    "level \(heading.hashes): the area starts at \(heading.renderingSurfaceBounds.minX), the hashes at \(-(HeadingLayoutFragment.gap + width))")
            checked += 1
            return true
        }
        #expect(checked == 4)
    }

    @Test("The hashes show in the margin while the caret is on the heading, in seamless and on a print sheet, light and dark",
          arguments: [PageLayout(), PageLayout(mode: .print)], [UIUserInterfaceStyle.light, .dark])
    func drawnInTheMargin(layout: PageLayout, style: UIUserInterfaceStyle) async throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note, style: style, layout: layout)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let margin = margin(of: harness, line: "Hash tables")
        #expect(margin.width > 40, "the margin is wide enough to see: \(margin)")

        try await harness.caret(at: harness.offset(of: "A hash"))
        let away = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin)
        try await harness.caret(at: 4)
        let editing = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin)
        try await harness.caret(at: harness.offset(of: "A hash"))
        let awayAgain = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin)

        #expect(away == 0, "hashes drawn with the caret elsewhere: \(away) pixels")
        #expect(editing > 20, "no hashes in the margin with the caret on the heading: \(editing) pixels")
        #expect(awayAgain == 0, "hashes left behind: \(awayAgain) pixels")
    }

    @Test("Show Markdown: Always draws every heading's hashes, with the caret anywhere")
    func always() async throws {
        let harness = harness(mode: .always)
        try await harness.caret(at: harness.offset(of: "A hash"))
        let first = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin(of: harness, line: "Hash tables"))
        let second = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin(of: harness, line: "Second"))
        #expect(first > 20 && second > 20, "\(first), \(second)")
    }

    @Test("Ink mode draws no hashes, whatever the setting")
    func inkMode() async throws {
        let harness = harness(mode: .always)
        try await harness.caret(at: 4)
        harness.editor.setMode(.ink)
        try await harness.settle()
        let pixels = CodeFenceDisplayTests.inkPixels(of: harness.textView, in: margin(of: harness, line: "Hash tables"))
        #expect(pixels == 0, "\(pixels) pixels in the margin in ink mode")
    }

    @Test("A legacy note draws no hashes: they are in its text")
    func legacy() async throws {
        let harness = CodeFenceDisplayTests.Harness(Self.note)
        harness.layOut()
        try await harness.caret(at: 4)
        #expect(harness.coordinator.headingVisibility == .hidden)
    }

    // MARK: Layout never depends on the caret

    @Test("Every line sits where it did with the caret on the heading or off it, and showing the hashes lays nothing out")
    func nothingMoves() async throws {
        let harness = harness()
        try await harness.settle()
        let storageEdits = StorageEditCounter(harness.textView.textStorage)
        let counter = FragmentCounter(forwardingTo: harness.coordinator)
        harness.textView.textLayoutManager?.delegate = counter
        defer { harness.textView.textLayoutManager?.delegate = harness.coordinator }

        try await harness.caret(at: harness.offset(of: "A hash"))
        let away = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        try await harness.caret(at: 4)
        let editing = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        #expect(away == editing)
        try await harness.caret(at: harness.offset(of: "A hash"))
        #expect(CodeFenceDisplayTests.lineFrames(of: harness.textView) == away)

        #expect(counter.count == 0, "caret moves made \(counter.count) fragments")
        #expect(storageEdits.count == 0, "caret moves edited the text storage \(storageEdits.count) times")
    }
}

#endif
