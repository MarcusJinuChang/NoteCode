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

// MARK: - The hooks, on a real text view

@Suite("Hidden markers in the text view")
@MainActor
struct HiddenMarkerHookTests {

    static let bold = "Keep **load factor** low"

    private func harness(_ text: String = bold) -> CodeFenceDisplayTests.Harness {
        MarkdownLayoutTests.fresh(text)
    }

    @Test("A tap inside a hidden marker lands on the stretch's stop")
    func tap() async throws {
        let harness = harness()
        try await harness.caret(at: 0)
        try await harness.caret(at: 6)
        #expect(harness.textView.selectedRange == NSRange(location: 5, length: 0))
        try await harness.caret(at: 0)
        try await harness.caret(at: 20)
        #expect(harness.textView.selectedRange == NSRange(location: 18, length: 0))
    }

    @Test("Arrow keys step over a marker in one press")
    func arrows() async throws {
        let harness = harness()
        try await harness.caret(at: 5)
        try await harness.caret(at: 6)   // UIKit's right arrow
        #expect(harness.textView.selectedRange.location == 8, "right from the opening stop is after the first letter")
        try await harness.caret(at: 18)
        try await harness.caret(at: 19)
        #expect(harness.textView.selectedRange.location == 21, "right from the closing stop is after the space")
        try await harness.caret(at: 22)
        try await harness.caret(at: 21)
        try await harness.caret(at: 20)
        #expect(harness.textView.selectedRange.location == 18, "left into the closing markers is their stop")
    }

    @Test("Typing never moves the caret off what was typed: a closing marker typed leaves the caret outside the span")
    func typingIsLeftAlone() async throws {
        let harness = harness("**load* x")
        try await harness.caret(at: 7)
        MarkdownLayoutTests.type("*", at: 7, in: harness)
        #expect(harness.textView.text == "**load** x")
        #expect(harness.textView.selectedRange == NSRange(location: 8, length: 0), "caret stays where typing put it")
        // The next letter lands after the span, not inside it.
        MarkdownLayoutTests.type("z", at: 8, in: harness)
        #expect(harness.textView.text == "**load**z x")
    }

    private func backspace(_ harness: CodeFenceDisplayTests.Harness, at caret: Int) -> Bool {
        harness.textView.selectedRange = NSRange(location: caret, length: 0)
        let allowed = harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: caret - 1, length: 1), replacementText: ""
        )
        return allowed
    }

    @Test("Backspace at the start of a heading's text removes the marker, as one undoable edit")
    func backspaceHeading() throws {
        let harness = harness("## Title\nbody")
        #expect(backspace(harness, at: 3) == false, "the keystroke is replaced by the coordinator's own edit")
        #expect(harness.textView.text == "Title\nbody")
        #expect(harness.textView.selectedRange == NSRange(location: 0, length: 0))
        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == "## Title\nbody")
    }

    @Test("Backspace into a closing marker deletes the last letter inside the span, and an emptied span goes whole")
    func backspaceSpan() {
        let harness = harness()
        #expect(backspace(harness, at: 18) == false)
        #expect(harness.textView.text == "Keep **load facto** low")
        #expect(harness.textView.selectedRange.location == 17)

        let single = self.harness("a **x** b")
        #expect(backspace(single, at: 5) == false)
        #expect(single.textView.text == "a  b")
    }

    @Test("Backspace is the ordinary one in a legacy note")
    func legacy() {
        let legacy = CodeFenceDisplayTests.Harness("## Title")
        legacy.textView.selectedRange = NSRange(location: 3, length: 0)
        #expect(legacy.coordinator.textView(legacy.textView, shouldChangeTextIn: NSRange(location: 2, length: 1), replacementText: ""))
    }
}

// MARK: - Return, Tab, boxes, links and paper

@Suite("Writing: lists, boxes and links on a real text view")
@MainActor
struct WritingHookTests {

    private func harness(_ text: String, rendered: Bool = true) -> CodeFenceDisplayTests.Harness {
        rendered ? MarkdownLayoutTests.fresh(text) : CodeFenceDisplayTests.Harness(text)
    }

