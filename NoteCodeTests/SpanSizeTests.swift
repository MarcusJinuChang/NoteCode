//
//  SpanSizeTests.swift
//  NoteCodeTests
//
//  Size anywhere (step 10), at any size (text overhaul, phase 1):
//  `font-size` in a run's tag, beside its colour, chosen in points.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Sized text")
struct SpanSizeTests {

    static let red = TextColour.red.hex

    /// Step 10's three sizes, which notes written since then hold.
    static let small = SpanSize(em: 0.85)!
    static let large = SpanSize(em: 1.25)!
    static let larger = SpanSize(em: 1.5)!

    /// A 17pt note's blocks, spelled out: body, then H1 to H6.
    static let blockSizes = MarkdownFormatting.BlockSizes(body: 17, headings: [34, 28, 22, 20, 17, 15])

    static func styles(_ line: String) -> [SpanStyle] {
        (DocumentParser.parse(line).first?.inlines ?? []).compactMap {
            if case .opening(.styled(let style)) = $0.kind { style } else { nil }
        }
    }

    // MARK: Writing and reading

    @Test("A size is written beside a colour, colour first, in one tag")
    func written() {
        #expect(SpanStyle(size: Self.large).openTag == "<span style=\"font-size:1.25em\">")
        #expect(SpanStyle(colour: Self.red, size: Self.small).openTag == "<span style=\"color:#E5484D;font-size:0.85em\">")
        #expect(SpanStyle(size: Self.larger).openTag == "<span style=\"font-size:1.5em\">")
    }

    @Test("Any size is written to the thousandth, with no trailing zeros")
    func writtenToTheThousandth() {
        #expect(SpanSize(em: 24.0 / 17)?.written == "1.412em")
        #expect(SpanSize(em: 2)?.written == "2em")
        #expect(SpanSize(em: 0.5)?.written == "0.5em")
        #expect(SpanSize(em: 0.706)?.written == "0.706em")
        #expect(SpanSize(em: 3.05)?.written == "3.05em")
    }

    @Test("Each written style reads back as itself", arguments: [0.1, 0.47, 0.85, 1.002, 1.25, 1.412, 1.5, 2, 3.333, 10])
    func roundTrip(em: Double) throws {
        let size = try #require(SpanSize(em: em))
        for colour in [nil, Self.red] as [Int?] {
            let style = SpanStyle(colour: colour, size: size)
            #expect(Self.styles("a \(style.openTag)b\(SpanStyle.close) c") == [style])
        }
    }

    @Test("Step 10's sizes read as they always did, and any other as written")
    func readsAnySize() {
        #expect(Self.styles("<span style=\"font-size:1.25em\">x</span>") == [SpanStyle(size: Self.large)])
        #expect(Self.styles("<span style=\"font-size:0.85em\">x</span>") == [SpanStyle(size: Self.small)])
        #expect(Self.styles("<span style=\"font-size:1.5em\">x</span>") == [SpanStyle(size: Self.larger)])
        #expect(Self.styles("<span style=\"font-size:1.2em\">x</span>") == [SpanStyle(size: SpanSize(em: 1.2))])
        #expect(Self.styles("<span style=\"font-size:1.41176em\">x</span>") == [SpanStyle(size: SpanSize(em: 1.412))])
    }

    @Test("1em is no size, and sizes past the ends read as the ends")
    func noSizeAndEnds() {
        #expect(SpanSize(em: 1) == nil)
        #expect(SpanSize(em: 1.0004) == nil, "rounds to 1em")
        #expect(SpanSize(em: 1.002)?.thousandths == 1002)
        #expect(SpanSize(em: 0) == nil)
        #expect(SpanSize(em: -2) == nil)
        #expect(SpanSize(em: .nan) == nil)
        #expect(SpanSize(em: 50)?.em == 10)
        #expect(SpanSize(em: 0.01)?.em == 0.1)
        // A 1em tag is still a run: hidden, and nothing set.
        #expect(Self.styles("<span style=\"font-size:1em\">x</span>") == [SpanStyle()])
    }

