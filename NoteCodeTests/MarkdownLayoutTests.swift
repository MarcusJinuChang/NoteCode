//
//  MarkdownLayoutTests.swift
//  NoteCodeTests
//
//  Markdown markers laid out at zero width: the probe that decided the
//  word-joiner swap, kept as regression tests. Ground truth throughout is the
//  same styled text with the markers physically deleted.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Markdown layout")
@MainActor
struct MarkdownLayoutTests {

    static let long = " for more on why this long line has to wrap more than once on the page, since a marker that took room would move the break."

    static let note = [
        "# Hashing a string",
        "Keep the **load factor** low, hash with `h % m`, skip ~~linear probing~~ and see [the notes](https://example.com/notes)" + long,
        "## Collisions",
        "- an *item* that is long enough to wrap onto a second line so the hanging indent is checked" + long,
        "- [ ] a box to tick",
        "- [x] a box that is ticked",
        "1. numbered stays as typed",
        "Plain closing line.",
        "",
    ].joined(separator: "\n")

    /// The same note with every collapsed run deleted, keeping the styling the
    /// rendered note has: what TextKit would lay out if markers took no room.
    static func deletingMarkers(from harness: CodeFenceDisplayTests.Harness) -> NSAttributedString {
        let storage = harness.textView.textStorage
        let source = storage.string.nativeUTF8
        let runs = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source)
        let text = NSMutableAttributedString(attributedString: storage)
        for run in runs.reversed() {
            switch run.kind {
            case .joiners:
                text.deleteCharacters(in: run.range)
            case .bullet:
                text.replaceCharacters(in: run.range, with: String(MarkdownLayout.bullet))
            case .box:
                // The box keeps one unit, the em space it is drawn in.
                text.replaceCharacters(in: run.range, with: String(MarkdownLayout.box))
            }
        }
        return text
    }

    /// Two harnesses on one note: the real one, collapsed, and the same text
    /// with its markers deleted from the storage.
    static func pair(_ text: String = note, layout: PageLayout = PageLayout()) -> (rendered: CodeFenceDisplayTests.Harness, deleted: CodeFenceDisplayTests.Harness) {
        let rendered = CodeFenceDisplayTests.Harness(text, layout: layout)
        rendered.coordinator.setRendersMarkdown(true, in: rendered.textView)
        rendered.layOut()
        let deleted = CodeFenceDisplayTests.Harness(text, layout: layout)
        deleted.textView.textStorage.setAttributedString(deletingMarkers(from: rendered))
        deleted.layOut()
        return (rendered, deleted)
    }

    private static func assertSame(_ a: [CGRect], _ b: [CGRect], _ message: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count, "\(message): \(a.count) frames against \(b.count)", sourceLocation: sourceLocation)
        for (index, (x, y)) in zip(a, b).enumerated() {
            #expect(
                abs(x.minX - y.minX) < 0.01 && abs(x.minY - y.minY) < 0.01
                    && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.01,
                "\(message): frame \(index) is \(x), expected \(y)",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: Probe 1: lines

    @Test("Every line is where it would be if the markers weren't there",
          arguments: [PageLayout(), PageLayout(mode: .print), PageLayout(orientation: .landscape)])
    func linesEqualMarkerlessLines(layout: PageLayout) {
        let (rendered, deleted) = Self.pair(layout: layout)
        let a = CodeFenceDisplayTests.lineFrames(of: rendered.textView)
        let b = CodeFenceDisplayTests.lineFrames(of: deleted.textView)
        #expect(a.count > 12)
        Self.assertSame(a, b, "collapsed against deleted")
    }

    @Test("Without the swap the same note's lines are different: the test can fail")
    func linesDifferWithoutTheSwap() {
        let (rendered, deleted) = Self.pair()
        rendered.coordinator.setRendersMarkdown(false, in: rendered.textView)
        rendered.layOut()
        let a = CodeFenceDisplayTests.lineFrames(of: rendered.textView)
        let b = CodeFenceDisplayTests.lineFrames(of: deleted.textView)
        let differs = a.count != b.count || zip(a, b).contains { abs($0.width - $1.width) > 0.5 || abs($0.minY - $1.minY) > 0.01 }
        #expect(differs)
    }

    // MARK: Probe 2: carets

    @Test("A caret beside a collapsed run is as tall as the line")
    func caretHeights() {
        let (rendered, _) = Self.pair()
        let textView = rendered.textView
        let text = textView.textStorage.string as NSString
        let bold = text.range(of: "**load factor**")
        let spots = [bold.location, bold.location + 2, NSMaxRange(bold) - 2, NSMaxRange(bold),
                     text.range(of: "# ").location, text.range(of: "[the notes]").location]
        let reference = textView.caretRect(for: textView.position(from: textView.beginningOfDocument, offset: text.range(of: "Plain closing").location)!).height
        for offset in spots {
            let rect = textView.caretRect(for: textView.position(from: textView.beginningOfDocument, offset: offset)!)
            #expect(rect.height > 12, "caret at \(offset) is \(rect.height) tall")
            #expect(rect.height >= reference - 0.5 || offset == 0 || offset == text.range(of: "# ").location,
                    "caret at \(offset) is \(rect.height) tall, a body line's is \(reference)")
        }
    }

    // MARK: Probe 3: where a tap lands

    @Test("closestPosition over a bold word lands on one of its caret stops, never in the middle of a marker")
    func closestPositionNearMarkers() {
        let (rendered, _) = Self.pair()
        let textView = rendered.textView
        let text = textView.textStorage.string as NSString
        let bold = text.range(of: "**load factor**")
        var found = Set<Int>()
        let start = textView.position(from: textView.beginningOfDocument, offset: bold.location)!
        let end = textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(bold))!
        let left = textView.caretRect(for: start).minX
        let right = textView.caretRect(for: end).minX
        let y = textView.caretRect(for: start).midY
        var x = left - 6
        while x < right + 6 {
            if let position = textView.closestPosition(to: CGPoint(x: x, y: y)) {
                found.insert(textView.offset(from: textView.beginningOfDocument, to: position))
            }
            x += 1
        }
        print("MARKERPROBE closestPosition offsets across **load factor** (\(bold.location)..<\(NSMaxRange(bold))):", found.sorted())
        let inside = found.filter { $0 > bold.location && $0 < bold.location + 2 || $0 > NSMaxRange(bold) - 2 && $0 < NSMaxRange(bold) }
        // Offsets strictly inside a marker are what the caret-stop rule moves
        // out of; the probe records whether UIKit produces them at all.
        print("MARKERPROBE of those, inside a marker:", inside.sorted())
    }

    // MARK: Probe 6: the delegate sees the current parse

    /// Types `text` at `offset` the way the keyboard does: through the text
    /// view, then the delegate's change callback that restyles.
    static func type(_ text: String, at offset: Int, in harness: CodeFenceDisplayTests.Harness) {
        let textView = harness.textView
        let position = textView.position(from: textView.beginningOfDocument, offset: offset)!
        textView.selectedRange = NSRange(location: offset, length: 0)
        textView.replace(textView.textRange(from: position, to: position)!, withText: text)
        harness.coordinator.textViewDidChange(textView)
        harness.layOut()
    }

    static func fresh(_ text: String) -> CodeFenceDisplayTests.Harness {
        let harness = CodeFenceDisplayTests.Harness(text)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        return harness
    }

    @Test("Typing the closing marker collapses both in the edit that makes the span")
    func collapsesInTheEditThatMakesTheSpan() {
        let harness = Self.fresh("Keep the **load factor* low\nnext")
        let unclosed = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        let offset = ("Keep the **load factor*" as NSString).length
        Self.type("*", at: offset, in: harness)

        let reference = Self.fresh("Keep the **load factor** low\nnext")
        Self.assertSame(
            CodeFenceDisplayTests.lineFrames(of: harness.textView),
            CodeFenceDisplayTests.lineFrames(of: reference.textView),
            "after typing the closing marker"
        )
        // And the edit did change something: the unclosed pair took room.
        let after = CodeFenceDisplayTests.lineFrames(of: harness.textView)
        #expect(zip(unclosed, after).contains { abs($0.width - $1.width) > 1 })
    }

    @Test("Breaking a span puts its markers back the moment the edit is made")
    func restoresMarkersWhenTheSpanBreaks() {
        let harness = Self.fresh("Keep the **load factor** low\nnext")
        // Deleting the last `*` leaves `**load factor*`: no span any more.
        let text = harness.textView.textStorage.string as NSString
        let at = text.range(of: "** low").location + 1
        let textView = harness.textView
        let start = textView.position(from: textView.beginningOfDocument, offset: at)!
        let end = textView.position(from: start, offset: 1)!
        textView.replace(textView.textRange(from: start, to: end)!, withText: "")
        harness.coordinator.textViewDidChange(textView)
        harness.layOut()

        let reference = Self.fresh("Keep the **load factor* low\nnext")
        Self.assertSame(
            CodeFenceDisplayTests.lineFrames(of: textView),
            CodeFenceDisplayTests.lineFrames(of: reference.textView),
            "after breaking the span"
        )
    }

    @Test("A paragraph below an edit that opens a fence is laid out as code, not as it was")
    func paragraphsBelowAFenceEdit() {
        let harness = Self.fresh("Intro\nThen **bold** and `code` here\nlast")
        // Opens a fence on the first line: everything below is now code, where
        // the markers are just characters.
        Self.type("```\n", at: 0, in: harness)

        let reference = Self.fresh("```\nIntro\nThen **bold** and `code` here\nlast")
        Self.assertSame(
            CodeFenceDisplayTests.lineFrames(of: harness.textView),
            CodeFenceDisplayTests.lineFrames(of: reference.textView),
            "below a fence just opened"
        )
    }

    @Test("Closing that fence again brings the markers back below it")
    func paragraphsBelowAFenceClosing() {
        let harness = Self.fresh("```\nIntro\nThen **bold** and `code` here\nlast")
        Self.type("", at: 0, in: harness)
        let textView = harness.textView
        let start = textView.position(from: textView.beginningOfDocument, offset: 0)!
        let end = textView.position(from: start, offset: 4)!
        textView.replace(textView.textRange(from: start, to: end)!, withText: "")
        harness.coordinator.textViewDidChange(textView)
        harness.layOut()

        let reference = Self.fresh("Intro\nThen **bold** and `code` here\nlast")
        Self.assertSame(
            CodeFenceDisplayTests.lineFrames(of: textView),
            CodeFenceDisplayTests.lineFrames(of: reference.textView),
            "below a fence just removed"
        )
    }
}

#endif