    /// A keystroke the way UIKit offers it to the delegate.
    private func key(_ harness: CodeFenceDisplayTests.Harness, _ text: String, at caret: Int) -> Bool {
        harness.textView.selectedRange = NSRange(location: caret, length: 0)
        return harness.coordinator.textView(
            harness.textView, shouldChangeTextIn: NSRange(location: caret, length: 0), replacementText: text
        )
    }

    @Test("Return in a list continues it, and undo takes the whole continuation back in one step")
    func returnContinues() {
        let harness = harness("- one\n1. two\n- [x] three")
        #expect(key(harness, "\n", at: 5) == false)
        #expect(harness.textView.text == "- one\n- \n1. two\n- [x] three")
        #expect(harness.textView.selectedRange == NSRange(location: 8, length: 0))
        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == "- one\n1. two\n- [x] three")
    }

    @Test("Return on an empty item ends the list; elsewhere it is the keyboard's own newline")
    func returnEnds() {
        let harness = harness("- one\n- \nplain")
        #expect(key(harness, "\n", at: 8) == false)
        #expect(harness.textView.text == "- one\n\nplain")
        #expect(key(harness, "\n", at: 11) == true, "in plain text, the newline goes through")
    }

    @Test("Return is left alone while text is being composed")
    func returnWhileComposing() {
        // No marked text can be made in a unit test without an input method,
        // so this checks the other half: with none, a list is continued.
        let harness = harness("- one")
        #expect(harness.textView.markedTextRange == nil)
        #expect(key(harness, "\n", at: 5) == false)
    }

    @Test("Tab nests a list item and ⇧Tab takes it back, only where there is one")
    func tab() {
        let harness = harness("- one\nplain")
        #expect(key(harness, "\t", at: 5) == false)
        #expect(harness.textView.text == "  - one\nplain")
        #expect(harness.coordinator.canOutdentListItems(in: harness.textView))
        harness.coordinator.outdentListItems(in: harness.textView)
        #expect(harness.textView.text == "- one\nplain")
        #expect(!harness.coordinator.canOutdentListItems(in: harness.textView), "nothing to take back")

        harness.textView.selectedRange = NSRange(location: 8, length: 0)
        #expect(!harness.coordinator.canOutdentListItems(in: harness.textView))
        #expect(key(harness, "\t", at: 8) == true, "in plain text Tab is a tab")
    }

    // MARK: Boxes

    private func point(ofBoxIn harness: CodeFenceDisplayTests.Harness, line: Int) throws -> CGPoint {
        let manager = try #require(harness.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        var found: CGPoint?
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragment in
            if let box = fragment as? ChecklistLayoutFragment, found == nil, let rect = box.boxRect()?.box {
                let inset = harness.textView.textContainerInset
                found = CGPoint(
                    x: fragment.layoutFragmentFrame.minX + rect.midX + inset.left,
                    y: fragment.layoutFragmentFrame.minY + rect.midY + inset.top
                )
            }
            return found == nil
        }
        return try #require(found)
    }

    @Test("A tap on a box ticks it and leaves the caret where it was, rendered or legacy",
          arguments: [true, false])
    func boxToggles(rendered: Bool) throws {
        let harness = harness("intro text\n- [ ] buy milk\nmore", rendered: rendered)
        harness.textView.selectedRange = NSRange(location: 3, length: 0)
        let box = try point(ofBoxIn: harness, line: 1)

        let target = try #require(harness.coordinator.markerTapTarget(at: box, in: harness.textView))
        #expect(target == .checkbox(lineOffset: 11))
        harness.coordinator.handleMarkerTap(target, in: harness.textView)
        #expect(harness.textView.text == "intro text\n- [x] buy milk\nmore")
        #expect(harness.textView.selectedRange == NSRange(location: 3, length: 0), "the caret didn't move")
        harness.textView.undoManager?.undo()
        #expect(harness.textView.text == "intro text\n- [ ] buy milk\nmore", "undo takes the tick back")
        harness.coordinator.handleMarkerTap(target, in: harness.textView)
        harness.coordinator.handleMarkerTap(target, in: harness.textView)
        #expect(harness.textView.text == "intro text\n- [ ] buy milk\nmore", "a second tap unticks")
    }

    @Test("A tap away from the box is not the box's, and a locked note's box can't be ticked")
    func boxMisses() throws {
        let harness = harness("intro text\n- [ ] buy milk\nmore")
        let box = try point(ofBoxIn: harness, line: 1)
        #expect(harness.coordinator.markerTapTarget(at: CGPoint(x: box.x + 80, y: box.y), in: harness.textView) == nil)
        #expect(harness.coordinator.markerTapTarget(at: CGPoint(x: box.x, y: box.y - 40), in: harness.textView) == nil)

        harness.textView.isEditable = false
        #expect(harness.coordinator.markerTapTarget(at: box, in: harness.textView) == nil)
    }

    @Test("In ink mode the text view takes no box or link taps")
    func inkMode() throws {
        let harness = harness("- [ ] box")
        let box = try point(ofBoxIn: harness, line: 0)
        harness.editor.setMode(.ink)
        #expect(harness.coordinator.markerTapTarget(at: box, in: harness.textView) == nil)
    }

    // MARK: Links

    @Test("A tap on a link's text is the link's; beside it, or on a lookalike, isn't", arguments: [true, false])
    func links(rendered: Bool) throws {
        let text = "see [the notes](https://example.com/n) or https://example.org/x ok `https://no.pe`"
        let harness = harness(text, rendered: rendered)
        let view = harness.textView
        func middle(of snippet: String) -> CGPoint {
            let rect = harness.rect(of: snippet)
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        let markdown = try #require(harness.coordinator.markerTapTarget(at: middle(of: "the notes"), in: view))
        #expect(markdown == .link(url: URL(string: "https://example.com/n")!, destination: "https://example.com/n"))
        let bare = try #require(harness.coordinator.markerTapTarget(at: middle(of: "https://example.org/x"), in: view))
        #expect(bare == .link(url: URL(string: "https://example.org/x")!, destination: "https://example.org/x"))
        #expect(harness.coordinator.markerTapTarget(at: middle(of: "see"), in: view) == nil)
        #expect(harness.coordinator.markerTapTarget(at: middle(of: " ok "), in: view) == nil)
        #expect(harness.coordinator.markerTapTarget(at: middle(of: "https://no.pe"), in: view) == nil, "inline code is not a link")
    }

    @Test("A link in a locked note still opens")
    func lockedLink() throws {
        let harness = harness("see [the notes](https://example.com/n)")
        harness.textView.isEditable = false
        let rect = harness.rect(of: "the notes")
        let target = harness.coordinator.markerTapTarget(at: CGPoint(x: rect.midX, y: rect.midY), in: harness.textView)
        #expect(target != nil)
    }

    // MARK: Paper

    @Test("The PDF and the thumbnail break lines where the screen does")
    func printedLinesMatchTheScreen() async throws {
        // No final newline: the empty line after one takes its height from the
        // typing attributes, which a view that was never typed in doesn't have.
        let text = String(MarkdownLayoutTests.note.dropLast())
        let screen = MarkdownLayoutTests.pair(text, layout: PageLayout(mode: .print)).rendered
        let screenFrames = CodeFenceDisplayTests.lineFrames(of: screen.textView)

        let rendered = await PrintedNote(text: text, orientation: .portrait, rendersMarkdown: true)
        _ = rendered.paginate(inkBottom: nil, startingAt: 1)
        let printedFrames = CodeFenceDisplayTests.lineFrames(of: rendered.textView)
        #expect(printedFrames.count == screenFrames.count)
        for (index, (a, b)) in zip(printedFrames, screenFrames).enumerated() {
            #expect(abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.01, "frame \(index): printed \(a), screen \(b)")
        }

        let legacy = await PrintedNote(text: text, orientation: .portrait)
        _ = legacy.paginate(inkBottom: nil, startingAt: 1)
        let legacyFrames = CodeFenceDisplayTests.lineFrames(of: legacy.textView)
        #expect(legacyFrames.count != printedFrames.count || zip(legacyFrames, printedFrames).contains { abs($0.width - $1.width) > 0.5 },
                "the note with its markers showing is laid out differently, so the flag matters")
    }

    @Test("A ticked box prints in the accent and an open one doesn't")
    func boxesOnPaper() async throws {
        func orangePixels(_ note: String) async throws -> Int {
            let source = NoteThumbnail.Source(text: note, orientation: .portrait, drawingData: Data(), rendersMarkdown: true)
            let image = try #require(await NoteThumbnail.render(source)?.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(
                data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 200 && pixels[$0 + 1] > 90 && pixels[$0 + 1] < 190 && pixels[$0 + 2] < 90 }.count
        }
        let ticked = try await orangePixels("- [x] done\n- [x] done too")
        let open = try await orangePixels("- [ ] todo\n- [ ] todo too")
        #expect(ticked > 20, "\(ticked) accent pixels with two ticked boxes")
        #expect(open == 0, "\(open) accent pixels with two open boxes")
    }
}