    @Test("Another order, another unit or a missing separator is text", arguments: [
        "<span style=\"font-size:1.25em;color:#E5484D\">a</span>",
        "<span style=\"font-size:12px\">a</span>",
        "<span style=\"color:#E5484Dfont-size:1.25em\">a</span>",
        "<span style=\"color:#E5484D;\">a</span>",
        "<span style=\"font-size:em\">a</span>",
        "<span style=\"font-size:1.2.5em\">a</span>",
    ])
    func notASize(line: String) {
        #expect(Self.styles(line).isEmpty, "\(line)")
    }

    // MARK: Points

    /// Every block size a note can have lies in 11 to 41 points; the
    /// laid-out suite below checks the real fonts.
    @Test("Every half point the control sets comes back exactly, beside text of any size")
    func pointsRoundTrip() {
        for base in stride(from: 11.0, through: 41, by: 0.5) {
            for points in stride(from: 8.0, through: 72, by: 0.5) {
                let size = SpanSize(points: points, against: base)
                #expect(SpanSize.points(size, against: base) == points, "\(points)pt beside \(base)pt: \(size?.written ?? "none")")
            }
        }
    }

    @Test("A size at the text's own is no size")
    func ownSizeIsNone() {
        #expect(SpanSize(points: 17, against: 17) == nil)
        #expect(SpanSize(points: 34, against: 34) == nil)
        #expect(SpanSize.points(nil, against: 22) == 22)
    }

    @Test("Sizes are written as the control shows them")
    func labels() {
        #expect(SpanSize.label(points: 24) == "24")
        #expect(SpanSize.label(points: 24.5) == "24.5")
        #expect(SpanSize.label(points: 8) == "8")
    }

    // MARK: Editing

