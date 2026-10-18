//
//  TextColourTests.swift
//  NoteCodeTests
//
//  Coloured text (step 10): `<span style="color:#RRGGBB">…</span>`.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Coloured text")
struct TextColourTests {

    static let red = TextColour.red.hex
    static let blue = TextColour.blue.hex
    static func tag(_ hex: Int) -> String { SpanStyle(colour: hex).openTag }
    static let close = SpanStyle.close

    static func kinds(_ line: String) -> [InlineNode.Kind] {
        DocumentParser.parse(line).first?.inlines.map(\.kind) ?? []
    }

    static func texts(_ line: String) -> [String] {
        DocumentParser.parse(line).first?.inlines.map { String(line[$0.range]) } ?? []
    }

    // MARK: Reading

    @Test("A run is two tags of markers with ordinary spans between them")
    func parsesARun() {
        let line = "a \(Self.tag(Self.red))red **bold**\(Self.close) b"
        #expect(Self.kinds(line) == [.text, .spanOpen(SpanStyle(colour: Self.red)), .text, .strong, .spanClose, .text])
        #expect(Self.texts(line) == ["a ", Self.tag(Self.red), "red ", "**bold**", Self.close, " b"])

        // The tags are markers, wholly: nothing of them is content.
        let inlines = DocumentParser.parse(line).first!.inlines
        #expect(inlines[1].markerRanges == [inlines[1].range])
        #expect(inlines[4].markerRanges == [inlines[4].range])
    }

    @Test("The tag is written in one shape, its hex read in either case")
    func tagShape() {
        #expect(Self.tag(0x0A0B0C) == "<span style=\"color:#0A0B0C\">")
        #expect(Self.kinds("<span style=\"color:#e5484d\">x</span>").contains(.spanOpen(SpanStyle(colour: Self.red))))
    }

    @Test("Anything else is text", arguments: [
        "<span class=\"x\">a</span>",
        "<span style=\"color:red\">a</span>",
        "<span style=\"color: #E5484D\">a</span>",
        "<span style=\"color:#E5484D;font-weight:bold\">a</span>",
        "<span style=\"color:#E5484D\">never closed",
        "<span style=\"color:#E5484D\"></span>",
        "<span style=\"color:#E5484\">a</span>",
    ])
    func notColour(line: String) {
        #expect(!Self.kinds(line).contains { $0.isSpanTag }, "\(line)")
    }

    @Test("Two runs on a line, and a run in a heading and a list item")
    func severalRuns() {
        let two = "\(Self.tag(Self.red))a\(Self.close) and \(Self.tag(Self.blue))b\(Self.close)"
        #expect(Self.kinds(two) == [.spanOpen(SpanStyle(colour: Self.red)), .text, .spanClose, .text, .spanOpen(SpanStyle(colour: Self.blue)), .text, .spanClose])
        #expect(Self.kinds("# \(Self.tag(Self.red))Title\(Self.close)").contains(.spanOpen(SpanStyle(colour: Self.red))))
        #expect(Self.kinds("- \(Self.tag(Self.red))item\(Self.close)").contains(.spanOpen(SpanStyle(colour: Self.red))))
    }

    @Test("A span can't cross a run's edge")
    func spansDontCross() {
        let line = "**a \(Self.tag(Self.red))b** c\(Self.close)"
        #expect(!Self.kinds(line).contains(.strong))
    }

    @Test("A recolour changes the block's signature, though no length changes")
    func recolourChangesTheSignature() {
        #expect(InlineNode.Kind.spanOpen(SpanStyle(colour: Self.red)).discriminant != InlineNode.Kind.spanOpen(SpanStyle(colour: Self.blue)).discriminant)
    }

    @Test("Every colour reads at 4.5:1 or better on the page in both appearances")
    func contrast() {
        for colour in TextColour.allCases {
            #expect(AccentPalette.contrast(AccentPalette.textHex(for: colour.hex, isDark: false), 0xFFFFFF) >= 4.5, "\(colour.name) light")
            #expect(AccentPalette.contrast(AccentPalette.textHex(for: colour.hex, isDark: true), 0x000000) >= 4.5, "\(colour.name) dark")
        }
    }