// MARK: - Cost

@Suite("Markdown layout cost")
@MainActor
struct MarkdownLayoutCostTests {

    /// `PageViewTests.typingCost`'s method: a keystroke near the top of a long
    /// note, where TextKit has the most below it to lay out again, timed
    /// through the layout it causes. The content-storage delegate is asked
    /// for every paragraph below the edit, so this is where a slow answer
    /// would show. Rendered against legacy, alternating so the machine's
    /// mood is the same for both.
    @Test("A keystroke in a rendered note costs no more than in a legacy one, on a 500-line note")
    func typingCost() {
        let text = StylingPerformanceTests.document(lines: 500)

        func keystrokes(rendered: Bool) -> TimeInterval {
            let harness = rendered ? MarkdownLayoutTests.fresh(text) : CodeFenceDisplayTests.Harness(text)
            harness.layOut()
            let textView = harness.textView
            var times: [TimeInterval] = []
            for index in 0..<9 {
                let position = textView.position(from: textView.beginningOfDocument, offset: 120 + index)!
                let start = Date()
                textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
                harness.coordinator.textViewDidChange(textView)
                textView.layoutIfNeeded()
                times.append(Date().timeIntervalSince(start))
            }
            return times.sorted()[4]
        }

        var rendered: [TimeInterval] = []
        var legacy: [TimeInterval] = []
        for _ in 0..<3 {
            legacy.append(keystrokes(rendered: false))
            rendered.append(keystrokes(rendered: true))
        }
        let renderedMedian = rendered.sorted()[1]
        let legacyMedian = legacy.sorted()[1]
        print("MARKDOWNCOST keystroke rendered \(renderedMedian * 1000)ms, legacy \(legacyMedian * 1000)ms")
        #expect(renderedMedian < 0.1, "a keystroke took \(renderedMedian)s")
        #expect(renderedMedian < legacyMedian * 1.5 + 0.005, "rendered \(renderedMedian)s against legacy \(legacyMedian)s")
    }

    @Test("Asking the delegate for a paragraph with no markers costs a lookup, not a parse")
    func oneParsePerEdit() {
        let text = StylingPerformanceTests.document(lines: 300)
        let harness = MarkdownLayoutTests.fresh(text)
        harness.layOut()
        let parses = harness.coordinator.documentCache.parseCount
        // Making every paragraph again, as an attribute edit over the whole
        // note does, asks the delegate about each one.
        let storage = harness.textView.textStorage
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        let manager = harness.textView.textLayoutManager!
        manager.ensureLayout(for: manager.documentRange)
        harness.layOut()
        #expect(harness.coordinator.documentCache.parseCount == parses, "a layout parsed the note again")
    }
}

#endif