    static func apply(_ edit: TextEdit?, to text: String) -> String? {
        edit.map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) }
    }

    static func size(_ size: SpanSize?, _ text: String, _ selection: NSRange) -> String? {
        apply(MarkdownFormatting.size(size, selection: selection, in: text as NSString, codeRanges: []), to: text)
    }

    static func size(points: Double?, _ text: String, _ selection: NSRange) -> String? {
        apply(MarkdownFormatting.size(
            points: points, blockSizes: blockSizes, selection: selection, in: text as NSString, codeRanges: []
        ), to: text)
    }

    static func colour(_ hex: Int?, _ text: String, _ selection: NSRange) -> String? {
        apply(MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: []), to: text)
    }

    static func caret(in word: String, of text: String) -> NSRange {
        NSRange(location: (text as NSString).range(of: word).location + 1, length: 0)
    }

    static func tag(_ em: Double) -> String {
        SpanStyle(size: SpanSize(em: em)).openTag
    }

    @Test("A size on a word wraps it")
    func sizesAWord() {
        let text = "keep it small"
        #expect(Self.size(Self.large, text, Self.caret(in: "small", of: text)) == "keep it \(SpanStyle(size: Self.large).openTag)small</span>")
    }

    @Test("A size in points is written against the line's own text")
    func pointsAgainstTheLine() {
        let body = "keep it small"
        #expect(Self.size(points: 24, body, Self.caret(in: "small", of: body)) == "keep it \(Self.tag(1.412))small</span>")

        let heading = "# A big title"
        #expect(Self.size(points: 24, heading, Self.caret(in: "title", of: heading)) == "# A big \(Self.tag(0.706))title</span>")
    }

    @Test("A selection from a heading into a paragraph comes out one size")
    func pointsAcrossLines() {
        let text = "# Head\nbody text"
        let selection = NSRange(location: 2, length: (text as NSString).length - 2)
        #expect(Self.size(points: 24, text, selection) == "# \(Self.tag(0.706))Head</span>\n\(Self.tag(1.412))body text</span>")
    }

    @Test("The text's own size, or none, takes a size off; on plain text it does nothing")
    func pointsTakeOff() {
        let sized = "a \(Self.tag(1.412))word</span> b"
        #expect(Self.size(points: 17, sized, Self.caret(in: "word", of: sized)) == "a word b")
        #expect(Self.size(points: nil, sized, Self.caret(in: "word", of: sized)) == "a word b")

        let both = "a \(SpanStyle(colour: Self.red, size: SpanSize(em: 1.412)).openTag)word</span> b"
        #expect(Self.size(points: 17, both, Self.caret(in: "word", of: both)) == "a \(SpanStyle(colour: Self.red).openTag)word</span> b")

        #expect(Self.size(points: 17, "plain words", Self.caret(in: "words", of: "plain words")) == nil)
    }

    @Test("A size on a coloured run keeps its colour, and a colour on a sized one keeps its size")
    func keepsTheOtherSetting() {
        let red = "a \(SpanStyle(colour: Self.red).openTag)word</span> b"
        #expect(Self.size(Self.larger, red, Self.caret(in: "word", of: red))
                == "a \(SpanStyle(colour: Self.red, size: Self.larger).openTag)word</span> b")

        let large = "a \(SpanStyle(size: Self.large).openTag)word</span> b"
        #expect(Self.colour(Self.red, large, Self.caret(in: "word", of: large))
                == "a \(SpanStyle(colour: Self.red, size: Self.large).openTag)word</span> b")
    }

    @Test("Taking one setting off keeps the other; taking the last off unwraps")
    func takesSettingsOff() {
        let both = "a \(SpanStyle(colour: Self.red, size: Self.large).openTag)word</span> b"
        #expect(Self.size(nil, both, Self.caret(in: "word", of: both)) == "a \(SpanStyle(colour: Self.red).openTag)word</span> b")
        #expect(Self.colour(nil, both, Self.caret(in: "word", of: both)) == "a \(SpanStyle(size: Self.large).openTag)word</span> b")

        let large = "a \(SpanStyle(size: Self.large).openTag)word</span> b"
        #expect(Self.size(nil, large, Self.caret(in: "word", of: large)) == "a word b")
        #expect(Self.size(nil, "plain words", NSRange(location: 2, length: 3)) == nil)
    }

    // MARK: Reading the size at the caret

    static func sizes(_ text: String, _ selection: NSRange, code: [CodeRange] = []) -> (samples: [MarkdownFormatting.SizeSample], hasTarget: Bool) {
        MarkdownFormatting.sizes(at: selection, in: text as NSString, codeRanges: code)
    }

    static func sample(_ level: Int = 0, _ size: SpanSize? = nil) -> MarkdownFormatting.SizeSample {
        MarkdownFormatting.SizeSample(headingLevel: level, size: size)
    }

    @Test("The caret's size is the run it is in")
    func caretSize() {
        let text = "a \(SpanStyle(colour: Self.red, size: Self.small).openTag)word</span> b" as NSString
        let state = MarkdownFormatting.formatting(at: Self.caret(in: "word", of: text as String), in: text, codeRanges: [])
        #expect(state.size == Self.small)
        #expect(state.colour == Self.red)
        #expect(state.sizes == [Self.sample(0, Self.small)])
        #expect(state.canResize)
        #expect(MarkdownFormatting.formatting(at: NSRange(location: 1, length: 0), in: text, codeRanges: []).size == nil)
    }

    @Test("A caret reads its block's size, and there is something to size only in a word or a run")
    func caretTargets() {
        #expect(Self.sizes("plain words", Self.caret(in: "words", of: "plain words")) == ([Self.sample()], true))
        #expect(Self.sizes("# Title", Self.caret(in: "Title", of: "# Title")) == ([Self.sample(1)], true))
        // After the space at a line's end: no word, no run. Phase 4's typing
        // style is what will size text there.
        let afterSpace = NSRange(location: ("plain " as NSString).length, length: 0)
        #expect(Self.sizes("plain ", afterSpace) == ([Self.sample()], false))
    }

    @Test("A selection reads each size its text is in, in order, spaces and tags not counted")
    func selectionSizes() {
        let text = "plain \(Self.tag(1.5))big</span> end"
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        #expect(Self.sizes(text, all) == ([Self.sample(), Self.sample(0, Self.larger)], true))

        let big = ns.range(of: "big")
        #expect(Self.sizes(text, big) == ([Self.sample(0, Self.larger)], true))
        // The visible word with its hidden tags about it, as a drag can take.
        let withTags = NSRange(location: ns.range(of: "<span").location, length: NSMaxRange(ns.range(of: "</span>")) - ns.range(of: "<span").location)
        #expect(Self.sizes(text, withTags) == ([Self.sample(0, Self.larger)], true))

        let bigToEnd = NSRange(location: big.location, length: ns.length - big.location)
        #expect(Self.sizes(text, bigToEnd) == ([Self.sample(0, Self.larger), Self.sample()], true))

        #expect(Self.sizes("a    b", NSRange(location: 1, length: 3)) == ([], false), "spaces alone")
    }

    @Test("A selection over a heading and a paragraph reads both")
    func selectionAcrossBlocks() {
        let text = "# Head\nbody"
        #expect(Self.sizes(text, NSRange(location: 0, length: (text as NSString).length)) == ([Self.sample(1), Self.sample()], true))
    }

    @Test("Nothing is sized in or across code")
    func notInCode() {
        let text = "prose\n```\ncode\n```\n"
        let ns = text as NSString
        let code = [CodeRange(range: NSRange(location: 6, length: ns.length - 6), isClosed: true)]
        #expect(Self.sizes(text, NSRange(location: 0, length: ns.length), code: code) == ([], false))
        #expect(Self.sizes(text, NSRange(location: ns.range(of: "code").location + 1, length: 0), code: code) == ([], false))
        #expect(Self.sizes(text, Self.caret(in: "prose", of: text), code: code) == ([Self.sample()], true))
    }
}