    // MARK: Colouring

    static func apply(_ edit: TextEdit?, to text: String) -> (text: String, selection: NSRange)? {
        guard let edit else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    static func colour(_ hex: Int?, _ text: String, _ selection: NSRange, codeRanges: [CodeRange] = []) -> (text: String, selection: NSRange)? {
        apply(MarkdownFormatting.colour(hex, selection: selection, in: text as NSString, codeRanges: codeRanges), to: text)
    }

    static func range(of part: String, in text: String) -> NSRange {
        (text as NSString).range(of: part)
    }

    @Test("A selection is wrapped, and stays selected")
    func wrapsASelection() throws {
        let text = "keep the invariant true"
        let result = try #require(Self.colour(Self.red, text, Self.range(of: "invariant", in: text)))
        #expect(result.text == "keep the \(Self.tag(Self.red))invariant\(Self.close) true")
        #expect((result.text as NSString).substring(with: result.selection) == "invariant")
    }

    @Test("A caret colours its word and stays where it was in it")
    func wrapsTheWordAtTheCaret() throws {
        let text = "keep the invariant true"
        let caret = Self.range(of: "invariant", in: text).location + 3
        let result = try #require(Self.colour(Self.red, text, NSRange(location: caret, length: 0)))
        #expect(result.text == "keep the \(Self.tag(Self.red))invariant\(Self.close) true")
        let before = (result.text as NSString).substring(to: result.selection.location)
        #expect(before.hasSuffix("inv"))
    }

    @Test("In a run, another colour recolours it and Default takes it off")
    func recoloursAndRemoves() throws {
        let text = "a \(Self.tag(Self.red))word\(Self.close) b"
        let caret = Self.range(of: "word", in: text).location + 2
        let recoloured = try #require(Self.colour(Self.blue, text, NSRange(location: caret, length: 0)))
        #expect(recoloured.text == "a \(Self.tag(Self.blue))word\(Self.close) b")

        let removed = try #require(Self.colour(nil, text, NSRange(location: caret, length: 0)))
        #expect(removed.text == "a word b")
        #expect(removed.selection == NSRange(location: 4, length: 0))
    }

    @Test("Part of a run recolours the whole run: colours don't nest")
    func noNesting() throws {
        let text = "a \(Self.tag(Self.red))long word\(Self.close) b"
        let result = try #require(Self.colour(Self.blue, text, Self.range(of: "word", in: text)))
        #expect(result.text == "a \(Self.tag(Self.blue))long word\(Self.close) b")
    }

    @Test("Half a bold word is taken in whole, so the bold isn't cut")
    func takesSpansWhole() throws {
        let text = "a **load factor** b"
        let result = try #require(Self.colour(Self.red, text, Self.range(of: "factor** b", in: text)))
        #expect(result.text == "a \(Self.tag(Self.red))**load factor** b\(Self.close)")
    }

    @Test("Over several lines, a run on each line, after a heading's or list item's marker")
    func severalLines() throws {
        let text = "# Title\n- item one\nplain"
        let result = try #require(Self.colour(Self.red, text, NSRange(location: 0, length: (text as NSString).length)))
        #expect(result.text == "# \(Self.tag(Self.red))Title\(Self.close)\n- \(Self.tag(Self.red))item one\(Self.close)\n\(Self.tag(Self.red))plain\(Self.close)")
        #expect((result.text as NSString).substring(with: result.selection).hasPrefix("Title"))
        #expect((result.text as NSString).substring(with: result.selection).hasSuffix("plain"))
    }

    @Test("Spaces at a selection's ends stay outside the run")
    func trimsSpaces() throws {
        let text = "a word b"
        let result = try #require(Self.colour(Self.red, text, Self.range(of: " word ", in: text)))
        #expect(result.text == "a \(Self.tag(Self.red))word\(Self.close) b")
    }

    @Test("Nothing to do in code, at a caret on no word, or Default where nothing is coloured")
    func nothingToDo() {
        let text = "prose\n```cpp\nint x;\n```\n"
        let codeRanges = [CodeRange(range: NSRange(location: 6, length: 18), isClosed: true, lastCaret: 23, isOutput: false, language: .cpp, tag: "cpp")]
        #expect(Self.colour(Self.red, text, NSRange(location: 14, length: 2), codeRanges: codeRanges) == nil)
        #expect(Self.colour(Self.red, "a  b", NSRange(location: 2, length: 0)) == nil)
        #expect(Self.colour(nil, "plain words", NSRange(location: 2, length: 3)) == nil)
    }

    // MARK: Elsewhere

    @Test("Smart punctuation is a straight quote made curly or hyphens made a dash, and nothing else")
    func smartPunctuation() {
        #expect(TextRewritingPolicy.isSmartPunctuation(replacing: "\"", with: "\u{201C}"))
        #expect(TextRewritingPolicy.isSmartPunctuation(replacing: "\"", with: "\u{201D}"))
        #expect(TextRewritingPolicy.isSmartPunctuation(replacing: "'", with: "\u{2019}"))
        #expect(TextRewritingPolicy.isSmartPunctuation(replacing: "--", with: "\u{2014}"))
        #expect(!TextRewritingPolicy.isSmartPunctuation(replacing: "\"", with: "x"))
        #expect(!TextRewritingPolicy.isSmartPunctuation(replacing: "lo", with: "log"))
    }

    @Test("Search never finds a tag, never shows one, and points at the note's own characters")
    func search() throws {
        let text = "keep the \(Self.tag(Self.red))load factor\(Self.close) low"
        #expect(NoteSearch("span").match(title: "Note", content: text) == nil)
        #expect(NoteSearch("color").match(title: "Note", content: text) == nil)

        let match = try #require(NoteSearch("factor").match(title: "Note", content: text))
        #expect(match.excerpt?.contains("<") == false)
        let found = try #require(NoteSearch("factor").matches(in: text).first)
        #expect((text as NSString).substring(with: found) == "factor")
    }

    @Test("A colour's tags aren't words in Get Info")
    func wordCount() {
        #expect(NoteInfo(content: "a \(Self.tag(Self.red))red word\(Self.close) b").words == 4)
    }

    // MARK: The caret

    @Test("The caret's colour is the run it is in, by the span rule")
    func caretColour() {
        let text = "a \(Self.tag(Self.red))word\(Self.close) b" as NSString
        let open = text.range(of: Self.tag(Self.red))
        let close = text.range(of: Self.close)
        func colour(at offset: Int) -> Int? {
            MarkdownFormatting.formatting(at: NSRange(location: offset, length: 0), in: text, codeRanges: []).colour
        }
        #expect(colour(at: open.location) == nil)                   // in front of the run
        #expect(colour(at: NSMaxRange(open) + 1) == Self.red)       // in its text
        #expect(colour(at: close.location) == Self.red)             // at its end
        #expect(colour(at: NSMaxRange(close)) == nil)               // past it
    }

    // MARK: Backspace

    @Test("Backspace on a run's only letter takes its tags too")
    func backspaceEmptiesTheRun() throws {
        let text = "a \(Self.tag(Self.red))x\(Self.close) b"
        let caret = Self.range(of: Self.close, in: text).location
        let result = try #require(Self.apply(MarkdownFormatting.backspace(at: caret, in: text as NSString, codeRanges: []), to: text))
        #expect(result.text == "a  b")
        #expect(result.selection == NSRange(location: 2, length: 0))
    }

    @Test("Backspace from inside or past a closing tag deletes the run's last letter, never the tag")
    func backspaceInsideTheTag() throws {
        let text = "a \(Self.tag(Self.red))word\(Self.close) b"
        let close = Self.range(of: Self.close, in: text)
        for caret in [close.location + 3, NSMaxRange(close)] {
            let result = try #require(Self.apply(MarkdownFormatting.backspace(at: caret, in: text as NSString, codeRanges: []), to: text))
            #expect(result.text == "a \(Self.tag(Self.red))wor\(Self.close) b", "from \(caret)")
        }
    }

    @Test("Backspace on a run's only letter inside bold takes the bold and the tags")
    func backspaceEmptiesThroughBold() throws {
        let text = "a \(Self.tag(Self.red))**x**\(Self.close) b"
        let caret = Self.range(of: Self.close, in: text).location
        let result = try #require(Self.apply(MarkdownFormatting.backspace(at: caret, in: text as NSString, codeRanges: []), to: text))
        #expect(result.text == "a  b")
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Coloured text, laid out and drawn")
@MainActor
struct TextColourLayoutTests {

    static let red = TextColour.red.hex
    static let note = [
        "A paragraph with \(SpanStyle(colour: red).openTag)red words and **bold**\(SpanStyle.close) in it, long enough that it wraps onto a second line on the page.",
        "# A \(SpanStyle(colour: TextColour.blue.hex).openTag)blue\(SpanStyle.close) heading",
        "- an item ending in \(SpanStyle(colour: TextColour.green.hex, size: SpanSize(em: 1.25)).openTag)green\(SpanStyle.close)",
        "plain",
        "",
    ].joined(separator: "\n")

    @Test("Tags take no room: every line is where it would be without them",
          arguments: [PageLayout(), PageLayout(mode: .print)])
    func tagsTakeNoRoom(layout: PageLayout) {
        // The comparison deletes what the layout hides, so first: the tags
        // are what it hides, every one of them.
        let source = Self.note.nativeUTF8
        let hidden = MarkdownLayout.runs(for: DocumentParser.parse(source), in: source).filter { $0.kind == .joiners }.map(\.range)
        let ns = source as NSString
        var tags: [NSRange] = []
        for pattern in [SpanStyle.tagPrefix, SpanStyle.close] {
            var from = 0
            while case let found = ns.range(of: pattern, range: NSRange(location: from, length: ns.length - from)), found.location != NSNotFound {
                let end = pattern == SpanStyle.close ? NSMaxRange(found) : NSMaxRange(ns.range(of: SpanStyle.tagSuffix, range: NSRange(location: found.location, length: ns.length - found.location)))
                tags.append(NSRange(location: found.location, length: end - found.location))
                from = end
            }
        }
        #expect(tags.count == 6)
        for tag in tags {
            #expect(hidden.contains { NSIntersectionRange($0, tag) == tag }, "\(ns.substring(with: tag)) is drawn")
        }

        let (rendered, deleted) = MarkdownLayoutTests.pair(Self.note, layout: layout)
        let a = CodeFenceDisplayTests.lineFrames(of: rendered.textView)
        let b = CodeFenceDisplayTests.lineFrames(of: deleted.textView)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(abs(x.minX - y.minX) < 0.01 && abs(x.minY - y.minY) < 0.01 && abs(x.width - y.width) < 0.5, "\(x) against \(y)")
        }
    }

    @Test("A run's text is drawn in its colour, made legible for each appearance", arguments: [UIUserInterfaceStyle.light, .dark])
    func drawnInColour(style: UIUserInterfaceStyle) throws {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = Self.note
        DocumentStyler.applyStyling(to: textView)
        let offset = (Self.note as NSString).range(of: "red words").location
        let colour = try #require(textView.textStorage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? UIColor)
        let resolved = colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
        #expect((byte(red) << 16 | byte(green) << 8 | byte(blue)) == AccentPalette.textHex(for: Self.red, isDark: style == .dark))

        // Plain text beside it is not.
        let plain = try #require(textView.textStorage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? UIColor)
        #expect(plain == .label)
        // Bold inside the run is coloured too.
        let bold = (Self.note as NSString).range(of: "bold").location
        #expect(textView.textStorage.attribute(.foregroundColor, at: bold, effectiveRange: nil) as? UIColor === colour)
    }

    /// The styler writes only what differs from the storage. A dynamic colour
    /// made afresh each restyle isn't equal to the last, and would rewrite
    /// every run, and lay out the note below it, on every keystroke.
    @Test("Restyling coloured text that's already styled leaves the storage alone")
    func restyleIsNotAnEdit() {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = Self.note
        DocumentStyler.applyStyling(to: textView)
        var edits = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
        ) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        DocumentStyler.applyStyling(to: textView)
        #expect(edits == 0)
    }
}

#endif