#if canImport(UIKit)

import PencilKit
import PaperKit
import UIKit

@Suite("Sized text, laid out")
@MainActor
struct SpanSizeLayoutTests {

    static func font(_ textView: UITextView, at word: String) -> UIFont? {
        let offset = (textView.text as NSString).range(of: word).location
        return textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
    }

    static func styled(_ text: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = text
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    /// Spelled out, not asked of the styler's own function: 17pt body,
    /// 34pt H1, each step's em, to the half point.
    @Test("A run is set at its size against the text around it, bold and all")
    func fonts() throws {
        let large = SpanStyle(size: SpanSizeTests.large).openTag
        let small = SpanStyle(size: SpanSizeTests.small).openTag
        let textView = Self.styled("# A \(large)big\(SpanStyle.close) title\nplain \(large)larger **bold**\(SpanStyle.close) and \(small)tiny\(SpanStyle.close)\n")

        #expect(Self.font(textView, at: "plain")?.pointSize == 17)
        #expect(Self.font(textView, at: "larger")?.pointSize == 21.5)
        #expect(Self.font(textView, at: "tiny")?.pointSize == 14.5)
        #expect(Self.font(textView, at: "big")?.pointSize == 42.5)
        // A heading's run is a larger heading: still bold, as the heading is.
        #expect(Self.font(textView, at: "big")?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        #expect(Self.font(textView, at: "big")?.fontName == Self.font(textView, at: "title")?.fontName)

        let bold = try #require(Self.font(textView, at: "bold"))
        #expect(bold.pointSize == 21.5)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    /// The pure suite sweeps block sizes; this one the note's real fonts, at
    /// every text size a note can have.
    @Test("A size chosen in points is drawn at exactly those points in every block, at every note size")
    func pointsInEveryBlock() throws {
        for bodySize in NoteTypography.sizes {
            let typography = NoteTypography(bodySize: bodySize)
            let sizes = typography.blockSizes
            #expect(sizes.body == Double(typography.prose.pointSize))
            for level in 0...6 {
                let base = sizes.size(forHeadingLevel: level)
                for points in [8, 13, 24, 36.5, 72] {
                    #expect(SpanSize.points(SpanSize(points: points, against: base), against: base) == points,
                            "\(points)pt in level \(level) of a \(bodySize)pt note")
                }
            }
        }

        // And drawn so: a word in a paragraph and one in a heading, both 24.
        let text = "# A big title\nplain words\n"
        var edited = text
        for word in ["title", "words"] {
            let edit = try #require(MarkdownFormatting.size(
                points: 24, blockSizes: NoteTypography.standard.blockSizes,
                selection: SpanSizeTests.caret(in: word, of: edited), in: edited as NSString, codeRanges: []
            ))
            edited = (edited as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        let textView = Self.styled(edited)
        #expect(Self.font(textView, at: "title")?.pointSize == 24)
        #expect(Self.font(textView, at: "words")?.pointSize == 24)
        #expect(Self.font(textView, at: "title")?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    /// Measured 18 Oct before free sizes went in: if `withSize` dropped the
    /// leading, as `systemFont(ofSize:)` does, a run at the text's own size
    /// would be a shorter line, and every page break below it would move.
    @Test("A line holding a run at its text's own size lays out as plain text does")
    func ownSizeLaysOutAsPlain() {
        let body = NoteTypography.standard.prose
        #expect(DocumentStyler.font(body, sizedTo: SpanSize(em: 1.0004)) == body)
        let sized = body.withSize(17)
        #expect(sized.leading == body.leading)
        #expect(sized.lineHeight == body.lineHeight)
        let larger = DocumentStyler.font(body, sizedTo: SpanSize(points: 24, against: 17))
        #expect(larger.pointSize == 24)
        #expect(larger.leading > 0, "a sized run keeps the system's leading")
    }

    @Test("Restyling sized text that's already styled leaves the storage alone")
    func restyleIsNotAnEdit() {
        let textView = Self.styled("plain \(SpanStyle(colour: TextColour.red.hex, size: SpanSize(em: 1.412)).openTag)larger\(SpanStyle.close) text\n")
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        DocumentStyler.applyStyling(to: textView)
        #expect(edits == 0)
    }
}

@Suite("Sized text: the size control", .serialized)
@MainActor
struct SizeControlTests {

    typealias Harness = TextSizeEditorTests.Harness

    static func caret(in word: String, of harness: Harness) -> NSRange {
        SpanSizeTests.caret(in: word, of: harness.textView.text)
    }

    /// What the coordinator would report on a caret move: the harness has
    /// none.
    static func report(_ harness: Harness) {
        harness.editor.setCaretFormatting(MarkdownFormatting.formatting(
            at: harness.textView.selectedRange, in: harness.textView.textStorage.mutableString, codeRanges: []
        ))
    }

    static func characterEdits(of harness: Harness, during body: () async -> Void) async -> Int {
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: harness.textView.textStorage, queue: nil
        ) { note in
            if let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) { edits += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        await body()
        return edits
    }

    // MARK: Reading

    @Test("It reads the size at the caret in points, and a dash for several")
    func reads() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "Title", of: harness)
        Self.report(harness)
        #expect(harness.editor.selectionTextSize.points == 34)
        #expect(harness.editor.selectionTextSize.canChange)

        harness.textView.text = "plain \(SpanSizeTests.tag(1.412))big</span> end\n"
        harness.textView.selectedRange = Self.caret(in: "big", of: harness)
        Self.report(harness)
        #expect(harness.editor.selectionTextSize.points == 24)
        #expect(harness.editor.selectionTextSize.ownPoints == 17)

        harness.textView.selectedRange = NSRange(location: 0, length: (harness.textView.text as NSString).length - 1)
        Self.report(harness)
        #expect(harness.editor.selectionTextSize.points == nil, "17 and 24")
        #expect(harness.editor.selectionTextSize.startPoints == 17)
    }

    @Test("Same em in a heading and a paragraph is two sizes")
    func sameEmTwoSizes() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = NSRange(location: 0, length: (harness.textView.text as NSString).length - 1)
        Self.report(harness)
        #expect(harness.editor.selectionTextSize.points == nil, "a 34pt heading and 17pt text")
        #expect(harness.editor.selectionTextSize.startPoints == 34)
    }

    // MARK: + and −

    @Test("+ steps a point at a time, and five quick taps change the text once")
    func stepsSettleOnce() async {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        let edits = await Self.characterEdits(of: harness) {
            for _ in 0..<5 { harness.editor.stepSelectionSize(by: 1) }
            #expect(harness.editor.selectionTextSize.points == 22, "the control shows the taps at once")
            #expect(!harness.textView.text.contains("<span"), "…and the text waits for them to stop")
            await harness.wait()
        }
        #expect(edits == 1)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(22.0 / 17))words</span>"))
        #expect(harness.editor.pendingSelectionSize == nil)
    }

    @Test("Moving the caret during the pause puts the size on at once")
    func caretMoveFlushes() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        harness.editor.stepSelectionSize(by: 1)
        harness.textView.selectedRange = NSRange(location: 0, length: 0)
        Self.report(harness)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(18.0 / 17))words</span>"))
        #expect(harness.editor.pendingSelectionSize == nil)
        #expect(harness.textView.selectedRange == NSRange(location: 0, length: 0), "the caret stays where the reader put it")
    }

    @Test("A caret moved past the sized text stays on its letter, after the tags")
    func caretMoveKeepsItsPlace() {
        let harness = Harness(withInk: false)
        harness.textView.text = "some words and more\n"
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        harness.editor.stepSelectionSize(by: 1)
        let more = (harness.textView.text as NSString).range(of: "more").location
        harness.textView.selectedRange = NSRange(location: more, length: 0)
        Self.report(harness)
        let moved = (harness.textView.text as NSString).range(of: "more").location
        #expect(harness.textView.selectedRange == NSRange(location: moved, length: 0))
    }

    @Test("Text typed during the pause drops the tap")
    func typingDrops() async {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        harness.editor.stepSelectionSize(by: 1)
        harness.textView.insertText("x")
        Self.report(harness)
        await harness.wait()
        #expect(!harness.textView.text.contains("<span"))
        #expect(harness.editor.pendingSelectionSize == nil)
    }

    @Test("A selection in several sizes goes to its start's size, a point on")
    func mixedSteps() async {
        let harness = Harness(withInk: false)
        harness.textView.text = "some \(SpanSizeTests.tag(1.412))big</span> words\n"
        harness.textView.selectedRange = NSRange(location: 0, length: (harness.textView.text as NSString).length - 1)
        Self.report(harness)
        harness.editor.stepSelectionSize(by: 1)
        await harness.wait()
        #expect(harness.textView.text == "\(SpanSizeTests.tag(18.0 / 17))some big words</span>\n")
    }

    @Test("Stepping stops at 8 and 72, and text past them steps back towards them")
    func ends() {
        #expect(NoteEditor.stepped(72, by: 1) == nil)
        #expect(NoteEditor.stepped(8, by: -1) == nil)
        #expect(NoteEditor.stepped(71, by: 1) == 72)
        #expect(NoteEditor.stepped(97, by: -1) == 96)
        #expect(NoteEditor.stepped(97, by: 1) == nil)
        #expect(NoteEditor.stepped(7, by: 1) == 8)
        #expect(NoteEditor.stepped(24.5, by: 1) == 25.5)
    }

    @Test("A caret on no word and in no run has nothing to size")
    func nothingToSize() async {
        let harness = Harness(withInk: false)
        harness.textView.text = "words \n"
        harness.textView.selectedRange = NSRange(location: 6, length: 0)
        Self.report(harness)
        #expect(!harness.editor.selectionTextSize.canChange)
        #expect(harness.editor.canStepSelectionSize == (false, false))
        harness.editor.stepSelectionSize(by: 1)
        await harness.wait()
        #expect(harness.textView.text == "words \n")
    }

    @Test("A locked note's text isn't sized")
    func locked() async {
        let harness = Harness(withInk: false)
        harness.editor.setTextLocked(true)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        #expect(!harness.editor.selectionTextSize.canChange)
        harness.editor.stepSelectionSize(by: 1)
        harness.editor.setSelectionSize(points: 30)
        await harness.wait()
        #expect(!harness.textView.text.contains("<span"))
    }

    // MARK: The list

    @Test("A size from the list goes on at once; Default takes it off")
    func pickAndDefault() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        harness.editor.setSelectionSize(points: 24)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(1.412))words</span>"))

        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        harness.editor.setSelectionSize(points: nil)
        #expect(harness.textView.text == "# Title\nsome words\n")
    }

    @Test("A typed size: a number, pt or not, clamped and to the half point", arguments: [
        ("24", 24.0), ("24.5pt", 24.5), (" 30 pt ", 30), ("24,5", 24.5), ("24.3", 24.5), ("100", 72), ("3", 8),
    ] as [(String, Double)])
    func typed(text: String, points: Double) {
        #expect(NoteEditor.points(typed: text) == points)
    }

    @Test("Not a number sets nothing", arguments: ["", "big", "pt", "nan", "inf"])
    func notTyped(text: String) {
        #expect(NoteEditor.points(typed: text) == nil)
    }

    // MARK: Ink

    @Test("Without ink, a size goes on at once")
    func noInk() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        harness.editor.setSelectionSize(points: 24)

        #expect(harness.editor.selectionSizeAwaitingConfirmation == nil)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(1.412))words</span>"))
    }

    @Test("With ink, a size waits for Change, then goes on where it was asked for")
    func inkAsks() {
        let harness = Harness(withInk: true)
        let caret = Self.caret(in: "words", of: harness)
        harness.textView.selectedRange = caret
        harness.editor.setSelectionSize(points: 24)

        #expect(harness.editor.selectionSizeAwaitingConfirmation == NoteEditor.SizeRequest(points: 24, selection: caret))
        #expect(!harness.textView.text.contains("<span"), "nothing changes until the reader says so")

        // The alert took the keyboard; the selection it was asked for holds.
        harness.textView.selectedRange = NSRange(location: 0, length: 0)
        harness.editor.confirmSelectionSize()
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(1.412))words</span>"))

        // One yes covers the note until it is next opened.
        harness.textView.selectedRange = Self.caret(in: "Title", of: harness)
        harness.editor.setSelectionSize(points: 24)
        #expect(harness.editor.selectionSizeAwaitingConfirmation == nil)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(0.706))Title</span>"))
    }

    @Test("With ink, a run of taps asks once, after they stop")
    func inkAsksAfterTheTaps() async {
        let harness = Harness(withInk: true)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        Self.report(harness)
        for _ in 0..<3 { harness.editor.stepSelectionSize(by: 1) }
        #expect(harness.editor.selectionSizeAwaitingConfirmation == nil)
        await harness.wait()
        #expect(harness.editor.selectionSizeAwaitingConfirmation?.points == 20)
        #expect(harness.editor.selectionTextSize.points == 20, "the control shows what is being asked about")
        harness.editor.confirmSelectionSize()
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(20.0 / 17))words</span>"))
    }

    @Test("Cancel changes nothing")
    func inkCancel() {
        let harness = Harness(withInk: true)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        harness.editor.setSelectionSize(points: 24)
        harness.editor.cancelSelectionSize()

        #expect(harness.editor.selectionSizeAwaitingConfirmation == nil)
        #expect(!harness.textView.text.contains("<span"))
    }

    @Test("Custom… sizes what it was asked for, and on a note with ink its Set is the yes")
    func custom() {
        let harness = Harness(withInk: true)
        let caret = Self.caret(in: "words", of: harness)
        harness.textView.selectedRange = caret
        harness.editor.beginCustomSize()
        #expect(harness.editor.customSizeSelection == caret)
        #expect(harness.editor.customSizeAsksAboutInk)

        harness.textView.selectedRange = NSRange(location: 0, length: 0)
        harness.editor.finishCustomSize(typed: "30")
        #expect(harness.editor.customSizeSelection == nil)
        #expect(harness.textView.text.contains("\(SpanSizeTests.tag(30.0 / 17))words</span>"))

        harness.textView.selectedRange = Self.caret(in: "Title", of: harness)
        harness.editor.setSelectionSize(points: 24)
        #expect(harness.editor.selectionSizeAwaitingConfirmation == nil, "already answered")
    }

    @Test("Custom… with nothing typed, or cancelled, sets nothing")
    func customNothing() {
        let harness = Harness(withInk: false)
        harness.textView.selectedRange = Self.caret(in: "words", of: harness)
        harness.editor.beginCustomSize()
        harness.editor.finishCustomSize(typed: "big")
        harness.editor.beginCustomSize()
        harness.editor.cancelCustomSize()
        #expect(harness.editor.customSizeSelection == nil)
        #expect(harness.textView.text == "# Title\nsome words\n")
    }
}

#endif
